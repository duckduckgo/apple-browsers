//
//  DuckAiNativeStorageHandlerTests.swift
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

import XCTest
import Persistence
import PersistenceTestingUtils
import DuckAiDataStore
@testable import AIChat

final class DuckAiNativeStorageHandlerTests: XCTestCase {

    private var settingsStore: InMemoryThrowingKeyValueStore!
    private var mockDataStore: MockDuckAiNativeDataStore!
    private var handler: DuckAiNativeStorageHandler!

    override func setUp() {
        super.setUp()
        settingsStore = InMemoryThrowingKeyValueStore()
        mockDataStore = MockDuckAiNativeDataStore()
        handler = DuckAiNativeStorageHandler(
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

    // MARK: - Settings

    func testWhenPutSettingThenGetSettingReturnsValue() throws {
        try handler.putSetting(key: "theme", value: "dark")

        let result = try handler.getSetting(key: "theme") as? String
        XCTAssertEqual(result, "dark")
    }

    func testWhenGetAllSettingsThenReturnsDictionary() throws {
        try handler.putSetting(key: "theme", value: "dark")
        try handler.putSetting(key: "lang", value: "en")

        let all = try handler.getAllSettings()
        XCTAssertEqual(all["theme"] as? String, "dark")
        XCTAssertEqual(all["lang"] as? String, "en")
    }

    func testWhenDeleteSettingThenItIsRemoved() throws {
        try handler.putSetting(key: "theme", value: "dark")
        try handler.deleteSetting(key: "theme")

        let result = try handler.getSetting(key: "theme")
        XCTAssertNil(result)
    }

    func testWhenReplaceAllSettingsThenPreviousSettingsCleared() throws {
        try handler.putSetting(key: "theme", value: "dark")
        try handler.replaceAllSettings(["lang": "fr"])

        let all = try handler.getAllSettings()
        XCTAssertNil(all["theme"])
        XCTAssertEqual(all["lang"] as? String, "fr")
    }

    func testWhenDeleteAllSettingsThenAllCleared() throws {
        try handler.putSetting(key: "theme", value: "dark")
        try handler.deleteAllSettings()

        let all = try handler.getAllSettings()
        XCTAssertTrue(all.isEmpty)
    }

    func testWhenGetSettingOnEmptyStoreThenReturnsNil() throws {
        let result = try handler.getSetting(key: "nonexistent")
        XCTAssertNil(result)
    }

    // MARK: - Concurrency

    func testWhenConcurrentPutSettingsThenNoUpdatesAreLost() throws {
        let iterations = 100
        let queue1 = DispatchQueue(label: "test.queue1", qos: .userInitiated)
        let queue2 = DispatchQueue(label: "test.queue2", qos: .userInitiated)
        let group = DispatchGroup()

        for i in 0..<iterations {
            group.enter()
            queue1.async {
                try? self.handler.putSetting(key: "q1_\(i)", value: i)
                group.leave()
            }
            group.enter()
            queue2.async {
                try? self.handler.putSetting(key: "q2_\(i)", value: i)
                group.leave()
            }
        }

        group.wait()

        let all = try handler.getAllSettings()
        XCTAssertEqual(all.count, iterations * 2, "Expected \(iterations * 2) keys but got \(all.count) — updates were lost")
        for i in 0..<iterations {
            XCTAssertNotNil(all["q1_\(i)"], "Missing key q1_\(i)")
            XCTAssertNotNil(all["q2_\(i)"], "Missing key q2_\(i)")
        }
    }

    func testWhenConcurrentDeleteSettingsThenNoUpdatesAreLost() throws {
        // Pre-populate settings that should survive
        for i in 0..<100 {
            try handler.putSetting(key: "keep_\(i)", value: i)
            try handler.putSetting(key: "delete_\(i)", value: i)
        }

        let queue1 = DispatchQueue(label: "test.delete1", qos: .userInitiated)
        let queue2 = DispatchQueue(label: "test.delete2", qos: .userInitiated)
        let group = DispatchGroup()

        for i in 0..<100 {
            group.enter()
            queue1.async {
                try? self.handler.deleteSetting(key: "delete_\(i)")
                group.leave()
            }
            // Concurrently add new settings while deleting others
            group.enter()
            queue2.async {
                try? self.handler.putSetting(key: "new_\(i)", value: i)
                group.leave()
            }
        }

        group.wait()

        let all = try handler.getAllSettings()
        for i in 0..<100 {
            XCTAssertNotNil(all["keep_\(i)"], "Surviving key keep_\(i) was lost")
            XCTAssertNil(all["delete_\(i)"], "Deleted key delete_\(i) still present")
            XCTAssertNotNil(all["new_\(i)"], "Concurrently added key new_\(i) was lost")
        }
    }

    // MARK: - Migration

    func testWhenMigrationNotDoneThenReturnsFalse() throws {
        let result = try handler.isMigrationDone()
        XCTAssertFalse(result)
    }

    func testWhenMarkMigrationDoneThenReturnsTrue() throws {
        try handler.markMigrationDone()

        let result = try handler.isMigrationDone()
        XCTAssertTrue(result)
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

    func testWhenPutFileThenDelegatesToDataStore() throws {
        try handler.putFile(uuid: "f1", chatId: "c1", data: Data())
        XCTAssertEqual(mockDataStore.putFileCallCount, 1)
    }

    func testWhenDeleteAllFilesThenDelegatesToDataStore() throws {
        try handler.deleteAllFiles()
        XCTAssertEqual(mockDataStore.deleteAllFilesCallCount, 1)
    }
}

// MARK: - Mock

private final class MockDuckAiNativeDataStore: DuckAiNativeDataStoring {

    var putChatCallCount = 0
    var lastPutChatId: String?
    var lastPutChatData: Data?

    var getAllChatsCallCount = 0
    var stubbedChats: [DuckAiChatRecord] = []

    var putChatsCallCount = 0
    var lastPutChats: [DuckAiChatRecord]?

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

    func getAllChats() throws -> [DuckAiChatRecord] {
        getAllChatsCallCount += 1
        return stubbedChats
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

    func deleteAllFiles() throws {
        deleteAllFilesCallCount += 1
    }
}
