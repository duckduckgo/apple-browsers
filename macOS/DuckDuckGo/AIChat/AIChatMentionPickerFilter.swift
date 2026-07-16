//
//  AIChatMentionPickerFilter.swift
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

/// Filtering + scoring rules for the `@`-mention tab picker.
///
/// Extracted so the rules are unit-testable without instantiating any AppKit views, and
/// so the picker view controller stays a pure renderer of a pre-filtered list.
///
/// Rules (per the planning conversation):
/// - **Case-insensitive substring match**: a tab matches if `tab.title.lowercased()` or
///   `tab.url.absoluteString.lowercased()` contains the lowercased query.
/// - **Scoring**: title match = `2`, url-only match = `1`. Higher score wins.
/// - **Stable order**: ties (same score) preserve the original input order — handy when
///   the user has e.g. several "Wikipedia" tabs and expects the first window-tab to stay
///   first.
/// - **Empty query**: returns the input list unchanged (every tab visible).
/// - **Current tab pinning**: if `currentTabId` is supplied and a matching tab survives
///   filtering, it's hoisted to index 0 — the picker always shows "(Current Tab)" on top.
///   Caller passes `nil` to opt out.
enum AIChatMentionPickerFilter {
    /// Returns the filtered + sorted tabs for the supplied query.
    static func filter(_ tabs: [AIChatTabAttachment], query: String, currentTabId: String? = nil) -> [AIChatTabAttachment] {
        let trimmedQuery = query.lowercased()
        let result: [AIChatTabAttachment]

        if trimmedQuery.isEmpty {
            result = tabs
        } else {
            struct ScoredTab {
                let tab: AIChatTabAttachment
                let score: Int
                let inputIndex: Int
            }

            let scored: [ScoredTab] = tabs.enumerated().compactMap { index, tab in
                var score = 0
                if tab.title.lowercased().contains(trimmedQuery) {
                    score += 2
                }
                if tab.url.absoluteString.lowercased().contains(trimmedQuery) {
                    score += 1
                }
                guard score > 0 else { return nil }
                return ScoredTab(tab: tab, score: score, inputIndex: index)
            }

            // Sort by score desc, then by input index asc (stable). Swift's `sorted` is not
            // guaranteed stable, so we explicitly fall back on the captured index.
            result = scored
                .sorted { lhs, rhs in
                    if lhs.score != rhs.score { return lhs.score > rhs.score }
                    return lhs.inputIndex < rhs.inputIndex
                }
                .map(\.tab)
        }

        // Pin the current tab at the top of whatever survived the filter/scoring. We do this
        // *after* scoring so the current tab only appears when it actually matches the query
        // (e.g. user types `@goog` on a non-Google current tab → "(Current Tab)" stays
        // hidden because it doesn't match). When the current tab matches, the user expects
        // it to be the obvious first choice regardless of score order.
        guard let currentTabId,
              let currentIndex = result.firstIndex(where: { $0.id == currentTabId }),
              currentIndex != 0 else {
            return result
        }
        return [result[currentIndex]] + result.prefix(currentIndex) + result.suffix(from: currentIndex + 1)
    }
}
