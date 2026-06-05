//
//  SearchSuggestionsSource.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import Combine
import Suggestions

/// Search-typing source: maps `SuggestionResult` categories to unified sections,
/// porting `AutocompleteViewModel.updateSuggestions` semantics. History rows expose delete.
@MainActor
final class SearchSuggestionsSource: SuggestionsSource {

    let sectionsPublisher: AnyPublisher<[SuggestionSection], Never>

    private let query: () -> String
    private let resultBox = ResultBox()

    init(resultPublisher: AnyPublisher<SuggestionResult, Never>,
         query: @escaping () -> String,
         showAskAIChat: Bool) {
        self.query = query
        let box = resultBox
        sectionsPublisher = resultPublisher
            .map { result in
                box.value = result
                let q = query()
                var sections: [SuggestionSection] = []

                func section(_ id: String, _ suggestions: [Suggestion]) {
                    guard !suggestions.isEmpty else { return }
                    sections.append(SuggestionSection(
                        id: id,
                        rows: suggestions.map { SuggestionRowMapper.row(for: $0, query: q, idPrefix: id, includesDeleteAccessory: true) }))
                }

                var topHits = result.topHits
                // Empty → single non-tap-ahead phrase fallback (mirrors AutocompleteViewModel).
                if topHits.isEmpty && result.duckduckgoSuggestions.isEmpty && result.localSuggestions.isEmpty && !q.isEmpty {
                    topHits = [.phrase(phrase: q)]
                }
                section("topHits", topHits)
                section("ddg", result.duckduckgoSuggestions)
                section("local", result.localSuggestions)
                if showAskAIChat, !q.isEmpty {
                    section("askAIChat", [.askAIChat(value: q)])
                }
                return sections
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Resolves a row id back to its `Suggestion` (across all categories).
    func suggestion(forRowID id: String) -> Suggestion? {
        let r = resultBox.value
        let all = r.topHits + r.duckduckgoSuggestions + r.localSuggestions
        let q = query()
        for prefix in ["topHits", "ddg", "local"] {
            if let match = all.first(where: { SuggestionRowMapper.row(for: $0, query: q, idPrefix: prefix, includesDeleteAccessory: true).id == id }) {
                return match
            }
        }
        if id == "askAIChat-askAIChat-\(q)" { return .askAIChat(value: q) }
        return nil
    }
}

private final class ResultBox {
    var value: SuggestionResult = .appEmpty
}
