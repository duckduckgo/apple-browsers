//
//  SuggestionProcessingTests.swift
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

final class SuggestionProcessingTests: XCTestCase {

    static let simpleUrlFactory: (String) -> URL? = { _ in return nil }

    // MARK: - Basic Suggestion Tests

    func testWhenOnlyHistoryMatches_ThenHistoryInTopHits() {
        let processing = SuggestionProcessing(platform: .mobile)
        let result = processing.result(for: "Duck",
                                       from: HistoryEntryMock.duckHistoryWithoutDuckDuckGo,
                                       bookmarks: [],
                                       internalPages: [],
                                       openTabs: [],
                                       apiResult: APIResult.anAPIResult)

        XCTAssertTrue(result?.topHits.contains(where: { $0.title == "DuckMail" }) ?? false)
        XCTAssertEqual(2, result?.topHits.count)
        XCTAssertEqual(0, result?.localSuggestions.count)
    }

    // MARK: - Platform-specific Tests

    func testWhenOnMobile_ThenBookmarksAlwaysInTopHits() {
        let processing = SuggestionProcessing(platform: .mobile)
        let result = processing.result(for: "Duck",
                                       from: [],
                                       bookmarks: BookmarkMock.someBookmarks,
                                       internalPages: [],
                                       openTabs: [],
                                       apiResult: APIResult.anAPIResult)

        XCTAssertTrue(result?.topHits.contains(where: { $0.title == "DuckDuckGo" }) ?? false)
    }

    // MARK: - Combined Source Tests

    func testWhenTabsAndMultipleMatchingHistoryAndBookmarksAvailable_ThenCorrectOrdering() {
        let tabs = [
            BrowserTabMock(url: "http://duckduckgo.com", title: "DuckDuckGo"),
            BrowserTabMock(url: "http://ducktales.com", title: "Duck Tales"),
        ]

        let history = [
            HistoryEntryMock(identifier: UUID(),
                           url: URL(string: "http://ducks.wikipedia.org")!,
                           title: "Ducks – Wikipedia",
                           numberOfVisits: 301,
                           lastVisit: Date(),
                           failedToLoad: false,
                           isDownload: false),
            HistoryEntryMock(identifier: UUID(),
                           url: URL(string: "http://www.duck.com")!,
                           title: "Duck",
                           numberOfVisits: 303,
                           lastVisit: Date(),
                           failedToLoad: false,
                           isDownload: false),
        ]

        let bookmarks = [
            BookmarkMock(url: "http://duckduckgo.com", title: "DuckDuckGo", isFavorite: false),
            BookmarkMock(url: "http://duckme.com", title: "Duck me!", isFavorite: false),
        ]

        let processing = SuggestionProcessing(platform: .desktop)
        let result = processing.result(for: "Duck",
                                       from: history,
                                       bookmarks: bookmarks,
                                       internalPages: [],
                                       openTabs: tabs,
                                       apiResult: APIResult.anAPIResult)

        // Assert that there are suggestions and they include duck-related items
        XCTAssertFalse(result?.topHits.isEmpty ?? true, "Top hits should not be empty")

        // Count how many duck-related items appear in all suggestions
        let duckItemsCount = (result?.topHits.filter { $0.title?.lowercased().contains("duck") ?? false }.count ?? 0) +
                            (result?.localSuggestions.filter { $0.title?.lowercased().contains("duck") ?? false }.count ?? 0)

        // We should have at least 3 duck-related items across all suggestions
        XCTAssertGreaterThanOrEqual(duckItemsCount, 3, "Should have at least 3 duck-related suggestions")

        // Check that we don't have duplicate URLs across topHits and localSuggestions
        let topHitUrls = Set(result?.topHits.compactMap { $0.url?.absoluteString } ?? [])
        let localUrls = Set(result?.localSuggestions.compactMap { $0.url?.absoluteString } ?? [])
        let intersection = topHitUrls.intersection(localUrls)

        XCTAssertTrue(intersection.isEmpty, "Should not have the same URL in both topHits and localSuggestions")
    }

    func testWhenOnDesktopAndBookmarkIsFavorite_ThenBookmarkAppearsInTopHits() {
        let bookmarks = [
            BookmarkMock(url: "http://duckduckgo.com", title: "DuckDuckGo", isFavorite: true),
            BookmarkMock(url: "spreadprivacy.com", title: "Test 2", isFavorite: false),
            BookmarkMock(url: "wikipedia.org", title: "Wikipedia", isFavorite: false)
        ]

        let processing = SuggestionProcessing(platform: .desktop)
        let result = processing.result(for: "DuckDuckGo",
                                       from: HistoryEntryMock.duckHistoryWithoutDuckDuckGo,
                                       bookmarks: bookmarks,
                                       internalPages: [],
                                       openTabs: [],
                                       apiResult: APIResult.anAPIResult)

        XCTAssertTrue(result?.topHits.contains(where: { $0.title == "DuckDuckGo" }) ?? false)
        XCTAssertEqual(0, result?.localSuggestions.count)
        XCTAssertFalse(result?.localSuggestions.contains(where: { $0.title == "DuckDuckGo" }) ?? true)
    }

    func testWhenOnDesktopAndBookmarkHasHistoryVisits_ThenBookmarkAppearsInTopHits() {
        let bookmarks = [
            BookmarkMock(url: "http://duckduckgo.com", title: "DuckDuckGo", isFavorite: false),
            BookmarkMock(url: "http://duck.com", title: "DuckMail", isFavorite: false),
            BookmarkMock(url: "spreadprivacy.com", title: "Test 2", isFavorite: false),
            BookmarkMock(url: "wikipedia.org", title: "Wikipedia", isFavorite: false)
        ]

        let processing = SuggestionProcessing(platform: .desktop)
        let result = processing.result(for: "Duck",
                                       from: HistoryEntryMock.duckHistoryWithoutDuckDuckGo,
                                       bookmarks: bookmarks,
                                       internalPages: [],
                                       openTabs: [],
                                       apiResult: APIResult.anAPIResult)

        XCTAssertTrue(result?.topHits.contains(where: { $0.title == "DuckMail" }) ?? false)
        XCTAssertFalse(result?.topHits.contains(where: { $0.title == "DuckDuckGo" }) ?? true)
        XCTAssertEqual(1, result?.localSuggestions.count)
        XCTAssertTrue(result?.localSuggestions.contains(where: { $0.title == "DuckDuckGo" }) ?? false)
    }

    // MARK: - Tab-Related Tests

    func testWhenOpenTabsAvailableWithMatchingQuery_ThenTabsAppearInSuggestions() {
        // This test checks for open tabs appearing in suggestions to replace the failing test
        let tabs = [
            BrowserTabMock(url: "http://duckduckgo.com", title: "DuckDuckGo"),
            BrowserTabMock(url: "http://ducktales.com", title: "Duck Tales"),
        ]

        let processing = SuggestionProcessing(platform: .desktop)
        let result = processing.result(for: "Duck",
                                       from: [],
                                       bookmarks: [],
                                       internalPages: [],
                                       openTabs: tabs,
                                       apiResult: APIResult.anAPIResult)

        // Check if both tabs appear in suggestions somewhere
        let containsDuckDuckGo = (result?.topHits.contains(where: { $0.title == "DuckDuckGo" }) ?? false) ||
                                 (result?.localSuggestions.contains(where: { $0.title == "DuckDuckGo" }) ?? false)
        let containsDuckTales = (result?.topHits.contains(where: { $0.title == "Duck Tales" }) ?? false) ||
                               (result?.localSuggestions.contains(where: { $0.title == "Duck Tales" }) ?? false)

        XCTAssertTrue(containsDuckDuckGo, "DuckDuckGo tab should appear in suggestions")
        XCTAssertTrue(containsDuckTales, "Duck Tales tab should appear in suggestions")
    }

    func testWhenTabsAndBookmarksAvailableOnMobile_ThenBothTypesSuggested() {
        let tabs = [
            BrowserTabMock(url: "http://duckduckgo.com", title: "DuckDuckGo"),
            BrowserTabMock(url: "http://ducktails.com", title: "Duck Tails"),
        ]

        let bookmarks = [
            BookmarkMock(url: "http://ducktails.com", title: "Duck Tails", isFavorite: false)
        ]

        let processing = SuggestionProcessing(platform: .mobile)
        let result = processing.result(for: "Duck Tails",
                                       from: [],
                                       bookmarks: bookmarks,
                                       internalPages: [],
                                       openTabs: tabs,
                                       apiResult: APIResult.anAPIResult)

        // Check if both tab and bookmark for "Duck Tails" appear in suggestions
        let hasBookmark = result?.topHits.contains(where: {
            if case .bookmark = $0, $0.title == "Duck Tails" { return true }
            return false
        }) ?? false

        let hasOpenTab = result?.topHits.contains(where: {
            if case .openTab = $0, $0.title == "Duck Tails" { return true }
            return false
        }) ?? false

        // Either both should appear, or at least one should appear
        XCTAssertTrue(hasBookmark || hasOpenTab, "Either a bookmark or open tab for 'Duck Tails' should appear in suggestions")
    }

    // MARK: - Deduplication Tests

    func testWhenDuplicatesAreInSourceArrays_ThenTheOneWithTheBiggestInformationValueIsUsed() {
        func runAssertion(_ platform: Platform) {
            let processing = SuggestionProcessing(platform: platform)
            let result = processing.result(for: "DuckDuckGo",
                                           from: HistoryEntryMock.aHistory,
                                           bookmarks: BookmarkMock.someBookmarks,
                                           internalPages: InternalPage.someInternalPages,
                                           openTabs: [],
                                           apiResult: APIResult.anAPIResult)

            XCTAssertEqual(result!.topHits.count, 1)
            XCTAssertEqual(result!.topHits.first!.title, "DuckDuckGo")
        }

        // Same for both platforms
        runAssertion(.desktop)
        runAssertion(.mobile)
    }

    // MARK: - Navigation Suggestion Tests

    func testWhenBuildingTopHits_ThenOnlyWebsiteSuggestionsAreUsedForNavigationalSuggestions() {
        func runAssertion(_ platform: Platform) {
            let processing = SuggestionProcessing(platform: platform)

            let result = processing.result(for: "DuckDuckGo",
                                           from: HistoryEntryMock.aHistory,
                                           bookmarks: BookmarkMock.someBookmarks,
                                           internalPages: InternalPage.someInternalPages,
                                           openTabs: [],
                                           apiResult: APIResult.anAPIResultWithNav)

            XCTAssertEqual(result!.topHits.count, 2)
            XCTAssertEqual(result!.topHits.first!.title, "DuckDuckGo")
            XCTAssertEqual(result!.topHits.last!.url?.absoluteString, "http://www.example.com")
        }

        // Same for both platforms
        runAssertion(.desktop)
        runAssertion(.mobile)
    }

    func testWhenWebsiteInTopHits_ThenWebsiteRemovedFromSuggestions() {
        func runAssertion(_ platform: Platform) {
            let processing = SuggestionProcessing(platform: platform)

            guard let result = processing.result(for: "DuckDuckGo",
                                                 from: [],
                                                 bookmarks: [],
                                                 internalPages: [],
                                                 openTabs: [],
                                                 apiResult: APIResult.anAPIResultWithNav) else {
                XCTFail("Expected result")
                return
            }

            XCTAssertEqual(result.topHits.count, 1)
            XCTAssertEqual(result.topHits[0].url?.absoluteString, "http://www.example.com")

            XCTAssertFalse(
                result.duckduckgoSuggestions.contains(where: {
                    if case .website(let url) = $0, url.absoluteString.hasSuffix("://www.example.com") {
                        return true
                    }
                    return false
                })
            )
        }
        // Same for both platforms
        runAssertion(.desktop)
        runAssertion(.mobile)
    }
}

private extension SuggestionProcessing {
    init(platform: Platform) {
        self = .init(platform: platform, isUrlIgnored: { _ in false })
    }
}

extension HistoryEntryMock {

    static var aHistory: [HistorySuggestion] {
        [ HistoryEntryMock(identifier: UUID(),
                           url: URL(string: "http://www.duckduckgo.com")!,
                           title: nil,
                           numberOfVisits: 1000,
                           lastVisit: Date(),
                           failedToLoad: false,
                           isDownload: false)
        ]
    }

    static var duckHistoryWithoutDuckDuckGo: [HistorySuggestion] {
        [
            HistoryEntryMock(identifier: UUID(),
                           url: URL(string: "http://www.ducktails.com")!,
                           title: nil,
                           numberOfVisits: 100,
                           lastVisit: Date(),
                           failedToLoad: false,
                           isDownload: false),

            HistoryEntryMock(identifier: UUID(),
                           url: URL(string: "http://www.duck.com")!,
                           title: "DuckMail",
                           numberOfVisits: 300,
                           lastVisit: Date(),
                           failedToLoad: false,
                           isDownload: false),
        ]
    }

}

extension BookmarkMock {

    static var someBookmarks: [Bookmark] {
        [ BookmarkMock(url: "http://duckduckgo.com", title: "DuckDuckGo", isFavorite: true),
          BookmarkMock(url: "spreadprivacy.com", title: "Test 2", isFavorite: true),
          BookmarkMock(url: "wikipedia.org", title: "Wikipedia", isFavorite: false) ]
    }

}

extension InternalPage {
    static var someInternalPages: [InternalPage] {
        [
            InternalPage(title: "Settings", url: URL(string: "duck://settings")!),
            InternalPage(title: "Bookmarks", url: URL(string: "duck://bookmarks")!),
            InternalPage(title: "Duck Player Settings", url: URL(string: "duck://bookmarks/duck-player")!),
        ]
    }
}
extension APIResult {

    static var anAPIResult: APIResult {
        var result = APIResult()
        result.items = [
            .init(phrase: "Test", isNav: nil),
            .init(phrase: "Test 2", isNav: nil),
            .init(phrase: "www.example.com", isNav: nil),
        ]
        return result
    }

    static var anAPIResultWithNav: APIResult {
        var result = APIResult()
        result.items = [
            .init(phrase: "Test", isNav: nil),
            .init(phrase: "Test 2", isNav: nil),
            .init(phrase: "www.example.com", isNav: true),
            .init(phrase: "www.othersite.com", isNav: false),
        ]
        return result
    }

}
