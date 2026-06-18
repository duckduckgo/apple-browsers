//
//  SearchSuggestionsSource.swift
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

import Combine
import Suggestions

/// Search-typing source: maps `SuggestionResult` categories to unified sections,
/// porting `AutocompleteViewModel.updateSuggestions` semantics. History rows expose delete.
@MainActor
final class SearchSuggestionsSource: SuggestionsSource {

    let sectionsPublisher: AnyPublisher<[SuggestionSection], Never>

    private let loader: SearchSuggestionsLoader
    private let query: () -> String
    private let showAskAIChat: Bool

    init(loader: SearchSuggestionsLoader,
         query: @escaping () -> String,
         showAskAIChat: Bool) {
        self.loader = loader
        self.query = query
        self.showAskAIChat = showAskAIChat
        let showChat = showAskAIChat
        sectionsPublisher = loader.$result
            .map { result in Self.sections(from: result, query: query(), showAskAIChat: showChat) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func start(textPublisher: AnyPublisher<String, Never>) {
        loader.subscribeToTextChanges(textPublisher)
    }

    func tearDown() {
        loader.tearDown()
    }

    // MARK: - Section mapping

    /// The top-hits actually shown: the result's hits, or a single phrase fallback (the query itself)
    /// when every category is empty — mirrors `AutocompleteViewModel`. Display and row resolution both
    /// use this so the fallback row stays tappable (resolving against the raw, empty result returned nil).
    private static func effectiveTopHits(from result: SuggestionResult, query: String) -> [Suggestion] {
        guard result.topHits.isEmpty, result.duckduckgoSuggestions.isEmpty, result.localSuggestions.isEmpty, !query.isEmpty
        else { return result.topHits }
        return [.phrase(phrase: query)]
    }

    static func sections(from result: SuggestionResult, query: String, showAskAIChat: Bool) -> [SuggestionSection] {
        var sections: [SuggestionSection] = []

        func section(_ id: String, _ suggestions: [Suggestion]) {
            guard !suggestions.isEmpty else { return }
            sections.append(SuggestionSection(
                id: id,
                rows: suggestions.map { SuggestionRowMapper.row(for: $0, query: query, idPrefix: id, includesDeleteAccessory: true) }))
        }

        section("topHits", effectiveTopHits(from: result, query: query))
        section("ddg", result.duckduckgoSuggestions)
        section("local", result.localSuggestions)
        if showAskAIChat, !query.isEmpty {
            section("askAIChat", [.askAIChat(value: query)])
        }
        return sections
    }

    // MARK: - Row resolution

    /// Resolves a row id back to its `Suggestion` (across all categories).
    func suggestion(forRowID id: String) -> Suggestion? {
        Self.suggestion(forRowID: id, in: loader.result, query: query())
    }

    static func suggestion(forRowID id: String, in result: SuggestionResult, query: String) -> Suggestion? {
        let all = effectiveTopHits(from: result, query: query) + result.duckduckgoSuggestions + result.localSuggestions
        for prefix in ["topHits", "ddg", "local"] {
            if let match = all.first(where: { SuggestionRowMapper.row(for: $0, query: query, idPrefix: prefix, includesDeleteAccessory: true).id == id }) {
                return match
            }
        }
        if id == "askAIChat-askAIChat-\(query)" { return .askAIChat(value: query) }
        return nil
    }
}
