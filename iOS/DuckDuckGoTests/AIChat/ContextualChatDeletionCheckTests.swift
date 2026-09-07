//
//  ContextualChatDeletionCheckTests.swift
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
import XCTest
@testable import DuckDuckGo

/// Only `getChat` and `isMigrationDone` carry behaviour; the rest satisfies the protocol.
final class StubDuckAiNativeStorage: DuckAiNativeStorageHandling {

    var chats: [String: DuckAiChatRecord] = [:]
    var migrationDone = true
    var readError: Error?

    struct ReadFailure: Error {}

    func getChat(chatId: String) throws -> DuckAiChatRecord? {
        if let readError { throw readError }
        return chats[chatId]
    }

    func isMigrationDone() throws -> Bool { migrationDone }

    func putEntry(key: String, value: Any) throws {}
    func getEntry(key: String) throws -> Any? { nil }
    func getAllEntries() throws -> [String: Any] { [:] }
    func deleteEntry(key: String) throws {}
    func deleteAllEntries() throws {}
    func replaceAllEntries(_ entries: [String: Any]) throws {}
    func putChat(chatId: String, data: Data) throws {}
    func putChats(_ chats: [DuckAiChatRecord]) throws {}
    func getAllChats() throws -> [DuckAiChatRecord] { [] }
    func deleteChat(chatId: String) throws {}
    func deleteAllChats() throws {}
    func putFile(uuid: String, chatId: String, data: Data) throws {}
    func getFile(uuid: String) throws -> DuckAiFileContent? { nil }
    func listFiles() throws -> [DuckAiFileMetadata] { [] }
    func deleteFile(uuid: String) throws {}
    func deleteFiles(chatId: String) throws {}
    func deleteAllFiles() throws {}
    func isMigrationDone(key: String) throws -> Bool { migrationDone }
    func markMigrationDone(key: String) throws {}
}

final class DeletedChatCheckTests: XCTestCase {

    private let chatID = "760d681e-9173-4abd-a120-d660783787e9"
    private var storage: StubDuckAiNativeStorage!

    override func setUp() {
        super.setUp()
        storage = StubDuckAiNativeStorage()
    }

    private func makeSUT(nativeDataAccess: Bool = true, storage: DuckAiNativeStorageHandling?) -> DeletedChatCheck {
        DeletedChatCheck(storage: storage, isNativeDataAccessEnabled: nativeDataAccess)
    }

    func testWhenTheStoreHasNoSuchChatThenItWasDeleted() {
        let sut = makeSUT(storage: storage)

        XCTAssertTrue(sut.wasDeleted(chatID: chatID))
    }

    func testWhenTheStoreHasTheChatThenItWasNotDeleted() {
        storage.chats[chatID] = DuckAiChatRecord(chatId: chatID, data: Data())
        let sut = makeSUT(storage: storage)

        XCTAssertFalse(sut.wasDeleted(chatID: chatID))
    }

    func testWhenTheReadFailsThenNoDeletionIsClaimed() {
        // The bug this replaces: an unanswerable store read as proof of deletion.
        storage.readError = StubDuckAiNativeStorage.ReadFailure()
        let sut = makeSUT(storage: storage)

        XCTAssertFalse(sut.wasDeleted(chatID: chatID))
    }

    func testWhenTheStoreIsNotMigratedThenNoDeletionIsClaimed() {
        storage.migrationDone = false
        let sut = makeSUT(storage: storage)

        XCTAssertFalse(sut.wasDeleted(chatID: chatID))
    }

    func testWhenNativeDataAccessIsOffThenNoDeletionIsClaimed() {
        let sut = makeSUT(nativeDataAccess: false, storage: storage)

        XCTAssertFalse(sut.wasDeleted(chatID: chatID))
    }

    func testWhenThereIsNoStoreThenNoDeletionIsClaimed() {
        let sut = makeSUT(storage: nil)

        XCTAssertFalse(sut.wasDeleted(chatID: chatID))
    }

    func testWhenTheURLCarriesNoChatIDThenNoDeletionIsClaimed() {
        let sut = makeSUT(storage: storage)

        XCTAssertFalse(sut.wasDeleted(chatAt: URL(string: "https://duckduckgo.com/chat")!))
    }
}
