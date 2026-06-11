//
//  SearchSuggestionsSourceTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import Suggestions
import XCTest
@testable import DuckDuckGo

@MainActor
final class SearchSuggestionsSourceTests: XCTestCase {

    func test_categoriesBecomeSectionsInOrder() {
        let result = SuggestionResult(
            topHits: [.website(url: URL(string: "https://a.com")!)],
            duckduckgoSuggestions: [.phrase(phrase: "cats")],
            localSuggestions: [.bookmark(title: "B", url: URL(string: "https://b.com")!, isFavorite: false, score: 0)]
        )
        let sections = SearchSuggestionsSource.sections(from: result, query: "ca", showAskAIChat: false)
        XCTAssertEqual(sections.map(\.id), ["topHits", "ddg", "local"])
    }

    func test_askAIChatSection_whenEnabled_withQuery() {
        let sections = SearchSuggestionsSource.sections(from: .appEmpty, query: "weather", showAskAIChat: true)
        XCTAssertTrue(sections.contains { $0.id == "askAIChat" })
    }

    func test_historyRow_hasDeleteAccessory() {
        let url = URL(string: "https://h.com")!
        let result = SuggestionResult(
            topHits: [.historyEntry(title: "H", url: url, score: 0)],
            duckduckgoSuggestions: [],
            localSuggestions: []
        )
        let sections = SearchSuggestionsSource.sections(from: result, query: "h", showAskAIChat: false)
        XCTAssertEqual(sections.first?.rows.first?.accessory, .delete)
    }

    func test_resolvesRowIDToSuggestion() {
        let url = URL(string: "https://a.com")!
        let suggestion = Suggestion.website(url: url)
        let result = SuggestionResult(topHits: [suggestion], duckduckgoSuggestions: [], localSuggestions: [])
        let resolved = SearchSuggestionsSource.suggestion(forRowID: "topHits-website-\(url.absoluteString)", in: result, query: "a")
        XCTAssertEqual(resolved, suggestion)
    }

    func test_emptyResultFallbackPhraseRow_isResolvable() {
        // No results → a single phrase fallback row (the query). The displayed row must resolve back
        // to a suggestion so tapping it is handled (it previously resolved against the empty result → nil).
        let sections = SearchSuggestionsSource.sections(from: .appEmpty, query: "zxqw", showAskAIChat: false)
        let rowID = try? XCTUnwrap(sections.first?.rows.first?.id)
        XCTAssertEqual(rowID, "topHits-phrase-zxqw")
        let resolved = SearchSuggestionsSource.suggestion(forRowID: "topHits-phrase-zxqw", in: .appEmpty, query: "zxqw")
        XCTAssertEqual(resolved, .phrase(phrase: "zxqw"))
    }
}
