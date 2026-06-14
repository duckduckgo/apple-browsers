//
//  DuckAISuggestionsSelectionTests.swift
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

import AIChat
import Combine
import Suggestions
import XCTest
@testable import DuckDuckGo

@MainActor
final class DuckAISuggestionsSelectionTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func tearDown() { cancellables.removeAll(); super.tearDown() }

    // MARK: - Helpers

    private func makeSource(chats: [AIChatSuggestion] = [],
                            urls: [Suggestion] = [],
                            query: String = "") -> DuckAISuggestionsSource {
        let chatViewModel = AIChatSuggestionsViewModel()
        chatViewModel.setChats(pinned: [], recent: chats)

        let urlLoader = DuckAIURLSuggestionsLoader(dataSource: StubSuggestionLoadingDataSource())
        urlLoader.publishURLsForTesting(urls)

        let chatManager = AIChatHistoryManager(
            suggestionsReader: NilSuggestionsReader(),
            aiChatSettings: MockAIChatSettingsProvider(),
            aiChatDeleter: StubAIChatDeleter(),
            viewModel: chatViewModel,
            isFireTab: false
        )

        let source = DuckAISuggestionsSource(
            chatViewModel: chatViewModel,
            urlLoader: urlLoader,
            chatManager: chatManager,
            query: { query }
        )
        // Drain one emission so internal state is current.
        source.sectionsPublisher.sink { _ in }.store(in: &cancellables)
        return source
    }

    // MARK: - Tests

    func test_resolvesChatRowToChatSelection() {
        let chat = AIChatSuggestion(id: "abc", title: "Hi", isPinned: false, chatId: "c1")
        let source = makeSource(chats: [chat], query: "")
        XCTAssertEqual(source.selection(forRowID: "chat-abc"), .chat(chat))
    }

    func test_resolvesURLRowToURLSelection() {
        let url = URL(string: "https://swift.org")!
        let suggestion = Suggestion.website(url: url)
        let source = makeSource(urls: [suggestion], query: "sw")
        XCTAssertEqual(source.selection(forRowID: "urls-website-\(url.absoluteString)"), .url(suggestion))
    }

    func test_resolvesSearchRowToSearchSelection() {
        let source = makeSource(query: "weather")
        XCTAssertEqual(source.selection(forRowID: "search-searchDuckDuckGo"), .searchDuckDuckGo("weather"))
    }

    func test_unknownRowIDResolvesToNil() {
        let source = makeSource(query: "")
        XCTAssertNil(source.selection(forRowID: "does-not-exist"))
    }
}

// MARK: - Stubs

private final class StubSuggestionLoadingDataSource: SuggestionLoadingDataSource {
    var platform: Platform { .mobile }
    func history(for suggestionLoading: SuggestionLoading) -> [HistorySuggestion] { [] }
    func bookmarks(for suggestionLoading: SuggestionLoading) -> [Bookmark] { [] }
    func internalPages(for suggestionLoading: SuggestionLoading) -> [InternalPage] { [] }
    func openTabs(for suggestionLoading: SuggestionLoading) -> [BrowserTab] { [] }
    func suggestionLoading(_ suggestionLoading: SuggestionLoading,
                           suggestionDataFromUrl url: URL,
                           withParameters parameters: [String: String],
                           completion: @escaping (Data?, Error?) -> Void) {}
}

@MainActor
private struct StubAIChatDeleter: AIChatDeleting {
    func deleteChat(chatID: String, isFireMode: Bool) async -> Result<Void, Error> { .success(()) }
    func scheduleSync() {}
}
