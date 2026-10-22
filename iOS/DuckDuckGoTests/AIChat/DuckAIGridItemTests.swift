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
import UIKit
import AIChat
import Core
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

    func testWhenChatIsImageGenerationModelAndHasNoFileRefsThenReturnsEmptyWithChatChip() {
        let chat = makeChat(title: "A duck wearing sunglasses", model: "image-generation", fileRefs: [])

        let item = DuckAIGridItem.from(chat: chat, lastMessageContent: nil)

        XCTAssertEqual(item, .empty(title: "A duck wearing sunglasses", chip: .chat))
    }

    func testWhenChatIsImageGenerationAndTitleIsEmptyThenFallsBackToUntitledChatPlaceholder() {
        let chat = makeChat(title: "", model: "image-generation", fileRefs: ["uuid-1"])

        let item = DuckAIGridItem.from(chat: chat, lastMessageContent: nil)

        XCTAssertEqual(item, .image(title: UserText.aiChatTabSwitcherCardUntitledChat, imageFileRef: "uuid-1"))
    }

    // MARK: - Voice / transcript branch

    func testWhenChatIsVoiceKindAndHasTranscriptThenReturnsTranscriptItem() {
        let chat = makeChat(title: "Weekend plans", model: "voice-mode")

        let item = DuckAIGridItem.from(chat: chat, lastMessageContent: "Let's go hiking on Saturday.")

        XCTAssertEqual(item, .transcript(title: "Weekend plans", snippet: "Let's go hiking on Saturday."))
    }

    func testWhenChatIsVoiceKindAndTranscriptHasWhitespaceThenSnippetIsTrimmed() {
        let chat = makeChat(title: "Weekend plans", model: "voice-mode")

        let item = DuckAIGridItem.from(chat: chat, lastMessageContent: "  Let's go hiking\n")

        XCTAssertEqual(item, .transcript(title: "Weekend plans", snippet: "Let's go hiking"))
    }

    func testWhenChatIsVoiceKindAndTranscriptExceedsSnippetCapThenSnippetIsTruncatedToCap() {
        let chat = makeChat(title: "Weekend plans", model: "voice-mode")
        let longTranscript = String(repeating: "a", count: DuckAIGridItem.snippetCharacterCap + 100)

        let item = DuckAIGridItem.from(chat: chat, lastMessageContent: longTranscript)

        let expectedSnippet = String(repeating: "a", count: DuckAIGridItem.snippetCharacterCap)
        XCTAssertEqual(item, .transcript(title: "Weekend plans", snippet: expectedSnippet))
    }

    func testWhenChatIsVoiceKindAndTitleIsEmptyThenFallsBackToUntitledChatPlaceholder() {
        let chat = makeChat(title: "", model: "voice-mode")

        let item = DuckAIGridItem.from(chat: chat, lastMessageContent: "Hi")

        XCTAssertEqual(item, .transcript(title: UserText.aiChatTabSwitcherCardUntitledChat, snippet: "Hi"))
    }

    func testWhenChatIsVoiceKindAndTranscriptIsNilThenReturnsEmptyWithTranscriptChip() {
        let chat = makeChat(title: "Weekend plans", model: "voice-mode")

        let item = DuckAIGridItem.from(chat: chat, lastMessageContent: nil)

        XCTAssertEqual(item, .empty(title: "Weekend plans", chip: .transcript))
    }

    // MARK: - Empty-content branch

    func testWhenChatIsTextKindAndContentIsEmptyThenReturnsEmptyWithChatChip() {
        let chat = makeChat(title: "Cute ducks", model: "gpt-4o-mini")

        let item = DuckAIGridItem.from(chat: chat, lastMessageContent: "   \n")

        XCTAssertEqual(item, .empty(title: "Cute ducks", chip: .chat))
    }

    func testWhenContentIsEmptyAndTitleIsEmptyThenFallsBackToUntitledChatPlaceholder() {
        let chat = makeChat(title: "", model: "gpt-4o-mini")

        let item = DuckAIGridItem.from(chat: chat, lastMessageContent: nil)

        XCTAssertEqual(item, .empty(title: UserText.aiChatTabSwitcherCardUntitledChat, chip: .chat))
    }

    // MARK: - chipKind

    func testChipKindMapping() {
        XCTAssertEqual(DuckAIGridItem.text(title: "t", snippet: "s").chipKind, .chat)
        XCTAssertEqual(DuckAIGridItem.image(title: "t", imageFileRef: "r").chipKind, .chat)
        XCTAssertEqual(DuckAIGridItem.transcript(title: "t", snippet: "s").chipKind, .transcript)
        XCTAssertEqual(DuckAIGridItem.voice.chipKind, .voice)
        XCTAssertEqual(DuckAIGridItem.empty(title: "t", chip: .chat).chipKind, .chat)
        XCTAssertNil(DuckAIGridItem.empty(title: nil, chip: nil).chipKind)
    }

    @MainActor
    func testWhenGridShowsWebsiteOrNewTabThenRichCardIsNotCreated() {
        let cell = TabViewGridCell(frame: .zero)
        let website = Tab(link: Link(title: nil, url: URL(string: "https://example.com")!), fireTab: false)
        update(cell, tab: website)
        XCTAssertNil(cell.richCardContainer)

        let newTab = Tab(fireTab: false)
        update(cell, tab: newTab)
        XCTAssertNil(cell.richCardContainer)
    }

    @MainActor
    func testWhenGridShowsRichAIContentThenCardIsCreatedAndReused() throws {
        let cell = TabViewGridCell(frame: .zero)
        let tab = makeAITab()
        update(cell, tab: tab, item: .text(title: "Chat", snippet: "Hello"))
        let card = try XCTUnwrap(cell.richCardContainer)
        XCTAssertFalse(card.isHidden)
        XCTAssertTrue(cell.preview?.isHidden == true)

        update(cell, tab: tab, item: .voice)
        XCTAssertTrue(cell.richCardContainer === card)
        XCTAssertFalse(card.isHidden)
        XCTAssertTrue(cell.accessibilityElements?.contains { ($0 as? UIView) === card } == true)
    }

    @MainActor
    func testWhenRichGridCellShowsScreenshotFallbackThenCardIsHidden() throws {
        let cell = TabViewGridCell(frame: .zero)
        let tab = makeAITab()
        update(cell, tab: tab, item: .voice)
        let card = try XCTUnwrap(cell.richCardContainer)

        cell.prepareForReuse()
        let screenshot = UIImage()
        cell.update(withTab: tab, isSelectionModeEnabled: false, preview: screenshot, isFireModeEnabled: false)
        XCTAssertTrue(cell.richCardContainer === card)
        XCTAssertTrue(card.isHidden)
        XCTAssertTrue(cell.preview?.isHidden == false)
        XCTAssertTrue(cell.preview?.image === screenshot)
        XCTAssertFalse(cell.accessibilityElements?.contains { ($0 as? UIView) === card } == true)
    }

    @MainActor
    func testWhenGridShowsBareEmptyAIContentThenRichCardIsNotCreated() {
        let cell = TabViewGridCell(frame: .zero)
        let tab = makeAITab()
        update(cell, tab: tab, item: .empty(title: nil, chip: nil))
        XCTAssertNil(cell.richCardContainer)
        XCTAssertNotNil(cell.preview?.image)
        XCTAssertTrue(cell.preview?.isHidden == false)
    }

    @MainActor
    func testWhenListShowsRichAIContentThenGridCardIsNotCreated() {
        let cell = TabViewListCell(frame: .zero)
        let tab = makeAITab()
        update(cell, tab: tab, item: .text(title: "Chat", snippet: "Hello"))
        XCTAssertNil(cell.richCardContainer)
    }

    // MARK: - Helpers

    @MainActor
    private func makeAITab() -> Tab {
        Tab(link: Link(title: nil, url: URL(string: "https://duckduckgo.com/?ia=chat&chatID=chat-1")!), fireTab: false)
    }

    @MainActor
    private func update(_ cell: TabViewCell, tab: Tab, item: DuckAIGridItem? = nil) {
        cell.update(withTab: tab, isSelectionModeEnabled: false, preview: nil, isFireModeEnabled: false, duckAIGridItem: item)
    }

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
