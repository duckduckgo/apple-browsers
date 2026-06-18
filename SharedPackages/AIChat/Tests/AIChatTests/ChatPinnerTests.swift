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
import AIChatTestingUtilities

final class ChatPinnerTests: XCTestCase {

    func testSetPinnedTrue_persistsPinnedTrue() throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        try storage.putChat(chatId: "c1", data: Self.chatJSON(chatId: "c1", pinned: false))
        let pinner = ChatPinner(storageHandler: storage)

        try pinner.setPinned(chatId: "c1", pinned: true)

        XCTAssertEqual(try Self.readPinned(from: storage, chatId: "c1"), true)
    }

    func testSetPinnedFalse_persistsPinnedFalse() throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        try storage.putChat(chatId: "c1", data: Self.chatJSON(chatId: "c1", pinned: true))
        let pinner = ChatPinner(storageHandler: storage)

        try pinner.setPinned(chatId: "c1", pinned: false)

        XCTAssertEqual(try Self.readPinned(from: storage, chatId: "c1"), false)
    }

    func testSetPinned_isIdempotentWhenValueAlreadyMatches() throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        try storage.putChat(chatId: "c1", data: Self.chatJSON(chatId: "c1", pinned: true))
        let pinner = ChatPinner(storageHandler: storage)

        try pinner.setPinned(chatId: "c1", pinned: true)

        XCTAssertEqual(try Self.readPinned(from: storage, chatId: "c1"), true)
    }

    func testSetPinned_addsPinnedKey_whenBlobIsMissingIt() throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        let json = #"{"chatId":"c1","title":"x","model":"gpt-4o-mini","lastEdit":"2026-05-01T00:00:00.000Z"}"#
        try storage.putChat(chatId: "c1", data: Data(json.utf8))
        let pinner = ChatPinner(storageHandler: storage)

        try pinner.setPinned(chatId: "c1", pinned: true)

        XCTAssertEqual(try Self.readPinned(from: storage, chatId: "c1"), true)
    }

    func testSetPinned_preservesAllOtherBlobFields() throws {
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

        try pinner.setPinned(chatId: "c1", pinned: true)

        let after = try XCTUnwrap(storage.getChat(chatId: "c1"))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: after.data) as? [String: Any])
        XCTAssertEqual(dict["pinned"] as? Bool, true)
        XCTAssertEqual(dict["title"] as? String, "Hello")
        XCTAssertEqual(dict["model"] as? String, "gpt-4o-mini")
        XCTAssertEqual(dict["lastEdit"] as? String, "2026-05-01T00:00:00.000Z",
                       "lastEdit is not bumped on pin (matches Android)")
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

    func testSetPinned_throwsChatNotFound_whenChatIdIsAbsent() {
        let storage = DuckAiNativeMemoryStorageHandler()
        let pinner = ChatPinner(storageHandler: storage)

        XCTAssertThrowsError(try pinner.setPinned(chatId: "missing", pinned: true)) { error in
            XCTAssertEqual(error as? ChatPinningError, .chatNotFound)
        }
    }

    func testSetPinned_throwsInvalidChatBlob_whenStoredDataIsNotJSON() throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        try storage.putChat(chatId: "c1", data: Data("not even json".utf8))
        let pinner = ChatPinner(storageHandler: storage)

        XCTAssertThrowsError(try pinner.setPinned(chatId: "c1", pinned: true)) { error in
            XCTAssertEqual(error as? ChatPinningError, .invalidChatBlob)
        }
    }

    func testSetPinned_throwsInvalidChatBlob_whenJSONRootIsNotADictionary() throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        // Valid JSON, but the root is an array — can't carry a `pinned` field.
        try storage.putChat(chatId: "c1", data: Data("[1, 2, 3]".utf8))
        let pinner = ChatPinner(storageHandler: storage)

        XCTAssertThrowsError(try pinner.setPinned(chatId: "c1", pinned: true)) { error in
            XCTAssertEqual(error as? ChatPinningError, .invalidChatBlob)
        }
    }

    // MARK: - Sync integration

    func testSetPinned_onSuccess_callsRecordChatUpdateOnSyncCleaner() async throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        try storage.putChat(chatId: "c1", data: Self.chatJSON(chatId: "c1", pinned: false))
        let cleaner = MockAIChatSyncCleaning()
        let pinner = ChatPinner(storageHandler: storage, syncCleaner: cleaner)

        try pinner.setPinned(chatId: "c1", pinned: true)

        // The record is fired off in a Task — give it a chance to run before asserting.
        try await waitForCondition(timeout: 1.0) { await cleaner.recordChatUpdateCalls == ["c1"] }
    }

    func testSetPinned_onFailure_doesNotCallRecordChatUpdate() async throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        // Missing chat → setPinned throws → no record should fire.
        let cleaner = MockAIChatSyncCleaning()
        let pinner = ChatPinner(storageHandler: storage, syncCleaner: cleaner)

        XCTAssertThrowsError(try pinner.setPinned(chatId: "missing", pinned: true))

        // Brief wait to make sure no late Task fires anyway.
        try await Task.sleep(nanoseconds: 50_000_000)
        await MainActor.run {}
        XCTAssertEqual(cleaner.recordChatUpdateCalls, [])
    }

    /// Polls a predicate until it returns true or the timeout elapses. Lets us assert on
    /// the outcome of a fire-and-forget Task without depending on a specific scheduler tick.
    private func waitForCondition(timeout: TimeInterval, _ predicate: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Condition not met within \(timeout)s")
    }

    // MARK: - Fixtures

    private static func chatJSON(chatId: String, pinned: Bool) -> Data {
        let json = """
        {"chatId":"\(chatId)","title":"x","model":"gpt-4o-mini","lastEdit":"2026-05-01T00:00:00.000Z","pinned":\(pinned)}
        """
        return Data(json.utf8)
    }

    private static func readPinned(from storage: DuckAiNativeMemoryStorageHandler, chatId: String) throws -> Bool? {
        let record = try XCTUnwrap(storage.getChat(chatId: chatId))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: record.data) as? [String: Any])
        return dict["pinned"] as? Bool
    }
}
