//
//  SuggestionContainerTests.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
import Common
import History
import NetworkingTestingUtils
import os.log
import SnapshotTesting
import Suggestions
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class SuggestionContainerTests: XCTestCase {

    func testWhenGetSuggestionsIsCalled_ThenContainerAsksAndHoldsSuggestionsFromLoader() {
        let suggestionLoadingMock = SuggestionLoadingMock()
        let historyCoordinatingMock = HistoryProviderMock()
        let suggestionContainer = SuggestionContainer(openTabsProvider: { [] },
                                                      suggestionLoading: suggestionLoadingMock,
                                                      historyProvider: historyCoordinatingMock,
                                                      bookmarkProvider: LocalBookmarkManager.shared,
                                                      burnerMode: .regular)

        let e = expectation(description: "Suggestions updated")
        let cancellable = suggestionContainer.$result.sink {
            if $0 != nil {
                e.fulfill()
            }
        }

        suggestionContainer.getSuggestions(for: "test")
        let result = SuggestionResult.aSuggestionResult
        suggestionLoadingMock.completion!(result, nil)

        XCTAssert(suggestionLoadingMock.getSuggestionsCalled)
        withExtendedLifetime(cancellable) {
            waitForExpectations(timeout: 1)
        }
        XCTAssertEqual(suggestionContainer.result?.all, result.topHits + result.duckduckgoSuggestions + result.localSuggestions)
    }

    func testWhenStopGettingSuggestionsIsCalled_ThenNoSuggestionsArePublished() {
        let suggestionLoadingMock = SuggestionLoadingMock()
        let historyCoordinatingMock = HistoryProviderMock()
        let suggestionContainer = SuggestionContainer(openTabsProvider: { [] },
                                                      suggestionLoading: suggestionLoadingMock,
                                                      historyProvider: historyCoordinatingMock,
                                                      bookmarkProvider: LocalBookmarkManager.shared,
                                                      burnerMode: .regular)

        suggestionContainer.getSuggestions(for: "test")
        suggestionContainer.stopGettingSuggestions()
        suggestionLoadingMock.completion?(SuggestionResult.aSuggestionResult, nil)

        XCTAssert(suggestionLoadingMock.getSuggestionsCalled)
        XCTAssertNil(suggestionContainer.result)
    }

    func testSuggestionLoadingCacheClearing() {
        let suggestionLoadingMock = SuggestionLoadingMock()
        let historyCoordinatingMock = HistoryProviderMock()
        let suggestionContainer = SuggestionContainer(openTabsProvider: { [] },
                                                      suggestionLoading: suggestionLoadingMock,
                                                      historyProvider: historyCoordinatingMock,
                                                      bookmarkProvider: LocalBookmarkManager.shared,
                                                      burnerMode: .regular)

        XCTAssertNil(suggestionContainer.suggestionDataCache)
        let e = expectation(description: "Suggestions updated")
        suggestionContainer.suggestionLoading(suggestionLoadingMock, suggestionDataFromUrl: URL.testsServer, withParameters: [:]) { data, error in
            XCTAssertNotNil(suggestionContainer.suggestionDataCache)
            e.fulfill()

            // Test the cache is not cleared if useCachedData is true
            XCTAssertFalse(suggestionLoadingMock.getSuggestionsCalled)
            suggestionContainer.getSuggestions(for: "test", useCachedData: true)
            XCTAssertNotNil(suggestionContainer.suggestionDataCache)
            XCTAssert(suggestionLoadingMock.getSuggestionsCalled)

            suggestionLoadingMock.getSuggestionsCalled = false

            // Test the cache is cleared if useCachedData is false
            XCTAssertFalse(suggestionLoadingMock.getSuggestionsCalled)
            suggestionContainer.getSuggestions(for: "test", useCachedData: false)
            XCTAssertNil(suggestionContainer.suggestionDataCache)
            XCTAssert(suggestionLoadingMock.getSuggestionsCalled)
        }

        waitForExpectations(timeout: 1)
    }

}

extension SuggestionContainerTests {

    class WindowControllersManagerMock: WindowControllersManagerProtocol {

        var pinnedTabsManagerProvider: any DuckDuckGo_Privacy_Browser.PinnedTabsManagerProviding

        var mainWindowControllers: [DuckDuckGo_Privacy_Browser.MainWindowController] = []

        var lastKeyMainWindowController: DuckDuckGo_Privacy_Browser.MainWindowController?

        var didRegisterWindowController = PassthroughSubject<(DuckDuckGo_Privacy_Browser.MainWindowController), Never>()

        var didUnregisterWindowController = PassthroughSubject<(DuckDuckGo_Privacy_Browser.MainWindowController), Never>()

        func register(_ windowController: DuckDuckGo_Privacy_Browser.MainWindowController) {
        }

        func unregister(_ windowController: DuckDuckGo_Privacy_Browser.MainWindowController) {
        }

        func show(url: URL?, tabId: String?, source: DuckDuckGo_Privacy_Browser.Tab.TabContent.URLSource, newTab: Bool) {
        }

        func showBookmarksTab() {
        }

        func showTab(with content: DuckDuckGo_Privacy_Browser.Tab.TabContent) {
        }

        var selectedTab: Tab?
        var allTabCollectionViewModels: [TabCollectionViewModel] = []

        func openNewWindow(with tabCollectionViewModel: DuckDuckGo_Privacy_Browser.TabCollectionViewModel?, burnerMode: DuckDuckGo_Privacy_Browser.BurnerMode, droppingPoint: NSPoint?, contentSize: NSSize?, showWindow: Bool, popUp: Bool, lazyLoadTabs: Bool, isMiniaturized: Bool, isMaximized: Bool, isFullscreen: Bool) -> DuckDuckGo_Privacy_Browser.MainWindow? {
            nil
        }

        init(pinnedTabsManagerProvider: PinnedTabsManagerProvider, tabCollectionViewModels: [TabCollectionViewModel] = []) {
            self.pinnedTabsManagerProvider = pinnedTabsManagerProvider
            self.allTabCollectionViewModels = tabCollectionViewModels
        }
    }

    @MainActor
    private func tabCollection(_ openTabs: [OpenTab], burnerMode: BurnerMode = .regular) -> TabCollection {
        let tabs = openTabs.map {
            Tab(content: TabContent.contentFromURL($0.url, source: .link), title: $0.title, burnerMode: burnerMode)
        }
        return TabCollection(tabs: tabs)
    }

    @MainActor
    private func pinnedTabsManager(tabs: [OpenTab]) -> PinnedTabsManager {
        PinnedTabsManager(tabCollection: tabCollection(tabs))
    }

    struct Bookmark: Decodable, Suggestions.Bookmark {
        enum CodingKeys: String, CodingKey {
            case title
            case url="uri"
            case isFavorite
        }
        let title: String
        var url: String
        let isFavorite: Bool
    }

    struct HistoryEntry: Decodable, Hashable, Suggestions.HistorySuggestion {
        enum CodingKeys: String, CodingKey {
            case title
            case url = "uri"
            case numberOfVisits = "visitCount"
            case _lastVisit = "lastVisit"
            case _failedToLoad = "failedToLoad"
        }
        let title: String?
        let url: URL
        let numberOfVisits: Int
        let _lastVisit: Date?
        var lastVisit: Date { _lastVisit ?? .distantPast }
        let _failedToLoad: Bool?
        var failedToLoad: Bool { _failedToLoad ?? false }

        var identifier: UUID { Self.uuidFromHash(self.hashValue) }

        private static func uuidFromHash(_ hash: Int) -> UUID {
            // Convert the integer hash to a string
            let hashString = String(hash)

            // Create a UUID from the hash string by padding/truncating to fit UUID format
            let paddedHashString = hashString.padding(toLength: 32, withPad: "0", startingAt: 0)

            // Format the string to match UUID format (8-4-4-4-12)
            let uuidString = "\(paddedHashString.prefix(8))-\(paddedHashString.dropFirst(8).prefix(4))-\(paddedHashString.dropFirst(12).prefix(4))-\(paddedHashString.dropFirst(16).prefix(4))-\(paddedHashString.dropFirst(20).prefix(12))"

            // Create and return a UUID from the formatted string
            return UUID(uuidString: uuidString)!
        }

    }

}

class HistoryProviderMock: SuggestionContainer.HistoryProvider {
    let history: [SuggestionContainerTests.HistoryEntry]

    func history(for suggestionLoading: any Suggestions.SuggestionLoading) -> [any Suggestions.HistorySuggestion] {
        history
    }

    init(history: [SuggestionContainerTests.HistoryEntry] = []) {
        self.history = history
    }
}

private class BookmarkProviderMock: SuggestionContainer.BookmarkProvider {
    let bookmarks: [SuggestionContainerTests.Bookmark]

    func bookmarks(for suggestionLoading: any Suggestions.SuggestionLoading) -> [any Suggestions.Bookmark] {
        bookmarks
    }

    init(bookmarks: [SuggestionContainerTests.Bookmark]) {
        self.bookmarks = bookmarks
    }
}
