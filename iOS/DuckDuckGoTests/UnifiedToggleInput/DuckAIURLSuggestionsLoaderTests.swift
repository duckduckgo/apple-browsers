//
//  DuckAIURLSuggestionsLoaderTests.swift
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

import Combine
import Suggestions
import XCTest
@testable import DuckDuckGo

@MainActor
final class DuckAIURLSuggestionsLoaderTests: XCTestCase {

    func test_filtersToURLTypesOnly_droppingPhrasesAndAskAIChat() throws {
        let raw = SuggestionResult(
            topHits: [
                .website(url: try XCTUnwrap(URL(string: "https://example.com/"))),
                .phrase(phrase: "weather"),
                .askAIChat(value: "weather")
            ],
            duckduckgoSuggestions: [.phrase(phrase: "x")],
            localSuggestions: [
                .historyEntry(title: "Y", url: try XCTUnwrap(URL(string: "https://y.com")), score: 1)
            ]
        )

        let urls = DuckAIURLSuggestionsLoader.urlOnlyTopHits(from: raw, max: 3)

        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls.first?.url?.host, "example.com")
        XCTAssertEqual(urls.last?.url?.host, "y.com")
    }

    func test_capsAtMaximumCount() throws {
        let many = try (0..<10).map {
            Suggestion.website(url: try XCTUnwrap(URL(string: "https://h\($0).com/")))
        }
        let raw = SuggestionResult(topHits: many, duckduckgoSuggestions: [], localSuggestions: [])

        let urls = DuckAIURLSuggestionsLoader.urlOnlyTopHits(from: raw, max: 3)

        XCTAssertEqual(urls.count, 3)
    }

    func test_returnsEmptyWhenAllSourcesEmpty() {
        let raw = SuggestionResult(topHits: [], duckduckgoSuggestions: [], localSuggestions: [])

        let urls = DuckAIURLSuggestionsLoader.urlOnlyTopHits(from: raw, max: 3)

        XCTAssertTrue(urls.isEmpty)
    }

    func test_takesFromTopHitsBeforeDuckDuckGoSuggestionsBeforeLocal() throws {
        let raw = SuggestionResult(
            topHits: [.website(url: try XCTUnwrap(URL(string: "https://top.com/")))],
            duckduckgoSuggestions: [.website(url: try XCTUnwrap(URL(string: "https://ddg.com/")))],
            localSuggestions: [.bookmark(title: "L", url: try XCTUnwrap(URL(string: "https://local.com/")), isFavorite: false, score: 1)]
        )

        let urls = DuckAIURLSuggestionsLoader.urlOnlyTopHits(from: raw, max: 2)

        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls.first?.url?.host, "top.com")
        XCTAssertEqual(urls.last?.url?.host, "ddg.com")
    }

    // MARK: - Settle tracking
    // `hasSettled(forQuery:)` on the coordinator gates Dax visibility — if the loader never records
    // `lastCompletedFetchQuery`, Dax stays permanently suppressed. Empty-query fetches must settle synchronously.

    func test_emptyQueryFetch_setsLastCompletedFetchQuerySynchronously() {
        let loader = DuckAIURLSuggestionsLoader(dataSource: EmptySuggestionLoadingDataSource())
        XCTAssertNil(loader.lastCompletedFetchQuery)

        loader.fetch(query: "")

        XCTAssertEqual(loader.lastCompletedFetchQuery, "")
    }

    func test_emptyQueryFetch_clearsTopURLsOnlyWhenNonEmpty() {
        let loader = DuckAIURLSuggestionsLoader(dataSource: EmptySuggestionLoadingDataSource())
        loader.publishURLsForTesting([.website(url: URL(string: "https://example.com/")!)])
        var emissions: [[Suggestion]] = []
        let cancellable = loader.$topURLs.sink { emissions.append($0) }
        emissions.removeAll()

        loader.fetch(query: "")

        XCTAssertEqual(emissions.count, 1, "non-empty → empty transition emits exactly once")
        XCTAssertTrue(emissions.first?.isEmpty ?? false)

        emissions.removeAll()
        loader.fetch(query: "")

        XCTAssertTrue(emissions.isEmpty, "already-empty must not re-emit (downstream reload-coalesce relies on this)")
        cancellable.cancel()
    }
}

