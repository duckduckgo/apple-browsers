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
struct SuggestionProcessing {

    // MARK: - Constants
    
    static let maximumNumberOfSuggestions = 12
    static let maximumNumberOfTopHits = 2
    static let minimumNumberInSuggestionGroup = 5

    private let platform: Platform
    private var urlFactory: (String) -> URL?

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
        
        guard !query.isEmpty else { return .empty }
        let lowerQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let queryTokens = lowerQuery.tokenized()

        // Get DuckDuckGo suggestions
        let duckDuckGoSuggestions = (try? self.duckDuckGoSuggestions(from: apiResult)) ?? []
        
        // STEP 1: Get DDG suggestions that point to a website
        let duckDuckGoDomainSuggestions = duckDuckGoSuggestions.compactMap { suggestion -> ScoredSuggestion? in
            guard case .website(url: let url) = suggestion, !isUrlIgnored(url) else { return nil }
            return ScoredSuggestion(suggestion: .website(url), score: 0)
        }
        
        // STEP 2: Get best ordered matches from history, bookmarks, open tabs and internal pages (settings, bookmarks…)
        let allHistoryAndBookmarkAndOpenTabSuggestions = [
            bookmarks.compactMap(ScoringService.scored(lowerQuery: lowerQuery, queryTokens: queryTokens)),
            openTabs.compactMap(ScoringService.scored(lowerQuery: lowerQuery, queryTokens: queryTokens)),
            history.compactMap(ScoringService.scored(lowerQuery: lowerQuery, queryTokens: queryTokens)),
            internalPages.compactMap(ScoringService.scored(lowerQuery: lowerQuery, queryTokens: queryTokens)),
        ]
            .joined()
            .sorted { $0.score > $1.score }

        // STEP 3: Combine all navigational suggestions
        // All bookmark/favorite, history and duckDuckGoDomainSuggestions point directly to a URL browser can navigate to
        let navigationalSuggestions = allHistoryAndBookmarkAndOpenTabSuggestions + duckDuckGoDomainSuggestions
        
        // STEP 4: Deduplicate results by URL
        let dedupedSuggestionTuples = removeDuplicates(navigationalSuggestions)
            .sorted { $0.suggestion.score > $1.suggestion.score }
        
        // STEP 5: Find top hits based on specific criteria
        let topHitsDeduped = dedupedSuggestionTuples
            .filter { isTopHit($0.suggestion, $0.kinds) }
            .prefix(Self.maximumNumberOfTopHits)
            .map(\.self)

        // STEP 6: Handle special case for open tab suggestions
        let finalTopHits = handleTopHitsOpenTabCase(topHitsDeduped)

        // STEP 7: Extract final top hits
        let topHits = finalTopHits.compactMap { Suggestion($0) }

        // STEP 8: Calculate count for history/bookmarks/open tabs section
        let countForHistoryAndBookmarksAndOpenTabs = min(
            Self.maximumNumberOfSuggestions - (topHits.count + Self.minimumNumberInSuggestionGroup),
            lowerQuery.count + 1 - topHits.count
        )
        
        // STEP 9: Build history, bookmarks, and open tabs suggestions
        let historyAndBookmarksAndOpenTabs = dedupedSuggestionTuples
            .filter {
                guard $0.kinds.intersects([.historyEntry, .bookmark, .favorite, .browserTab]),
                      let suggestion = Suggestion($0.suggestion),
                      !topHits.contains(suggestion) else { return false } // Don't include items already in top hits
                return true
            }
            .map(\.suggestion)
            .prefix(countForHistoryAndBookmarksAndOpenTabs)
            .map(\.self)

        // STEP 10: Build search phrase suggestions
        let duckDuckGoPhrases = duckDuckGoSuggestions
            .filter { if case .phrase = $0 { return true } else { return false } }
            .prefix(Self.maximumNumberOfSuggestions - (topHits.count + historyAndBookmarksAndOpenTabs.count))
            .map(\.self)

        // STEP 11: Return final ordered suggestions
        return SuggestionResult(
            topHits: topHits,
            duckduckgoSuggestions: duckDuckGoPhrases,
            localSuggestions: historyAndBookmarksAndOpenTabs.compactMap { Suggestion($0) }
        )
    }
    
    /// Removes duplicate entries (based on the URL) from a list of suggestions.
    /// When duplicates are found, ones with more info (e.g. bookmarks) will take precedence.
    private func removeDuplicates(_ suggestions: [ScoredSuggestion]) -> [(suggestion: ScoredSuggestion, kinds: Set<SuggestionType.Kind>)] {
        // Group suggestions by normalized URL preserving original order for same-score suggestions
        let groupedByURL = Dictionary(grouping: suggestions.enumerated().lazy.map { (item: $0.element, originalIndex: $0.offset) }) { $0.item.suggestion.url?.nakedString ?? UUID().uuidString }

        var result = [(item: (ScoredSuggestion, Set<SuggestionType.Kind>), originalIndex: Int)]()

        for group in groupedByURL.values {
            // We can have multiple kinds of suggestion for a given url, for example:
            // 1. A search suggestion promoted to website due to being a valid URL
            // 2. A history item
            // 3. A bookmark
            // 4. An open tab

            // We want to display the suggestion of the highest "quality"
            guard var suggestion = group.max(by: { $0.item.suggestion.quality < $1.item.suggestion.quality })?.item,
                  let minOriginalIndex = group.max(by: { $0.item.suggestion.quality < $1.item.suggestion.quality })?.originalIndex else { continue }

            // ... but we also need to provide all the kinds of suggestion for this URL so
            // downstream logic can do further filtering (i.e. TopHits shouldn't contain Bookmarks
            // unless they're also part of a History or Website suggestion).
            let suggestionKinds = Set(group.map(\.item.suggestion.kind))

            // Should only ever have a single history entry instance per
            // group so can simply use Sum to get the VisitCount
            // TODO: why the visitCount is here?
//            let visitCount = group.reduce(0) { $0 + ($1.item.suggestion.kind == .historyEntry ? $1.item.suggestion.visitCount ?? 0 : 0) }

            // Get the highest score for this group
            let maxScore = group.max(by: { $0.item.score < $1.item.score })?.item.score ?? 0

            // If the chosen suggestion has a different visit count or score than the
            // prioritized suggestion (for example open tab is prioritized over history,
            // but it will have a lower score and visit count).
            suggestion.score = maxScore

            result.append(((suggestion, suggestionKinds), minOriginalIndex))
        }
        
        return result.sorted {
            $0.item.0.score > $1.item.0.score || ($0.item.0.score == $1.item.0.score && $0.originalIndex < $1.originalIndex)
        }.map(\.item)
    }

    /// Determines if a suggestion should be included in top hits, following Windows algorithm rules
    private func isTopHit(_ scoredSuggestion: ScoredSuggestion, _ suggestionKinds: Set<SuggestionType.Kind>) -> Bool {
        let suggestion = scoredSuggestion.suggestion
        
        // Check if the suggestion is for website, favorite or history
        // Otherwise the suggestion should not be part of top hits
        guard [.website, .favorite, .historyEntry].contains(suggestion.kind) else { return false }

        // If the suggestion is based solely on history
        if suggestionKinds == [.historyEntry] {
            // Include in TopHits only if root domain or has more than 3 visits
            if let url = scoredSuggestion.url {
                return url.isRoot || scoredSuggestion.visitCount > 3
            }
            return false
        }

        // If the suggestion is based solely on an open tab
        if suggestionKinds == [.browserTab] {
            // Don't include open tabs in top hits by default
            return false
        } else {
            // Other kinds of suggestion can be included in top hits
            return true
        }
    }

    // MARK: - Special Processing for Open Tabs in Top Hits
    
    /// Handles special case for open tab suggestions in top hits
    private func handleTopHitsOpenTabCase(_ topHitsDeduped: [(suggestion: ScoredSuggestion, kinds: Set<SuggestionType.Kind>)]) -> [ScoredSuggestion] {
        var result = topHitsDeduped.map(\.suggestion)
        
        // If there are no top hits, return empty array
        if result.isEmpty {
            return result
        }
        
        // Retrieve the top switch to tab result if there is one
        let topSwitchToTabHit = topHitsDeduped.first { tuple in
            tuple.kinds.contains(.browserTab)
        }
        
        if let topSwitchToTabHit = topSwitchToTabHit, 
           !topHitsDeduped.isEmpty {
            
            // If the top suggestion is open tab based and also a history entry,
            // bookmark or favorite...
            if topHitsDeduped[0].kinds.contains(.browserTab)
                && topHitsDeduped[0].kinds.intersects([.historyEntry, .bookmark, .favorite]) {

                // Choose new suggestion kind based on highest quality non-open tab suggestion type
                let newSuggestionKind: SuggestionType.Kind
                if topHitsDeduped[0].suggestion.suggestion.kind == .browserTab {
                    // Find highest quality non-open tab type from available kinds
                    let nonOpenTabKinds = topHitsDeduped[0].kinds.filter { $0 != .browserTab }
                    if nonOpenTabKinds.contains(.favorite) {
                        newSuggestionKind = .favorite
                    } else if nonOpenTabKinds.contains(.bookmark) {
                        newSuggestionKind = .bookmark
                    } else {
                        newSuggestionKind = .historyEntry
                    }
                } else {
                    newSuggestionKind = .browserTab
                }
                
                // ...we split the open tab/other suggestion into separate suggestions...
                // Note: In real implementation, we would create a new suggestion here with the chosen kind
                let newSuggestion = topHitsDeduped[0].suggestion
                
                // ...and prioritize the non-open tab suggestion so it can autocomplete.
                if newSuggestionKind == .browserTab {
                    // If new suggestion is open tab, put it second (original stays at top)
                    result.insert(newSuggestion, at: 1)
                } else {
                    // If new suggestion is not open tab, put it first (prioritize for autocomplete)
                    result.insert(newSuggestion, at: 0)
                }
                
                // Ensure we don't exceed MAX_TOP_HITS
                if result.count > Self.maximumNumberOfTopHits {
                    result = Array(result.prefix(Self.maximumNumberOfTopHits))
                }
            }
        }
        
        return result
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
    
    // MARK: - Helper Functions

    /// Checks if a URL should be ignored in suggestions
    private func isUrlIgnored(_ url: URL) -> Bool {
        // Implement any URL filtering logic here
        // For now we don't ignore any URLs
        return false
    }

}

extension SuggestionType {
    // Suggestion quality ranking (higher numbers = higher quality)
    var quality: Int {
        switch self {
        case .phrase: 1
        case .website, .internalPage: 2
        case .historyEntry: 3
        case .browserTab: 4
        case .bookmark(let bookmark) where bookmark.isFavorite: 6
        case .bookmark: 5
        }
    }
}

private extension Suggestion {
    init?(_ scoredSuggestion: ScoredSuggestion) {
        switch scoredSuggestion.suggestion {
        case .phrase(let phrase):
            self = .phrase(phrase: phrase)
        case .website(let url):
            self = .website(url: url)
        case .bookmark(let bookmark):
            guard let url = URL(string: bookmark.url) else { return nil }
            self = .bookmark(title: bookmark.title, url: url, isFavorite: bookmark.isFavorite, score: scoredSuggestion.score)
        case .historyEntry(let historySuggestion):
            self = .historyEntry(title: historySuggestion.title, url: historySuggestion.url, score: scoredSuggestion.score)
        case .internalPage(let internalPage):
            self = .internalPage(title: internalPage.title, url: internalPage.url, score: scoredSuggestion.score)
        case .browserTab(let browserTab):
            self = .openTab(title: browserTab.title, url: browserTab.url, score: scoredSuggestion.score)
        }
    }
}
