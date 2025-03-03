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

    private typealias TopHitsEligibleSuggestion = (suggestion: Suggestion, allowedInTopHits: Bool)

    init(platform: Platform, urlFactory: @escaping (String) -> URL?) {
        self.platform = platform
        self.urlFactory = urlFactory
    }

    func result(for query: String,
                from history: [HistorySuggestion],
                bookmarks: [Bookmark],
                internalPages: [InternalPage],
                openTabs: [BrowserTab],
                apiResult: APIResult?) -> SuggestionResult? {
        let query = query.lowercased()

        let duckDuckGoSuggestions = (try? self.duckDuckGoSuggestions(from: apiResult)) ?? []

        // Get domain suggestions from the DuckDuckGo Suggestions section (for the Top Hits section)
        let duckDuckGoDomainSuggestions = duckDuckGoSuggestions.compactMap { suggestion -> TopHitsEligibleSuggestion? in
            // The JSON response tells us explicitly what is navigational now, so we only need to find website suggestions here
            if case .website = suggestion {
                return (suggestion: suggestion, allowedInTopHits: true)
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
        let localSuggestions = Array(dedupedNavigationalSuggestions.dropFirst(topHits.count).filter {
            switch $0.suggestion {
            case .bookmark, .openTab, .historyEntry, .internalPage:
                return true
            default:
                return false
            }
        })

        let dedupedDuckDuckGoSuggestions = removeDuplicateWebsiteSuggestions(in: topHits, from: duckDuckGoSuggestions)

        return makeResult(topHits: topHits,
                          duckduckgoSuggestions: dedupedDuckDuckGoSuggestions,
                          localSuggestions: localSuggestions.map(\.suggestion))
    }

    // MARK: - History and Bookmarks

    enum LocalSuggestion {
        case bookmark(Bookmark)
        case history(HistorySuggestion)
        case internalPage(InternalPage)
        case openTab(BrowserTab)

        func isAlowedInTopHits(platform: Platform) -> Bool {
            switch self {
            case .history(let historyEntry):
                let areVisitsLow = historyEntry.numberOfVisits < 4
                let allowedInTopHits = !(historyEntry.failedToLoad
                                         || (areVisitsLow && !historyEntry.url.isRoot))
                return allowedInTopHits
            case .bookmark(let bookmark):
                switch platform {
                case .desktop: return bookmark.isFavorite
                case .mobile: return true
                }
            case .internalPage, .openTab:
                return false
            }
        }
    }

    private func localSuggestions(from history: [HistorySuggestion], bookmarks: [Bookmark], internalPages: [InternalPage], openTabs: [BrowserTab], query: String) -> [TopHitsEligibleSuggestion] {
        // Precompute query tokens once
        let lowerQuery = query.lowercased()
        let queryTokens = lowerQuery.tokenized()

        // Build local suggestions with proper type ordering (similar to Windows implementation)
        let localSuggestions = [
            bookmarks.map(LocalSuggestion.bookmark),
            openTabs.map(LocalSuggestion.openTab),
            history.map(LocalSuggestion.history),
            internalPages.map(LocalSuggestion.internalPage),
        ].joined()

        // First pass: score all items
        let scoredSuggestions = localSuggestions.compactMap { localSuggestion -> (LocalSuggestion, Int)? in
            let score = ScoringService.score(for: localSuggestion, lowerQuery: lowerQuery, queryTokens: queryTokens)

            guard score > 0 else { return nil } // Filter out suggestions with zero score
            return (localSuggestion, score)
        }

        // Sort suggestions by score in descending order
        let sortedSuggestions = scoredSuggestions.sorted { $0.1 > $1.1 }

        // Create final array of scored and sorted suggestions
        let result = sortedSuggestions.compactMap { localSuggestion, score -> TopHitsEligibleSuggestion? in
            if let suggestion = Suggestion(localSuggestion: localSuggestion, score: score) {
                return (suggestion: suggestion, allowedInTopHits: localSuggestion.isAlowedInTopHits(platform: platform))
            }
            return nil
        }

        return result
    }


    private func dedupLocalSuggestions(_ suggestions: [TopHitsEligibleSuggestion]) -> [TopHitsEligibleSuggestion] {
        return suggestions.reduce([TopHitsEligibleSuggestion]()) { partialResult, scoredSuggestion -> [TopHitsEligibleSuggestion] in
            if partialResult.contains(where: { item in
                switch item.suggestion {
                case .bookmark(title: let title, url: let url, isFavorite: let isFavorite, _):
                    if case .bookmark(title, url: let searchUrl, isFavorite, _) = scoredSuggestion.suggestion,
                       searchUrl.naked == url.naked {
                        return true
                    }

                case .historyEntry(title: let title, url: let url, _):
                    if case .historyEntry(title, url: let searchUrl, _) = scoredSuggestion.suggestion,
                       searchUrl.naked == url.naked {
                        return true
                    }

                case .internalPage(title: let title, url: let url, _):
                    if case .internalPage(title, url, _) = scoredSuggestion.suggestion {
                        return true
                    }

                case .openTab(title: let title, url: let url, _):
                    if case .openTab(title, url: let searchUrl, _) = scoredSuggestion.suggestion,
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
            return partialResult + [scoredSuggestion]
        }
    }

    private func replaceHistoryWithBookmarksAndTabs(_ sourceSuggestions: [TopHitsEligibleSuggestion]) -> [TopHitsEligibleSuggestion] {
        var expanded = [TopHitsEligibleSuggestion]()
        for i in 0 ..< sourceSuggestions.count {
            let item = sourceSuggestions[i]
            let suggestion = item.suggestion
            guard case .historyEntry = suggestion else {
                expanded.append(item)
                continue
            }

            if let bookmark = sourceSuggestions[i ..< sourceSuggestions.endIndex].first(where: {
                $0.suggestion.isBookmark && $0.suggestion.url?.naked == suggestion.url?.naked
            }) {
                expanded.append(bookmark)
            } else {
                expanded.append(item)
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

    // MARK: - Top Hits

    /// Take the top two items from the suggestions, but only up to the first suggestion that is not allowed in top hits
    private func topHits(from suggestions: [TopHitsEligibleSuggestion]) -> [Suggestion] {
        var topHits = [Suggestion]()

        for item in suggestions {
            guard topHits.count < Self.maximumNumberOfTopHits else { break }

            if item.allowedInTopHits {
                topHits.append(item.suggestion)
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

private extension Suggestion {
    init?(localSuggestion: SuggestionProcessing.LocalSuggestion, score: Int) {
        switch localSuggestion {
        case .bookmark(let bookmark):
            guard let suggestion = Suggestion(bookmark: bookmark, score: score) else { return nil }
            self = suggestion
        case .history(let historyEntry):
            self = Suggestion(historyEntry: historyEntry, score: score)
        case .internalPage(let internalPage):
            self = Suggestion(internalPage: internalPage, score: score)
        case .openTab(let tab):
            self = Suggestion(tab: tab, score: score)
        }
    }
}
