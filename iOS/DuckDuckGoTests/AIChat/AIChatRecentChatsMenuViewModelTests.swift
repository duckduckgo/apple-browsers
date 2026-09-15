//
//  AIChatRecentChatsMenuViewModelTests.swift
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
final class AIChatRecentChatsMenuViewModelTests: XCTestCase {

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

    // MARK: - Initialization Tests

    func testInitWithEmptySuggestions() {
        let vm = AIChatRecentChatsMenuViewModel(suggestions: [])

        XCTAssertTrue(vm.suggestions.isEmpty)
    }

    func testInitWithSuggestions() {
        let suggestions = makeSuggestions(count: 3)
        let vm = AIChatRecentChatsMenuViewModel(suggestions: suggestions)

        XCTAssertEqual(vm.suggestions.count, 3)
    }

    func testInitCapsAtMaxVisibleChats() {
        let suggestions = makeSuggestions(count: 10)
        let vm = AIChatRecentChatsMenuViewModel(suggestions: suggestions)

        XCTAssertEqual(vm.suggestions.count, AIChatRecentChatsMenuViewModel.maxVisibleChats)
    }

    // MARK: - Pinned vs Regular Tests

    func testPinnedSuggestionPreservesFlag() {
        let pinned = AIChatSuggestion(id: "1", title: "Pinned", isPinned: true, chatId: "c1")
        let regular = AIChatSuggestion(id: "2", title: "Regular", isPinned: false, chatId: "c2")
        let vm = AIChatRecentChatsMenuViewModel(suggestions: [pinned, regular])

        XCTAssertTrue(vm.suggestions[0].isPinned)
        XCTAssertFalse(vm.suggestions[1].isPinned)
    }

    // MARK: - Action Tests

    // MARK: - fetch() Tests

    func testFetchReturnsNilWhenReaderIsNil() async {
        let result = await AIChatRecentChatsMenuViewModel.fetch(using: nil)
        XCTAssertNil(result)
    }

    func testFetchReturnsViewModelWhenNoSuggestions() async {
        let reader = MockSuggestionsReader()

        let result = await AIChatRecentChatsMenuViewModel.fetch(using: reader)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.suggestions.isEmpty ?? false)
        XCTAssertEqual(reader.fetchCallCount, 1)
    }

    func testFetchReturnsViewModelWithSuggestions() async {
        let reader = MockSuggestionsReader()
        reader.recentToReturn = makeSuggestions(count: 3)

        let result = await AIChatRecentChatsMenuViewModel.fetch(using: reader)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.suggestions.count, 3)
    }

    func testFetchRequestsMaxPlusOneToDetectMore() async {
        let reader = MockSuggestionsReader()
        reader.recentToReturn = makeSuggestions(count: 3)

        _ = await AIChatRecentChatsMenuViewModel.fetch(using: reader)

        XCTAssertEqual(reader.lastMaxChats, AIChatRecentChatsMenuViewModel.maxVisibleChats + 1)
    }

    func testFetchCapsAtMaxVisibleChats() async {
        let reader = MockSuggestionsReader()
        reader.recentToReturn = makeSuggestions(count: AIChatRecentChatsMenuViewModel.maxVisibleChats + 1)

        let result = await AIChatRecentChatsMenuViewModel.fetch(using: reader)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.suggestions.count, AIChatRecentChatsMenuViewModel.maxVisibleChats)
    }

    func testFetchCombinesPinnedAndRecent() async {
        let reader = MockSuggestionsReader()
        reader.pinnedToReturn = [
            AIChatSuggestion(id: "p1", title: "Pinned Chat", isPinned: true, chatId: "pinned-1")
        ]
        reader.recentToReturn = [
            AIChatSuggestion(id: "r1", title: "Recent Chat", isPinned: false, chatId: "recent-1")
        ]

        let result = await AIChatRecentChatsMenuViewModel.fetch(using: reader)

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
