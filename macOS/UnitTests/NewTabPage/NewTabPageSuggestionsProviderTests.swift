//
//  NewTabPageSuggestionsProviderTests.swift
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

import XCTest
@testable import DuckDuckGo_Privacy_Browser
@testable import NewTabPage
import Suggestions

final class NewTabPageOmnibarSuggestionsProviderTests: XCTestCase {

    private var suggestionContainerMock: SuggestionContainerMock!
    private var provider: NewTabPageOmnibarSuggestionsProvider!

    override func setUp() {
        super.setUp()
        suggestionContainerMock = SuggestionContainerMock()
        provider = NewTabPageOmnibarSuggestionsProvider(suggestionContainer: suggestionContainerMock)
    }

    override func tearDown() {
        suggestionContainerMock = nil
        provider = nil
        super.tearDown()
    }

    func testWhenSuggestionsAreReturned_thenSuggestionsAreMappedCorrectly() async {
        suggestionContainerMock.suggestionResultToReturn = SuggestionResult.aSuggestionResult

        let suggestions = await provider.suggestions(for: "duck")

        XCTAssertEqual(suggestions.topHits.count, 2)
        XCTAssertEqual(suggestions.duckduckgoSuggestions.count, 0)
        XCTAssertEqual(suggestions.localSuggestions.count, 0)
    }

    func testWhenNoSuggestionsReturned_thenEmptySuggestionsAreReturned() async {
        suggestionContainerMock.suggestionResultToReturn = nil

        let suggestions = await provider.suggestions(for: "duck")

        XCTAssertTrue(suggestions.topHits.isEmpty)
        XCTAssertTrue(suggestions.duckduckgoSuggestions.isEmpty)
        XCTAssertTrue(suggestions.localSuggestions.isEmpty)
    }

    func testSuggestionMapping_toNewTabPageSuggestion() {
        let url = URL(string: "https://duckduckgo.com")!
        let suggestions: [Suggestion] = [
            .phrase(phrase: "search term"),
            .website(url: url),
            .bookmark(title: "Bookmark", url: url, isFavorite: true, score: 1),
            .historyEntry(title: "History", url: url, score: 2),
            .internalPage(title: "Settings", url: url, score: 3),
            .openTab(title: "Tab", url: url, tabId: "123", score: 4),
            .unknown(value: "unknown")
        ]

        let mapped = suggestions.compactMap { $0.newTabPageSuggestion }

        XCTAssertEqual(mapped.count, 6)

        XCTAssertEqual(mapped[0], .phrase(phrase: "search term"))
        XCTAssertEqual(mapped[1], .website(url: "https://duckduckgo.com"))
        XCTAssertEqual(mapped[2], .bookmark(title: "Bookmark", url: "https://duckduckgo.com", isFavorite: true, score: 1))
        XCTAssertEqual(mapped[3], .historyEntry(title: "History", url: "https://duckduckgo.com", score: 2))
        XCTAssertEqual(mapped[4], .internalPage(title: "Settings", url: "https://duckduckgo.com", score: 3))
        XCTAssertEqual(mapped[5], .openTab(title: "Tab", tabId: "123", score: 4))
    }
}

// MARK: - Mocks

final class SuggestionContainerMock: SuggestionContainerProtocol {

    var suggestionResultToReturn: SuggestionResult?

    func getSuggestions(for query: String, useCachedData: Bool = false, completion: ((SuggestionResult?) -> Void)? = nil) {
        completion?(suggestionResultToReturn)
    }
}
