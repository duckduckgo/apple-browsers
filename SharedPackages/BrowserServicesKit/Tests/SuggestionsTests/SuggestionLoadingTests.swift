//
//  SuggestionLoadingTests.swift
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

final class SuggestionLoadingTests: XCTestCase {

    class SuggestionLoadingDataSourceMock: SuggestionLoadingDataSource {

        private var bookmarks: [Bookmark]
        private var history: [HistorySuggestion]
        private var internalPages: [InternalPage]
        private var openTabs: [BrowserTab]

        private var completionData: Data?
        private var completionError: Error?

        private var asyncDelay: TimeInterval?

        private(set) var bookmarkCallCount = 0
        private(set) var historyCallCount = 0
        private(set) var dataCallCount = 0
        private(set) var internalPagesCallCount = 0
        private(set) var openTabsCallCount = 0

        let platform: Platform

        init(data: Data? = nil,
             error: Error? = nil,
             platform: Platform,
             history: [HistorySuggestion] = [],
             bookmarks: [Bookmark] = [],
             internalPages: [InternalPage] = [],
             openTabs: [BrowserTab] = [],
             delay: TimeInterval? = 0.01) {
            self.completionData = data
            self.bookmarks = bookmarks
            self.history = history
            self.internalPages = internalPages
            self.openTabs = openTabs
            self.completionError = error
            self.asyncDelay = delay
            self.platform = platform
        }

        func history(for suggestionLoading: SuggestionLoading) -> [HistorySuggestion] {
            historyCallCount += 1
            return history
        }

        func bookmarks(for suggestionLoading: SuggestionLoading) -> [Bookmark] {
            bookmarkCallCount += 1
            return bookmarks
        }

        func internalPages(for suggestionLoading: Suggestions.SuggestionLoading) -> [Suggestions.InternalPage] {
            internalPagesCallCount += 1
            return internalPages
        }

        func openTabs(for suggestionLoading: Suggestions.SuggestionLoading) -> [Suggestions.BrowserTab] {
            openTabsCallCount += 1
            return openTabs
        }

        func suggestionLoading(_ suggestionLoading: SuggestionLoading,
                               suggestionDataFromUrl url: URL,
                               withParameters parameters: [String: String],
                               completion: @escaping (Data?, Error?) -> Void) {
            dataCallCount += 1
            if let asyncDelay = asyncDelay {
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(Int(asyncDelay * 1000))) {
                    completion(self.completionData, self.completionError)
                }
            } else {
                completion(completionData, completionError)
            }
        }
    }

    struct E: Error {}

    func testWhenQueryIsEmpty_ThenSuggestionsAreEmpty() {
        let dataSource = SuggestionLoadingDataSourceMock(platform: .desktop)
        let loader = SuggestionLoader()

        let e = expectation(description: "suggestions callback")
        loader.getSuggestions(query: "", usingDataSource: dataSource) { (suggestions, error) in
            XCTAssertEqual(suggestions, .empty)
            XCTAssertNil(error)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testWhenGetSuggestionsIsCalled_ThenDataSourceAsksForHistoryBookmarksAndDataOnce() {
        let dataSource = SuggestionLoadingDataSourceMock(data: Data.anAPIResultData,
                                                         platform: .desktop,
                                                         bookmarks: BookmarkMock.someBookmarks)
        let loader = SuggestionLoader()

        let e = expectation(description: "suggestions callback")
        loader.getSuggestions(query: "test", usingDataSource: dataSource) { (_, _) in
            XCTAssertEqual(dataSource.historyCallCount, 1)
            XCTAssertEqual(dataSource.bookmarkCallCount, 1)
            XCTAssertEqual(dataSource.internalPagesCallCount, 1)
            XCTAssertEqual(dataSource.dataCallCount, 1)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testWhenAPIReturnsError_ThenErrorAndLocalSuggestionsAreReturned() {
        let dataSource = SuggestionLoadingDataSourceMock(error: E(), platform: .desktop, bookmarks: [], delay: 0)
        let loader = SuggestionLoader()

        let e = expectation(description: "suggestions callback")
        loader.getSuggestions(query: "test", usingDataSource: dataSource) { (suggestions, error) in
            XCTAssertNotNil(suggestions)
            XCTAssertNotNil(error)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testWhenAPIReturnsMalformedData_ThenErrorAndLocalSuggestionsAreReturned() {
        let dataSource = SuggestionLoadingDataSourceMock(data: "malformed data".data(using: .utf8),
                                                         platform: .desktop,
                                                         bookmarks: [], delay: 0)
        let loader = SuggestionLoader()

        let e = expectation(description: "suggestions callback")
        loader.getSuggestions(query: "test", usingDataSource: dataSource) { (suggestions, error) in
            XCTAssertNotNil(suggestions)
            XCTAssertNotNil(error)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testWhenDataSourceProvidesAllData_ThenResultAndNoErrorIsReturned() {
        let dataSource = SuggestionLoadingDataSourceMock(data: Data.anAPIResultData,
                                                         platform: .desktop,
                                                         history: HistoryEntryMock.aHistory,
                                                         bookmarks: BookmarkMock.someBookmarks)
        let loader = SuggestionLoader()

        let e = expectation(description: "suggestions callback")
        loader.getSuggestions(query: "test", usingDataSource: dataSource) { (result, error) in
            XCTAssertNotNil(result)
            XCTAssertNil(error)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

}

fileprivate extension Data {

    static var anAPIResultData: Data {
        let encoder = JSONEncoder()
        return try! encoder.encode(APIResult.anAPIResult.items)
    }

}

fileprivate extension SuggestionLoader {

    convenience init() {
        self.init(urlFactory: { _ in return nil }, isUrlIgnored: { _ in false })
    }

}
