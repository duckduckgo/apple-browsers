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
        let bookmarkMock = BookmarkMock(url: url.absoluteString, title: title, isFavorite: isFavorite)
        let suggestion = Suggestion(bookmark: bookmarkMock, score: 0)

        XCTAssertEqual(suggestion, Suggestion.bookmark(title: title, url: url, isFavorite: isFavorite, score: 0))
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

        let historyEntry = HistoryEntryMock(identifier: UUID(), url: url, title: title, numberOfVisits: 1, lastVisit: Date(), failedToLoad: false, isDownload: false)
        let suggestion = Suggestion(historyEntry: historyEntry, score: 0)

        guard case .historyEntry = suggestion else {
            XCTFail("Wrong type of suggestion")
            return
        }

        XCTAssertEqual(suggestion.url, url)
        XCTAssertEqual(suggestion.title, title)
    }

    func testWhenInitFromBookmark_ThenBookmarkSuggestionIsInitialized() {
        let url = URL.aURL
        let title = "Title"

        let bookmark = BookmarkMock(url: url.absoluteString, title: title, isFavorite: true)
        let suggestion = Suggestion(bookmark: bookmark, score: 0)

        guard let suggestion = suggestion,
              case .bookmark = suggestion else {
            XCTFail("Wrong type of suggestion")
            return
        }

        XCTAssertEqual(suggestion.url, url)
        XCTAssertEqual(suggestion.title, title)
    }

    func testWhenInitFromURL_ThenWebsiteSuggestionIsInitialized() {
        let url = URL.aURL
        let suggestion = Suggestion(url: url)

        guard case .website(let websiteUrl) = suggestion else {
            XCTFail("Wrong type of suggestion")
            return
        }

        XCTAssertEqual(suggestion.url, url)
        XCTAssertEqual(websiteUrl, url)
    }

}

fileprivate extension URL {

    static let aURL = URL(string: "https://www.duckduckgo.com")!
    static let aRootUrl = aURL
    static let aNonRootUrl = URL(string: "https://www.duckduckgo.com/traffic")!

}
