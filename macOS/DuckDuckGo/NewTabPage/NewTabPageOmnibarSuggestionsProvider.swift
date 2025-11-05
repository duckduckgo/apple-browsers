//
//  NewTabPageOmnibarSuggestionsProvider.swift
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
import os.log

final class NewTabPageOmnibarSuggestionsProvider: NewTabPageOmnibarSuggestionsProviding {

    let suggestionContainer: SuggestionContainerProtocol

    init(suggestionContainer: SuggestionContainerProtocol) {
        self.suggestionContainer = suggestionContainer
    }

    func suggestions(for term: String) async -> NewTabPageDataModel.Suggestions {
        await withCheckedContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(returning: .empty)
                return
            }
            self.suggestionContainer.getSuggestions(for: term, useCachedData: false) { result in
                guard let result else {
                    Logger.newTabPageOmnibar.error("Failed to get suggestions")
                    continuation.resume(returning: .empty)
                    return
                }
                continuation.resume(returning: result.asNewTabPageSuggestions)
            }
        }
    }

}

private extension SuggestionResult {

    var asNewTabPageSuggestions: NewTabPageDataModel.Suggestions {
        .init(
            topHits: topHits.asNewTabPageSuggestions,
            duckduckgoSuggestions: duckduckgoSuggestions.asNewTabPageSuggestions,
            localSuggestions: localSuggestions.asNewTabPageSuggestions
        )
    }

}

extension Suggestion {

    var newTabPageSuggestion: NewTabPageDataModel.Suggestion? {
        switch self {
        case .phrase(let phrase):
            return .phrase(phrase: phrase)
        case .website(let url):
            return .website(url: url.absoluteString)
        case .bookmark(let title, let url, let isFavorite, let score):
            return .bookmark(title: title, url: url.absoluteString, isFavorite: isFavorite, score: score)
        case .historyEntry(let title, let url, let score):
            return .historyEntry(title: title, url: url.absoluteString, score: score)
        case .internalPage(let title, let url, let score):
            return .internalPage(title: title, url: url.absoluteString, score: score)
        case .openTab(let title, _, let tabId, let score):
            return .openTab(title: title, tabId: tabId, score: score)
        case .unknown, .askAIChat:
            return nil
        }
    }

}

private extension Array where Element == Suggestion {

    var asNewTabPageSuggestions: [NewTabPageDataModel.Suggestion] {
        compactMap { $0.newTabPageSuggestion }
    }

}
