//
//  SearchHistoryBrowserToolTests.swift
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
import History
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class SearchHistoryBrowserToolTests: XCTestCase {

    private var history: HistoryCoordinatingMock!
    private var tool: SearchHistoryBrowserTool!
    /// `Visit.historyEntry` is weak, so fixtures must keep their entries alive.
    private var retainedEntries: [HistoryEntry] = []

    override func setUp() {
        super.setUp()
        history = HistoryCoordinatingMock()
        tool = SearchHistoryBrowserTool(historyCoordinator: history)
    }

    override func tearDown() {
        tool = nil
        history = nil
        retainedEntries = []
        super.tearDown()
    }

    // MARK: - Search

    func testWhenSearchingThenTitleAndURLMatchCaseInsensitivelyNewestFirst() {
        let visits = [
            visit("https://apple.com/mac", title: "Apple Mac", at: 100),
            visit("https://example.com/", title: "Buy apples", at: 300),
            visit("https://other.org/", title: "Nothing", at: 200)
        ]

        let results = SearchHistoryBrowserTool.search(visits: visits, query: "APPLE", start: nil, end: nil, limit: 10)

        XCTAssertEqual(results.map(\.url), ["https://example.com/", "https://apple.com/mac"])
    }

    func testWhenQueryIsOmittedThenTheMostRecentVisitsAreReturnedUpToTheLimit() {
        let visits = (1...5).map { visit("https://s\($0).example/", title: "s\($0)", at: TimeInterval($0)) }

        let results = SearchHistoryBrowserTool.search(visits: visits, query: nil, start: nil, end: nil, limit: 2)

        XCTAssertEqual(results.map(\.title), ["s5", "s4"])
    }

    func testWhenARangeIsGivenThenItIsInclusive() {
        let visits = (1...4).map { visit("https://s\($0).example/", title: "s\($0)", at: TimeInterval($0)) }

        let results = SearchHistoryBrowserTool.search(visits: visits, query: nil, start: Date(timeIntervalSince1970: 2), end: Date(timeIntervalSince1970: 3), limit: 10)

        XCTAssertEqual(results.map(\.title), ["s3", "s2"])
    }

    func testWhenAVisitHasNoEntryThenItIsSkipped() {
        let orphan = Visit(date: Date(timeIntervalSince1970: 500), historyEntry: nil)

        let results = SearchHistoryBrowserTool.search(visits: [orphan, visit("https://a.example/", title: "a", at: 1)], query: nil, start: nil, end: nil, limit: 10)

        XCTAssertEqual(results.map(\.title), ["a"])
    }

    func testWhenTitleIsBlankThenHostAndPathStandIn() {
        XCTAssertEqual(SearchHistoryBrowserTool.displayTitle(title: "  Real  ", url: URL(string: "https://a.example/x")!), "Real")
        XCTAssertEqual(SearchHistoryBrowserTool.displayTitle(title: nil, url: URL(string: "https://a.example/")!), "a.example")
        XCTAssertEqual(SearchHistoryBrowserTool.displayTitle(title: " ", url: URL(string: "https://a.example/docs/intro")!), "a.example/docs/intro")
    }

    // MARK: - Dates

    func testWhenDateOnlyBoundsAreGivenThenTheyCoverWholeUTCDays() throws {
        let start = try XCTUnwrap(SearchHistoryBrowserTool.dateBound(from: "2026-09-24", isEnd: false))
        let end = try XCTUnwrap(SearchHistoryBrowserTool.dateBound(from: "2026-09-24", isEnd: true))

        XCTAssertEqual(start, Date(timeIntervalSince1970: 1_790_208_000))
        XCTAssertEqual(try XCTUnwrap(end).timeIntervalSince1970, 1_790_208_000 + 86_399.999, accuracy: 0.0005)
    }

    func testWhenISODateTimesAreGivenThenTheyAreParsedWithOrWithoutFractions() throws {
        let plain = try XCTUnwrap(SearchHistoryBrowserTool.dateBound(from: "2026-09-24T10:00:00Z", isEnd: false))
        let fractional = try XCTUnwrap(SearchHistoryBrowserTool.dateBound(from: "2026-09-24T10:00:00.500Z", isEnd: false))

        XCTAssertEqual(plain, Date(timeIntervalSince1970: 1_790_244_000))
        XCTAssertEqual(try XCTUnwrap(fractional).timeIntervalSince1970, 1_790_244_000.5, accuracy: 0.001)
    }

    func testWhenBoundIsAbsentBlankOrNullThenThereIsNoBound() {
        XCTAssertEqual(SearchHistoryBrowserTool.dateBound(from: nil, isEnd: false), .some(nil))
        XCTAssertEqual(SearchHistoryBrowserTool.dateBound(from: .null, isEnd: false), .some(nil))
        XCTAssertEqual(SearchHistoryBrowserTool.dateBound(from: "  ", isEnd: false), .some(nil))
    }

    func testWhenBoundIsUnparseableThenItIsRejected() {
        XCTAssertNil(SearchHistoryBrowserTool.dateBound(from: "yesterday", isEnd: false))
        XCTAssertNil(SearchHistoryBrowserTool.dateBound(from: 20260924, isEnd: false))
    }

    // MARK: - Execute

    func testWhenExecutedThenResultsCarryISOTimestampsInUTC() async throws {
        history.allHistoryVisits = [visit("https://a.example/", title: "A", at: 1_790_244_000.25)]

        let result = await tool.execute(arguments: ["query": "a"], context: context())

        guard case .success(let payload) = result else { return XCTFail("expected success, got \(result)") }
        let first = try XCTUnwrap(payload["results"]?.arrayValue?.first)
        XCTAssertEqual(first["title"], "A")
        XCTAssertEqual(first["url"], "https://a.example/")
        XCTAssertEqual(first["visitedAt"], "2026-09-24T10:00:00.250Z")
    }

    func testWhenArgumentsAreMalformedThenTheyAreInvalid() async {
        let ctx = context()

        let notObject = await tool.execute(arguments: "x", context: ctx)
        let badQuery = await tool.execute(arguments: ["query": 1], context: ctx)
        let badLimit = await tool.execute(arguments: ["limit": 51], context: ctx)
        let badDate = await tool.execute(arguments: ["startDate": "soon"], context: ctx)
        let inverted = await tool.execute(arguments: ["startDate": "2026-09-24", "endDate": "2026-09-23"], context: ctx)

        for result in [notObject, badQuery, badLimit, badDate, inverted] {
            XCTAssertEqual(result, .failure(.invalidArguments))
        }
    }

    func testWhenHistoryIsEmptyOrArgumentsAbsentThenResultsAreEmpty() async {
        history.allHistoryVisits = nil

        let result = await tool.execute(arguments: nil, context: context())

        XCTAssertEqual(result, .success(["results": []]))
    }

    func testWhenCalledInAFireWindowThenCallIsUnavailable() async {
        let result = await tool.execute(arguments: nil, context: context(isBurner: true))

        XCTAssertEqual(result, .failure(.unavailable))
    }

    // MARK: -

    private func visit(_ url: String, title: String, at seconds: TimeInterval) -> Visit {
        let date = Date(timeIntervalSince1970: seconds)
        let entry = HistoryEntry(identifier: UUID(), url: URL(string: url)!, title: title, failedToLoad: false,
                                 numberOfTotalVisits: 1, lastVisit: date, visits: [], numberOfTrackersBlocked: 0,
                                 blockedTrackingEntities: [], trackersFound: false)
        let visit = Visit(date: date, historyEntry: entry)
        entry.visits = [visit]
        retainedEntries.append(entry)
        return visit
    }

    private func context(isBurner: Bool = false) -> BrowserToolCallContext {
        BrowserToolCallContext(ownerTabID: "owner", ownerWindowToken: "w", isBurner: isBurner, supportsElicitationForm: true)
    }
}
