//
//  ScoringService.swift
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

import Foundation
import Common

struct ScoringService  {

    /// Scores a suggestion based on the query and the suggestion's title and URL.
    ///
    /// - Parameters:
    ///   - title: The title of the suggestion, which can be `nil`.
    ///   - url: The URL of the suggestion.
    ///   - visitCount: The number of times the History Record suggestion has been visited. Defaults to 0 for other type of suggestions.
    ///   - lowercasedQuery: The query string entered by user, which should be in lowercase.
    ///   - queryTokens: An optional array of precomputed query tokens (`lowercasedQuery.tokenized()`). If `nil`, tokens will be computed.
    ///
    /// - Returns: An integer score representing how well the suggestion matches the query.
    static func score(title: String?, url: URL, visitCount: Int = 0, lowercasedQuery lowerQuery: String, queryTokens: [String]? = nil) -> Int { // swiftlint:disable:this cyclomatic_complexity
        // To optimize, query tokens can be precomputed
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
        } else if queryCount > 2 && lowercasedTitle.contains(" \(lowerQuery)") { // Exact match from the begining of the word within string.
            score += 100
        } else {
            // Tokenized matches
            if queryTokens.count > 1 {
                var matchesAllTokens = true
                for token in queryTokens {
                    // Match only from the begining of the word to avoid unintuitive matches.
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
                        } else if lowercasedTitle.leadingBoundaryStartsWith(firstToken) { // begining of the title - moderate score boost
                            score += 50
                        }
                    }
                }
            }
        }

        if score > 0 {
            // Second sort based on visitCount
            score *= 1000
            score += visitCount
        }

        return score
    }

    static func score(bookmark: Bookmark, lowercasedQuery: String, queryTokens: [String]? = nil) -> Int {
        guard let urlObject = URL(string: bookmark.url) else {
            return 0
        }
        return score(title: bookmark.title, url: urlObject, visitCount: 0, lowercasedQuery: lowercasedQuery, queryTokens: queryTokens)
    }

    static func score(historyEntry: HistorySuggestion, lowercasedQuery: String, queryTokens: [String]? = nil) -> Int {
        return score(title: historyEntry.title ?? "",
                     url: historyEntry.url,
                     visitCount: historyEntry.numberOfVisits,
                     lowercasedQuery: lowercasedQuery,
                     queryTokens: queryTokens)
    }

    static func score(internalPage: InternalPage, lowercasedQuery: String, queryTokens: [String]? = nil) -> Int {
        return score(title: internalPage.title, url: internalPage.url, visitCount: 0, lowercasedQuery: lowercasedQuery, queryTokens: queryTokens)
    }

    static func score(browserTab: BrowserTab, lowercasedQuery: String, queryTokens: [String]? = nil) -> Int {
        return score(title: browserTab.title, url: browserTab.url, visitCount: 0, lowercasedQuery: lowercasedQuery, queryTokens: queryTokens)
    }

}

extension String {

    /// Splits the search query into tokens (separate words).
    func tokenized() -> [String] {
        components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    }

    /// e.g. "Cats and Dogs" would match `Cats` or `"Cats`
    func leadingBoundaryStartsWith(_ s: String) -> Bool {
        return starts(with: s) || trimmingCharacters(in: .alphanumerics.inverted).starts(with: s)
    }

}
