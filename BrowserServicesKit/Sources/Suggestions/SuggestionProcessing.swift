//
//  SuggestionProcessing.swift
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

public enum Platform {

    case mobile, desktop

}

/// Class encapsulates the whole ordering and filtering algorithm
/// It takes query, history, bookmarks, and apiResult as input parameters
/// The output is instance of SuggestionResult
final class SuggestionProcessing {

    private let platform: Platform
    private var urlFactory: (String) -> URL?

    init(platform: Platform, urlFactory: @escaping (String) -> URL?) {
        self.platform = platform
        self.urlFactory = urlFactory
    }

    func result(for query: Query,
                from history: [HistorySuggestion],
                bookmarks: [Bookmark],
                internalPages: [InternalPage],
                openTabs: [BrowserTab],
                apiResult: APIResult?) -> SuggestionResult? {
        let query = query.lowercased()

        let duckDuckGoSuggestions = (try? self.duckDuckGoSuggestions(from: apiResult)) ?? []

        // Get domain suggestions from the DuckDuckGo Suggestions section (for the Top Hits section)
        let duckDuckGoDomainSuggestions = duckDuckGoSuggestions.compactMap { suggestion -> Suggestion? in
            // The JSON response tells us explicitly what is navigational now, so we only need to find website suggestions here
            if case .website = suggestion {
                return suggestion
            }
            return nil
        }

        // Get best matches from history and bookmarks
        let allLocalSuggestions = Array(localSuggestions(from: history, bookmarks: bookmarks, internalPages: internalPages, openTabs: openTabs, query: query)
            .prefix(100)) // temporary optimsiation

        // Combine HaB and domains into navigational suggestions and remove duplicates
        let navigationalSuggestions = allLocalSuggestions + duckDuckGoDomainSuggestions

        let maximumOfNavigationalSuggestions = min(
            Self.maximumNumberOfSuggestions - Self.minimumNumberInSuggestionGroup,
            query.count + 1)
        let expandedSuggestions = replaceHistoryWithBookmarksAndTabs(navigationalSuggestions)

        let dedupedNavigationalSuggestions = Array(dedupLocalSuggestions(expandedSuggestions).prefix(maximumOfNavigationalSuggestions))

        // Split the Top Hits and the History and Bookmarks section
        let topHits = topHits(from: dedupedNavigationalSuggestions)
        let localSuggestions = Array(dedupedNavigationalSuggestions.dropFirst(topHits.count).filter { suggestion in
            switch suggestion {
            case .bookmark, .openTab, .historyEntry, .internalPage:
                return true
            default:
                return false
            }
        })

        let dedupedDuckDuckGoSuggestions = removeDuplicateWebsiteSuggestions(in: topHits, from: duckDuckGoSuggestions)

        return makeResult(topHits: topHits,
                          duckduckgoSuggestions: dedupedDuckDuckGoSuggestions,
                          localSuggestions: localSuggestions)
    }

    private func dedupLocalSuggestions(_ suggestions: [Suggestion]) -> [Suggestion] {
        return suggestions.reduce([]) { partialResult, suggestion in
            if partialResult.contains(where: {

                switch $0 {
                case .bookmark(title: let title, url: let url, isFavorite: let isFavorite, allowedInTopHits: _):
                    if case .bookmark(let searchTitle, let searchUrl, let searchIsFavorite, _) = suggestion,
                       searchTitle == title,
                       searchUrl.naked == url.naked,
                       searchIsFavorite == isFavorite {
                        return true
                    }

                case .historyEntry(title: let title, url: let url, allowedInTopHits: _):
                    if case .historyEntry(let searchTitle, let searchUrl, _) = suggestion,
                       searchTitle == title,
                       searchUrl.naked == url {
                        return true
                    }

                case .internalPage(title: let title, url: let url):
                    if case .internalPage(let searchTitle, let searchUrl) = suggestion,
                       searchTitle == title,
                       searchUrl == url {
                        return true
                    }

                case .openTab(title: let title, url: let url):
                    if case .openTab(let searchTitle, let searchUrl) = suggestion,
                       searchTitle == title,
                       searchUrl.naked == url.naked {
                        return true
                    }

                default:
                    assertionFailure("Unexpected suggestion in local suggestions")
                    return true
                }

                return false
            }) {
                return partialResult
            }
            return partialResult + [suggestion]
        }
    }

    private func replaceHistoryWithBookmarksAndTabs(_ sourceSuggestions: [Suggestion]) -> [Suggestion] {
        var expanded = [Suggestion]()
        for i in 0 ..< sourceSuggestions.count {
            let suggestion = sourceSuggestions[i]
            guard case .historyEntry = suggestion else {
                expanded.append(suggestion)
                continue
            }

            var foundTab = false
            var foundBookmark = false

            if let tab = sourceSuggestions[i ..< sourceSuggestions.endIndex].first(where: {
                $0.isOpenTab && $0.url?.naked == suggestion.url?.naked
            }) {
                foundTab = true
                expanded.append(tab)
            }

            if case .bookmark(title: let title, url: let url, isFavorite: let isFavorite, allowedInTopHits: _) = sourceSuggestions[i ..< sourceSuggestions.endIndex].first(where: {
                $0.isBookmark && $0.url?.naked == suggestion.url?.naked
            }) {
                foundBookmark = true
                expanded.append(.bookmark(title: title, url: url, isFavorite: isFavorite, allowedInTopHits: suggestion.allowedInTopHits))
            }

            if !foundTab && !foundBookmark {
                expanded.append(suggestion)
            }
        }
        return expanded
    }

    private func removeDuplicateWebsiteSuggestions(in sourceSuggestions: [Suggestion], from targetSuggestions: [Suggestion]) -> [Suggestion] {
        return targetSuggestions.compactMap { targetSuggestion in
            if case .website = targetSuggestion, sourceSuggestions.contains(where: {
                targetSuggestion == $0
            }) {
                return nil
            }
            return targetSuggestion
        }
    }

    // MARK: - DuckDuckGo Suggestions

    private func duckDuckGoSuggestions(from result: APIResult?) throws -> [Suggestion]? {
        return result?.items
            .compactMap {
                guard let phrase = $0.phrase else {
                    return nil
                }
                return Suggestion(phrase: phrase, isNav: $0.isNav ?? false)
            }
    }

    // MARK: - History and Bookmarks

    private func localSuggestions(from history: [HistorySuggestion], bookmarks: [Bookmark], internalPages: [InternalPage], openTabs: [BrowserTab], query: Query) -> [Suggestion] {
        enum LocalSuggestion {
            case bookmark(Bookmark)
            case history(HistorySuggestion)
            case internalPage(InternalPage)
            case openTab(BrowserTab)
        }
        let localSuggestions: [LocalSuggestion] = bookmarks.map(LocalSuggestion.bookmark) + openTabs.map(LocalSuggestion.openTab) + history.map(LocalSuggestion.history) + internalPages.map(LocalSuggestion.internalPage)
        let queryTokens = Score.tokens(from: query)

        let result: [Suggestion] = localSuggestions
            // Score items
            .map { item -> (item: LocalSuggestion, score: Score) in
                let score = switch item {
                case .bookmark(let bookmark):
                    Score(bookmark: bookmark, query: query, queryTokens: queryTokens)
                case .history(let historyEntry):
                    Score(historyEntry: historyEntry, query: query, queryTokens: queryTokens)
                case .internalPage(let internalPage):
                    Score(internalPage: internalPage, query: query, queryTokens: queryTokens)
                case .openTab(let tab):
                    Score(browserTab: tab, query: query)
                }

                return (item, score)
            }
            // Filter not relevant
            .filter { $0.score > 0 }
            // Sort according to the score
            .sorted {
                switch ($0.item, $1.item) {
                // place open tab suggestions on top
                case (.openTab, .openTab): break
                case (.openTab, _): return true
                case (_, .openTab): return false
                default: break
                }
                return $0.score > $1.score
            }
            // Create suggestion array
            .compactMap {
                switch $0.item {
                case .bookmark(let bookmark):
                    switch platform {
                    case .desktop: return Suggestion(bookmark: bookmark)
                    case .mobile: return Suggestion(bookmark: bookmark, allowedInTopHits: true)
                    }

                case .history(let historyEntry):
                    return Suggestion(historyEntry: historyEntry)
                case .internalPage(let internalPage):
                    return Suggestion(internalPage: internalPage)
                case .openTab(let tab):
                    return Suggestion(tab: tab)
                }
            }

        return result
    }

    // MARK: - Top Hits

    /// Take the top two items from the suggestions, but only up to the first suggestion that is not allowed in top hits
    private func topHits(from suggestions: [Suggestion]) -> [Suggestion] {
        var topHits = [Suggestion]()

        for suggestion in suggestions {
            guard topHits.count < Self.maximumNumberOfTopHits else { break }

            if suggestion.allowedInTopHits {
                topHits.append(suggestion)
            } else {
                break
            }
        }

        return topHits
    }

    // MARK: - Cutting off and making the result

    static let maximumNumberOfSuggestions = 12
    static let maximumNumberOfTopHits = 2
    static let minimumNumberInSuggestionGroup = 5

    private func makeResult(topHits: [Suggestion],
                            duckduckgoSuggestions: [Suggestion],
                            localSuggestions: [Suggestion]) -> SuggestionResult {

        assert(topHits.count <= Self.maximumNumberOfTopHits)

        // Top Hits
        var total = topHits.count

        // History and Bookmarks
        let prefixForLocalSuggestions = Self.maximumNumberOfSuggestions - (total + Self.minimumNumberInSuggestionGroup)
        let localSuggestions = Array(localSuggestions.prefix(prefixForLocalSuggestions))
        total += localSuggestions.count

        // DuckDuckGo Suggestions
        let prefixForDuckDuckGoSuggestions = Self.maximumNumberOfSuggestions - total
        let duckduckgoSuggestions = Array(duckduckgoSuggestions.prefix(prefixForDuckDuckGoSuggestions))

        return SuggestionResult(topHits: topHits,
                                duckduckgoSuggestions: duckduckgoSuggestions,
                                localSuggestions: localSuggestions)
    }

}
