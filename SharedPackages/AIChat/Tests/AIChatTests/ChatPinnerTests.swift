//
//  ChatPinnerTests.swift
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
@testable import AIChat

final class ChatPinnerTests: XCTestCase {

    func testToggle_flipsFalseToTrue_andPersistsViaPutChat() throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        let original = Self.chatJSON(chatId: "c1", pinned: false)
        try storage.putChat(chatId: "c1", data: original)
        let pinner = ChatPinner(storageHandler: storage)

        try pinner.togglePin(chatId: "c1")

        let after = try XCTUnwrap(storage.getChat(chatId: "c1"))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: after.data) as? [String: Any])
        XCTAssertEqual(dict["pinned"] as? Bool, true)
    }

    func testToggle_flipsTrueToFalse() throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        try storage.putChat(chatId: "c1", data: Self.chatJSON(chatId: "c1", pinned: true))
        let pinner = ChatPinner(storageHandler: storage)

        try pinner.togglePin(chatId: "c1")

        let after = try XCTUnwrap(storage.getChat(chatId: "c1"))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: after.data) as? [String: Any])
        XCTAssertEqual(dict["pinned"] as? Bool, false)
    }

    func testToggle_twiceReturnsToOriginalState() throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        try storage.putChat(chatId: "c1", data: Self.chatJSON(chatId: "c1", pinned: false))
        let pinner = ChatPinner(storageHandler: storage)

        try pinner.togglePin(chatId: "c1")
        try pinner.togglePin(chatId: "c1")

        let after = try XCTUnwrap(storage.getChat(chatId: "c1"))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: after.data) as? [String: Any])
        XCTAssertEqual(dict["pinned"] as? Bool, false)
    }

    func testToggle_treatsMissingPinnedKeyAsFalse_andFlipsToTrue() throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        let json = #"{"chatId":"c1","title":"x","model":"gpt-4o-mini","lastEdit":"2026-05-01T00:00:00.000Z"}"#
        try storage.putChat(chatId: "c1", data: Data(json.utf8))
        let pinner = ChatPinner(storageHandler: storage)

        try pinner.togglePin(chatId: "c1")

        let after = try XCTUnwrap(storage.getChat(chatId: "c1"))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: after.data) as? [String: Any])
        XCTAssertEqual(dict["pinned"] as? Bool, true)
    }

    func testToggle_preservesAllOtherBlobFields() throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        let json = #"""
        {
          "chatId": "c1",
          "title": "Hello",
          "model": "gpt-4o-mini",
          "lastEdit": "2026-05-01T00:00:00.000Z",
          "pinned": false,
          "reasoningMode": "off",
          "fileRefs": ["11111111-2222-3333-4444-555555555555"],
          "extras": { "futureField": "keep me" },
          "messages": [
            { "role": "user", "content": "draw a duck" },
            { "role": "assistant", "content": "", "parts": [ { "type": "ui-component", "name": "generate-image" } ] }
          ]
        }
        """#
        try storage.putChat(chatId: "c1", data: Data(json.utf8))
        let pinner = ChatPinner(storageHandler: storage)

        try pinner.togglePin(chatId: "c1")

        let after = try XCTUnwrap(storage.getChat(chatId: "c1"))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: after.data) as? [String: Any])
        XCTAssertEqual(dict["pinned"] as? Bool, true, "pin flipped")
        XCTAssertEqual(dict["title"] as? String, "Hello")
        XCTAssertEqual(dict["model"] as? String, "gpt-4o-mini")
        XCTAssertEqual(dict["lastEdit"] as? String, "2026-05-01T00:00:00.000Z")
        XCTAssertEqual(dict["reasoningMode"] as? String, "off")
        XCTAssertEqual(dict["fileRefs"] as? [String], ["11111111-2222-3333-4444-555555555555"])
        let extras = try XCTUnwrap(dict["extras"] as? [String: Any])
        XCTAssertEqual(extras["futureField"] as? String, "keep me")
        let messages = try XCTUnwrap(dict["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        let assistantParts = try XCTUnwrap(messages[1]["parts"] as? [[String: Any]])
        XCTAssertEqual(assistantParts.first?["type"] as? String, "ui-component")
        XCTAssertEqual(assistantParts.first?["name"] as? String, "generate-image")
    }

    func testToggle_throwsChatNotFound_whenChatIdIsAbsent() {
        let storage = DuckAiNativeMemoryStorageHandler()
        let pinner = ChatPinner(storageHandler: storage)

        XCTAssertThrowsError(try pinner.togglePin(chatId: "missing")) { error in
            XCTAssertEqual(error as? ChatPinningError, .chatNotFound)
        }
    }

    func testToggle_throwsInvalidChatBlob_whenStoredDataIsNotJSONObject() throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        try storage.putChat(chatId: "c1", data: Data("not even json".utf8))
        let pinner = ChatPinner(storageHandler: storage)

        XCTAssertThrowsError(try pinner.togglePin(chatId: "c1")) { error in
            XCTAssertEqual(error as? ChatPinningError, .invalidChatBlob)
        }
    }

    // MARK: - Fixtures

    private static func chatJSON(chatId: String, pinned: Bool) -> Data {
        let json = """
        {"chatId":"\(chatId)","title":"x","model":"gpt-4o-mini","lastEdit":"2026-05-01T00:00:00.000Z","pinned":\(pinned)}
        """
        return Data(json.utf8)
    }
}
