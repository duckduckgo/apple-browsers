//
//  Suggestion+URLFilter.swift
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

import Suggestions

extension Suggestion {
    /// True for `Suggestion` cases that represent a navigable URL (websites, bookmarks,
    /// history entries, open tabs). False for search phrases, internal pages, AI-chat shortcuts.
    var isURLSuggestion: Bool {
        switch self {
        case .website, .bookmark, .historyEntry, .openTab: return true
        case .phrase, .internalPage, .unknown, .askAIChat: return false
        }
    }
}

extension SuggestionResult {
    /// Returns a copy keeping only `Suggestion`s whose `isURLSuggestion` is true.
    func filteringToURLsOnly() -> SuggestionResult {
        SuggestionResult(
            topHits: topHits.filter(\.isURLSuggestion),
            duckduckgoSuggestions: duckduckgoSuggestions.filter(\.isURLSuggestion),
            localSuggestions: localSuggestions.filter(\.isURLSuggestion)
        )
    }
}
