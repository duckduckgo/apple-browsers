//
//  DuckAiTermsOfServiceChatsObserverTests.swift
//  DuckDuckGo
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

import AIChat
import Combine
import DuckAiDataStore
import XCTest
@testable import DuckDuckGo

final class DuckAiTermsOfServiceChatsObserverTests: XCTestCase {

    private let termsKey = DuckAiNativeStorageConsent.termsOfServiceEntryKey
    private let chat = DuckAiChatRecord(chatId: "chat-1", data: Data("{}".utf8))

    private var userDefaults: UserDefaults!
    private var store: DuckAiTermsOfServiceStore!
    private var storage: ObservableChatStorage!
    private var queue: DispatchQueue!
    private var sut: DuckAiTermsOfServiceChatsObserver?

    private var suiteName: String { String(describing: self) }

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        store = DuckAiTermsOfServiceStore(keyValueStore: userDefaults)
        storage = ObservableChatStorage()
        queue = DispatchQueue(label: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        store = nil
        storage = nil
        queue = nil
        sut = nil
        super.tearDown()
    }

    func testWhenChatsExistThenTermsAreAcceptedForNativeAndWeb() throws {
        storage.chats.send([chat])

        start()

        XCTAssertTrue(store.hasAccepted)
        XCTAssertEqual(try storage.getEntry(key: termsKey) as? String, "true")
    }

    func testWhenNoChatsExistThenNothingIsRecorded() throws {
        start()

        XCTAssertFalse(store.hasAccepted)
        XCTAssertNil(try storage.getEntry(key: termsKey))
    }

    /// Chats synced from another device land while the app runs.
    func testWhenChatsArriveAfterLaunchThenTermsAreAccepted() throws {
        start()

        storage.chats.send([chat])

        XCTAssertTrue(store.hasAccepted)
        XCTAssertEqual(try storage.getEntry(key: termsKey) as? String, "true")
    }

    func testWhenWebRecordedFalseAndChatsExistThenItIsReplacedWithTrue() throws {
        try storage.putEntry(key: termsKey, value: "false")
        storage.chats.send([chat])

        start()

        XCTAssertEqual(try storage.getEntry(key: termsKey) as? String, "true")
    }

    func testWhenWebAlreadyAcceptedThenOnlyNativeIsRecorded() throws {
        try storage.putEntry(key: termsKey, value: true)
        storage.chats.send([chat])

        start()

        XCTAssertTrue(store.hasAccepted)
        XCTAssertEqual(try storage.getEntry(key: termsKey) as? Bool, true)
    }

    /// The chats database opens in the background, so there's no reason to wait for it.
    func testWhenBothSidesAlreadyAcceptedThenChatsAreNotRead() throws {
        store.recordWebReport()
        try storage.putEntry(key: termsKey, value: "true")

        start()

        XCTAssertEqual(storage.chatsPublisherRequests, 0)
    }

    func testWhenNativeTermsOfServiceIsOffThenNothingIsObserved() {
        XCTAssertNil(DuckAiTermsOfServiceChatsObserver(storageHandler: storage,
                                                       feature: StubNativeTermsOfServiceFeature(isAvailable: false),
                                                       store: store,
                                                       queue: queue))
    }

    func testWhenNativeStorageIsUnavailableThenNothingIsObserved() {
        XCTAssertNil(DuckAiTermsOfServiceChatsObserver(storageHandler: nil,
                                                       feature: StubNativeTermsOfServiceFeature(isAvailable: true),
                                                       store: store,
                                                       queue: queue))
    }

    private func start() {
        sut = DuckAiTermsOfServiceChatsObserver(storageHandler: storage,
                                                feature: StubNativeTermsOfServiceFeature(isAvailable: true),
                                                store: store,
                                                queue: queue)
        sut?.start()
        queue.sync {}
    }
}

private final class ObservableChatStorage: DuckAiNativeStorageHandling, DuckAiNativeChatsObserving {

    let chats = CurrentValueSubject<[DuckAiChatRecord], Error>([])
    private(set) var chatsPublisherRequests = 0

    private let backing = DuckAiNativeMemoryStorageHandler()

    func chatsPublisher() -> AnyPublisher<[DuckAiChatRecord], Error> {
        chatsPublisherRequests += 1
        return chats.eraseToAnyPublisher()
    }

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
    func isMigrationDone() throws -> Bool { try backing.isMigrationDone() }
    func isMigrationDone(key: String) throws -> Bool { try backing.isMigrationDone(key: key) }
    func markMigrationDone(key: String) throws { try backing.markMigrationDone(key: key) }
}
