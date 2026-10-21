//
//  IPadOmnibarFocusModelTests.swift
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

import XCTest
@testable import DuckDuckGo

final class IPadOmnibarFocusModelTests: XCTestCase {

    typealias Model = IPadOmnibarFocusModel

    private let pageURL = "https://www.onet.pl/"
    private let duckAIURL = "https://duck.ai/chat?duckai=4"

    /// Builds a context with website defaults; override only what each test cares about.
    private func context(
        mode: Model.Mode = .search,
        pageKind: Model.PageKind = .website,
        hasFavorites: Bool = true,
        fieldText: String = "https://www.onet.pl/",
        pageURL: String? = "https://www.onet.pl/",
        userHasEditedText: Bool = false
    ) -> Model.Context {
        Model.Context(mode: mode,
                      pageKind: pageKind,
                      hasFavorites: hasFavorites,
                      fieldText: fieldText,
                      pageURL: pageURL,
                      userHasEditedText: userHasEditedText)
    }

    // MARK: - isShowingUneditedPageURL

    func testWhenFieldEqualsPageURLAndNotEditedThenShowingUneditedPageURL() {
        XCTAssertTrue(Model.isShowingUneditedPageURL(context()))
    }

    func testWhenUserHasEditedThenNotShowingUneditedPageURLEvenIfTextMatches() {
        XCTAssertFalse(Model.isShowingUneditedPageURL(context(userHasEditedText: true)))
    }

    func testWhenFieldDiffersFromPageURLThenNotShowingUneditedPageURL() {
        XCTAssertFalse(Model.isShowingUneditedPageURL(context(fieldText: "weather")))
    }

    func testWhenNoPageURLThenNotShowingUneditedPageURL() {
        XCTAssertFalse(Model.isShowingUneditedPageURL(context(fieldText: "", pageURL: nil)))
    }

    // MARK: - effectiveQuery

    func testWhenShowingUneditedPageURLThenEffectiveQueryIsEmpty() {
        XCTAssertEqual(Model.effectiveQuery(context()), "")
    }

    func testWhenEditedThenEffectiveQueryIsFieldText() {
        XCTAssertEqual(Model.effectiveQuery(context(fieldText: "weather", userHasEditedText: true)), "weather")
    }

    // MARK: - Search surface

    func testWhenSearchOnWebsiteWithUneditedURLAndFavoritesThenFavorites() {
        XCTAssertEqual(Model.surface(for: context(mode: .search)), .favorites)
    }

    func testWhenSearchOnWebsiteWithUneditedURLAndNoFavoritesThenNone() {
        XCTAssertEqual(Model.surface(for: context(mode: .search, hasFavorites: false)), .none)
    }

    func testWhenSearchAndUserTypesQueryThenSearchSuggestions() {
        let ctx = context(mode: .search, fieldText: "weather", userHasEditedText: true)
        XCTAssertEqual(Model.surface(for: ctx), .searchSuggestions(query: "weather"))
    }

    func testWhenSearchClearedToEmptyOnWebsiteThenFavoritesReshown() {
        // Clearing the field (no typed query) reshows favorites on a website.
        let ctx = context(mode: .search, fieldText: "", userHasEditedText: true)
        XCTAssertEqual(Model.surface(for: ctx), .favorites)
    }

    func testWhenSearchClearedToEmptyWithNoFavoritesThenNone() {
        let ctx = context(mode: .search, hasFavorites: false, fieldText: "", userHasEditedText: true)
        XCTAssertEqual(Model.surface(for: ctx), .none)
    }

    func testWhenSearchAndUserEditsURLBackToExactMatchThenStillSearchSuggestions() {
        // Edited, but text happens to equal the page URL again → autocomplete, not favorites.
        let ctx = context(mode: .search, fieldText: pageURL, userHasEditedText: true)
        XCTAssertEqual(Model.surface(for: ctx), .searchSuggestions(query: pageURL))
    }

    func testWhenSearchOnNewTabPageWithEmptyFieldThenNone() {
        // NTP shows its own favorites grid; the popover stays out until the user types.
        let ctx = context(mode: .search, pageKind: .newTabPage, fieldText: "", pageURL: nil)
        XCTAssertEqual(Model.surface(for: ctx), .none)
    }

    func testWhenSearchOnNewTabPageAndTypingThenSearchSuggestions() {
        let ctx = context(mode: .search, pageKind: .newTabPage, fieldText: "weather", pageURL: nil, userHasEditedText: true)
        XCTAssertEqual(Model.surface(for: ctx), .searchSuggestions(query: "weather"))
    }

    func testWhenSearchOnSERPWithQueryThenSearchSuggestions() {
        // On SERP the field shows the query (not the page URL), so it is a real query.
        let ctx = context(mode: .search, pageKind: .serp, fieldText: "cats", pageURL: "https://duckduckgo.com/?q=cats")
        XCTAssertEqual(Model.surface(for: ctx), .searchSuggestions(query: "cats"))
    }

    func testWhenSearchOnSERPWithUneditedURLThenNoneNotFavorites() {
        // Even unedited, SERP never shows favorites.
        let serp = "https://duckduckgo.com/?q=cats"
        let ctx = context(mode: .search, pageKind: .serp, fieldText: serp, pageURL: serp)
        XCTAssertEqual(Model.surface(for: ctx), .none)
    }

    // MARK: - Duck.ai surface

    func testWhenDuckAIOnDuckAISiteWithUneditedURLThenRecents() {
        // The unedited Duck.ai page URL → empty query → recents (not URL hits).
        let ctx = context(mode: .duckAI, fieldText: duckAIURL, pageURL: duckAIURL)
        XCTAssertEqual(Model.surface(for: ctx), .duckAISuggestions(query: ""))
    }

    func testWhenDuckAIWithEmptyClearedFieldThenRecents() {
        let ctx = context(mode: .duckAI, fieldText: "")
        XCTAssertEqual(Model.surface(for: ctx), .duckAISuggestions(query: ""))
    }

    func testWhenDuckAIAndUserTypesThenDuckAISuggestionsForQuery() {
        let ctx = context(mode: .duckAI, fieldText: "weather", userHasEditedText: true)
        XCTAssertEqual(Model.surface(for: ctx), .duckAISuggestions(query: "weather"))
    }
}
