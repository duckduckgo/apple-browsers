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

    /// Gets the "quality" of a suggestion type.
    /// Bookmarks, favorites, and history items have a valid page title, so are considered higher quality.
    /// This matches the Windows implementation's GetSuggestionQuality method.
    private func getSuggestionTypeQuality(_ localSuggestion: LocalSuggestion) -> Int {
        switch localSuggestion {
        case .bookmark(let bookmark) where bookmark.isFavorite:
            return 6 // Favorite (highest quality)
        case .bookmark:
            return 5 // Regular bookmark
        case .openTab:
            return 4 // Open tab
        case .history:
            return 3 // History entry
        case .internalPage:
            return 2 // Internal page (treated similar to website)
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

        // Sort suggestions first by type priority, then by score
        // This aligns with Windows implementation which prioritizes by suggestion type first
        let sortedSuggestions = scoredSuggestions.sorted { 
            let quality1 = getSuggestionTypeQuality($0.0)
            let quality2 = getSuggestionTypeQuality($1.0)
            
            // If qualities are different, sort by quality
            if quality1 != quality2 {
                return quality1 > quality2
            }
            
            // If qualities are the same, sort by score
            return $0.1 > $1.1
        }

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
        // Group suggestions by URL (normalized to remove scheme and www prefix)
        let groupedSuggestions = Dictionary(grouping: suggestions) { suggestion -> String in
            guard let url = suggestion.suggestion.url else {
                return UUID().uuidString // Ensure unique key for items without URL
            }
            let nakedUrl = url.nakedString
            return nakedUrl ?? url.absoluteString
        }
        
        // Process each group of suggestions with the same URL
        return groupedSuggestions.values.compactMap { suggestionsForSameUrl -> TopHitsEligibleSuggestion? in
            guard let firstSuggestion = suggestionsForSameUrl.first else { return nil }
            
            // If we only have one suggestion for this URL, return it directly
            if suggestionsForSameUrl.count == 1 {
                return firstSuggestion
            }
            
            // For multiple suggestions with the same URL, we need to merge information
            // This is similar to the Windows RemoveDuplicates method
            
            // Get all suggestion types that apply to this URL
            let suggestionTypes = Set(suggestionsForSameUrl.map { suggestion -> SuggestionType in
                switch suggestion.suggestion {
                case .bookmark(_, _, let isFavorite, _):
                    return isFavorite ? .favorite : .bookmark
                case .historyEntry:
                    return .historyEntry
                case .openTab:
                    return .openTab
                case .internalPage:
                    return .internalPage
                case .website:
                    return .website
                case .phrase, .unknown:
                    return .other
                }
            })
            
            // Find the highest quality suggestion type in this group
            let highestQualitySuggestion = suggestionsForSameUrl
                .sorted { lhs, rhs in
                    // Sort by suggestion quality (using our quality method)
                    let quality1: Int = {
                        switch lhs.suggestion {
                        case .bookmark(_, _, let isFavorite, _): return isFavorite ? 6 : 5
                        case .openTab: return 4
                        case .historyEntry: return 3
                        case .internalPage: return 2
                        case .website: return 1
                        default: return 0
                        }
                    }()
                    
                    let quality2: Int = {
                        switch rhs.suggestion {
                        case .bookmark(_, _, let isFavorite, _): return isFavorite ? 6 : 5
                        case .openTab: return 4
                        case .historyEntry: return 3
                        case .internalPage: return 2
                        case .website: return 1
                        default: return 0
                        }
                    }()
                    
                    return quality1 > quality2
                }
                .first!
            
            // Get highest score among all suggestions for this URL
            let maxScore = suggestionsForSameUrl.max { $0.suggestion.score < $1.suggestion.score }?.suggestion.score ?? 0
            
            // Determine if this suggestion should be allowed in top hits
            // If any of the suggestions for this URL is allowed in top hits, the result should be allowed
            let allowedInTopHits = suggestionsForSameUrl.contains { $0.allowedInTopHits }
            
            // Check if we have both an openTab and a historyEntry/bookmark for the same URL
            // This is special handling similar to Windows implementation
            let hasOpenTab = suggestionTypes.contains(.openTab)
            let hasHistoryOrBookmark = suggestionTypes.contains(.historyEntry) || 
                                      suggestionTypes.contains(.bookmark) ||
                                      suggestionTypes.contains(.favorite)
            
            // Return the highest quality suggestion with the maximum score
            // and combined information about suggestion types
            return (suggestion: highestQualitySuggestion.suggestion.withScore(maxScore), 
                    allowedInTopHits: allowedInTopHits)
        }
        .sorted { 
            // Final sort by score to ensure highest scored items appear first
            $0.suggestion.score > $1.suggestion.score
        }
    }
    
    // Helper enum for categorizing suggestions during deduplication
    private enum SuggestionType {
        case favorite
        case bookmark
        case openTab
        case historyEntry
        case internalPage
        case website
        case other
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
        
        // Get candidates that are eligible for top hits, up to the maximum
        let topHitsCandidates = suggestions
            .filter { $0.allowedInTopHits }
            .prefix(Self.maximumNumberOfTopHits)
            .map { $0.suggestion }
        
        // Check if we have any special open tab cases for top hits
        let anyOpenTabsInTopHits = topHitsCandidates.contains { $0.isOpenTab }
        
        // Process top hits according to rules similar to Windows implementation
        if anyOpenTabsInTopHits && topHitsCandidates.count > 0 {
            // Find the first open tab in the candidates
            if let firstOpenTabIndex = topHitsCandidates.firstIndex(where: { $0.isOpenTab }),
               let firstOpenTab = topHitsCandidates[safe: firstOpenTabIndex] {
                
                // Find a corresponding bookmark/history entry for the same URL
                let openTabUrl = firstOpenTab.url
                let sameUrlNonTabSuggestion = suggestions
                    .filter { 
                        // Not an open tab but has the same URL
                        !$0.suggestion.isOpenTab && 
                        $0.suggestion.url?.naked == openTabUrl?.naked && 
                        $0.allowedInTopHits
                    }
                    .first
                
                if let nonTabSuggestion = sameUrlNonTabSuggestion {
                    // We have both an open tab and another suggestion (bookmark/history) for the same URL
                    // Similar to Windows, prioritize the non-tab suggestion for autocomplete purposes
                    topHits.append(nonTabSuggestion.suggestion)
                    
                    // Only add the open tab as well if we haven't reached max yet
                    if topHits.count < Self.maximumNumberOfTopHits {
                        topHits.append(firstOpenTab)
                    }
                } else {
                    // Just a regular open tab with no corresponding bookmark/history
                    topHits.append(firstOpenTab)
                }
            }
            
            // Add remaining top hits until we reach the maximum
            for candidate in topHitsCandidates {
                if !topHits.contains(where: { $0.url?.naked == candidate.url?.naked }) && 
                   topHits.count < Self.maximumNumberOfTopHits {
                    topHits.append(candidate)
                }
            }
        } else {
            // No special open tab handling needed, just take the top N allowed suggestions
            topHits = Array(topHitsCandidates)
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
