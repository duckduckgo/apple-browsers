//
//  UnifiedSuggestionsInputsMerger.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import Foundation

/// Merges the per-surface facts (search + optional duck.ai) and the current mode/text into
/// the single `UnifiedSuggestionsInputs` the resolver consumes. Pure — no UIKit, no managers —
/// so the single host can drive both surfaces from one inputs publisher.
enum UnifiedSuggestionsInputsMerger {

    struct SearchFacts: Equatable {
        let hasFavorites: Bool
        let hasMessages: Bool
    }

    struct DuckAIFacts: Equatable {
        let hasRecents: Bool
        /// Both duck.ai fetchers (chat + url) have completed for the current query.
        let settled: Bool
    }

    /// `duckAI` is nil when the duck.ai source isn't installed (its lazy lifecycle), which the
    /// resolver treats as no recents and nothing pending.
    static func merge(mode: TextEntryMode,
                      text: String,
                      search: SearchFacts,
                      duckAI: DuckAIFacts?) -> UnifiedSuggestionsInputs {
        let isTyping = !text.isEmpty
        switch mode {
        case .search:
            return UnifiedSuggestionsInputs(
                mode: .search,
                isTyping: isTyping,
                hasFavorites: search.hasFavorites,
                hasMessages: search.hasMessages,
                hasRecents: false,
                resultsPending: false
            )
        case .aiChat:
            return UnifiedSuggestionsInputs(
                mode: .aiChat,
                isTyping: isTyping,
                hasFavorites: false,
                hasMessages: false,
                hasRecents: duckAI?.hasRecents ?? false,
                resultsPending: isTyping && (duckAI.map { !$0.settled } ?? false)
            )
        }
    }
}
