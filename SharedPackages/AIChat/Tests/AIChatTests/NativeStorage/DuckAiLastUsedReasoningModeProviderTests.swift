//
//  DuckAiLastUsedReasoningModeProviderTests.swift
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

final class DuckAiLastUsedReasoningModeProviderTests: XCTestCase {

    private var storage: ReasoningModeStubStorageHandler!
    private var pixelFiring: MockDuckAiNativeStoragePixelFiring!
    private var sut: DuckAiLastUsedReasoningModeProvider!

    override func setUp() {
        super.setUp()
        storage = ReasoningModeStubStorageHandler()
        pixelFiring = MockDuckAiNativeStoragePixelFiring()
        sut = DuckAiLastUsedReasoningModeProvider(storage: storage, pixelFiring: pixelFiring)
    }

    func testWhenPayloadHasFastReasoningModeThenReturnsFastRawValue() {
        storage.stubbedChat = makeRecord(chatId: "chat-1", json: #"{"chatId":"chat-1","reasoningMode":"fast"}"#)
        XCTAssertEqual(sut.reasoningMode(forChatId: "chat-1"), "fast")
    }

    func testWhenPayloadHasReasoningReasoningModeThenReturnsReasoningRawValue() {
        storage.stubbedChat = makeRecord(chatId: "chat-1", json: #"{"chatId":"chat-1","reasoningMode":"reasoning"}"#)
        XCTAssertEqual(sut.reasoningMode(forChatId: "chat-1"), "reasoning")
    }

    func testWhenPayloadHasExtendedReasoningModeThenReturnsExtendedRawValue() {
        storage.stubbedChat = makeRecord(chatId: "chat-1", json: #"{"chatId":"chat-1","reasoningMode":"extended_reasoning"}"#)
        XCTAssertEqual(sut.reasoningMode(forChatId: "chat-1"), "extended_reasoning")
    }

    func testWhenPayloadHasNoReasoningModeFieldThenReturnsNil() {
        storage.stubbedChat = makeRecord(chatId: "chat-1", json: #"{"chatId":"chat-1","model":"gpt-5-mini"}"#)
        XCTAssertNil(sut.reasoningMode(forChatId: "chat-1"))
    }

    func testWhenPayloadHasUnknownReasoningModeValueThenStillReturnsRawValueLeavingMappingToCaller() {
        // Provider returns the raw string; caller maps to enum and decides what to do
        // when the value is unrecognized (the contract: "keep current picker state").
        storage.stubbedChat = makeRecord(chatId: "chat-1", json: #"{"chatId":"chat-1","reasoningMode":"some_new_mode"}"#)
        XCTAssertEqual(sut.reasoningMode(forChatId: "chat-1"), "some_new_mode")
    }

    func testWhenReasoningModeIsNullThenReturnsNil() {
        storage.stubbedChat = makeRecord(chatId: "chat-1", json: #"{"chatId":"chat-1","reasoningMode":null}"#)
        XCTAssertNil(sut.reasoningMode(forChatId: "chat-1"))
    }

    func testWhenChatNotInStorageThenReturnsNilWithoutPixel() {
        storage.stubbedChat = nil
        XCTAssertNil(sut.reasoningMode(forChatId: "missing"))
        XCTAssertTrue(pixelFiring.firedEvents.isEmpty)
    }

    func testWhenStorageThrowsThenReturnsNilAndFiresChatGetErrorPixel() {
        struct E: Error {}
        storage.stubbedGetChatError = E()
        XCTAssertNil(sut.reasoningMode(forChatId: "chat-1"))
        XCTAssertEqual(pixelFiring.firedEvents.count, 1)
        guard case .chatGetError = pixelFiring.firedEvents[0] else {
            return XCTFail("Expected chatGetError pixel, got \(pixelFiring.firedEvents[0])")
        }
    }

    func testWhenStoredDataIsNotJsonThenReturnsNilAndFiresParseErrorPixel() {
        storage.stubbedChat = DuckAiChatRecord(chatId: "chat-1", data: Data([0xFF, 0xFE, 0xFD]))
        XCTAssertNil(sut.reasoningMode(forChatId: "chat-1"))
        XCTAssertEqual(pixelFiring.firedEvents.count, 1)
        guard case .lastUsedReasoningModeParseError = pixelFiring.firedEvents[0] else {
            return XCTFail("Expected lastUsedReasoningModeParseError pixel, got \(pixelFiring.firedEvents[0])")
        }
    }

    func testWhenChatIdFieldIsMissingThenReturnsNilAndFiresParseErrorPixel() {
        // Forces decode failure via missing required `chatId` key.
        storage.stubbedChat = makeRecord(chatId: "chat-1", json: #"{"reasoningMode":"fast"}"#)
        XCTAssertNil(sut.reasoningMode(forChatId: "chat-1"))
        XCTAssertEqual(pixelFiring.firedEvents.count, 1)
        guard case .lastUsedReasoningModeParseError = pixelFiring.firedEvents[0] else {
            return XCTFail("Expected lastUsedReasoningModeParseError pixel, got \(pixelFiring.firedEvents[0])")
        }
    }

    func testWhenFullChatPayloadMatchingFEContractThenReturnsReasoningMode() {
        let json = """
        {
          "title": "Hello",
          "model": "claude-sonnet-4-5",
          "reasoningMode": "extended_reasoning",
          "messages": [
            { "role": "user", "content": "hi" }
          ],
          "chatId": "abc"
        }
        """
        storage.stubbedChat = makeRecord(chatId: "abc", json: json)
        XCTAssertEqual(sut.reasoningMode(forChatId: "abc"), "extended_reasoning")
    }

    // MARK: - Helpers

    private func makeRecord(chatId: String, json: String) -> DuckAiChatRecord {
        DuckAiChatRecord(chatId: chatId, data: Data(json.utf8))
    }
}

// MARK: - Stub

private final class ReasoningModeStubStorageHandler: DuckAiNativeStorageHandling {
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
