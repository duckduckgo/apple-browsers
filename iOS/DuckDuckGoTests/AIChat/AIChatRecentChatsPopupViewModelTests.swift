//
//  AIChatRecentChatsPopupViewModelTests.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import AIChat
import XCTest
@testable import DuckDuckGo

@MainActor
final class AIChatRecentChatsPopupViewModelTests: XCTestCase {

    // MARK: - Mock

    private final class MockSuggestionsReader: AIChatSuggestionsReading {
        var maxHistoryCount: Int = 50
        var pinnedToReturn: [AIChatSuggestion] = []
        var recentToReturn: [AIChatSuggestion] = []
        var fetchCallCount = 0
        var lastMaxChats: Int?
        var tearDownCallCount = 0

        func fetchSuggestions(query: String?, maxChats: Int) async -> (pinned: [AIChatSuggestion], recent: [AIChatSuggestion]) {
            fetchCallCount += 1
            lastMaxChats = maxChats
            return (pinned: pinnedToReturn, recent: recentToReturn)
        }

        func tearDown() {
            tearDownCallCount += 1
        }
    }

    // MARK: - Initialization Tests

    func testInitWithEmptySuggestions() {
        let vm = AIChatRecentChatsPopupViewModel(suggestions: [], hasMore: false)

        XCTAssertTrue(vm.suggestions.isEmpty)
        XCTAssertFalse(vm.showViewAll)
        XCTAssertFalse(vm.hasContent)
        XCTAssertTrue(vm.items.isEmpty)
    }

    func testInitWithSuggestionsAndNoMore() {
        let suggestions = makeSuggestions(count: 3)
        let vm = AIChatRecentChatsPopupViewModel(suggestions: suggestions, hasMore: false)

        XCTAssertEqual(vm.suggestions.count, 3)
        XCTAssertFalse(vm.showViewAll)
        XCTAssertTrue(vm.hasContent)
        XCTAssertEqual(vm.items.count, 3)

        // All items should be chat items
        for item in vm.items {
            if case .viewAllChats = item {
                XCTFail("Should not contain viewAllChats item")
            }
        }
    }

    func testInitWithSuggestionsAndHasMore() {
        let suggestions = makeSuggestions(count: 5)
        let vm = AIChatRecentChatsPopupViewModel(suggestions: suggestions, hasMore: true)

        XCTAssertEqual(vm.suggestions.count, 5)
        XCTAssertTrue(vm.showViewAll)
        XCTAssertTrue(vm.hasContent)
        XCTAssertEqual(vm.items.count, 6) // 5 chats + 1 view all

        // Last item should be viewAllChats
        XCTAssertEqual(vm.items.last, .viewAllChats)
    }

    func testInitCapsAtMaxVisibleChats() {
        let suggestions = makeSuggestions(count: 10)
        let vm = AIChatRecentChatsPopupViewModel(suggestions: suggestions, hasMore: true)

        XCTAssertEqual(vm.suggestions.count, AIChatRecentChatsPopupViewModel.maxVisibleChats)
    }

    // MARK: - Items Construction Tests

    func testItemsContainCorrectChatSuggestions() {
        let suggestions = makeSuggestions(count: 3)
        let vm = AIChatRecentChatsPopupViewModel(suggestions: suggestions, hasMore: false)

        for (index, item) in vm.items.enumerated() {
            guard case .chat(let suggestion) = item else {
                XCTFail("Expected chat item at index \(index)")
                return
            }
            XCTAssertEqual(suggestion, suggestions[index])
        }
    }

    func testItemsWithViewAllAppendsFooter() {
        let suggestions = makeSuggestions(count: 2)
        let vm = AIChatRecentChatsPopupViewModel(suggestions: suggestions, hasMore: true)

        XCTAssertEqual(vm.items.count, 3)
        if case .chat(let s) = vm.items[0] {
            XCTAssertEqual(s.chatId, "chat-0")
        } else {
            XCTFail("Expected chat item at index 0")
        }
        if case .chat(let s) = vm.items[1] {
            XCTAssertEqual(s.chatId, "chat-1")
        } else {
            XCTFail("Expected chat item at index 1")
        }
        XCTAssertEqual(vm.items[2], .viewAllChats)
    }

    // MARK: - suggestion(at:) Tests

    func testSuggestionAtValidIndex() {
        let suggestions = makeSuggestions(count: 3)
        let vm = AIChatRecentChatsPopupViewModel(suggestions: suggestions, hasMore: false)

        XCTAssertEqual(vm.suggestion(at: 0)?.chatId, "chat-0")
        XCTAssertEqual(vm.suggestion(at: 2)?.chatId, "chat-2")
    }

    func testSuggestionAtOutOfBoundsReturnsNil() {
        let suggestions = makeSuggestions(count: 3)
        let vm = AIChatRecentChatsPopupViewModel(suggestions: suggestions, hasMore: false)

        XCTAssertNil(vm.suggestion(at: -1))
        XCTAssertNil(vm.suggestion(at: 3))
        XCTAssertNil(vm.suggestion(at: 100))
    }

    func testSuggestionAtOnEmptyReturnsNil() {
        let vm = AIChatRecentChatsPopupViewModel(suggestions: [], hasMore: false)
        XCTAssertNil(vm.suggestion(at: 0))
    }

    // MARK: - Pinned vs Regular Icon Tests

    func testPinnedSuggestionPreservesFlag() {
        let pinned = AIChatSuggestion(id: "1", title: "Pinned", isPinned: true, chatId: "c1")
        let regular = AIChatSuggestion(id: "2", title: "Regular", isPinned: false, chatId: "c2")
        let vm = AIChatRecentChatsPopupViewModel(suggestions: [pinned, regular], hasMore: false)

        if case .chat(let s) = vm.items[0] {
            XCTAssertTrue(s.isPinned)
        }
        if case .chat(let s) = vm.items[1] {
            XCTAssertFalse(s.isPinned)
        }
    }

    // MARK: - fetch() Tests

    func testFetchReturnsNilWhenReaderIsNil() async {
        let result = await AIChatRecentChatsPopupViewModel.fetch(using: nil)
        XCTAssertNil(result)
    }

    func testFetchReturnsNilWhenNoSuggestions() async {
        let reader = MockSuggestionsReader()
        reader.pinnedToReturn = []
        reader.recentToReturn = []

        let result = await AIChatRecentChatsPopupViewModel.fetch(using: reader)

        XCTAssertNil(result)
        XCTAssertEqual(reader.fetchCallCount, 1)
    }

    func testFetchReturnsViewModelWithSuggestions() async {
        let reader = MockSuggestionsReader()
        reader.recentToReturn = makeSuggestions(count: 3)

        let result = await AIChatRecentChatsPopupViewModel.fetch(using: reader)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.suggestions.count, 3)
        XCTAssertFalse(result?.showViewAll ?? true)
    }

    func testFetchRequestsMaxPlusOneToDetectMore() async {
        let reader = MockSuggestionsReader()
        reader.recentToReturn = makeSuggestions(count: 3)

        _ = await AIChatRecentChatsPopupViewModel.fetch(using: reader)

        XCTAssertEqual(reader.lastMaxChats, AIChatRecentChatsPopupViewModel.maxVisibleChats + 1)
    }

    func testFetchSetsHasMoreWhenExceedsMax() async {
        let reader = MockSuggestionsReader()
        reader.recentToReturn = makeSuggestions(count: AIChatRecentChatsPopupViewModel.maxVisibleChats + 1)

        let result = await AIChatRecentChatsPopupViewModel.fetch(using: reader)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.showViewAll ?? false)
        XCTAssertEqual(result?.suggestions.count, AIChatRecentChatsPopupViewModel.maxVisibleChats)
    }

    func testFetchCombinesPinnedAndRecent() async {
        let reader = MockSuggestionsReader()
        reader.pinnedToReturn = [
            AIChatSuggestion(id: "p1", title: "Pinned Chat", isPinned: true, chatId: "pinned-1")
        ]
        reader.recentToReturn = [
            AIChatSuggestion(id: "r1", title: "Recent Chat", isPinned: false, chatId: "recent-1")
        ]

        let result = await AIChatRecentChatsPopupViewModel.fetch(using: reader)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.suggestions.count, 2)
        // Pinned comes first (pinned array is concatenated before recent)
        XCTAssertTrue(result?.suggestions[0].isPinned ?? false)
        XCTAssertFalse(result?.suggestions[1].isPinned ?? true)
    }

    // MARK: - Helpers

    private func makeSuggestions(count: Int) -> [AIChatSuggestion] {
        (0..<count).map { index in
            AIChatSuggestion(
                id: "id-\(index)",
                title: "Chat \(index)",
                isPinned: false,
                chatId: "chat-\(index)"
            )
        }
    }
}
