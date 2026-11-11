//
//  SuggestionLoaderDebounceTests.swift
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
import CombineSchedulers
import Suggestions
import XCTest
@testable import DuckDuckGo

@MainActor
final class SuggestionLoaderDebounceTests: XCTestCase {

    func testSearchRejectsPreviousQueryDuringDebounce() async throws {
        for enabled in [false, true] {
            try await assertPreviousQueryIsRejected(duckAI: false, enabled: enabled, returnToOriginal: false)
        }
    }

    func testDuckAIRejectsPreviousQueryDuringDebounce() async throws {
        for enabled in [false, true] {
            try await assertPreviousQueryIsRejected(duckAI: true, enabled: enabled, returnToOriginal: false)
        }
    }

    func testSearchFetchesAgainWhenTypingReturnsToOriginalQuery() async throws {
        for enabled in [false, true] {
            try await assertPreviousQueryIsRejected(duckAI: false, enabled: enabled, returnToOriginal: true)
        }
    }

    func testDuckAIFetchesAgainWhenTypingReturnsToOriginalQuery() async throws {
        for enabled in [false, true] {
            try await assertPreviousQueryIsRejected(duckAI: true, enabled: enabled, returnToOriginal: true)
        }
    }

    private func assertPreviousQueryIsRejected(duckAI: Bool, enabled: Bool, returnToOriginal: Bool) async throws {
        let scheduler = DispatchQueue.test
        let text = PassthroughSubject<String, Never>()
        let dataSource = DeferredSuggestionDataSource()
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: enabled ? [.suggestionDebounce200ms] : [])
        let delay = enabled ? 200 : 100
        let results: AnyPublisher<Int, Never>
        let lastCompletedQuery: () -> String?
        let tearDown: () -> Void
        if duckAI {
            let loader = DuckAIURLSuggestionsLoader(dataSource: dataSource, featureFlagger: featureFlagger)
            loader.subscribeToTextChanges(text, scheduler: scheduler)
            results = loader.$topURLs.map(\.count).eraseToAnyPublisher()
            lastCompletedQuery = { loader.lastCompletedFetchQuery }
            tearDown = { loader.tearDown() }
        } else {
            let loader = SearchSuggestionsLoader(dataSource: dataSource, useUnifiedURLPrediction: false, featureFlagger: featureFlagger)
            loader.subscribeToTextChanges(text, scheduler: scheduler)
            results = loader.$result.map { $0.all.count }.eraseToAnyPublisher()
            lastCompletedQuery = { loader.lastCompletedFetchQuery }
            tearDown = { loader.tearDown() }
        }
        defer { tearDown() }

        text.send("weather forecast")
        await scheduler.advance(by: .milliseconds(delay))
        XCTAssertEqual(dataSource.queries, ["weather forecast"])
        let oldResponse = try XCTUnwrap(dataSource.completions.first)

        text.send("weather forecastx")
        let staleResult = expectation(description: "Previous query must not publish during debounce")
        staleResult.isInverted = true
        var subscription = results.dropFirst().sink { _ in staleResult.fulfill() }
        oldResponse(Data("[]".utf8), nil)
        await fulfillment(of: [staleResult], timeout: 0.2)
        subscription.cancel()
        XCTAssertNil(lastCompletedQuery())
        XCTAssertEqual(dataSource.queries, ["weather forecast"])

        if returnToOriginal {
            text.send("weather forecast")
        }
        await scheduler.advance(by: .milliseconds(delay))
        let expectedQuery = returnToOriginal ? "weather forecast" : "weather forecastx"
        XCTAssertEqual(dataSource.queries, ["weather forecast", expectedQuery])
        let currentResponse = try XCTUnwrap(dataSource.completions.dropFirst().first)
        let currentResult = expectation(description: "Current query publishes suggestions")
        var count = 0
        subscription = results.dropFirst().sink {
            count = $0
            currentResult.fulfill()
        }
        defer { subscription.cancel() }
        currentResponse(Data("[]".utf8), nil)
        await fulfillment(of: [currentResult], timeout: 2)
        XCTAssertEqual(lastCompletedQuery(), expectedQuery)
        XCTAssertGreaterThan(count, 0)
    }
}

private final class DeferredSuggestionDataSource: SuggestionLoadingDataSource {
    var queries = [String]()
    var completions = [(Data?, Error?) -> Void]()
    var platform: Platform { .mobile }

    func bookmarks(for suggestionLoading: SuggestionLoading) -> [Bookmark] { [WeatherBookmark()] }
    func history(for suggestionLoading: SuggestionLoading) -> [HistorySuggestion] { [] }
    func internalPages(for suggestionLoading: SuggestionLoading) -> [InternalPage] { [] }
    func openTabs(for suggestionLoading: SuggestionLoading) -> [BrowserTab] { [] }

    func suggestionLoading(_ suggestionLoading: SuggestionLoading,
                           suggestionDataFromUrl url: URL,
                           withParameters parameters: [String: String],
                           completion: @escaping (Data?, Error?) -> Void) {
        queries.append(parameters["q"] ?? "")
        completions.append(completion)
    }

    private struct WeatherBookmark: Bookmark {
        let url = "https://weather.example/"
        let title = "weather forecastx"
        let isFavorite = false
    }
}
