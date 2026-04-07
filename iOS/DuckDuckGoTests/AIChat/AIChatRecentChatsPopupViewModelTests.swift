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

    // MARK: - Mocks

    private final class MockSuggestionsReader: AIChatSuggestionsReading {
        var maxHistoryCount: Int = 50
        var pinnedToReturn: [AIChatSuggestion] = []
        var recentToReturn: [AIChatSuggestion] = []
        var fetchCallCount = 0
        var lastMaxChats: Int?

        func fetchSuggestions(query: String?, maxChats: Int) async -> (pinned: [AIChatSuggestion], recent: [AIChatSuggestion]) {
            fetchCallCount += 1
            lastMaxChats = maxChats
            return (pinned: pinnedToReturn, recent: recentToReturn)
        }

        func tearDown() {}
    }

    private final class MockDelegate: AIChatRecentChatsPopupViewModelDelegate {
        var selectedChats: [AIChatSuggestion] = []
        var viewAllCallCount = 0
        var dismissCallCount = 0

        func recentChatsPopupDidSelectChat(_ chat: AIChatSuggestion) {
            selectedChats.append(chat)
        }

        func recentChatsPopupDidSelectViewAll() {
            viewAllCallCount += 1
        }

        func recentChatsPopupDidDismiss() {
            dismissCallCount += 1
        }
    }

    // MARK: - Initialization Tests

    func testInitWithEmptySuggestions() {
        let vm = AIChatRecentChatsPopupViewModel(suggestions: [], hasMore: false)

        XCTAssertTrue(vm.suggestions.isEmpty)
        XCTAssertFalse(vm.showViewAll)
    }

    func testInitWithSuggestionsAndNoMore() {
        let suggestions = makeSuggestions(count: 3)
        let vm = AIChatRecentChatsPopupViewModel(suggestions: suggestions, hasMore: false)

        XCTAssertEqual(vm.suggestions.count, 3)
        XCTAssertFalse(vm.showViewAll)
    }

    func testInitWithSuggestionsAndHasMore() {
        let suggestions = makeSuggestions(count: 5)
        let vm = AIChatRecentChatsPopupViewModel(suggestions: suggestions, hasMore: true)

        XCTAssertEqual(vm.suggestions.count, 5)
        XCTAssertTrue(vm.showViewAll)
    }

    func testInitCapsAtMaxVisibleChats() {
        let suggestions = makeSuggestions(count: 10)
        let vm = AIChatRecentChatsPopupViewModel(suggestions: suggestions, hasMore: true)

        XCTAssertEqual(vm.suggestions.count, AIChatRecentChatsPopupViewModel.maxVisibleChats)
    }

    // MARK: - Pinned vs Regular Tests

    func testPinnedSuggestionPreservesFlag() {
        let pinned = AIChatSuggestion(id: "1", title: "Pinned", isPinned: true, chatId: "c1")
        let regular = AIChatSuggestion(id: "2", title: "Regular", isPinned: false, chatId: "c2")
        let vm = AIChatRecentChatsPopupViewModel(suggestions: [pinned, regular], hasMore: false)

        XCTAssertTrue(vm.suggestions[0].isPinned)
        XCTAssertFalse(vm.suggestions[1].isPinned)
    }

    // MARK: - Action Tests

    func testDidSelectChatCallsDelegateWithCorrectSuggestion() {
        let suggestions = makeSuggestions(count: 3)
        let vm = AIChatRecentChatsPopupViewModel(suggestions: suggestions, hasMore: false)
        let mockDelegate = MockDelegate()
        vm.delegate = mockDelegate

        vm.didSelectChat(at: 1)

        XCTAssertEqual(mockDelegate.selectedChats.count, 1)
        XCTAssertEqual(mockDelegate.selectedChats.first?.chatId, "chat-1")
    }

    func testDidSelectChatOutOfBoundsDoesNotCallDelegate() {
        let suggestions = makeSuggestions(count: 3)
        let vm = AIChatRecentChatsPopupViewModel(suggestions: suggestions, hasMore: false)
        let mockDelegate = MockDelegate()
        vm.delegate = mockDelegate

        vm.didSelectChat(at: 5)

        XCTAssertTrue(mockDelegate.selectedChats.isEmpty)
    }

    func testDidSelectChatNegativeIndexDoesNotCallDelegate() {
        let suggestions = makeSuggestions(count: 3)
        let vm = AIChatRecentChatsPopupViewModel(suggestions: suggestions, hasMore: false)
        let mockDelegate = MockDelegate()
        vm.delegate = mockDelegate

        vm.didSelectChat(at: -1)

        XCTAssertTrue(mockDelegate.selectedChats.isEmpty)
    }

    func testDidSelectViewAllCallsDelegate() {
        let vm = AIChatRecentChatsPopupViewModel(suggestions: makeSuggestions(count: 5), hasMore: true)
        let mockDelegate = MockDelegate()
        vm.delegate = mockDelegate

        vm.didSelectViewAll()

        XCTAssertEqual(mockDelegate.viewAllCallCount, 1)
    }

    func testDidDismissCallsDelegate() {
        let vm = AIChatRecentChatsPopupViewModel(suggestions: makeSuggestions(count: 1), hasMore: false)
        let mockDelegate = MockDelegate()
        vm.delegate = mockDelegate

        vm.didDismiss()

        XCTAssertEqual(mockDelegate.dismissCallCount, 1)
    }

    // MARK: - fetch() Tests

    func testFetchReturnsNilWhenReaderIsNil() async {
        let result = await AIChatRecentChatsPopupViewModel.fetch(using: nil)
        XCTAssertNil(result)
    }

    func testFetchReturnsNilWhenNoSuggestions() async {
        let reader = MockSuggestionsReader()

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
