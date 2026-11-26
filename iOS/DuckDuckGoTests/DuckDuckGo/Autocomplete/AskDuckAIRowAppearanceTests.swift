//
//  AskDuckAIRowAppearanceTests.swift
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

final class AskDuckAIRowAppearanceTests: XCTestCase {

    private func phrases(_ count: Int) -> [Suggestion] {
        (0..<count).map { .phrase(phrase: "query \($0)") }
    }

    private func appearance(topHits: [Suggestion] = [],
                            ddg: [Suggestion] = [],
                            local: [Suggestion] = [],
                            isRedesignEnabled: Bool = true) -> AskDuckAIRowAppearance {
        AskDuckAIRowAppearance.make(isRedesignEnabled: isRedesignEnabled,
                                    result: SuggestionResult(topHits: topHits, duckduckgoSuggestions: ddg, localSuggestions: local))
    }

    func testWhenRedesignIsOff_AppearanceIsLegacyWhateverTheResult() {
        XCTAssertEqual(appearance(isRedesignEnabled: false), .legacy)
        XCTAssertEqual(appearance(ddg: phrases(8), isRedesignEnabled: false), .legacy)
    }

    func testEmptyResult_IsFullColour() {
        // The list shows a fallback row repeating the query here; it isn't a search suggestion.
        XCTAssertEqual(appearance(), .fullColour)
    }

    func testAtThreshold_IsFullColour() {
        XCTAssertEqual(appearance(ddg: phrases(AskDuckAIRowAppearance.highlightThreshold)), .fullColour)
    }

    func testAboveThreshold_IsOneColour() {
        XCTAssertEqual(appearance(ddg: phrases(AskDuckAIRowAppearance.highlightThreshold + 1)), .oneColour)
    }

    func testSearchSuggestionsCountFromEverySection() {
        XCTAssertEqual(appearance(topHits: phrases(1), ddg: phrases(1), local: phrases(1)), .oneColour)
    }

    func testSitesBookmarksHistoryAndOpenTabsDoNotCount() {
        let url = URL(string: "https://example.com")!
        let nonSearch: [Suggestion] = [
            .website(url: url),
            .bookmark(title: "Bookmark", url: url, isFavorite: false, score: 0),
            .bookmark(title: "Favorite", url: url, isFavorite: true, score: 0),
            .historyEntry(title: "History", url: url, score: 0),
            .openTab(title: "Tab", url: url, tabId: nil, score: 0)
        ]

        XCTAssertEqual(appearance(topHits: nonSearch, ddg: phrases(2), local: nonSearch), .fullColour)
    }
}
