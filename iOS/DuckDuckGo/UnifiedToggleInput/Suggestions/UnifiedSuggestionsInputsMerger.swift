//
//  UnifiedSuggestionsInputsMerger.swift
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

import Foundation

/// Merges the per-surface facts (search + optional duck.ai) and the current mode/text into
/// the single `UnifiedSuggestionsInputs` the resolver consumes. Pure — no UIKit, no managers —
/// so the single host can drive both surfaces from one inputs publisher.
enum UnifiedSuggestionsInputsMerger {

    struct SearchState: Equatable {
        let hasFavorites: Bool
        let hasMessages: Bool
    }

    struct DuckAIState: Equatable {
        let hasRecents: Bool
        /// Both duck.ai fetchers (chat + url) have completed for the current query.
        let settled: Bool
    }

    /// `duckAI` is nil when the duck.ai source isn't installed (its lazy lifecycle), which the
    /// resolver treats as no recents and nothing pending.
    /// A pre-filled, unedited URL stays in the not-typing state (favorites until the user edits),
    /// mirroring `SuggestionTrayManager.shouldDisplaySuggestionTray`.
    /// Whether the user is actively typing a query. A pre-filled, unedited URL counts as not typing
    /// (mirrors `SuggestionTrayManager.shouldDisplaySuggestionTray`). Shared so any consumer keying
    /// off the not-typing state (e.g. the escape hatch) uses the same rule as the resolver.
    static func isTyping(text: String, hasUserInteractedWithText: Bool) -> Bool {
        let isURL = URL.isValidAddressBarURLInput(text)
        return !text.isEmpty && (!isURL || hasUserInteractedWithText)
    }

    static func merge(mode: TextEntryMode,
                      text: String,
                      hasUserInteractedWithText: Bool,
                      search: SearchState,
                      duckAI: DuckAIState?) -> UnifiedSuggestionsInputs {
        let isTyping = isTyping(text: text, hasUserInteractedWithText: hasUserInteractedWithText)
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
