//
//  ScoringService.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import Common
import Foundation

struct ScoringService {

    /// Scores a suggestion based on the query and the suggestion's title and url.
    static func score(title: String?, url: URL, visitCount: Int = 0, lowerQuery: String, queryTokens: [String]? = nil) -> Int {
        let queryTokens = queryTokens ?? lowerQuery.tokenized()
        assert(lowerQuery.lowercased() == lowerQuery)
        assert(queryTokens == lowerQuery.tokenized())
        assert(!queryTokens.contains(where: { $0.isEmpty }))

        var score = 0
        let lowercasedTitle = title?.lowercased() ?? ""
        let queryCount = lowerQuery.count
        let domain = url.host?.droppingWwwPrefix() ?? ""
        let nakedUrl = url.nakedString ?? ""

        // Full matches
        if nakedUrl.starts(with: lowerQuery) {
            score += 300
            // Prioritize root URLs most
            if url.isRoot { score += 2000 }
        } else if lowercasedTitle.leadingBoundaryStartsWith(lowerQuery) {
            score += 200
            if url.isRoot { score += 2000 }
        } else if queryCount > 2 && domain.contains(lowerQuery) {
            score += 150
        } else if queryCount > 2 && lowercasedTitle.contains(" \(lowerQuery)") { // Exact match from the beginning of the word within string.
            score += 100
        } else {
            // Tokenized matches
            if queryTokens.count > 1 {
                var matchesAllTokens = true
                for token in queryTokens {
                    // Match only from the beginning of the word to avoid unintuitive matches.
                    if !lowercasedTitle.leadingBoundaryStartsWith(token) && !lowercasedTitle.contains(" \(token)") && !nakedUrl.starts(with: token) {
                        matchesAllTokens = false
                        break
                    }
                }

                if matchesAllTokens {
                    // Score tokenized matches
                    score += 10

                    // Boost score if first token matches:
                    if let firstToken = queryTokens.first { // nakedUrlString - high score boost
                        if nakedUrl.starts(with: firstToken) {
                            score += 70
                        } else if lowercasedTitle.leadingBoundaryStartsWith(firstToken) { // beginning of the title - moderate score boost
                            score += 50
                        }
                    }
                }
            }
        }

        if score > 0 {
            // If there are matches, add visitCount to prioritize more visited
            score <<= 10 // Small optimization equivalent to '*= 1024'
            score += visitCount
        }

        return score
    }

    static func score(for bookmark: Bookmark, lowerQuery: String, queryTokens: [String]? = nil) -> Int {
        guard let url = URL(string: bookmark.url) else { return 0 }
        return score(title: bookmark.title, url: url, lowerQuery: lowerQuery, queryTokens: queryTokens)
    }

    static func score(for historyEntry: HistorySuggestion, lowerQuery: String, queryTokens: [String]? = nil) -> Int {
        return score(title: historyEntry.title ?? "", url: historyEntry.url, visitCount: historyEntry.numberOfVisits, lowerQuery: lowerQuery, queryTokens: queryTokens)
    }

    static func score(for internalPage: InternalPage, lowerQuery: String, queryTokens: [String]? = nil) -> Int {
        return score(title: internalPage.title, url: internalPage.url, lowerQuery: lowerQuery, queryTokens: queryTokens)
    }

    static func score(for browserTab: BrowserTab, lowerQuery: String, queryTokens: [String]? = nil) -> Int {
        return score(title: browserTab.title, url: browserTab.url, lowerQuery: lowerQuery, queryTokens: queryTokens)
    }

    static func score(for localSuggestion: SuggestionProcessing.LocalSuggestion, lowerQuery: String, queryTokens: [String]? = nil) -> Int {
        switch localSuggestion {
        case .bookmark(let bookmark):
            score(for: bookmark, lowerQuery: lowerQuery, queryTokens: queryTokens)
        case .history(let historyEntry):
            score(for: historyEntry, lowerQuery: lowerQuery, queryTokens: queryTokens)
        case .internalPage(let internalPage):
            score(for: internalPage, lowerQuery: lowerQuery, queryTokens: queryTokens)
        case .openTab(let tab):
            score(for: tab, lowerQuery: lowerQuery, queryTokens: queryTokens)
        }
    }

}

extension String {

    func tokenized() -> [String] {
        components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    }

    /// e.g. "Cats and Dogs" would match `Cats` or `"Cats`
    func leadingBoundaryStartsWith(_ s: String) -> Bool {
        return starts(with: s) || trimmingCharacters(in: .alphanumerics.inverted).starts(with: s)
    }

}
