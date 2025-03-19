//
//  Score.swift
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

import Foundation
import Common

typealias Score = Int

extension Score {

    // swiftlint:disable:next cyclomatic_complexity
    init(title: String?, url: URL, visitCount: Int, query: Query, queryTokens: [Query]? = nil) {
        // To optimize, query tokens can be precomputed
        let query = query.lowercased()
        let queryTokens = queryTokens ?? Self.tokens(from: query)

        var score = 0
        let lowercasedTitle = title?.lowercased() ?? ""
        let queryCount = query.count
        let domain = url.host?.droppingWwwPrefix() ?? ""
        let nakedUrl = url.nakedString ?? ""

        // Full matches
        if nakedUrl.starts(with: query) {
            score += 300
            // Prioritize root URLs most
            if url.isRoot { score += 2000 }
        } else if lowercasedTitle.leadingBoundaryStartsWith(query) {
            score += 200
            if url.isRoot { score += 2000 }
        } else if queryCount > 2 && domain.contains(query) {
            score += 150
        } else if queryCount > 2 && lowercasedTitle.contains(" \(query)") { // Exact match from the begining of the word within string.
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

        self = score
    }

    init(bookmark: Bookmark, query: Query, queryTokens: [Query]? = nil) {
        guard let urlObject = URL(string: bookmark.url) else {
            self = 0
            return
        }
        self.init(title: bookmark.title, url: urlObject, visitCount: 0, query: query, queryTokens: queryTokens)
    }

    init(historyEntry: HistorySuggestion, query: Query, queryTokens: [Query]? = nil) {
        self.init(title: historyEntry.title ?? "",
                  url: historyEntry.url,
                  visitCount: historyEntry.numberOfVisits,
                  query: query,
                  queryTokens: queryTokens)
    }

    init(internalPage: InternalPage, query: Query, queryTokens: [Query]? = nil) {
        self.init(title: internalPage.title, url: internalPage.url, visitCount: 0, query: query, queryTokens: queryTokens)
    }

    static func tokens(from query: Query) -> [Query] {
        return query.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
    }

}

extension String {

    /// e.g. "Cats and Dogs" would match `Cats` or `"Cats`
    func leadingBoundaryStartsWith(_ s: String) -> Bool {
        return starts(with: s) || trimmingCharacters(in: .alphanumerics.inverted).starts(with: s)
    }

}
