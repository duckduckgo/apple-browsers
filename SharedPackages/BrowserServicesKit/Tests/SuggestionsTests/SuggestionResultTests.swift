//
//  SuggestionResultTests.swift
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

import XCTest
@testable import Suggestions

final class SuggestionResultTests: XCTestCase {

    func testWhenResultContainsNoSuggestions_ThenItIsEmpty() {
        let emptyResult = SuggestionResult.empty

        XCTAssert(emptyResult.isEmpty)
        XCTAssertEqual(emptyResult.topHits.count, 0)
        XCTAssertEqual(emptyResult.localSuggestions.count, 0)
        XCTAssertEqual(emptyResult.duckduckgoSuggestions.count, 0)
    }

    func testWhenResultContainsWebsiteSuggestionAsFirstSuggestion_ThenCanNotBeAutocompleted() {
        let suggestions = [Suggestion.website(url: URL(string: "duckduckgo.com")!), Suggestion.website(url: URL(string: "spreadprivacy.com")!)]
        let result = SuggestionResult(topHits: suggestions, duckduckgoSuggestions: [], localSuggestions: [])

        XCTAssertFalse(result.canBeAutocompleted)
    }

    func testWhenResultContainsHistoryOrBookmarkSuggestionAsFirstSuggestion_ThenCanBeAutocompleted() {
        let suggestions = [Suggestion.bookmark(title: "", url: URL(string: "duckduckgo.com")!, isFavorite: false, score: 0), Suggestion.bookmark(title: "", url: URL(string: "spreadprivacy.com")!, isFavorite: false, score: 0)]
        let result = SuggestionResult(topHits: suggestions, duckduckgoSuggestions: [], localSuggestions: [])

        XCTAssert(result.canBeAutocompleted)

        let suggestions2 = [Suggestion.historyEntry(title: nil, url: URL(string: "duckduckgo.com")!, score: 0), Suggestion.historyEntry(title: nil, url: URL(string: "spreadprivacy.com")!, score: 0)]
        let result2 = SuggestionResult(topHits: suggestions2, duckduckgoSuggestions: [], localSuggestions: [])
        XCTAssert(result2.canBeAutocompleted)
    }

}
