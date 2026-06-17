//
//  DuckAIGridItemTests.swift
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
@testable import DuckDuckGo

final class DuckAIGridItemTests: XCTestCase {

    // MARK: - Text branch

    func testWhenChatIsTextKindAndLastMessageContentIsPresentThenReturnsTextItem() {
        let chat = makeChat(title: "Cute ducks", model: "gpt-4o-mini")

        let item = DuckAIGridItem.from(chat: chat, lastMessageContent: "Sure! Ducks are highly social birds…")

        XCTAssertEqual(item, .text(title: "Cute ducks", snippet: "Sure! Ducks are highly social birds…"))
    }

    func testWhenChatHasEmptyTitleThenFallsBackToUntitledChatPlaceholder() {
        let chat = makeChat(title: "", model: "gpt-4o-mini")

        let item = DuckAIGridItem.from(chat: chat, lastMessageContent: "Hello")

        XCTAssertEqual(item, .text(title: UserText.aiChatTabSwitcherCardUntitledChat, snippet: "Hello"))
    }

    func testWhenLastMessageContentHasLeadingTrailingWhitespaceThenSnippetIsTrimmed() {
        let chat = makeChat(title: "Cute ducks", model: "gpt-4o-mini")

        let item = DuckAIGridItem.from(chat: chat, lastMessageContent: "  Hello world\n")

        XCTAssertEqual(item, .text(title: "Cute ducks", snippet: "Hello world"))
    }

    func testWhenChatModelIsEmptyStringThenClassifiedAsTextKind() {
        let chat = makeChat(title: "Cute ducks", model: "")

        let item = DuckAIGridItem.from(chat: chat, lastMessageContent: "Hello")

        XCTAssertEqual(item, .text(title: "Cute ducks", snippet: "Hello"))
    }

    // MARK: - Snippet length cap

    func testWhenLastMessageContentExceedsSnippetCapThenSnippetIsTruncatedToCap() {
        let chat = makeChat(title: "Cute ducks", model: "gpt-4o-mini")
        let longMessage = String(repeating: "a", count: DuckAIGridItem.snippetCharacterCap + 100)

        let item = DuckAIGridItem.from(chat: chat, lastMessageContent: longMessage)

        let expectedSnippet = String(repeating: "a", count: DuckAIGridItem.snippetCharacterCap)
        XCTAssertEqual(item, .text(title: "Cute ducks", snippet: expectedSnippet))
    }

    // MARK: - Image branch

    func testWhenChatIsImageGenerationModelAndHasFileRefsThenReturnsImageItemWithLastFileRef() {
        let chat = makeChat(
            title: "A duck wearing sunglasses",
            model: "image-generation",
            fileRefs: ["uuid-first", "uuid-second", "uuid-latest"]
        )

        let item = DuckAIGridItem.from(chat: chat, lastMessageContent: nil)

        XCTAssertEqual(item, .image(title: "A duck wearing sunglasses", imageFileRef: "uuid-latest"))
    }

    func testWhenChatIsImageGenerationModelAndHasNoFileRefsThenReturnsNil() {
        let chat = makeChat(title: "A duck wearing sunglasses", model: "image-generation", fileRefs: [])

        let item = DuckAIGridItem.from(chat: chat, lastMessageContent: nil)

        XCTAssertNil(item)
    }

    func testWhenChatIsImageGenerationAndTitleIsEmptyThenFallsBackToUntitledChatPlaceholder() {
        let chat = makeChat(title: "", model: "image-generation", fileRefs: ["uuid-1"])

        let item = DuckAIGridItem.from(chat: chat, lastMessageContent: nil)

        XCTAssertEqual(item, .image(title: UserText.aiChatTabSwitcherCardUntitledChat, imageFileRef: "uuid-1"))
    }

    // MARK: - Helpers

    private func makeChat(title: String,
                          model: String,
                          fileRefs: [String] = [],
                          isImageGeneration: Bool = false) -> DuckAiChat {
        DuckAiChat(
            chatId: "chat-1",
            title: title,
            model: model,
            lastEdit: "2026-01-01T00:00:00.000Z",
            pinned: false,
            fileRefs: fileRefs,
            isImageGeneration: isImageGeneration
        )
    }
}
