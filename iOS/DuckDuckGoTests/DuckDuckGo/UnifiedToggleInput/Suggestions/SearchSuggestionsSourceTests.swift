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

import AIChat
import Combine
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
        let sections = SearchSuggestionsSource.sections(from: result, query: "ca", showAskAIChat: false, isAskDuckAIRedesignEnabled: false)
        XCTAssertEqual(sections.map(\.id), ["topHits", "ddg", "local"])
    }

    func test_askAIChatSection_whenEnabled_withQuery() {
        let sections = SearchSuggestionsSource.sections(from: .appEmpty, query: "weather", showAskAIChat: true, isAskDuckAIRedesignEnabled: false)
        XCTAssertTrue(sections.contains { $0.id == "askAIChat" })
    }

    func test_historyRow_hasDeleteAccessory() {
        let url = URL(string: "https://h.com")!
        let result = SuggestionResult(
            topHits: [.historyEntry(title: "H", url: url, score: 0)],
            duckduckgoSuggestions: [],
            localSuggestions: []
        )
        let sections = SearchSuggestionsSource.sections(from: result, query: "h", showAskAIChat: false, isAskDuckAIRedesignEnabled: false)
        XCTAssertEqual(sections.first?.rows.first?.accessory, .delete)
    }

    func test_resolvesRowIDToSuggestion() {
        let url = URL(string: "https://a.com")!
        let suggestion = Suggestion.website(url: url)
        let result = SuggestionResult(topHits: [suggestion], duckduckgoSuggestions: [], localSuggestions: [])
        let resolved = SearchSuggestionsSource.suggestion(forRowID: "topHits-website-\(url.absoluteString)", in: result, query: "a", showAskAIChat: false)
        XCTAssertEqual(resolved, suggestion)
    }

    func test_emptyResultFallbackPhraseRow_isResolvable() {
        // No results → a single phrase fallback row (the query). The displayed row must resolve back
        // to a suggestion so tapping it is handled (it previously resolved against the empty result → nil).
        let sections = SearchSuggestionsSource.sections(from: .appEmpty, query: "zxqw", showAskAIChat: false, isAskDuckAIRedesignEnabled: false)
        let rowID = try? XCTUnwrap(sections.first?.rows.first?.id)
        XCTAssertEqual(rowID, "topHits-phrase-zxqw")
        let resolved = SearchSuggestionsSource.suggestion(forRowID: "topHits-phrase-zxqw", in: .appEmpty, query: "zxqw", showAskAIChat: false)
        XCTAssertEqual(resolved, .phrase(phrase: "zxqw"))
    }

    func test_settingsChangesUpdateExistingSourceWithoutNewQueryOrResults() async {
        let notifications = NotificationCenter()
        let settings = MockAIChatSettingsProvider(isAIChatEnabled: true)
        let loader = SearchSuggestionsLoader(dataSource: EmptySuggestionLoadingDataSource(), useUnifiedURLPrediction: false, featureFlagger: MockFeatureFlagger())
        let source = SearchSuggestionsSource(loader: loader, query: { "weather" }, aiChatSettings: settings, featureFlagger: MockFeatureFlagger(), notificationCenter: notifications)
        var emissions = [[SuggestionSection]]()
        let subscription = source.sectionsPublisher.sink { emissions.append($0) }
        defer { subscription.cancel() }

        XCTAssertEqual(emissions.last?.map(\.id), ["topHits", "askAIChat"])
        let searchRows = emissions.last?.first?.rows

        settings.isAIChatEnabled = false
        await postSettingsChanged(to: notifications)

        XCTAssertEqual(emissions.last?.map(\.id), ["topHits"])
        XCTAssertEqual(emissions.last?.first?.rows, searchRows)

        settings.isAIChatEnabled = true
        await postSettingsChanged(to: notifications)

        XCTAssertEqual(emissions.last?.map(\.id), ["topHits", "askAIChat"])
        XCTAssertEqual(emissions.last?.first?.rows, searchRows)
        XCTAssertEqual(emissions.count, 3)
        XCTAssertEqual(loader.result, .appEmpty)
        XCTAssertNil(loader.lastCompletedFetchQuery)
    }

    func test_sourceCreatedWhileAIChatIsDisabledAddsRowWhenEnabled() async {
        let notifications = NotificationCenter()
        let settings = MockAIChatSettingsProvider(isAIChatEnabled: false)
        let loader = SearchSuggestionsLoader(dataSource: EmptySuggestionLoadingDataSource(), useUnifiedURLPrediction: false, featureFlagger: MockFeatureFlagger())
        let source = SearchSuggestionsSource(loader: loader, query: { "weather" }, aiChatSettings: settings, featureFlagger: MockFeatureFlagger(), notificationCenter: notifications)
        var sections = [SuggestionSection]()
        let subscription = source.sectionsPublisher.sink { sections = $0 }
        defer { subscription.cancel() }

        XCTAssertEqual(sections.map(\.id), ["topHits"])

        settings.isAIChatEnabled = true
        await postSettingsChanged(to: notifications)

        XCTAssertEqual(sections.map(\.id), ["topHits", "askAIChat"])
        XCTAssertEqual(source.suggestion(forRowID: "askAIChat-askAIChat-weather"), .askAIChat(value: "weather"))
        XCTAssertNil(loader.lastCompletedFetchQuery)
    }

    func test_disablingAIChatRejectsStaleRowBeforeSettingsNotification() throws {
        let settings = MockAIChatSettingsProvider(isAIChatEnabled: true)
        let loader = SearchSuggestionsLoader(dataSource: EmptySuggestionLoadingDataSource(), useUnifiedURLPrediction: false, featureFlagger: MockFeatureFlagger())
        let source = SearchSuggestionsSource(loader: loader, query: { "weather" }, aiChatSettings: settings, featureFlagger: MockFeatureFlagger(), notificationCenter: NotificationCenter())
        var sections = [SuggestionSection]()
        let subscription = source.sectionsPublisher.sink { sections = $0 }
        defer { subscription.cancel() }
        let rowID = try XCTUnwrap(sections.first { $0.id == "askAIChat" }?.rows.first?.id)
        XCTAssertEqual(source.suggestion(forRowID: rowID), .askAIChat(value: "weather"))

        settings.isAIChatEnabled = false

        XCTAssertTrue(sections.contains { $0.id == "askAIChat" }, "The UI still has the stale row until its settings notification arrives")
        XCTAssertNil(source.suggestion(forRowID: rowID))
        XCTAssertEqual(source.suggestion(forRowID: "topHits-phrase-weather"), .phrase(phrase: "weather"))
    }

    func test_lateLoaderResponseAndResetDoNotRestoreDisabledAIChatRow() async throws {
        let notifications = NotificationCenter()
        let settings = MockAIChatSettingsProvider(isAIChatEnabled: true)
        let dataSource = DelayedSearchSuggestionLoadingDataSource()
        let loader = SearchSuggestionsLoader(dataSource: dataSource, useUnifiedURLPrediction: false, featureFlagger: MockFeatureFlagger())
        let source = SearchSuggestionsSource(loader: loader, query: { "weather" }, aiChatSettings: settings, featureFlagger: MockFeatureFlagger(), notificationCenter: notifications)
        var sections = [SuggestionSection]()
        let subscription = source.sectionsPublisher.sink { sections = $0 }
        defer { subscription.cancel() }
        XCTAssertTrue(sections.contains { $0.id == "askAIChat" })
        loader.fetch(query: "weather")
        let completeResponse = try XCTUnwrap(dataSource.pendingCompletion)
        dataSource.pendingCompletion = nil

        settings.isAIChatEnabled = false
        await postSettingsChanged(to: notifications)
        XCTAssertFalse(sections.contains { $0.id == "askAIChat" })

        let responsePublished = expectation(description: "Delayed suggestions are published")
        let resultSubscription = loader.$result.dropFirst().prefix(1).sink { _ in responsePublished.fulfill() }
        defer { resultSubscription.cancel() }
        completeResponse(Data(#"[{"phrase":"weather tomorrow"}]"#.utf8), nil)
        await fulfillment(of: [responsePublished], timeout: 2)

        XCTAssertEqual(loader.lastCompletedFetchQuery, "weather")
        XCTAssertTrue(loader.result.duckduckgoSuggestions.contains(.phrase(phrase: "weather tomorrow")))
        XCTAssertFalse(sections.contains { $0.id == "askAIChat" })
        XCTAssertEqual(source.suggestion(forRowID: "ddg-phrase-weather tomorrow"), .phrase(phrase: "weather tomorrow"))

        loader.reset()

        XCTAssertEqual(sections.map(\.id), ["topHits"])
        XCTAssertEqual(source.suggestion(forRowID: "topHits-phrase-weather"), .phrase(phrase: "weather"))
        XCTAssertNil(source.suggestion(forRowID: "askAIChat-askAIChat-weather"))
    }

    // MARK: - Ask Duck.ai row

    private func askDuckAIRow(in sections: [SuggestionSection]) -> SuggestionRow? {
        sections.first { $0.id == "askAIChat" }?.rows.first
    }

    func test_askDuckAIRow_whenRedesignOff_isTodaysRow() throws {
        let sections = SearchSuggestionsSource.sections(from: .appEmpty, query: "weather ", showAskAIChat: true, isAskDuckAIRedesignEnabled: false)
        let row = try XCTUnwrap(askDuckAIRow(in: sections))

        XCTAssertEqual(row.id, "askAIChat-askAIChat-weather ")
        XCTAssertEqual(row.accessibilityID, "Autocomplete.Suggestions.ListItem.AskAIChat-weather ")
        XCTAssertEqual(row.icon, .aiChat)
        XCTAssertEqual(row.title, "weather ")
        XCTAssertEqual(row.subtitle, UserText.autocompleteAskAIChat)
    }

    func test_askDuckAIRow_whenRedesignOn_readsAskDuckAIOverTheTrimmedQuery_withSameIDs() throws {
        let sections = SearchSuggestionsSource.sections(from: .appEmpty, query: "weather ", showAskAIChat: true, isAskDuckAIRedesignEnabled: true)
        let row = try XCTUnwrap(askDuckAIRow(in: sections))

        XCTAssertEqual(row.id, "askAIChat-askAIChat-weather ")
        XCTAssertEqual(row.accessibilityID, "Autocomplete.Suggestions.ListItem.AskAIChat-weather ")
        XCTAssertEqual(row.title, "Ask Duck.ai")
        XCTAssertEqual(row.subtitle, "weather")
        XCTAssertNil(row.query)
        XCTAssertEqual(row.accessory, .none)
    }

    func test_askDuckAIRow_whenRedesignOn_keepsOneListIdentityWhileTheQueryChanges() throws {
        // The logo can only cross-fade if the row's view survives the keystroke that crosses the threshold.
        let short = try XCTUnwrap(askDuckAIRow(in: SearchSuggestionsSource.sections(
            from: .appEmpty, query: "wea", showAskAIChat: true, isAskDuckAIRedesignEnabled: true)))
        let long = try XCTUnwrap(askDuckAIRow(in: SearchSuggestionsSource.sections(
            from: .appEmpty, query: "weather tomorrow", showAskAIChat: true, isAskDuckAIRedesignEnabled: true)))

        XCTAssertNotEqual(short.id, long.id)
        XCTAssertEqual(short.viewID, long.viewID)
    }

    func test_askDuckAIRow_whenRedesignOff_isIdentifiedByItsIDAsToday() throws {
        let row = try XCTUnwrap(askDuckAIRow(in: SearchSuggestionsSource.sections(
            from: .appEmpty, query: "weather", showAskAIChat: true, isAskDuckAIRedesignEnabled: false)))

        XCTAssertEqual(row.viewID, row.id)
    }

    func test_askDuckAIRow_whenRedesignOn_logoFollowsSearchSuggestionCount() throws {
        let threshold = AskDuckAIRowAppearance.highlightThreshold
        func icon(phraseCount: Int) throws -> SuggestionRowIcon {
            let result = SuggestionResult(topHits: [],
                                          duckduckgoSuggestions: (0..<phraseCount).map { .phrase(phrase: "weather \($0)") },
                                          localSuggestions: [.website(url: URL(string: "https://weather.com")!)])
            let sections = SearchSuggestionsSource.sections(from: result, query: "weather", showAskAIChat: true, isAskDuckAIRedesignEnabled: true)
            return try XCTUnwrap(askDuckAIRow(in: sections)).icon
        }

        XCTAssertEqual(try icon(phraseCount: 0), .duckAI(highlighted: true))
        XCTAssertEqual(try icon(phraseCount: threshold), .duckAI(highlighted: true))
        XCTAssertEqual(try icon(phraseCount: threshold + 1), .duckAI(highlighted: false))
    }

    func test_askDuckAIRow_whenRedesignOn_otherRowsAreUnchanged() {
        let result = SuggestionResult(topHits: [.website(url: URL(string: "https://a.com")!)],
                                      duckduckgoSuggestions: [.phrase(phrase: "cats")],
                                      localSuggestions: [])
        let off = SearchSuggestionsSource.sections(from: result, query: "ca", showAskAIChat: true, isAskDuckAIRedesignEnabled: false)
        let on = SearchSuggestionsSource.sections(from: result, query: "ca", showAskAIChat: true, isAskDuckAIRedesignEnabled: true)

        XCTAssertEqual(on.map(\.id), off.map(\.id))
        XCTAssertEqual(on.filter { $0.id != "askAIChat" }, off.filter { $0.id != "askAIChat" })
    }

    func test_askDuckAIRow_whenRedesignOn_tapResolvesToTheTypedQuery() throws {
        let loader = SearchSuggestionsLoader(dataSource: EmptySuggestionLoadingDataSource(), useUnifiedURLPrediction: false, featureFlagger: MockFeatureFlagger())
        let source = SearchSuggestionsSource(loader: loader,
                                             query: { "weather" },
                                             aiChatSettings: MockAIChatSettingsProvider(isAIChatEnabled: true),
                                             featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.askDuckAIRowRedesign]),
                                             notificationCenter: NotificationCenter())
        var sections = [SuggestionSection]()
        let subscription = source.sectionsPublisher.sink { sections = $0 }
        defer { subscription.cancel() }

        let row = try XCTUnwrap(askDuckAIRow(in: sections))
        XCTAssertEqual(row.title, "Ask Duck.ai")
        XCTAssertEqual(row.id, "askAIChat-askAIChat-weather")
        XCTAssertEqual(source.suggestion(forRowID: row.id), .askAIChat(value: "weather"))
    }

    private func postSettingsChanged(to notifications: NotificationCenter) async {
        notifications.post(name: .aiChatSettingsChanged, object: nil)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}

private final class DelayedSearchSuggestionLoadingDataSource: SuggestionLoadingDataSource {
    var pendingCompletion: ((Data?, Error?) -> Void)?

    var platform: Platform { .mobile }

    func bookmarks(for suggestionLoading: SuggestionLoading) -> [Bookmark] { [] }
    func history(for suggestionLoading: SuggestionLoading) -> [HistorySuggestion] { [] }
    func internalPages(for suggestionLoading: SuggestionLoading) -> [InternalPage] { [] }
    func openTabs(for suggestionLoading: SuggestionLoading) -> [BrowserTab] { [] }

    func suggestionLoading(_ suggestionLoading: SuggestionLoading,
                           suggestionDataFromUrl url: URL,
                           withParameters parameters: [String: String],
                           completion: @escaping (Data?, Error?) -> Void) {
        pendingCompletion = completion
    }
}
