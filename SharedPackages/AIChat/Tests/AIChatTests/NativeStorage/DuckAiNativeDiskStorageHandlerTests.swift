//
//  DuckAiNativeDiskStorageHandlerTests.swift
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
import XCTest
import Persistence
import PersistenceTestingUtils
import DuckAiDataStore
@testable import AIChat

final class DuckAiNativeDiskStorageHandlerTests: XCTestCase {

    private var settingsStore: InMemoryThrowingKeyValueStore!
    private var mockDataStore: MockDuckAiNativeDataStore!
    private var handler: DuckAiNativeDiskStorageHandler!

    override func setUp() {
        super.setUp()
        settingsStore = InMemoryThrowingKeyValueStore()
        mockDataStore = MockDuckAiNativeDataStore()
        handler = DuckAiNativeDiskStorageHandler(
            settingsStore: settingsStore.throwingKeyedStoring(),
            dataStore: mockDataStore
        )
    }

    override func tearDown() {
        settingsStore = nil
        mockDataStore = nil
        handler = nil
        super.tearDown()
    }

    // MARK: - Entries

    func testWhenPutEntryThenGetEntryReturnsValue() throws {
        try handler.putEntry(key: "theme", value: "dark")

        let result = try handler.getEntry(key: "theme") as? String
        XCTAssertEqual(result, "dark")
    }

    func testWhenGetAllEntriesThenReturnsDictionary() throws {
        try handler.putEntry(key: "theme", value: "dark")
        try handler.putEntry(key: "lang", value: "en")

        let all = try handler.getAllEntries()
        XCTAssertEqual(all["theme"] as? String, "dark")
        XCTAssertEqual(all["lang"] as? String, "en")
    }

    func testWhenDeleteEntryThenItIsRemoved() throws {
        try handler.putEntry(key: "theme", value: "dark")
        try handler.deleteEntry(key: "theme")

        let result = try handler.getEntry(key: "theme")
        XCTAssertNil(result)
    }

    func testWhenReplaceAllEntriesThenPreviousEntriesCleared() throws {
        try handler.putEntry(key: "theme", value: "dark")
        try handler.replaceAllEntries(["lang": "fr"])

        let all = try handler.getAllEntries()
        XCTAssertNil(all["theme"])
        XCTAssertEqual(all["lang"] as? String, "fr")
    }

    func testWhenDeleteAllEntriesThenAllCleared() throws {
        try handler.putEntry(key: "theme", value: "dark")
        try handler.deleteAllEntries()

        let all = try handler.getAllEntries()
        XCTAssertTrue(all.isEmpty)
    }

    func testWhenGetEntryOnEmptyStoreThenReturnsNil() throws {
        let result = try handler.getEntry(key: "nonexistent")
        XCTAssertNil(result)
    }

    // MARK: - Concurrency

    func testWhenConcurrentPutEntriesThenNoUpdatesAreLost() throws {
        let iterations = 100
        let queue1 = DispatchQueue(label: "test.queue1", qos: .userInitiated)
        let queue2 = DispatchQueue(label: "test.queue2", qos: .userInitiated)
        let group = DispatchGroup()

        for i in 0..<iterations {
            group.enter()
            queue1.async {
                try? self.handler.putEntry(key: "q1_\(i)", value: i)
                group.leave()
            }
            group.enter()
            queue2.async {
                try? self.handler.putEntry(key: "q2_\(i)", value: i)
                group.leave()
            }
        }

        group.wait()

        let all = try handler.getAllEntries()
        XCTAssertEqual(all.count, iterations * 2, "Expected \(iterations * 2) keys but got \(all.count) — updates were lost")
        for i in 0..<iterations {
            XCTAssertNotNil(all["q1_\(i)"], "Missing key q1_\(i)")
            XCTAssertNotNil(all["q2_\(i)"], "Missing key q2_\(i)")
        }
    }

    func testWhenConcurrentDeleteEntriesThenNoUpdatesAreLost() throws {
        // Pre-populate entries that should survive
        for i in 0..<100 {
            try handler.putEntry(key: "keep_\(i)", value: i)
            try handler.putEntry(key: "delete_\(i)", value: i)
        }

        let queue1 = DispatchQueue(label: "test.delete1", qos: .userInitiated)
        let queue2 = DispatchQueue(label: "test.delete2", qos: .userInitiated)
        let group = DispatchGroup()

        for i in 0..<100 {
            group.enter()
            queue1.async {
                try? self.handler.deleteEntry(key: "delete_\(i)")
                group.leave()
            }
            // Concurrently add new entries while deleting others
            group.enter()
            queue2.async {
                try? self.handler.putEntry(key: "new_\(i)", value: i)
                group.leave()
            }
        }

        group.wait()

        let all = try handler.getAllEntries()
        for i in 0..<100 {
            XCTAssertNotNil(all["keep_\(i)"], "Surviving key keep_\(i) was lost")
            XCTAssertNil(all["delete_\(i)"], "Deleted key delete_\(i) still present")
            XCTAssertNotNil(all["new_\(i)"], "Concurrently added key new_\(i) was lost")
        }
    }

    // MARK: - Migration

    func testWhenMigrationNotDoneThenReturnsFalse() throws {
        let result = try handler.isMigrationDone(key: DuckAiMigrationKey.chats)
        XCTAssertFalse(result)
    }

    func testWhenMarkMigrationDoneThenReturnsTrue() throws {
        try handler.markMigrationDone(key: DuckAiMigrationKey.chats)

        let result = try handler.isMigrationDone(key: DuckAiMigrationKey.chats)
        XCTAssertTrue(result)
    }

    func testWhenMarkMigrationDoneForKeyThenOtherKeyStillFalse() throws {
        try handler.markMigrationDone(key: DuckAiMigrationKey.chats)

        XCTAssertTrue(try handler.isMigrationDone(key: DuckAiMigrationKey.chats))
        XCTAssertFalse(try handler.isMigrationDone(key: DuckAiMigrationKey.files))
    }

    // MARK: - Chat delegation

    func testWhenPutChatThenDelegatesToDataStore() throws {
        let data = Data("test".utf8)
        try handler.putChat(chatId: "chat-1", data: data)

        XCTAssertEqual(mockDataStore.putChatCallCount, 1)
        XCTAssertEqual(mockDataStore.lastPutChatId, "chat-1")
        XCTAssertEqual(mockDataStore.lastPutChatData, data)
    }

    func testWhenPutChatsThenDelegatesToDataStore() throws {
        let chats = [
            DuckAiChatRecord(chatId: "chat-1", data: Data("a".utf8)),
            DuckAiChatRecord(chatId: "chat-2", data: Data("b".utf8))
        ]
        try handler.putChats(chats)

        XCTAssertEqual(mockDataStore.putChatsCallCount, 1)
        XCTAssertEqual(mockDataStore.lastPutChats?.count, 2)
        XCTAssertEqual(mockDataStore.lastPutChats?[0].chatId, "chat-1")
        XCTAssertEqual(mockDataStore.lastPutChats?[1].chatId, "chat-2")
    }

    func testWhenDeleteChatThenDelegatesToDataStore() throws {
        try handler.deleteChat(chatId: "chat-1")

        XCTAssertEqual(mockDataStore.deleteChatCallCount, 1)
        XCTAssertEqual(mockDataStore.lastDeleteChatId, "chat-1")
    }

    // MARK: - Locally deleted chat IDs

    func testWhenDeleteChatThenRecordsLocallyDeletedChatId() throws {
        try handler.deleteChat(chatId: "chat-1")

        let recorded = try handler.getEntry(key: DuckAiNativeStorageReservedEntryKeys.locallyDeletedChatIds.rawValue) as? [String]
        XCTAssertEqual(recorded, ["chat-1"])
    }

    func testWhenDeleteUnknownChatThenStillRecordsId() throws {
        // The mock data store does not track chats; deleting an absent id must still record it.
        try handler.deleteChat(chatId: "never-existed")

        let recorded = try handler.getEntry(key: DuckAiNativeStorageReservedEntryKeys.locallyDeletedChatIds.rawValue) as? [String]
        XCTAssertEqual(recorded, ["never-existed"])
    }

    func testWhenDeletingSameChatTwiceThenRecordedOnce() throws {
        try handler.deleteChat(chatId: "dup")
        try handler.deleteChat(chatId: "dup")

        let recorded = try handler.getEntry(key: DuckAiNativeStorageReservedEntryKeys.locallyDeletedChatIds.rawValue) as? [String]
        XCTAssertEqual(recorded, ["dup"])
    }

    func testWhenDeletingMultipleChatsThenIdsAccumulate() throws {
        try handler.deleteChat(chatId: "a")
        try handler.deleteChat(chatId: "b")

        let recorded = try handler.getEntry(key: DuckAiNativeStorageReservedEntryKeys.locallyDeletedChatIds.rawValue) as? [String]
        XCTAssertEqual(recorded.map { Set($0) }, Set(["a", "b"]))
    }

    func testWhenConcurrentDeleteChatsThenNoIdsAreLost() throws {
        let iterations = 100
        let queue1 = DispatchQueue(label: "test.delchat1", qos: .userInitiated)
        let queue2 = DispatchQueue(label: "test.delchat2", qos: .userInitiated)
        let group = DispatchGroup()

        for i in 0..<iterations {
            group.enter()
            queue1.async {
                try? self.handler.deleteChat(chatId: "a\(i)")
                group.leave()
            }
            group.enter()
            queue2.async {
                try? self.handler.deleteChat(chatId: "b\(i)")
                group.leave()
            }
        }

        group.wait()

        let recorded = Set((try handler.getEntry(key: DuckAiNativeStorageReservedEntryKeys.locallyDeletedChatIds.rawValue) as? [String]) ?? [])
        XCTAssertEqual(recorded.count, iterations * 2, "Expected \(iterations * 2) ids but got \(recorded.count) — updates were lost")
        for i in 0..<iterations {
            XCTAssertTrue(recorded.contains("a\(i)"), "Missing id a\(i)")
            XCTAssertTrue(recorded.contains("b\(i)"), "Missing id b\(i)")
        }
    }

    func testWhenGetAllChatsThenDelegatesToDataStore() throws {
        mockDataStore.stubbedChats = [DuckAiChatRecord(chatId: "c1", data: Data())]
        let result = try handler.getAllChats()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].chatId, "c1")
    }

    func testWhenDeleteAllChatsThenDelegatesToDataStore() throws {
        try handler.deleteAllChats()
        XCTAssertEqual(mockDataStore.deleteAllChatsCallCount, 1)
    }

    func testWhenGetChatThenDelegatesToDataStore() throws {
        mockDataStore.stubbedChat = DuckAiChatRecord(chatId: "c1", data: Data("x".utf8))
        let result = try handler.getChat(chatId: "c1")
        XCTAssertEqual(mockDataStore.getChatCallCount, 1)
        XCTAssertEqual(mockDataStore.lastGetChatId, "c1")
        XCTAssertEqual(result?.chatId, "c1")
    }

    func testWhenGetChatNotFoundThenReturnsNil() throws {
        mockDataStore.stubbedChat = nil
        let result = try handler.getChat(chatId: "missing")
        XCTAssertNil(result)
    }

    func testWhenPutFileThenDelegatesToDataStore() throws {
        try handler.putFile(uuid: "f1", chatId: "c1", data: Data())
        XCTAssertEqual(mockDataStore.putFileCallCount, 1)
    }

    func testWhenDeleteFilesByChatIdThenDelegatesToDataStore() throws {
        try handler.deleteFiles(chatId: "c1")
        XCTAssertEqual(mockDataStore.deleteFilesByChatIdCallCount, 1)
        XCTAssertEqual(mockDataStore.lastDeleteFilesChatId, "c1")
    }

    func testWhenDeleteAllFilesThenDelegatesToDataStore() throws {
        try handler.deleteAllFiles()
        XCTAssertEqual(mockDataStore.deleteAllFilesCallCount, 1)
    }
}

// MARK: - Mock

private final class MockDuckAiNativeDataStore: DuckAiNativeDataStoring, DuckAiNativeChatsRecordObserving {

    var putChatCallCount = 0
    var lastPutChatId: String?
    var lastPutChatData: Data?

    var getAllChatsCallCount = 0
    var stubbedChats: [DuckAiChatRecord] = []

    var putChatsCallCount = 0
    var lastPutChats: [DuckAiChatRecord]?

    var getChatCallCount = 0
    var lastGetChatId: String?
    var stubbedChat: DuckAiChatRecord?

    var deleteChatCallCount = 0
    var lastDeleteChatId: String?

    var deleteAllChatsCallCount = 0

    var putFileCallCount = 0
    var lastPutFileUuid: String?
    var lastPutFileChatId: String?
    var lastPutFileData: Data?

    var getFileCallCount = 0
    var stubbedFile: DuckAiFileContent?

    var listFilesCallCount = 0
    var stubbedFiles: [DuckAiFileMetadata] = []

    var deleteFileCallCount = 0
    var lastDeleteFileUuid: String?

    var deleteFilesByChatIdCallCount = 0
    var lastDeleteFilesChatId: String?

    var deleteAllFilesCallCount = 0

    func putChat(chatId: String, data: Data) throws {
        putChatCallCount += 1
        lastPutChatId = chatId
        lastPutChatData = data
    }

    func putChats(_ chats: [DuckAiChatRecord]) throws {
        putChatsCallCount += 1
        lastPutChats = chats
    }

    func getChat(chatId: String) throws -> DuckAiChatRecord? {
        getChatCallCount += 1
        lastGetChatId = chatId
        return stubbedChat
    }

    func getAllChats() throws -> [DuckAiChatRecord] {
        getAllChatsCallCount += 1
        return stubbedChats
    }

    func chatsPublisher() -> AnyPublisher<[DuckAiChatRecord], Error> {
        Just(stubbedChats).setFailureType(to: Error.self).eraseToAnyPublisher()
    }

    func deleteChat(chatId: String) throws {
        deleteChatCallCount += 1
        lastDeleteChatId = chatId
    }

    func deleteAllChats() throws {
        deleteAllChatsCallCount += 1
    }

    func putFile(uuid: String, chatId: String, data: Data) throws {
        putFileCallCount += 1
        lastPutFileUuid = uuid
        lastPutFileChatId = chatId
        lastPutFileData = data
    }

    func getFile(uuid: String) throws -> DuckAiFileContent? {
        getFileCallCount += 1
        return stubbedFile
    }

    func listFiles() throws -> [DuckAiFileMetadata] {
        listFilesCallCount += 1
        return stubbedFiles
    }

    func deleteFile(uuid: String) throws {
        deleteFileCallCount += 1
        lastDeleteFileUuid = uuid
    }

    func deleteFiles(chatId: String) throws {
        deleteFilesByChatIdCallCount += 1
        lastDeleteFilesChatId = chatId
    }

    func deleteAllFiles() throws {
        deleteAllFilesCallCount += 1
    }
}
