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

    func testEnabledLocalSuggestionsPublishBeforeRemoteRequestInBothLoaders() async {
        for duckAI in [false, true] {
            let harness = Harness(duckAI: duckAI, enabled: true)
            defer { harness.tearDown() }
            let localResult = expectation(description: "Local suggestions publish without waiting for ac")
            let subscription = harness.results.dropFirst().filter { $0 > 0 }.prefix(1).sink { _ in localResult.fulfill() }
            harness.text.send("weather")
            await fulfillment(of: [localResult], timeout: 2)
            subscription.cancel()
            XCTAssertEqual(harness.dataSource.localLoads, 1)
            XCTAssertTrue(harness.dataSource.queries.isEmpty)
            XCTAssertNil(harness.lastCompletedQuery())

            await harness.scheduler.advance(by: .milliseconds(149))
            XCTAssertTrue(harness.dataSource.queries.isEmpty)
            await harness.scheduler.advance(by: .milliseconds(1))
            XCTAssertEqual(harness.dataSource.queries, ["weather"])
            let remoteResult = expectation(description: "Remote response publishes")
            let remoteSubscription = harness.results.dropFirst().prefix(1).sink { _ in remoteResult.fulfill() }
            harness.dataSource.completions[0](Data("[]".utf8), nil)
            await fulfillment(of: [remoteResult], timeout: 2)
            remoteSubscription.cancel()
            XCTAssertEqual(harness.lastCompletedQuery(), "weather")
        }
    }

    func testDisabledFlagKeeps100MillisecondCombinedFetchAndAcceptsResponseDuringDebounce() async {
        for duckAI in [false, true] {
            let harness = Harness(duckAI: duckAI, enabled: false)
            defer { harness.tearDown() }
            harness.text.send("weather")
            await harness.scheduler.advance(by: .milliseconds(99))
            XCTAssertEqual(harness.dataSource.localLoads, 0)
            XCTAssertTrue(harness.dataSource.queries.isEmpty)
            await harness.scheduler.advance(by: .milliseconds(1))
            XCTAssertEqual(harness.dataSource.localLoads, 1)
            XCTAssertEqual(harness.dataSource.queries, ["weather"])
            harness.text.send("weather forecast")
            let response = expectation(description: "Production accepts the last dispatched query during debounce")
            let subscription = harness.results.dropFirst().prefix(1).sink { _ in response.fulfill() }
            harness.dataSource.completions[0](Data("[]".utf8), nil)
            await fulfillment(of: [response], timeout: 2)
            subscription.cancel()
            XCTAssertEqual(harness.lastCompletedQuery(), "weather")
            await harness.scheduler.advance(by: .milliseconds(100))
            XCTAssertEqual(harness.dataSource.queries, ["weather", "weather forecast"])
        }
    }

    func testEnabledFirstRemoteResponsePublishesWhileTypingIfLocalResultsAreEmpty() async {
        for duckAI in [false, true] {
            let harness = Harness(duckAI: duckAI, enabled: true)
            defer { harness.tearDown() }
            harness.dataSource.hasBookmarks = false
            let localResult = expectation(description: "Empty local fetch completes")
            let localSubscription = harness.results.dropFirst().prefix(1).sink { _ in localResult.fulfill() }
            harness.text.send("weather")
            await fulfillment(of: [localResult], timeout: 2)
            localSubscription.cancel()
            await harness.scheduler.advance(by: .milliseconds(150))
            harness.text.send("weather forecast")
            let remoteResult = expectation(description: "First remote response fills empty list during typing")
            let subscription = harness.results.dropFirst().filter { $0 > 0 }.prefix(1).sink { _ in remoteResult.fulfill() }
            harness.dataSource.completions[0](Data(#"[{"phrase":"https://weather.example/","isNav":true}]"#.utf8), nil)
            await fulfillment(of: [remoteResult], timeout: 2)
            subscription.cancel()
            XCTAssertEqual(harness.lastCompletedQuery(), "weather")
        }
    }

    func testEnabledResponseIsRejectedWhileTypingWhenResultsAlreadyExist() async {
        for duckAI in [false, true] {
            let harness = Harness(duckAI: duckAI, enabled: true)
            defer { harness.tearDown() }
            let localResult = expectation(description: "Local suggestions fill the list")
            let localSubscription = harness.results.dropFirst().filter { $0 > 0 }.prefix(1).sink { _ in localResult.fulfill() }
            harness.text.send("weather")
            await fulfillment(of: [localResult], timeout: 2)
            localSubscription.cancel()
            await harness.scheduler.advance(by: .milliseconds(150))
            harness.text.send("weather forecast")
            let staleResult = expectation(description: "Established list rejects outdated response during debounce")
            staleResult.isInverted = true
            let subscription = harness.results.dropFirst().sink { _ in staleResult.fulfill() }
            harness.dataSource.completions[0](Data("[]".utf8), nil)
            await fulfillment(of: [staleResult], timeout: 0.2)
            subscription.cancel()
            XCTAssertNil(harness.lastCompletedQuery())
        }
    }

    func testEnabledClearingQueryRejectsRemoteResponseAndRestartsLocalFetch() async {
        for duckAI in [false, true] {
            let harness = Harness(duckAI: duckAI, enabled: true)
            defer { harness.tearDown() }
            let localResult = expectation(description: "Local fetch completes")
            let localSubscription = harness.results.dropFirst().prefix(1).sink { _ in localResult.fulfill() }
            harness.text.send("weather")
            await fulfillment(of: [localResult], timeout: 2)
            localSubscription.cancel()
            await harness.scheduler.advance(by: .milliseconds(150))
            harness.text.send("")
            XCTAssertEqual(harness.lastCompletedQuery(), "")
            let staleResult = expectation(description: "Cleared results stay empty")
            staleResult.isInverted = true
            let subscription = harness.results.dropFirst().sink { _ in staleResult.fulfill() }
            harness.dataSource.completions[0](Data("[]".utf8), nil)
            await fulfillment(of: [staleResult], timeout: 0.2)
            subscription.cancel()
            let previousLocalLoads = harness.dataSource.localLoads
            harness.text.send("forecast")
            XCTAssertEqual(harness.dataSource.localLoads, previousLocalLoads + 1)
            XCTAssertEqual(harness.dataSource.queries, ["weather"])
        }
    }

    func testDisabledFlagDoesNotRefetchWhenTypingReturnsToLastDispatchedQuery() async {
        for duckAI in [false, true] {
            let harness = Harness(duckAI: duckAI, enabled: false)
            defer { harness.tearDown() }
            harness.text.send("weather")
            await harness.scheduler.advance(by: .milliseconds(100))
            harness.text.send("weather forecast")
            await harness.scheduler.advance(by: .milliseconds(50))
            harness.text.send("weather")
            await harness.scheduler.advance(by: .milliseconds(100))
            XCTAssertEqual(harness.dataSource.queries, ["weather"])
        }
    }

    func testReturningToSameQueryRejectsResponseFromEarlierFetch() async {
        let dataSource = DeferredSuggestionDataSource()
        let loader = DuckAIURLSuggestionsLoader(dataSource: dataSource,
                                                 featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.suggestionDebounce200ms]))
        loader.fetch(query: "weather")
        loader.fetch(query: "forecast")
        loader.fetch(query: "weather")
        let staleResult = expectation(description: "Earlier fetch for same query is rejected")
        staleResult.isInverted = true
        let subscription = loader.$topURLs.dropFirst().sink { _ in staleResult.fulfill() }
        dataSource.completions[0](Data("[]".utf8), nil)
        await fulfillment(of: [staleResult], timeout: 0.2)
        subscription.cancel()
        XCTAssertNil(loader.lastCompletedFetchQuery)

        let currentResult = expectation(description: "Latest fetch for same query publishes")
        let currentSubscription = loader.$topURLs.dropFirst().sink { _ in currentResult.fulfill() }
        defer { currentSubscription.cancel() }
        dataSource.completions[2](Data("[]".utf8), nil)
        await fulfillment(of: [currentResult], timeout: 2)
        XCTAssertEqual(loader.lastCompletedFetchQuery, "weather")
        XCTAssertFalse(loader.topURLs.isEmpty)
    }

    @MainActor
    private final class Harness {
        let scheduler = DispatchQueue.test
        let text = PassthroughSubject<String, Never>()
        let dataSource = DeferredSuggestionDataSource()
        let results: AnyPublisher<Int, Never>
        let lastCompletedQuery: () -> String?
        let tearDown: () -> Void

        init(duckAI: Bool, enabled: Bool) {
            let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: enabled ? [.suggestionDebounce200ms] : [])
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
        }
    }
}

private final class DeferredSuggestionDataSource: SuggestionLoadingDataSource {
    var queries = [String]()
    var completions = [(Data?, Error?) -> Void]()
    var localLoads = 0
    var hasBookmarks = true
    var platform: Platform { .mobile }

    func bookmarks(for suggestionLoading: SuggestionLoading) -> [Bookmark] {
        localLoads += 1
        return hasBookmarks ? [WeatherBookmark()] : []
    }
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
