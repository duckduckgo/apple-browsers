//
//  DuckAiUsageSnapshotProviderTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import Combine
import DuckAiDataStore
import XCTest
@testable import AIChat

final class DuckAiUsageSnapshotProviderTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_755_000_000) // 2025-08-12T12:00:00Z

    private var seededSnapshot: String {
        DuckAiUsageSnapshotSeed.weeklyReached.entryValue(now: now)
    }

    func testReadsWhatTheBridgeWrote() throws {
        let storage = try DuckAiNativeStorageHandler(.memory())
        try storage.putEntry(key: DuckAiNativeStorageReservedEntryKeys.usageLimits.rawValue,
                            value: seededSnapshot)
        let sut = DuckAiUsageSnapshotProvider(storage: storage, dateProvider: { self.now })

        XCTAssertEqual(sut.currentSnapshot().notice?.id, .weeklyReached)
    }

    func testReturnsNoDataWhenKeyWasNeverWritten() throws {
        let storage = try DuckAiNativeStorageHandler(.memory())
        let sut = DuckAiUsageSnapshotProvider(storage: storage, dateProvider: { self.now })

        XCTAssertEqual(sut.currentSnapshot(), .noData)
    }

    func testReturnsNoDataAndFiresPixelWhenStorageThrows() {
        struct StorageError: Error {}
        let pixelFiring = MockDuckAiNativeStoragePixelFiring()
        let sut = DuckAiUsageSnapshotProvider(storage: ThrowingStorageHandler(error: StorageError()),
                                             pixelFiring: pixelFiring,
                                             dateProvider: { self.now })

        XCTAssertEqual(sut.currentSnapshot(), .noData)
        XCTAssertEqual(pixelFiring.firedEvents.count, 1)
        guard case .settingsGetError = pixelFiring.firedEvents[0] else {
            return XCTFail("Expected settingsGetError pixel, got \(pixelFiring.firedEvents[0])")
        }
    }

    /// A snapshot that doesn't parse is an ordinary nothing-to-show state, not something to report.
    func testDoesNotFirePixelForUnparseableSnapshot() throws {
        let storage = try DuckAiNativeStorageHandler(.memory())
        try storage.putEntry(key: DuckAiNativeStorageReservedEntryKeys.usageLimits.rawValue, value: "{oops")
        let pixelFiring = MockDuckAiNativeStoragePixelFiring()
        let sut = DuckAiUsageSnapshotProvider(storage: storage, pixelFiring: pixelFiring, dateProvider: { self.now })

        XCTAssertEqual(sut.currentSnapshot(), .noData)
        XCTAssertTrue(pixelFiring.firedEvents.isEmpty)
    }

    // MARK: - Reserved entry updates

    /// What lets a surface re-read when web publishes a new snapshot, instead of waiting for the
    /// next time the user opens the input.
    func testPublishesReservedEntryWrites() throws {
        let storage = try DuckAiNativeStorageHandler(.memory())
        var published: [DuckAiNativeStorageReservedEntryKeys] = []
        let cancellable = storage.reservedEntryUpdatesPublisher.sink { published.append($0) }

        try storage.putEntry(key: DuckAiNativeStorageReservedEntryKeys.usageLimits.rawValue, value: seededSnapshot)
        try storage.deleteEntry(key: DuckAiNativeStorageReservedEntryKeys.usageLimits.rawValue)

        XCTAssertEqual(published, [.usageLimits, .usageLimits])
        cancellable.cancel()
    }

    /// The entries namespace is the web app's `localStorage`: publishing every key would fire on
    /// unrelated writes on every page load.
    func testDoesNotPublishUnreservedKeys() throws {
        let storage = try DuckAiNativeStorageHandler(.memory())
        var published: [DuckAiNativeStorageReservedEntryKeys] = []
        let cancellable = storage.reservedEntryUpdatesPublisher.sink { published.append($0) }

        try storage.putEntry(key: "duckaiSidebarCollapsed", value: "true")

        XCTAssertTrue(published.isEmpty)
        cancellable.cancel()
    }

    /// A blob replacement can change or drop any reserved key, so all of them are reported.
    func testPublishesEveryReservedKeyOnABlobReplacement() throws {
        let storage = try DuckAiNativeStorageHandler(.memory())
        var published: [DuckAiNativeStorageReservedEntryKeys] = []
        let cancellable = storage.reservedEntryUpdatesPublisher.sink { published.append($0) }

        try storage.replaceAllEntries(["something": "else"])

        XCTAssertEqual(Set(published), Set(DuckAiNativeStorageReservedEntryKeys.allCases))
        cancellable.cancel()
    }
}

/// Only the entries read matters here; everything else is inert.
private final class ThrowingStorageHandler: DuckAiNativeStorageHandling {
    private let error: Error

    init(error: Error) { self.error = error }

    func putEntry(key: String, value: Any) throws {}
    func getEntry(key: String) throws -> Any? { throw error }
    func getAllEntries() throws -> [String: Any] { [:] }
    func deleteEntry(key: String) throws {}
    func deleteAllEntries() throws {}
    func replaceAllEntries(_ entries: [String: Any]) throws {}
    func putChat(chatId: String, data: Data) throws {}
    func putChats(_ chats: [DuckAiChatRecord]) throws {}
    func getChat(chatId: String) throws -> DuckAiChatRecord? { nil }
    func getAllChats() throws -> [DuckAiChatRecord] { [] }
    func deleteChat(chatId: String) throws {}
    func deleteAllChats() throws {}
    func putFile(uuid: String, chatId: String, data: Data) throws {}
    func getFile(uuid: String) throws -> DuckAiFileContent? { nil }
    func listFiles() throws -> [DuckAiFileMetadata] { [] }
    func deleteFile(uuid: String) throws {}
    func deleteFiles(chatId: String) throws {}
    func deleteAllFiles() throws {}
    func isMigrationDone() throws -> Bool { false }
    func isMigrationDone(key: String) throws -> Bool { false }
    func markMigrationDone(key: String) throws {}
}
