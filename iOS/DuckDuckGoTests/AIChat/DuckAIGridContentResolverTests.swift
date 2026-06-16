//
//  DuckAIGridContentResolverTests.swift
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

import XCTest
import AIChat
import Core
@testable import DuckDuckGo

@MainActor
final class DuckAIGridContentResolverTests: XCTestCase {

    // MARK: - Inner gates: gridItem(forChatID:)

    func testWhenStorageHandlerIsNilThenReturnsNil() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatNativeDataAccess, .aiChatTabSwitcherRichCard])
        let sut = DuckAIGridContentResolver(featureFlagger: flagger, storageHandler: nil)

        XCTAssertNil(sut.gridItem(forChatID: "chat-1"))
    }

    func testWhenNativeDataAccessFlagOffThenReturnsNil() throws {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatTabSwitcherRichCard])
        let storage = makeStorageWithMigrationsDone()
        try storage.putChat(chatId: "chat-1", data: validChatData(chatId: "chat-1"))
        let sut = DuckAIGridContentResolver(featureFlagger: flagger, storageHandler: storage)

        XCTAssertNil(sut.gridItem(forChatID: "chat-1"))
    }

    func testWhenMigrationNotDoneThenReturnsNil() throws {
        // Mirrors SuggestionsReader/HistoryCleaner: gate on all migration keys, not just `chats`.
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatNativeDataAccess])
        let storage = DuckAiNativeMemoryStorageHandler()
        try storage.putChat(chatId: "chat-1", data: validChatData(chatId: "chat-1"))
        let sut = DuckAIGridContentResolver(featureFlagger: flagger, storageHandler: storage)

        XCTAssertNil(sut.gridItem(forChatID: "chat-1"))
    }

    func testWhenOnlyChatsMigrationKeyIsDoneThenReturnsNil() throws {
        // `files` migration still pending — full gate must still fail.
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatNativeDataAccess])
        let storage = DuckAiNativeMemoryStorageHandler()
        try storage.markMigrationDone(key: DuckAiMigrationKey.chats)
        try storage.putChat(chatId: "chat-1", data: validChatData(chatId: "chat-1"))
        let sut = DuckAIGridContentResolver(featureFlagger: flagger, storageHandler: storage)

        XCTAssertNil(sut.gridItem(forChatID: "chat-1"))
    }

    func testWhenChatNotFoundThenReturnsNil() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatNativeDataAccess])
        let storage = makeStorageWithMigrationsDone()
        let sut = DuckAIGridContentResolver(featureFlagger: flagger, storageHandler: storage)

        XCTAssertNil(sut.gridItem(forChatID: "missing-chat"))
    }

    func testWhenChatRecordIsValidThenReturnsTextItem() throws {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatNativeDataAccess])
        let storage = makeStorageWithMigrationsDone()
        try storage.putChat(
            chatId: "chat-1",
            data: validChatData(
                chatId: "chat-1",
                title: "Cute ducks",
                lastMessage: "Sure! Ducks are highly social birds."
            )
        )
        let sut = DuckAIGridContentResolver(featureFlagger: flagger, storageHandler: storage)

        XCTAssertEqual(
            sut.gridItem(forChatID: "chat-1"),
            .text(title: "Cute ducks", snippet: "Sure! Ducks are highly social birds.")
        )
    }

    // MARK: - Outer gates: gridItem(for:)

    func testWhenRichCardFeatureFlagOffThenReturnsNil() throws {
        // Outer flag is the first gate; storage state shouldn't matter.
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatNativeDataAccess])
        let storage = makeStorageWithMigrationsDone()
        try storage.putChat(chatId: "chat-1", data: validChatData(chatId: "chat-1"))
        let sut = DuckAIGridContentResolver(featureFlagger: flagger, storageHandler: storage)
        let tab = Tab(link: Link(title: nil, url: URL(string: "https://duckduckgo.com/?ia=chat&chatID=chat-1")!))

        XCTAssertNil(sut.gridItem(for: tab))
    }

    func testWhenTabHasNoChatIDThenReturnsNil() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatNativeDataAccess, .aiChatTabSwitcherRichCard])
        let storage = makeStorageWithMigrationsDone()
        let sut = DuckAIGridContentResolver(featureFlagger: flagger, storageHandler: storage)
        let tab = Tab(link: Link(title: nil, url: URL(string: "https://example.com")!))

        XCTAssertNil(sut.gridItem(for: tab))
    }

    func testWhenTabIsAIChatWithChatIDThenReturnsTextItem() throws {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatNativeDataAccess, .aiChatTabSwitcherRichCard])
        let storage = makeStorageWithMigrationsDone()
        try storage.putChat(
            chatId: "chat-1",
            data: validChatData(chatId: "chat-1", title: "Cute ducks", lastMessage: "hi there!")
        )
        let sut = DuckAIGridContentResolver(featureFlagger: flagger, storageHandler: storage)
        let tab = Tab(link: Link(title: nil, url: URL(string: "https://duckduckgo.com/?ia=chat&chatID=chat-1")!))

        XCTAssertEqual(sut.gridItem(for: tab), .text(title: "Cute ducks", snippet: "hi there!"))
    }

    // MARK: - Helpers

    private func makeStorageWithMigrationsDone() -> DuckAiNativeMemoryStorageHandler {
        let storage = DuckAiNativeMemoryStorageHandler()
        try? storage.markMigrationDone(key: DuckAiMigrationKey.chats)
        try? storage.markMigrationDone(key: DuckAiMigrationKey.files)
        return storage
    }

    private func validChatData(chatId: String,
                               title: String = "Cute ducks",
                               model: String = "gpt-4o-mini",
                               lastMessage: String = "hi there!") -> Data {
        let json = """
        {
          "chatId": "\(chatId)",
          "title": "\(title)",
          "model": "\(model)",
          "lastEdit": "2026-01-01T00:00:00.000Z",
          "pinned": false,
          "messages": [
            { "role": "user", "content": "Tell me about ducks" },
            { "role": "assistant", "content": "\(lastMessage)" }
          ]
        }
        """
        return Data(json.utf8)
    }
}
