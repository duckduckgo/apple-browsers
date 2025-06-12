//
//  SuggestionContainer+NewTabPage.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import NewTabPage
import Suggestions

extension SuggestionContainer: NewTabPageSearchSuggestionsProviding {
    func suggestions(for term: String) async -> NewTabPageDataModel.Suggestions {
        await withCheckedContinuation { continuation in
            getSuggestions(for: term) { result in
                continuation.resume(returning: result?.newTabPageSuggestions ?? .empty)
            }
        }
    }
}

extension SuggestionResult {
    var newTabPageSuggestions: NewTabPageDataModel.Suggestions {
        .init(
            duckduckgoSuggestions: duckduckgoSuggestions.compactMap(\.newTabPageSuggestion),
            localSuggestions: localSuggestions.compactMap(\.newTabPageSuggestion),
            topHits: topHits.compactMap(\.newTabPageSuggestion)
        )
    }
}

extension Suggestion {
    var newTabPageSuggestion: NewTabPageDataModel.Suggestion? {
        switch self {
        case .phrase(phrase: let phrase):
            return .phrase(phrase: phrase)
        case .website(url: let url):
            return .website(url: url.absoluteString)
        case .bookmark(title: let title, url: let url, isFavorite: let isFavorite, score: let score):
            return .bookmark(title: title, url: url.absoluteString, isFavorite: isFavorite, score: score)
        case .historyEntry(title: let title, url: let url, score: let score):
            return .historyEntry(title: title, url: url.absoluteString, score: score)
        case .internalPage(title: let title, url: let url, score: let score):
            return .internalPage(title: title, url: url.absoluteString, score: score)
        case .openTab(title: let title, url: let url, tabId: let tabId, score: let score):
            return .openTab(title: title, url: url.absoluteString, tabId: tabId, score: score)
        case .unknown(value: let value):
            return nil
        }
    }
}
