//
//  SuggestionProcessing.swift
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

public enum Platform {

    case mobile, desktop

}

/// Class encapsulates the whole ordering and filtering algorithm
/// It takes query, history, bookmarks, open tabs, and apiResult as input parameters
/// The output is instance of SuggestionResult
struct SuggestionProcessing {

    // MARK: - Constants

    static let maximumNumberOfSuggestions = 12
    static let maximumNumberOfTopHits = 2
    static let minimumNumberInSuggestionGroup = 5

    private let platform: Platform
    private var isUrlIgnored: (URL) -> Bool

    init(platform: Platform, isUrlIgnored: @escaping (URL) -> Bool) {
        self.platform = platform
        self.isUrlIgnored = isUrlIgnored
    }

    func result(for query: String,
                from history: [HistorySuggestion],
                bookmarks: [Bookmark],
                internalPages: [InternalPage],
                openTabs: [BrowserTab],
                apiResult: APIResult?) -> SuggestionResult? {

        let lowerQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let queryTokens = lowerQuery.tokenized()
        guard !lowerQuery.isEmpty else { return .empty }

        // STEP 1: Get DDG suggestions from the Suggestions API result
        let duckDuckGoSuggestions = duckDuckGoSuggestions(from: apiResult, isUrlIgnored: isUrlIgnored) ?? []

        // STEP 2: filter DDG suggestions that point to a website
        let duckDuckGoDomainSuggestions = duckDuckGoSuggestions.compactMap { suggestion -> (suggestion: ScoredSuggestion, kinds: Set<ScoredSuggestion.Kind>)? in
            guard case .website(let url) = suggestion else { return nil }
            return (ScoredSuggestion(kind: .website, url: url, title: url.absoluteString), [.website])
        }

        // STEP 3: Get best ordered matches from history, bookmarks, open tabs and internal pages (Settings, Bookmarks…)
        let allHistoryAndBookmarkAndOpenTabSuggestions = [
            bookmarks.compactMap(ScoringService.scored(lowercasedQuery: lowerQuery, queryTokens: queryTokens, isUrlIgnored: isUrlIgnored)),
            openTabs.compactMap(ScoringService.scored(lowercasedQuery: lowerQuery, queryTokens: queryTokens, isUrlIgnored: isUrlIgnored)),
            history.compactMap(ScoringService.scored(lowercasedQuery: lowerQuery, queryTokens: queryTokens, isUrlIgnored: isUrlIgnored)),
            internalPages.compactMap(ScoringService.scored(lowercasedQuery: lowerQuery, queryTokens: queryTokens, isUrlIgnored: isUrlIgnored)),
        ]
            .joined()
            .sorted { $0.score > $1.score }
            .prefix(100) // limit max len optimization

        // STEP 4: Deduplicate the results by grouping on URL and get the "best" suggestion for each. We also receive
        // a list of SuggestionKind values for each URL to support better categorization below.
        let dedupedLocalSuggestionTuples = removeDuplicates(allHistoryAndBookmarkAndOpenTabSuggestions)

        // STEP 5: Combine all navigational suggestions including the DDG website suggestions
        // All bookmark/favorite, history and duckDuckGoDomainSuggestions point directly to a URL browser can navigate to
        let dedupedNavigationalSuggestions = dedupedLocalSuggestionTuples
            .sorted { $0.suggestion.score > $1.suggestion.score } + duckDuckGoDomainSuggestions

        // STEP 6: Find Top Hits: Website, History Entry or Favorites suggestions.
        // Top Hits won't contain non-favorite Bookmarks unless it is also a Website or History suggestion
        // at which point the suggestion needs to display that it's a bookmark.
        let topHitsDeduped = dedupedNavigationalSuggestions
            .filter { isTopHit($0.suggestion, $0.kinds) }
            .prefix(Self.maximumNumberOfTopHits)

        // STEP 7: Handle special case for open tab suggestions
        // If the top suggestion is open tab based and also a history entry, bookmark or favorite
        // we split the open tab/other suggestion into separate suggestions and prioritize
        // the non-open tab suggestion so it can be autocompleted.
        let finalTopHits = handleTopHitsOpenTabCase(topHitsDeduped)

        // STEP 8: Prepare final Top Hits suggestions
        let topHits = finalTopHits.compactMap { Suggestion($0) }

        // STEP 9: Calculate remaining count for history/bookmarks/open tabs section
        let countForHistoryAndBookmarksAndOpenTabs = min(
            Self.maximumNumberOfSuggestions - (topHits.count + Self.minimumNumberInSuggestionGroup),
            lowerQuery.count + 1 - topHits.count
        )

        // STEP 10: Build history, bookmarks, and open tabs suggestions
        let historyAndBookmarksAndOpenTabs = dedupedNavigationalSuggestions
            .filter {
                guard $0.kinds.intersects([.historyEntry, .bookmark, .favorite, .browserTab, .internalPage]),
                      let suggestion = Suggestion($0.suggestion),
                      !topHits.contains(suggestion) else { return false } // Don't include items already in top hits
                return true
            }
            .prefix(countForHistoryAndBookmarksAndOpenTabs)
            .compactMap { Suggestion($0.suggestion) }

        // STEP 11: Filter out website suggestions already present in Top Hits
        let duckDuckGoPhrasesAndDomainSuggestions = duckDuckGoSuggestions.filter {
            !topHits.contains($0)
        }
            .prefix(Self.maximumNumberOfSuggestions - (topHits.count + historyAndBookmarksAndOpenTabs.count))

        // STEP 12: Return final ordered suggestions
        return SuggestionResult(
            topHits: topHits,
            duckduckgoSuggestions: Array(duckDuckGoPhrasesAndDomainSuggestions),
            localSuggestions: historyAndBookmarksAndOpenTabs
        )
    }

    /// Generates a list of phrase and website suggestions from the given API result filtering out the ignored URLs.
    private func duckDuckGoSuggestions(from result: APIResult?, isUrlIgnored: (URL) -> Bool) -> [Suggestion]? {
        return result?.items
            .compactMap { suggestion in
                guard let phrase = suggestion.phrase else { return nil }
                if suggestion.isNav == true {
                    guard let url = URL(string: URL.NavigationalScheme.http.separated() + phrase),
                          !isUrlIgnored(url) else { return nil }
                    return .website(url: url)
                } else {
                    return .phrase(phrase: phrase)
                }
            }
    }

    /// Removes duplicate entries (based on the URL) from a list of suggestions.
    /// When duplicates are found, ones with more info (e.g. bookmarks) will take precedence.
    private func removeDuplicates(_ suggestions: some Sequence<ScoredSuggestion>) -> [(suggestion: ScoredSuggestion, kinds: Set<ScoredSuggestion.Kind>)] {
        // Group suggestions by normalized URL preserving the keys order
        var orderedKeys = [String]()
        var seenKeys = Set<String>()
        let groupedByURL = Dictionary(grouping: suggestions) {
            let key = $0.url.nakedString ?? $0.url.absoluteString
            if seenKeys.insert(key).inserted {
                orderedKeys.append(key)
            }
            return key
        }

        var result = [(ScoredSuggestion, Set<ScoredSuggestion.Kind>)]()
        for key in orderedKeys {
            // We can have multiple kinds of suggestion for a given url, for example:
            // 1. A search suggestion promoted to website due to being a valid URL
            // 2. A history item
            // 3. A bookmark
            // 4. An open tab
            guard let group = groupedByURL[key],
                  // We want to display the suggestion of the highest "quality"
                  var suggestion = group.max(by: { $0.quality < $1.quality }) else {
                assertionFailure("Grouped suggestions should not be empty")
                continue
            }

            // …but we also need to provide all the kinds of suggestion for this URL so
            // downstream logic can do further filtering (i.e. TopHits shouldn't contain Bookmarks
            // unless they're also part of a History or Website suggestion).
            let suggestionKinds = Set(group.map(\.kind))

            // Should only ever have a single history entry instance per
            // group so can simply use Sum to get the VisitCount
            let visitCount = group.reduce(0) { $0 + ($1.kind == .historyEntry ? $1.visitCount : 0) }

            // set tabId even to non-browserTab suggestions so if it‘s duplicated in `handleTopHitsOpenTabCase`
            // as a browserTab suggestion the tabId is still present there (as the Title/URL may not match)
            let tabId = group.first(where: { $0.kind == .browserTab })?.tabId

            // Get the highest score for this group
            let maxScore = group.max(by: { $0.score < $1.score })?.score ?? 0

            // If the chosen suggestion has a different visit count or score than the
            // prioritized suggestion (for example open tab is prioritized over history,
            // but it will have a lower score and visit count).
            suggestion.score = maxScore
            suggestion.visitCount = visitCount
            suggestion.tabId = tabId

            result.append((suggestion, suggestionKinds))
        }

        return result
    }

    /// Determines if a suggestion should be included in top hits
    private func isTopHit(_ scoredSuggestion: ScoredSuggestion, _ suggestionKinds: Set<ScoredSuggestion.Kind>) -> Bool {
        // Check if the suggestion is allowed in Top Hits: is it for website, favorite or history (+bookmarks for mobile)
        var suggestionKindsAllowedInTopHits: [ScoredSuggestion.Kind] = [.website, .favorite, .historyEntry]
        if platform == .mobile {
            suggestionKindsAllowedInTopHits.append(.bookmark)
        }
        // Otherwise the suggestion should not be part of top hits
        guard suggestionKinds.intersects(suggestionKindsAllowedInTopHits) else { return false }

        // If the suggestion is based solely on history
        if suggestionKinds == [.historyEntry] {
            // Include in TopHits only if root domain or has more than 3 visits and didn‘t fail to load
            return !scoredSuggestion.failedToLoad && (scoredSuggestion.visitCount > 3 || scoredSuggestion.url.isRoot)
        }

        // If the suggestion is based solely on an open tab
        if suggestionKinds == [.browserTab] {
            // Don't include open tabs in top hits by default
            return false
        }

        // Other kinds of suggestion can be included in top hits
        return true
    }

    /// Handles special case for open tab suggestions in top hits
    private func handleTopHitsOpenTabCase(_ topHitsDeduped: some Collection<(suggestion: ScoredSuggestion, kinds: Set<ScoredSuggestion.Kind>)>) -> [ScoredSuggestion] {
        var result = topHitsDeduped.map(\.suggestion)

        // If the top suggestion is open tab based and also a history entry, bookmark or favorite…
        guard let topHit = topHitsDeduped.first,
              topHit.kinds.contains(.browserTab),
              topHit.kinds.intersects([.historyEntry, .bookmark, .favorite]) else { return result }

        // Choose new suggestion kind based on highest quality non-open tab suggestion type
        let newSuggestionKind = if topHit.suggestion.kind == .browserTab {
            topHit.kinds.filter { $0 != .browserTab }.max(by: { $0.quality < $1.quality }) ?? .browserTab
        } else {
            ScoredSuggestion.Kind.browserTab
        }

        // …we split the open tab/other suggestion into separate suggestions…
        var newSuggestion = topHit.suggestion
        newSuggestion.kind = newSuggestionKind
        // …and prioritize the non-open tab suggestion so it can autocomplete.
        // If new suggestion is open tab, put it second (original stays at top)
        // If new suggestion is not open tab, put it first (prioritize for autocomplete)
        let insertionIndex = (newSuggestionKind == .browserTab) ? 1 : 0
        result.insert(newSuggestion, at: insertionIndex)

        // Ensure we don't exceed MAX_TOP_HITS
        if result.count > Self.maximumNumberOfTopHits {
            result.removeSubrange(Self.maximumNumberOfTopHits...)
        }

        return result
    }

}

extension ScoredSuggestion.Kind {
    // Suggestion quality ranking (higher numbers = higher quality)
    var quality: Int {
        switch self {
        case .phrase: 1
        case .website, .internalPage: 2
        case .historyEntry: 3
        case .browserTab: 4
        case .bookmark: 5
        case .favorite: 6
        }
    }
}

extension ScoredSuggestion {
    var quality: Int { kind.quality }
}

private extension Suggestion {
    init?(_ suggestion: ScoredSuggestion) {
        switch suggestion.kind {
        case .phrase:
            self = .phrase(phrase: suggestion.title)
        case .website:
            self = .website(url: suggestion.url)
        case .bookmark:
            self = .bookmark(title: suggestion.title, url: suggestion.url, isFavorite: false, score: suggestion.score)
        case .favorite:
            self = .bookmark(title: suggestion.title, url: suggestion.url, isFavorite: true, score: suggestion.score)
        case .historyEntry:
            self = .historyEntry(title: suggestion.title, url: suggestion.url, score: suggestion.score)
        case .internalPage:
            self = .internalPage(title: suggestion.title, url: suggestion.url, score: suggestion.score)
        case .browserTab:
            self = .openTab(title: suggestion.title, url: suggestion.url, tabId: suggestion.tabId, score: suggestion.score)
        }
    }
}
