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

        let urlLoader = DuckAIURLSuggestionsLoader(dataSource: StubSuggestionLoadingDataSource(), featureFlagger: MockFeatureFlagger())
        urlLoader.publishURLsForTesting(urls)

        let chatManager = AIChatHistoryManager(
            suggestionsReader: NilSuggestionsReader(),
            aiChatDeleter: StubAIChatDeleter(),
            viewModel: chatViewModel,
            isFireTab: false
        )

        let source = DuckAISuggestionsSource(
            chatViewModel: chatViewModel,
            urlLoader: urlLoader,
            chatManager: chatManager,
            query: { query },
            searchSuggestionsEnabled: { true },
            chatSuggestionsEnabled: { true }
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

    // MARK: - "Search DuckDuckGo" row word cap

    private func words(_ count: Int, separator: String = " ") -> String {
        (1...count).map { "word\($0)" }.joined(separator: separator)
    }

    private func sectionIDs(for query: String, snapshot: DuckAISuggestionsPipeline.Snapshot) -> [String] {
        DuckAISuggestionsSource.sections(from: snapshot, query: query).map(\.id)
    }

    func test_searchRow_showsAtFifteenWords_andHidesFromSixteenth_leavingOtherSectionsUnchanged() {
        let chat = AIChatSuggestion(id: "abc", title: "Hi", isPinned: false, chatId: "c1")
        let snapshot = DuckAISuggestionsPipeline.Snapshot(
            chats: [chat], urls: [.website(url: URL(string: "https://swift.org")!)], isPending: false)

        let fifteen = DuckAISuggestionsSource.sections(from: snapshot, query: words(15))
        let sixteen = DuckAISuggestionsSource.sections(from: snapshot, query: words(16))

        XCTAssertEqual(fifteen.map(\.id), ["chats", "urls", "search"])
        XCTAssertEqual(sixteen.map(\.id), ["chats", "urls"])
        XCTAssertEqual(fifteen.first { $0.id == "chats" }, sixteen.first { $0.id == "chats" })
    }

    func test_searchRow_countsWordsAcrossAnyWhitespace() {
        let empty = DuckAISuggestionsPipeline.Snapshot(chats: [], urls: [], isPending: false)
        for separator in ["  ", "\n", "\t", " \n "] {
            XCTAssertEqual(sectionIDs(for: words(15, separator: separator), snapshot: empty), ["search"], "separator \(separator.debugDescription)")
            XCTAssertEqual(sectionIDs(for: words(16, separator: separator), snapshot: empty), [], "separator \(separator.debugDescription)")
        }
        XCTAssertEqual(sectionIDs(for: "  " + words(15) + " \n", snapshot: empty), ["search"])
        XCTAssertEqual(sectionIDs(for: "  " + words(16) + " \n", snapshot: empty), [])
    }

    func test_searchRow_isAbsentForEmptyQuery() {
        let empty = DuckAISuggestionsPipeline.Snapshot(chats: [], urls: [], isPending: false)
        XCTAssertEqual(sectionIDs(for: "", snapshot: empty), [])
    }

    /// With both settings off the fetchers never emit, so only the typed text can move the row.
    func test_searchRow_followsTypedText_whenFetchersStaySilent() {
        let chatViewModel = AIChatSuggestionsViewModel()
        let source = DuckAISuggestionsSource(
            chatViewModel: chatViewModel,
            urlLoader: DuckAIURLSuggestionsLoader(dataSource: StubSuggestionLoadingDataSource(), featureFlagger: MockFeatureFlagger()),
            chatManager: AIChatHistoryManager(suggestionsReader: NilSuggestionsReader(),
                                              aiChatDeleter: StubAIChatDeleter(),
                                              viewModel: chatViewModel,
                                              isFireTab: false),
            query: { "" },
            searchSuggestionsEnabled: { false },
            chatSuggestionsEnabled: { false }
        )
        var latest: [SuggestionSection] = []
        source.sectionsPublisher.sink { latest = $0 }.store(in: &cancellables)
        let textSubject = PassthroughSubject<String, Never>()
        source.start(textPublisher: textSubject.eraseToAnyPublisher())

        textSubject.send(words(15))
        XCTAssertEqual(latest, DuckAISuggestionsSource.sections(
            from: .init(chats: [], urls: [], isPending: false), query: words(15)))
        XCTAssertEqual(latest.map(\.id), ["search"])

        textSubject.send(words(16))
        XCTAssertEqual(latest.map(\.id), [])

        textSubject.send(words(15))
        XCTAssertEqual(latest.map(\.id), ["search"])
    }

    // MARK: - Search Suggestions gating

    func test_urlHits_areSuppressed_whenSearchSuggestionsDisabled() async {
        let urlLoader = DuckAIURLSuggestionsLoader(dataSource: StubSuggestionLoadingDataSource(), featureFlagger: MockFeatureFlagger())
        let chatViewModel = AIChatSuggestionsViewModel()
        let chatManager = AIChatHistoryManager(
            suggestionsReader: NilSuggestionsReader(),
            aiChatDeleter: StubAIChatDeleter(),
            viewModel: chatViewModel,
            isFireTab: false
        )
        let source = DuckAISuggestionsSource(
            chatViewModel: chatViewModel,
            urlLoader: urlLoader,
            chatManager: chatManager,
            query: { "hotmail" },
            searchSuggestionsEnabled: { false },
            chatSuggestionsEnabled: { true }
        )
        let textSubject = PassthroughSubject<String, Never>()
        source.start(textPublisher: textSubject.eraseToAnyPublisher())
        textSubject.send("hotmail")

        let predicate = NSPredicate { _, _ in urlLoader.lastCompletedFetchQuery != nil }
        await fulfillment(of: [expectation(for: predicate, evaluatedWith: nil)], timeout: 5.0)

        XCTAssertEqual(urlLoader.lastCompletedFetchQuery, "")
        XCTAssertTrue(urlLoader.topURLs.isEmpty)
    }

    func test_urlHits_fetch_whenSearchSuggestionsEnabled() async {
        let urlLoader = DuckAIURLSuggestionsLoader(dataSource: StubSuggestionLoadingDataSource(), featureFlagger: MockFeatureFlagger())
        let chatViewModel = AIChatSuggestionsViewModel()
        let chatManager = AIChatHistoryManager(
            suggestionsReader: NilSuggestionsReader(),
            aiChatDeleter: StubAIChatDeleter(),
            viewModel: chatViewModel,
            isFireTab: false
        )
        let source = DuckAISuggestionsSource(
            chatViewModel: chatViewModel,
            urlLoader: urlLoader,
            chatManager: chatManager,
            query: { "hotmail" },
            searchSuggestionsEnabled: { true },
            chatSuggestionsEnabled: { true }
        )
        let textSubject = PassthroughSubject<String, Never>()
        source.start(textPublisher: textSubject.eraseToAnyPublisher())
        textSubject.send("hotmail")

        let predicate = NSPredicate { _, _ in urlLoader.lastCompletedFetchQuery != nil }
        await fulfillment(of: [expectation(for: predicate, evaluatedWith: nil)], timeout: 5.0)

        XCTAssertEqual(urlLoader.lastCompletedFetchQuery, "hotmail")
    }

    // MARK: - Chat Suggestions gating

    func test_chatHistory_isSuppressed_whenChatSuggestionsDisabled() async {
        let urlLoader = DuckAIURLSuggestionsLoader(dataSource: StubSuggestionLoadingDataSource(), featureFlagger: MockFeatureFlagger())
        let chatViewModel = AIChatSuggestionsViewModel()
        let chatManager = AIChatHistoryManager(
            suggestionsReader: NilSuggestionsReader(),
            aiChatDeleter: StubAIChatDeleter(),
            viewModel: chatViewModel,
            isFireTab: false
        )
        let source = DuckAISuggestionsSource(
            chatViewModel: chatViewModel,
            urlLoader: urlLoader,
            chatManager: chatManager,
            query: { "" },
            searchSuggestionsEnabled: { true },
            chatSuggestionsEnabled: { false }
        )
        let textSubject = PassthroughSubject<String, Never>()
        source.start(textPublisher: textSubject.eraseToAnyPublisher())
        textSubject.send("recipes")

        // Wait past the chat manager's 150ms text debounce; a running fetch would set the query.
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertNil(chatManager.lastCompletedFetchQuery)
    }

    func test_chatHistory_fetches_whenChatSuggestionsEnabled() async {
        let urlLoader = DuckAIURLSuggestionsLoader(dataSource: StubSuggestionLoadingDataSource(), featureFlagger: MockFeatureFlagger())
        let chatViewModel = AIChatSuggestionsViewModel()
        let chatManager = AIChatHistoryManager(
            suggestionsReader: NilSuggestionsReader(),
            aiChatDeleter: StubAIChatDeleter(),
            viewModel: chatViewModel,
            isFireTab: false
        )
        let source = DuckAISuggestionsSource(
            chatViewModel: chatViewModel,
            urlLoader: urlLoader,
            chatManager: chatManager,
            query: { "" },
            searchSuggestionsEnabled: { true },
            chatSuggestionsEnabled: { true }
        )
        let textSubject = PassthroughSubject<String, Never>()
        source.start(textPublisher: textSubject.eraseToAnyPublisher())

        let predicate = NSPredicate { _, _ in chatManager.lastCompletedFetchQuery != nil }
        await fulfillment(of: [expectation(for: predicate, evaluatedWith: nil)], timeout: 5.0)

        XCTAssertEqual(chatManager.lastCompletedFetchQuery, "")
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
                           completion: @escaping (Data?, Error?) -> Void) {
        // Must call completion or SuggestionLoader's DispatchGroup never leaves and getSuggestions hangs forever.
        completion(nil, nil)
    }
}

@MainActor
private struct StubAIChatDeleter: AIChatDeleting {
    func deleteChat(chatID: String, isFireMode: Bool) async -> Result<Void, Error> { .success(()) }
    func deleteChats(chatIDs: [String], isFireMode: Bool) async -> Result<Void, Error> { .success(()) }
    func deleteAllChats(isFireMode: Bool) async -> Result<Void, Error> { .success(()) }
    func scheduleSync() {}
}
