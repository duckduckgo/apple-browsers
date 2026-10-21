//
//  DuckAiLastUsedModelProviderTests.swift
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

import DuckAiDataStore
import XCTest
@testable import AIChat

final class DuckAiLastUsedModelProviderTests: XCTestCase {

    private var storage: StubStorageHandler!
    private var pixelFiring: MockDuckAiNativeStoragePixelFiring!
    private var sut: DuckAiLastUsedModelProvider!

    override func setUp() {
        super.setUp()
        storage = StubStorageHandler()
        pixelFiring = MockDuckAiNativeStoragePixelFiring()
        sut = DuckAiLastUsedModelProvider(storage: storage, pixelFiring: pixelFiring)
    }

    func testWhenChatHasModelFieldThenReturnsModelId() {
        storage.stubbedChat = makeRecord(chatId: "chat-1", json: #"{"chatId":"chat-1","model":"gpt-5-mini","title":"x"}"#)
        XCTAssertEqual(sut.lastUsedModel(forChatId: "chat-1"), "gpt-5-mini")
        XCTAssertTrue(pixelFiring.firedEvents.isEmpty)
    }

    func testWhenChatHasNoModelFieldThenReturnsNilWithoutPixel() {
        storage.stubbedChat = makeRecord(chatId: "chat-1", json: #"{"chatId":"chat-1","title":"x"}"#)
        XCTAssertNil(sut.lastUsedModel(forChatId: "chat-1"))
        XCTAssertTrue(pixelFiring.firedEvents.isEmpty)
    }

    func testWhenChatModelFieldIsNullThenReturnsNilWithoutPixel() {
        storage.stubbedChat = makeRecord(chatId: "chat-1", json: #"{"chatId":"chat-1","model":null}"#)
        XCTAssertNil(sut.lastUsedModel(forChatId: "chat-1"))
        XCTAssertTrue(pixelFiring.firedEvents.isEmpty)
    }

    func testWhenChatModelFieldIsEmptyStringThenReturnsNilWithoutPixel() {
        storage.stubbedChat = makeRecord(chatId: "chat-1", json: #"{"chatId":"chat-1","model":""}"#)
        XCTAssertNil(sut.lastUsedModel(forChatId: "chat-1"))
        XCTAssertTrue(pixelFiring.firedEvents.isEmpty)
    }

    func testWhenChatIdFieldIsMissingThenReturnsNilAndFiresParseErrorPixel() {
        storage.stubbedChat = makeRecord(chatId: "chat-1", json: #"{"model":"gpt-5-mini"}"#)
        XCTAssertNil(sut.lastUsedModel(forChatId: "chat-1"))
        XCTAssertEqual(pixelFiring.firedEvents.count, 1)
        guard case .lastUsedModelParseError = pixelFiring.firedEvents[0] else {
            return XCTFail("Expected lastUsedModelParseError pixel, got \(pixelFiring.firedEvents[0])")
        }
    }

    func testWhenChatNotInStorageThenReturnsNilWithoutPixel() {
        storage.stubbedChat = nil
        XCTAssertNil(sut.lastUsedModel(forChatId: "missing"))
        XCTAssertTrue(pixelFiring.firedEvents.isEmpty)
    }

    func testWhenStorageThrowsThenReturnsNilAndFiresChatGetErrorPixel() {
        struct E: Error {}
        storage.stubbedGetChatError = E()
        XCTAssertNil(sut.lastUsedModel(forChatId: "chat-1"))
        XCTAssertEqual(pixelFiring.firedEvents.count, 1)
        guard case .chatGetError = pixelFiring.firedEvents[0] else {
            return XCTFail("Expected chatGetError pixel, got \(pixelFiring.firedEvents[0])")
        }
    }

    func testWhenStoredDataIsNotJsonThenReturnsNilAndFiresParseErrorPixel() {
        storage.stubbedChat = DuckAiChatRecord(chatId: "chat-1", data: Data([0xFF, 0xFE, 0xFD]))
        XCTAssertNil(sut.lastUsedModel(forChatId: "chat-1"))
        XCTAssertEqual(pixelFiring.firedEvents.count, 1)
        guard case .lastUsedModelParseError = pixelFiring.firedEvents[0] else {
            return XCTFail("Expected lastUsedModelParseError pixel, got \(pixelFiring.firedEvents[0])")
        }
    }

    func testWhenModelFieldHasWrongTypeThenReturnsNilAndFiresParseErrorPixel() {
        storage.stubbedChat = makeRecord(chatId: "chat-1", json: #"{"chatId":"chat-1","model":42}"#)
        XCTAssertNil(sut.lastUsedModel(forChatId: "chat-1"))
        XCTAssertEqual(pixelFiring.firedEvents.count, 1)
        guard case .lastUsedModelParseError = pixelFiring.firedEvents[0] else {
            return XCTFail("Expected lastUsedModelParseError pixel, got \(pixelFiring.firedEvents[0])")
        }
    }

    func testWhenFullChatPayloadThenReturnsTopLevelModel() {
        // Matches the shape we observed in the wild: per-message `model` fields plus
        // a top-level `model` indicating the latest active turn.
        let json = """
        {
          "chatId": "abc",
          "model": "meta-llama/Llama-4-Scout-17B-16E-Instruct",
          "messages": [
            { "role": "user", "content": "hi" },
            { "role": "assistant", "content": "", "model": "gpt-5-mini", "status": "inactive" },
            { "role": "assistant", "content": "", "model": "meta-llama/Llama-4-Scout-17B-16E-Instruct", "status": "active" }
          ]
        }
        """
        storage.stubbedChat = makeRecord(chatId: "abc", json: json)
        XCTAssertEqual(sut.lastUsedModel(forChatId: "abc"), "meta-llama/Llama-4-Scout-17B-16E-Instruct")
        XCTAssertTrue(pixelFiring.firedEvents.isEmpty)
    }

    // MARK: - Helpers

    private func makeRecord(chatId: String, json: String) -> DuckAiChatRecord {
        DuckAiChatRecord(chatId: chatId, data: Data(json.utf8))
    }
}

// MARK: - Stub

private final class StubStorageHandler: DuckAiNativeStorageHandling {
    var stubbedChat: DuckAiChatRecord?
    var stubbedGetChatError: Error?

    func putEntry(key: String, value: Any) throws {}
    func getEntry(key: String) throws -> Any? { nil }
    func getAllEntries() throws -> [String: Any] { [:] }
    func deleteEntry(key: String) throws {}
    func deleteAllEntries() throws {}
    func replaceAllEntries(_ entries: [String: Any]) throws {}
    func putChat(chatId: String, data: Data) throws {}
    func putChats(_ chats: [DuckAiChatRecord]) throws {}
    func getChat(chatId: String) throws -> DuckAiChatRecord? {
        if let stubbedGetChatError { throw stubbedGetChatError }
        return stubbedChat
    }
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
