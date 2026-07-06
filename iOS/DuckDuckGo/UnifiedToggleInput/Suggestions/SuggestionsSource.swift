//
//  SuggestionsSource.swift
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

/// Produces the unified sections for one list presentation. Conformers wrap an existing
/// data source and map its output to `[SuggestionSection]`.
@MainActor
protocol SuggestionsSource {
    var sectionsPublisher: AnyPublisher<[SuggestionSection], Never> { get }
    func start(textPublisher: AnyPublisher<String, Never>)
    func tearDown()
}

/// Duck.ai-typing source: recents + URL hits + a "Search DuckDuckGo" row.
@MainActor
final class DuckAISuggestionsSource: SuggestionsSource {

    let sectionsPublisher: AnyPublisher<[SuggestionSection], Never>

    private let chatViewModel: AIChatSuggestionsViewModel
    private let urlLoader: DuckAIURLSuggestionsLoader
    private let chatManager: AIChatHistoryManager
    private let query: () -> String
    /// Gates the URL-hits sub-source only (the "Search Suggestions" setting); chat history is unaffected.
    private let searchSuggestionsEnabled: () -> Bool

    init(chatViewModel: AIChatSuggestionsViewModel,
         urlLoader: DuckAIURLSuggestionsLoader,
         chatManager: AIChatHistoryManager,
         query: @escaping () -> String,
         deleteEnabled: @escaping () -> Bool = { false },
         viewAllChatsEnabled: @escaping () -> Bool = { false },
         searchSuggestionsEnabled: @escaping () -> Bool = { true }) {
        self.chatViewModel = chatViewModel
        self.urlLoader = urlLoader
        self.chatManager = chatManager
        self.query = query
        self.searchSuggestionsEnabled = searchSuggestionsEnabled

        let pipeline = DuckAISuggestionsPipeline(
            chatsPublisher: chatViewModel.$filteredSuggestions.eraseToAnyPublisher(),
            urlsPublisher: urlLoader.$topURLs.eraseToAnyPublisher(),
            latestDispatchedQuery: query,
            lastCompletedURLQuery: { [weak urlLoader] in urlLoader?.lastCompletedFetchQuery ?? "" }
        )

        sectionsPublisher = pipeline.snapshotPublisher
            .map { snapshot in Self.sections(from: snapshot, query: query(), deleteEnabled: deleteEnabled(), viewAllChatsEnabled: viewAllChatsEnabled()) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func start(textPublisher: AnyPublisher<String, Never>) {
        chatManager.subscribeToTextChanges(textPublisher)
        // Empty when "Search Suggestions" is off, so URL hits are suppressed without touching chat history.
        let urlTextPublisher = textPublisher
            .map { [searchSuggestionsEnabled] text in searchSuggestionsEnabled() ? text : "" }
            .removeDuplicates()
            .eraseToAnyPublisher()
        urlLoader.subscribeToTextChanges(urlTextPublisher)
        chatManager.refreshSuggestions(query: query())
    }

    func tearDown() {
        chatManager.tearDown()
        urlLoader.tearDown()
    }

    // MARK: - Section mapping

    private enum SectionID {
        static let chats = "chats"
        static let urls = "urls"
        static let search = "search"
    }

    /// Row-id prefixes/ids minted by `SuggestionRowMapper`, parsed back in `selection(forRowID:)`.
    private enum RowID {
        static let chatPrefix = "chat-"
        static let urlsPrefix = SectionID.urls + "-"
        static let searchDuckDuckGo = SectionID.search + "-searchDuckDuckGo"
        static let viewAllChats = "view-all-chats"
    }

    static func sections(from snapshot: DuckAISuggestionsPipeline.Snapshot, query: String, deleteEnabled: Bool = false, viewAllChatsEnabled: Bool = false) -> [SuggestionSection] {
        var sections: [SuggestionSection] = []
        if !snapshot.chats.isEmpty {
            var chatRows = snapshot.chats.map { SuggestionRowMapper.row(for: $0, includesFireDelete: deleteEnabled) }
            // Append the "View all chats" entry when browsing recents; hide it while the user is searching.
            if viewAllChatsEnabled && query.isEmpty {
                chatRows.append(SuggestionRowMapper.viewAllChatsRow(id: RowID.viewAllChats))
            }
            sections.append(SuggestionSection(id: SectionID.chats, rows: chatRows))
        }
        if !snapshot.urls.isEmpty {
            sections.append(SuggestionSection(
                id: SectionID.urls,
                rows: snapshot.urls.map { SuggestionRowMapper.row(for: $0, query: query, idPrefix: SectionID.urls, includesDeleteAccessory: deleteEnabled) }))
        }
        if !query.isEmpty {
            sections.append(SuggestionSection(
                id: SectionID.search,
                rows: [SuggestionRowMapper.searchRow(query: query, idPrefix: SectionID.search)]))
        }
        return sections
    }

    // MARK: - Selection resolution

    /// Resolves a row id (as minted by `SuggestionRowMapper`) back to a typed selection.
    func selection(forRowID id: String) -> DuckAISuggestionsSelection? {
        let chats = chatViewModel.filteredSuggestions
        let urls = urlLoader.topURLs
        let q = query()

        if id == RowID.viewAllChats {
            return .viewAllChats
        }
        if id.hasPrefix(RowID.chatPrefix) {
            let chatID = String(id.dropFirst(RowID.chatPrefix.count))
            return chats.first { $0.id == chatID }.map { .chat($0) }
        }
        if id == RowID.searchDuckDuckGo {
            return .searchDuckDuckGo(q)
        }
        if id.hasPrefix(RowID.urlsPrefix) {
            return urls.first { SuggestionRowMapper.row(for: $0, query: q, idPrefix: SectionID.urls).id == id }
                .map { .url($0) }
        }
        return nil
    }

    /// Triggers a fresh URL suggestions fetch; call after a history deletion.
    func fetchURLSuggestions(query: String) {
        urlLoader.fetch(query: query)
    }

    /// Deletes a recent-chat suggestion via the backing chat manager (after delete confirmation).
    func deleteChat(_ chat: AIChatSuggestion) {
        chatManager.deleteChatSuggestion(suggestion: chat)
    }
}

/// Duck.ai-empty source: a single section of recent chats.
@MainActor
final class RecentsSuggestionsSource: SuggestionsSource {

    let sectionsPublisher: AnyPublisher<[SuggestionSection], Never>

    init(viewModel: AIChatSuggestionsViewModel) {
        sectionsPublisher = viewModel.$filteredSuggestions
            .map { chats in
                guard !chats.isEmpty else { return [] }
                return [SuggestionSection(id: "recents",
                                          rows: chats.map { SuggestionRowMapper.row(for: $0) })]
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func start(textPublisher: AnyPublisher<String, Never>) {}
    func tearDown() {}
}

/// Empty placeholder for a `.list` presentation that has no backing data (e.g. Duck.ai suggestions
/// disabled or not yet attached) — keeps the list mounted without borrowing another mode's rows.
@MainActor
final class EmptySuggestionsSource: SuggestionsSource {
    let sectionsPublisher: AnyPublisher<[SuggestionSection], Never> = Just([]).eraseToAnyPublisher()
    func start(textPublisher: AnyPublisher<String, Never>) {}
    func tearDown() {}
}
