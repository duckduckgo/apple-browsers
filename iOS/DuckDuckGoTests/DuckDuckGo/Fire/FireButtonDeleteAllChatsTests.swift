//
//  FireButtonDeleteAllChatsTests.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AIChat
import Combine
import CryptoKit
import DuckAiDataStore
import XCTest
@_spi(Testing) import Persistence
@_spi(Testing) import PixelKit
@testable import DuckDuckGo

final class FireButtonDeleteAllChatsTests: XCTestCase {
    func testDisabledOrMissingStorageDoesNotRead() async {
        let storage = FireChatsStorage()
        storage.onMigration = { XCTFail("Disabled storage must not check migration"); return true }
        storage.makeCountPublisher = { XCTFail("Disabled storage must not count chats"); return Empty().eraseToAnyPublisher() }
        let disabled = await NativeChatsReader.readCount(storageHandler: storage, isStorageEnabled: false)
        let missing = await NativeChatsReader.readCount(storageHandler: nil, isStorageEnabled: true)
        let nonObserving = await NativeChatsReader.readCount(storageHandler: DuckAiNativeMemoryStorageHandler(), isStorageEnabled: true)
        assertFailure(disabled, .storageUnavailable)
        assertFailure(missing, .storageUnavailable)
        assertFailure(nonObserving, .storageUnavailable)
    }

    func testUnmigratedOrUnreadableMigrationNeverCountsChats() async {
        for throwsError in [false, true] {
            let storage = FireChatsStorage()
            storage.onMigration = {
                XCTAssertFalse(Thread.isMainThread)
                if throwsError { throw TestError.failed }
                return false
            }
            storage.makeCountPublisher = { XCTFail("Migration must finish before counting chats"); return Empty().eraseToAnyPublisher() }
            let result = await NativeChatsReader.readCount(storageHandler: storage, isStorageEnabled: true)
            assertFailure(result, .notMigrated)
        }
    }

    func testRecentChatsCanReadBeforeMigration() async throws {
        let storage = FireChatsStorage()
        storage.onMigration = { XCTFail("Reading recent chats does not require migration"); return false }
        let result = await NativeChatsReader.read(storageHandler: storage, isStorageEnabled: true)
        XCTAssertEqual(try result.get().count, 0)
    }

    @MainActor
    func testCountIncludesPersistedChatsWithoutDecodablePreviews() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let dataStore = try DuckAiNativeDataStore(databaseURL: directory.appendingPathComponent("chats.db"),
                                                  filesDirectoryURL: directory.appendingPathComponent("files"),
                                                  key: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
        let storage = DuckAiNativeDiskStorageHandler(settingsStore: InMemoryThrowingKeyValueStore().throwingKeyedStoring(), dataStore: dataStore)
        try storage.markMigrationDone(key: DuckAiMigrationKey.chats)
        try storage.markMigrationDone(key: DuckAiMigrationKey.files)
        try storage.putChat(chatId: "with-preview", data: Data(#"{"chatId":"with-preview","title":"Chat"}"#.utf8))
        try storage.putChat(chatId: "without-preview", data: Data(#"{"title":"Chat without an embedded ID"}"#.utf8))

        let count = await NativeChatsReader.readCount(storageHandler: storage, isStorageEnabled: true)
        let previews = await NativeChatsReader.read(storageHandler: storage, isStorageEnabled: true)

        XCTAssertEqual(try count.get(), 2)
        XCTAssertEqual(try previews.get().map(\.chatId), ["with-preview"])
    }

    func testSynchronousZeroCountAlwaysArrivesBeforeCompletion() async throws {
        let storage = FireChatsStorage()
        storage.makeCountPublisher = {
            XCTAssertFalse(Thread.isMainThread)
            return Deferred {
                XCTAssertFalse(Thread.isMainThread)
                return Just(0).setFailureType(to: Error.self)
            }.eraseToAnyPublisher()
        }
        for _ in 0..<1000 {
            let result = await NativeChatsReader.readCount(storageHandler: storage, isStorageEnabled: true)
            let count = try result.get()
            XCTAssertEqual(count, 0)
        }
    }

    func testFailureAndEmptyCompletionAreReadFailed() async {
        for fails in [false, true] {
            let storage = FireChatsStorage()
            storage.makeCountPublisher = {
                if fails { return Fail(error: TestError.failed).eraseToAnyPublisher() }
                return Empty().eraseToAnyPublisher()
            }
            let result = await NativeChatsReader.readCount(storageHandler: storage, isStorageEnabled: true)
            assertFailure(result, .readFailed)
        }
    }

    func testSilentPublisherHitsTheRealOneSecondDeadline() async {
        let storage = FireChatsStorage()
        storage.makeCountPublisher = { Empty(completeImmediately: false).eraseToAnyPublisher() }
        let start = Date()
        let result = await NativeChatsReader.readCount(storageHandler: storage, isStorageEnabled: true)
        assertFailure(result, .timeout)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.8)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testDeadlineIncludesMigrationAndPublisherCreation() async {
        for blocksMigration in [false, true] {
            let storage = FireChatsStorage()
            let release = DispatchSemaphore(value: 0)
            let started = expectation(description: "Background read started")
            if blocksMigration {
                storage.onMigration = {
                    started.fulfill()
                    _ = release.wait(timeout: .now() + 2)
                    return true
                }
            } else {
                storage.makeCountPublisher = {
                    started.fulfill()
                    _ = release.wait(timeout: .now() + 2)
                    return Just(0).setFailureType(to: Error.self).eraseToAnyPublisher()
                }
            }
            let start = Date()
            let result = await NativeChatsReader.readCount(storageHandler: storage, isStorageEnabled: true, timeout: .milliseconds(100))
            release.signal()
            assertFailure(result, .timeout)
            XCTAssertLessThan(Date().timeIntervalSince(start), 1)
            await fulfillment(of: [started], timeout: 1)
        }
    }

    func testShownFiresForEachContextWithItsLayout() {
        let pixels = PixelKitMock()
        let instrumentation = DefaultFireButtonDeleteAllChatsInstrumentation(pixelFiring: pixels)

        instrumentation.shown(layout: .withThisChat, context: .tab)
        instrumentation.shown(layout: .allChatsOnly, context: .contextual)

        let calls = pixels.actualFireCalls
        XCTAssertEqual(calls.map(\.pixel.name), ["aichat_fire_delete-all-chats_shown", "aichat_fire_delete-all-chats_shown"])
        XCTAssertEqual(calls.map(\.frequency), [.standard, .standard])
        XCTAssertEqual(calls.map(\.pixel.parameters), [
            ["layout": "with_this_chat", "context": "tab"],
            ["layout": "all_chats_only", "context": "contextual"]
        ])
        XCTAssertTrue(calls.allSatisfy(\.includeAppVersionParameter))
    }

    func testExecutedFiresDailyAndCountForEachContextWithItsLayoutAndMode() {
        let pixels = PixelKitMock()
        let instrumentation = DefaultFireButtonDeleteAllChatsInstrumentation(pixelFiring: pixels)

        instrumentation.executed(layout: .allChatsOnly, browsingMode: .normal, context: .tab)
        instrumentation.executed(layout: .withThisChat, browsingMode: .fire, context: .contextual)

        let calls = pixels.actualFireCalls
        XCTAssertEqual(calls.map(\.pixel.name), ["aichat_fire_delete-all-chats_executed", "aichat_fire_delete-all-chats_executed"])
        XCTAssertEqual(calls.map(\.frequency), [.dailyAndCount, .dailyAndCount])
        XCTAssertEqual(calls.map(\.pixel.parameters), [
            ["layout": "all_chats_only", "browsing_mode": "normal", "context": "tab"],
            ["layout": "with_this_chat", "browsing_mode": "fire", "context": "contextual"]
        ])
        XCTAssertTrue(calls.allSatisfy(\.includeAppVersionParameter))
    }

    func testCountUnavailableHasOnlyTheBoundedReasonAndNoErrorParameters() {
        let pixels = PixelKitMock()
        let instrumentation = DefaultFireButtonDeleteAllChatsInstrumentation(pixelFiring: pixels)
        let reasons: [(NativeChatsReadFailure, String)] = [
            (.storageUnavailable, "storage_unavailable"), (.notMigrated, "not_migrated"),
            (.timeout, "timeout"), (.readFailed, "read_failed")
        ]
        for (reason, _) in reasons { instrumentation.countUnavailable(reason: reason) }
        XCTAssertEqual(pixels.actualFireCalls.count, reasons.count)
        for (call, (_, expectedReason)) in zip(pixels.actualFireCalls, reasons) {
            XCTAssertEqual(call.pixel.name, "aichat_fire_delete-all-chats_count-unavailable")
            XCTAssertEqual(call.frequency, .dailyAndCount)
            XCTAssertEqual(call.pixel.parameters, ["reason": expectedReason])
            XCTAssertNil(call.pixel.error)
            XCTAssertTrue(call.includeAppVersionParameter)
        }
    }

    private func assertFailure(_ result: Result<Int, NativeChatsReadFailure>, _ expected: NativeChatsReadFailure,
                               file: StaticString = #filePath, line: UInt = #line) {
        guard case .failure(let actual) = result else { return XCTFail("Expected \(expected)", file: file, line: line) }
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    private enum TestError: Error { case failed }
}

private final class FireChatsStorage: DuckAiNativeStorageHandling, DuckAiNativeChatsObserving {
    var onMigration: () throws -> Bool = { true }
    var makeCountPublisher: () -> AnyPublisher<Int, Error> = { Just(0).setFailureType(to: Error.self).eraseToAnyPublisher() }
    private let backing = DuckAiNativeMemoryStorageHandler()

    func chatsPublisher() -> AnyPublisher<[DuckAiChatRecord], Error> { Just([]).setFailureType(to: Error.self).eraseToAnyPublisher() }
    func chatCountPublisher() -> AnyPublisher<Int, Error> { makeCountPublisher() }
    func isMigrationDone() throws -> Bool { try onMigration() }
    func isMigrationDone(key: String) throws -> Bool { try onMigration() }
    func putEntry(key: String, value: Any) throws { try backing.putEntry(key: key, value: value) }
    func getEntry(key: String) throws -> Any? { try backing.getEntry(key: key) }
    func getAllEntries() throws -> [String: Any] { try backing.getAllEntries() }
    func deleteEntry(key: String) throws { try backing.deleteEntry(key: key) }
    func deleteAllEntries() throws { try backing.deleteAllEntries() }
    func replaceAllEntries(_ entries: [String: Any]) throws { try backing.replaceAllEntries(entries) }
    func putChat(chatId: String, data: Data) throws { try backing.putChat(chatId: chatId, data: data) }
    func putChats(_ chats: [DuckAiChatRecord]) throws { try backing.putChats(chats) }
    func getChat(chatId: String) throws -> DuckAiChatRecord? { try backing.getChat(chatId: chatId) }
    func getAllChats() throws -> [DuckAiChatRecord] { try backing.getAllChats() }
    func deleteChat(chatId: String) throws { try backing.deleteChat(chatId: chatId) }
    func deleteAllChats() throws { try backing.deleteAllChats() }
    func putFile(uuid: String, chatId: String, data: Data) throws { try backing.putFile(uuid: uuid, chatId: chatId, data: data) }
    func getFile(uuid: String) throws -> DuckAiFileContent? { try backing.getFile(uuid: uuid) }
    func listFiles() throws -> [DuckAiFileMetadata] { try backing.listFiles() }
    func deleteFile(uuid: String) throws { try backing.deleteFile(uuid: uuid) }
    func deleteFiles(chatId: String) throws { try backing.deleteFiles(chatId: chatId) }
    func deleteAllFiles() throws { try backing.deleteAllFiles() }
    func markMigrationDone(key: String) throws { try backing.markMigrationDone(key: key) }
}
