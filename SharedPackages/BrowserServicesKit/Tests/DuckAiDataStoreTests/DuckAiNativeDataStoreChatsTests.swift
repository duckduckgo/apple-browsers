//
//  DuckAiNativeDataStoreChatsTests.swift
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

import CryptoKit
import Foundation
import XCTest
@testable import DuckAiDataStore

final class DuckAiNativeDataStoreChatsTests: XCTestCase {

    private var tempDirectory: URL!
    private var sut: DuckAiNativeDataStore!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let databaseURL = tempDirectory.appendingPathComponent("db.sqlite")
        let filesDirectoryURL = tempDirectory.appendingPathComponent("files")
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        sut = try! DuckAiNativeDataStore(databaseURL: databaseURL, filesDirectoryURL: filesDirectoryURL, key: key)
    }

    override func tearDown() {
        sut = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        super.tearDown()
    }

    func testWhenPutChatThenGetAllChatsReturnsIt() throws {
        let chatId = "chat-1"
        let data = Data("hello".utf8)

        try sut.putChat(chatId: chatId, data: data)

        let chats = try sut.getAllChats()
        XCTAssertEqual(chats.count, 1)
        XCTAssertEqual(chats.first, DuckAiChatRecord(chatId: chatId, data: data))
    }

    func testWhenPutChatWithSameIdThenItUpdates() throws {
        let chatId = "chat-1"
        let initialData = Data("initial".utf8)
        let updatedData = Data("updated".utf8)

        try sut.putChat(chatId: chatId, data: initialData)
        try sut.putChat(chatId: chatId, data: updatedData)

        let chats = try sut.getAllChats()
        XCTAssertEqual(chats.count, 1)
        XCTAssertEqual(chats.first, DuckAiChatRecord(chatId: chatId, data: updatedData))
    }

    func testWhenDeleteChatThenItIsRemoved() throws {
        let chatId = "chat-1"
        let data = Data("hello".utf8)

        try sut.putChat(chatId: chatId, data: data)
        try sut.deleteChat(chatId: chatId)

        let chats = try sut.getAllChats()
        XCTAssertTrue(chats.isEmpty)
    }

    func testWhenDeleteAllChatsThenAllAreRemoved() throws {
        try sut.putChat(chatId: "chat-1", data: Data("data1".utf8))
        try sut.putChat(chatId: "chat-2", data: Data("data2".utf8))

        try sut.deleteAllChats()

        let chats = try sut.getAllChats()
        XCTAssertTrue(chats.isEmpty)
    }

    func testWhenGetAllChatsOnEmptyDbThenReturnsEmptyArray() throws {
        let chats = try sut.getAllChats()
        XCTAssertTrue(chats.isEmpty)
    }

    func testWhenDeleteNonExistentChatThenNoError() throws {
        XCTAssertNoThrow(try sut.deleteChat(chatId: "non-existent"))
    }

    func testWhenGetChatOnExistingIdThenReturnsRecord() throws {
        try sut.putChat(chatId: "chat-1", data: Data("one".utf8))
        try sut.putChat(chatId: "chat-2", data: Data("two".utf8))

        let record = try sut.getChat(chatId: "chat-2")

        XCTAssertEqual(record, DuckAiChatRecord(chatId: "chat-2", data: Data("two".utf8)))
    }

    func testWhenGetChatOnMissingIdThenReturnsNil() throws {
        try sut.putChat(chatId: "chat-1", data: Data("one".utf8))

        let record = try sut.getChat(chatId: "chat-missing")

        XCTAssertNil(record)
    }
}
