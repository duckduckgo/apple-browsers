//
//  SuggestionTests.swift
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

final class SuggestionTests: XCTestCase {

    func testSuggestionInitializedFromBookmark() {
        let url = URL.aURL
        let title = "DuckDuckGo"
        let isFavorite = true
        let suggestion = Suggestion.bookmark(title: title, url: url, isFavorite: isFavorite, score: 0)

        XCTAssertEqual(suggestion.title, title)
        XCTAssertEqual(suggestion.url, url)
        XCTAssertFalse(suggestion.isHistoryEntry)
    }

    func testWhenUrlIsAccessed_ThenOnlySuggestionsThatContainUrlReturnsIt() {
        let url = URL.aURL

        let phraseSuggestion = Suggestion.phrase(phrase: "phrase")
        let websiteSuggestion = Suggestion.website(url: url)
        let bookmarkSuggestion = Suggestion.bookmark(title: "Title", url: url, isFavorite: true, score: 0)
        let historyEntrySuggestion = Suggestion.historyEntry(title: "Title", url: url, score: 0)
        _ = Suggestion.unknown(value: "phrase")

        XCTAssertNil(phraseSuggestion.url)
        XCTAssertEqual(websiteSuggestion.url, url)
        XCTAssertEqual(bookmarkSuggestion.url, url)
        XCTAssertEqual(historyEntrySuggestion.url, url)
        XCTAssertNil(phraseSuggestion.url)
    }

    func testWhenTitleIsAccessed_ThenOnlySuggestionsThatContainUrlStoreIt() {
        let url = URL.aURL
        let title = "Original Title"

        let phraseSuggestion = Suggestion.phrase(phrase: "phrase")
        let websiteSuggestion = Suggestion.website(url: url)
        let bookmarkSuggestion = Suggestion.bookmark(title: title, url: url, isFavorite: true, score: 0)
        let historyEntrySuggestion = Suggestion.historyEntry(title: title, url: url, score: 0)
        _ = Suggestion.unknown(value: "phrase")

        XCTAssertNil(phraseSuggestion.title)
        XCTAssertNil(websiteSuggestion.title)
        XCTAssertEqual(bookmarkSuggestion.title, title)
        XCTAssertEqual(historyEntrySuggestion.title, title)
        XCTAssertNil(phraseSuggestion.title)
    }

    func testWhenInitFromHistoryEntry_ThenHistroryEntrySuggestionIsInitialized() {
        let url = URL.aURL
        let title = "Title"

        let suggestion = Suggestion.historyEntry(title: title, url: url, score: 1)

        guard case .historyEntry = suggestion else {
            XCTFail("Wrong type of suggestion")
            return
        }

        XCTAssertEqual(suggestion.url, url)
        XCTAssertEqual(suggestion.title, title)
        XCTAssertTrue(suggestion.isHistoryEntry)
    }

    func testHistoryEntryWithNilTitle() {
        let url = URL.aURL
        let score = 7

        let suggestion = Suggestion.historyEntry(title: nil, url: url, score: score)

        guard case let .historyEntry(title, _, storedScore) = suggestion else {
            XCTFail("Wrong type of suggestion")
            return
        }

        XCTAssertNil(title)
        XCTAssertEqual(storedScore, score)
        XCTAssertTrue(suggestion.isHistoryEntry)
    }

    func testSuggestionInitializedFromInternalPage() {
        let url = URL.aURL
        let title = "Settings"
        let score = 5
        let suggestion = Suggestion.internalPage(title: title, url: url, score: score)

        guard case .internalPage = suggestion else {
            XCTFail("Wrong type of suggestion")
            return
        }

        XCTAssertEqual(suggestion.url, url)
        XCTAssertEqual(suggestion.title, title)
        XCTAssertFalse(suggestion.isHistoryEntry)
    }

    func testSuggestionInitializedFromOpenTab() {
        let url = URL.aURL
        let title = "DuckDuckGo Tab"
        let tabId = "tab123"
        let score = 10
        let suggestion = Suggestion.openTab(title: title, url: url, tabId: tabId, score: score)

        guard case let .openTab(_, _, storedTabId, storedScore) = suggestion else {
            XCTFail("Wrong type of suggestion")
            return
        }

        XCTAssertEqual(suggestion.url, url)
        XCTAssertEqual(suggestion.title, title)
        XCTAssertEqual(storedTabId, tabId)
        XCTAssertEqual(storedScore, score)
        XCTAssertFalse(suggestion.isHistoryEntry)
    }

    func testSuggestionInitializedFromUnknown() {
        let value = "unknown value"
        let suggestion = Suggestion.unknown(value: value)

        guard case let .unknown(storedValue) = suggestion else {
            XCTFail("Wrong type of suggestion")
            return
        }

        XCTAssertEqual(storedValue, value)
        XCTAssertNil(suggestion.url)
        XCTAssertNil(suggestion.title)
        XCTAssertFalse(suggestion.isHistoryEntry)
    }

    func testBookmarkSuggestionIsFavoriteFlag() {
        let url = URL.aURL
        let title = "Favorite Bookmark"
        let score = 15

        let favoriteSuggestion = Suggestion.bookmark(title: title, url: url, isFavorite: true, score: score)
        let regularSuggestion = Suggestion.bookmark(title: title, url: url, isFavorite: false, score: score)

        guard case let .bookmark(_, _, isFavorite1, storedScore1) = favoriteSuggestion,
              case let .bookmark(_, _, isFavorite2, storedScore2) = regularSuggestion else {
            XCTFail("Wrong type of suggestion")
            return
        }

        XCTAssertTrue(isFavorite1)
        XCTAssertFalse(isFavorite2)
        XCTAssertEqual(storedScore1, score)
        XCTAssertEqual(storedScore2, score)
        XCTAssertNotEqual(favoriteSuggestion, regularSuggestion)
    }

}

fileprivate extension URL {

    static let aURL = URL(string: "https://www.duckduckgo.com")!
    static let aRootUrl = aURL
    static let aNonRootUrl = URL(string: "https://www.duckduckgo.com/traffic")!

}
