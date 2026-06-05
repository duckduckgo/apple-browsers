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

    private let query: () -> String
    /// Reference holder recording the latest snapshot for `selection(forRowID:)`. A class lets the
    /// `map` closure (built in `init` before `self` is fully initialized) record without capturing `self`.
    private let captureBox = SnapshotBox()

    init(snapshotPublisher: AnyPublisher<DuckAISuggestionsPipeline.Snapshot, Never>,
         query: @escaping () -> String) {
        self.query = query
        let box = captureBox
        sectionsPublisher = snapshotPublisher
            .map { snapshot in
                box.value = snapshot
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
                        rows: snapshot.urls.map { SuggestionRowMapper.row(for: $0, query: q, idPrefix: "urls", includesDeleteAccessory: true) }))
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

    /// Resolves a row id (as minted by `SuggestionRowMapper`) back to a typed selection.
    func selection(forRowID id: String) -> DuckAISuggestionsSelection? {
        let snapshot = captureBox.value
        if id.hasPrefix("chat-") {
            let chatID = String(id.dropFirst("chat-".count))
            return snapshot.chats.first { $0.id == chatID }.map { .chat($0) }
        }
        if id == "search-searchDuckDuckGo" {
            return .searchDuckDuckGo(query())
        }
        if id.hasPrefix("urls-") {
            return snapshot.urls.first { SuggestionRowMapper.row(for: $0, query: query(), idPrefix: "urls").id == id }
                .map { .url($0) }
        }
        return nil
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

/// Reference holder so the section-mapping closure can record the latest snapshot
/// without capturing `self` (which isn't fully initialized when the publisher is built).
private final class SnapshotBox {
    var value = DuckAISuggestionsPipeline.Snapshot(chats: [], urls: [], isPending: false)
}
