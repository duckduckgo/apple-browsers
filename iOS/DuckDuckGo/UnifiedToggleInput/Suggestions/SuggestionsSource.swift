//
//  SuggestionsSource.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import AIChat
import Combine
import Suggestions

/// Produces the unified sections for one list presentation. Conformers wrap an existing
/// data source and map its output to `[SuggestionSection]`.
@MainActor
protocol SuggestionsSource {
    var sectionsPublisher: AnyPublisher<[SuggestionSection], Never> { get }
}

/// Duck.ai-typing source: recents + URL hits + a "Search DuckDuckGo" row.
@MainActor
final class DuckAISuggestionsSource: SuggestionsSource {

    let sectionsPublisher: AnyPublisher<[SuggestionSection], Never>

    init(snapshotPublisher: AnyPublisher<DuckAISuggestionsPipeline.Snapshot, Never>,
         query: @escaping () -> String) {
        sectionsPublisher = snapshotPublisher
            .map { snapshot in
                var sections: [SuggestionSection] = []

                if !snapshot.chats.isEmpty {
                    sections.append(SuggestionSection(
                        id: "chats",
                        rows: snapshot.chats.map { SuggestionRowMapper.row(for: $0) }))
                }
                if !snapshot.urls.isEmpty {
                    let q = query()
                    sections.append(SuggestionSection(
                        id: "urls",
                        rows: snapshot.urls.map { SuggestionRowMapper.row(for: $0, query: q, idPrefix: "urls") }))
                }
                let q = query()
                if !q.isEmpty {
                    sections.append(SuggestionSection(
                        id: "search",
                        rows: [SuggestionRowMapper.searchRow(query: q, idPrefix: "search")]))
                }
                return sections
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
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
}
