//
//  HistoryViewDataProviderTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import History
import HistoryView
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class HistoryViewDataProviderTests: XCTestCase {
    var provider: HistoryViewDataProvider!
    var dataSource: CapturingHistoryDataSource!
    var burner: CapturingHistoryBurner!
    var dateFormatter: MockHistoryViewDateFormatter!
    var featureFlagger: MockFeatureFlagger!
    var pixelHandler: CapturingHistoryViewDataProviderPixelHandler!

    @MainActor
    override func setUp() async throws {
        dataSource = CapturingHistoryDataSource()
        burner = CapturingHistoryBurner()
        dateFormatter = MockHistoryViewDateFormatter()
        featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.historyView, .historyViewSitesSection]
        pixelHandler = CapturingHistoryViewDataProviderPixelHandler()
        provider = HistoryViewDataProvider(
            historyDataSource: dataSource,
            historyBurner: burner,
            dateFormatter: dateFormatter,
            featureFlagger: featureFlagger,
            pixelHandler: pixelHandler
        )
        await provider.refreshData()
    }

    @MainActor
    override func tearDown() async throws {
        provider = nil
        dataSource = nil
        burner = nil
        dateFormatter = nil
        featureFlagger = nil
        pixelHandler = nil
    }

    // MARK: - ranges

    func testThatRangesReturnsAllWhenHistoryIsEmpty() async {
        dataSource.history = nil
        await provider.refreshData()
        XCTAssertEqual(provider.ranges, [
            .init(id: .all, count: 0),
            .init(id: .allSites, count: 0),
        ])

        dataSource.history = []
        await provider.refreshData()
        XCTAssertEqual(provider.ranges, [
            .init(id: .all, count: 0),
            .init(id: .allSites, count: 0),
        ])
    }

    func testThatRangesIncludesTodayWhenHistoryContainsEntriesFromToday() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24)
        let today = dateFormatter.currentDate().startOfDay

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example.com".url), visits: [
                .init(date: today.addingTimeInterval(10))
            ])
        ]
        await provider.refreshData()
        XCTAssertEqual(provider.ranges, [
            .init(id: .all, count: 1),
            .init(id: .today, count: 1),
            .init(id: .allSites, count: 1),
        ])
    }

    func testThatRangesIncludesYesterdayWhenHistoryContainsEntriesFromYesterday() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24)
        let today = dateFormatter.currentDate().startOfDay

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example.com".url), visits: [
                .init(date: today.addingTimeInterval(10)),
                .init(date: today.daysAgo(1))
            ])
        ]
        await provider.refreshData()
        XCTAssertEqual(provider.ranges, [
            .init(id: .all, count: 2),
            .init(id: .today, count: 1),
            .init(id: .yesterday, count: 1),
            .init(id: .allSites, count: 1),
        ])
    }

    func testThatRangesIncludesAllRangesUntilTheOldestRangeThatContainsEntries() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24) // Monday
        let today = dateFormatter.currentDate().startOfDay

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example.com".url), visits: [
                .init(date: today.daysAgo(5))
            ])
        ]
        await provider.refreshData()
        XCTAssertEqual(provider.ranges, [
            .init(id: .all, count: 1),
            .init(id: .today, count: 0),
            .init(id: .yesterday, count: 0),
            .init(id: .saturday, count: 0),
            .init(id: .friday, count: 0),
            .init(id: .thursday, count: 0),
            .init(id: .wednesday, count: 1),
            .init(id: .allSites, count: 1),
        ])
    }

    func testThatRangesIncludesAllDaysAndOlderWhenHistoryContainsEntriesOlderThan7Days() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24) // Monday
        let today = dateFormatter.currentDate().startOfDay

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example.com".url), visits: [
                .init(date: today.daysAgo(8))
            ])
        ]
        await provider.refreshData()
        XCTAssertEqual(provider.ranges, [
            .init(id: .all, count: 1),
            .init(id: .today, count: 0),
            .init(id: .yesterday, count: 0),
            .init(id: .saturday, count: 0),
            .init(id: .friday, count: 0),
            .init(id: .thursday, count: 0),
            .init(id: .wednesday, count: 0),
            .init(id: .tuesday, count: 0),
            .init(id: .older, count: 1),
            .init(id: .allSites, count: 1),
        ])
    }

    func testThatRangesIncludesNamedWeekdaysWhenHistoryContainsEntriesFrom2To4DaysAgo() async throws {
        func populateHistory(for date: Date) async throws {
            dateFormatter.date = date
            dataSource.history = [
                .make(url: try XCTUnwrap("https://example.com".url), visits: [
                    .init(date: dateFormatter.date.daysAgo(2)),
                    .init(date: dateFormatter.date.daysAgo(3)),
                    .init(date: dateFormatter.date.daysAgo(4))
                ])
            ]
            await provider.refreshData()
        }

        try await populateHistory(for: date(year: 2025, month: 2, day: 24)) // Monday
        XCTAssertEqual(provider.ranges, [
            .init(id: .all, count: 3),
            .init(id: .today, count: 0),
            .init(id: .yesterday, count: 0),
            .init(id: .saturday, count: 1),
            .init(id: .friday, count: 1),
            .init(id: .thursday, count: 1),
            .init(id: .allSites, count: 1),
        ])

        try await populateHistory(for: date(year: 2025, month: 2, day: 25)) // Tuesday
        XCTAssertEqual(provider.ranges, [
            .init(id: .all, count: 3),
            .init(id: .today, count: 0),
            .init(id: .yesterday, count: 0),
            .init(id: .sunday, count: 1),
            .init(id: .saturday, count: 1),
            .init(id: .friday, count: 1),
            .init(id: .allSites, count: 1),
        ])

        try await populateHistory(for: date(year: 2025, month: 2, day: 26)) // Wednesday
        XCTAssertEqual(provider.ranges, [
            .init(id: .all, count: 3),
            .init(id: .today, count: 0),
            .init(id: .yesterday, count: 0),
            .init(id: .monday, count: 1),
            .init(id: .sunday, count: 1),
            .init(id: .saturday, count: 1),
            .init(id: .allSites, count: 1),
        ])

        try await populateHistory(for: date(year: 2025, month: 2, day: 27)) // Thursday
        XCTAssertEqual(provider.ranges, [
            .init(id: .all, count: 3),
            .init(id: .today, count: 0),
            .init(id: .yesterday, count: 0),
            .init(id: .tuesday, count: 1),
            .init(id: .monday, count: 1),
            .init(id: .sunday, count: 1),
            .init(id: .allSites, count: 1),
        ])

        try await populateHistory(for: date(year: 2025, month: 2, day: 28)) // Friday
        XCTAssertEqual(provider.ranges, [
            .init(id: .all, count: 3),
            .init(id: .today, count: 0),
            .init(id: .yesterday, count: 0),
            .init(id: .wednesday, count: 1),
            .init(id: .tuesday, count: 1),
            .init(id: .monday, count: 1),
            .init(id: .allSites, count: 1),
        ])

        try await populateHistory(for: date(year: 2025, month: 3, day: 1)) // Saturday
        XCTAssertEqual(provider.ranges, [
            .init(id: .all, count: 3),
            .init(id: .today, count: 0),
            .init(id: .yesterday, count: 0),
            .init(id: .thursday, count: 1),
            .init(id: .wednesday, count: 1),
            .init(id: .tuesday, count: 1),
            .init(id: .allSites, count: 1),
        ])

        try await populateHistory(for: date(year: 2025, month: 3, day: 2)) // Sunday
        XCTAssertEqual(provider.ranges, [
            .init(id: .all, count: 3),
            .init(id: .today, count: 0),
            .init(id: .yesterday, count: 0),
            .init(id: .friday, count: 1),
            .init(id: .thursday, count: 1),
            .init(id: .wednesday, count: 1),
            .init(id: .allSites, count: 1),
        ])
    }

    // MARK: - visitsBatch

    func testThatVisitsBatchReturnsChunksOfVisits() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24)
        let today = dateFormatter.currentDate().startOfDay

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example1.com".url), visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://example2.com".url), visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://example3.com".url), visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://example4.com".url), visits: [.init(date: today)])
        ]
        await provider.refreshData()
        var batch = await provider.visitsBatch(for: .rangeFilter(.all), source: .auto, limit: 3, offset: 0)
        XCTAssertEqual(batch.finished, false)
        XCTAssertEqual(batch.visits.count, 3)

        batch = await provider.visitsBatch(for: .rangeFilter(.all), source: .auto, limit: 3, offset: 3)
        XCTAssertEqual(batch.finished, true)
        XCTAssertEqual(batch.visits.count, 1)
    }

    func testThatVisitsBatchReturnsVisitsDeduplicatedByDay() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24)
        let today = dateFormatter.currentDate().startOfDay
        let yesterday = dateFormatter.currentDate().startOfDay.daysAgo(1)

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example1.com".url), visits: [
                .init(date: today),
                .init(date: today.addingTimeInterval(10)),
                .init(date: yesterday.addingTimeInterval(3600))
            ]),
            .make(url: try XCTUnwrap("https://example2.com".url), visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://example3.com".url), visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://example4.com".url), visits: [.init(date: today)])
        ]
        await provider.refreshData()
        let batch = await provider.visitsBatch(for: .rangeFilter(.all), source: .auto, limit: 6, offset: 0)
        XCTAssertEqual(batch.finished, true)
        XCTAssertEqual(batch.visits.count, 5)
    }

    func testThatVisitsBatchWithDateFilterReturnsVisitsForThatDate() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24)
        let day = dateFormatter.currentDate().startOfDay
        let previousDay = day.daysAgo(1)

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example1.com".url), visits: [.init(date: day)]),
            .make(url: try XCTUnwrap("https://example2.com".url), visits: [.init(date: previousDay)])
        ]
        await provider.refreshData()
        let batch = await provider.visitsBatch(for: .dateFilter(day), source: .auto, limit: 10, offset: 0)
        XCTAssertEqual(batch.finished, true)
        XCTAssertEqual(Set(batch.visits.map(\.url)), ["https://example1.com"])
    }

    func testThatVisitsBatchWithVisitsIdentifiersReturnsThoseVisits() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24)
        let day = dateFormatter.currentDate().startOfDay
        let entry1 = HistoryEntry.make(url: try XCTUnwrap("https://example1.com".url), visits: [.init(date: day)])
        let entry2 = HistoryEntry.make(url: try XCTUnwrap("https://example2.com".url), visits: [.init(date: day)])
        dataSource.history = [entry1, entry2]
        await provider.refreshData()
        let ids: [VisitIdentifier] = [ .init(historyEntry: entry2, date: day) ]
        let batch = await provider.visitsBatch(for: .visits(ids), source: .auto, limit: 10, offset: 0)
        XCTAssertEqual(batch.finished, true)
        XCTAssertEqual(Set(batch.visits.map(\.url)), ["https://example2.com"])
    }

    func testThatVisitsBatchWithRangeFilterReturnsVisitsMatchingTheDateRange() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24)
        let today = dateFormatter.currentDate().startOfDay
        let yesterday = dateFormatter.currentDate().startOfDay.daysAgo(1)

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example1.com".url), visits: [
                .init(date: today),
                .init(date: yesterday.addingTimeInterval(10)),
                .init(date: yesterday.addingTimeInterval(3600))
            ]),
            .make(url: try XCTUnwrap("https://example2.com".url), visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://example3.com".url), visits: [.init(date: yesterday)]),
            .make(url: try XCTUnwrap("https://example4.com".url), visits: [.init(date: today)])
        ]
        await provider.refreshData()
        let batch = await provider.visitsBatch(for: .rangeFilter(.yesterday), source: .auto, limit: 4, offset: 0)
        XCTAssertEqual(batch.finished, true)
        XCTAssertEqual(Set(batch.visits.map(\.url)), ["https://example1.com", "https://example3.com"])
    }

    func testThatVisitsBatchWithEmptySearchTermOrDomainFilterReturnsAllVisits() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24)
        let today = dateFormatter.currentDate().startOfDay
        let yesterday = dateFormatter.currentDate().startOfDay.daysAgo(1)

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example1.com".url), visits: [
                .init(date: today),
                .init(date: yesterday.addingTimeInterval(10)),
                .init(date: yesterday.addingTimeInterval(3600))
            ]),
            .make(url: try XCTUnwrap("https://example2.com".url), visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://example3.com".url), visits: [.init(date: yesterday)]),
            .make(url: try XCTUnwrap("https://example4.com".url), visits: [.init(date: today)])
        ]
        await provider.refreshData()
        var batch = await provider.visitsBatch(for: .searchTerm(""), source: .auto, limit: 6, offset: 0)
        XCTAssertEqual(batch.finished, true)
        XCTAssertEqual(batch.visits.count, 5)

        batch = await provider.visitsBatch(for: .domainFilter([]), source: .auto, limit: 6, offset: 0)
        XCTAssertEqual(batch.finished, true)
        XCTAssertEqual(batch.visits.count, 5)
    }

    func testThatVisitsBatchReturnsVisitsMatchingSearchTerm() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24)
        let today = dateFormatter.currentDate().startOfDay

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example12.com".url), visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://example2.com".url), visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://example3.com".url), title: "12", visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://example4.com".url), visits: [.init(date: today)])
        ]
        await provider.refreshData()
        let batch = await provider.visitsBatch(for: .searchTerm("2"), source: .auto, limit: 4, offset: 0)
        XCTAssertEqual(batch.finished, true)
        XCTAssertEqual(batch.visits.count, 3)
        XCTAssertEqual(Set(batch.visits.map(\.url)), ["https://example12.com", "https://example2.com", "https://example3.com"])
    }

    func testThatVisitsBatchReturnsVisitsMatchingSearchTermIgnoringCase() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24)
        let today = dateFormatter.currentDate().startOfDay

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example12.com".url), title: "abcdE", visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://example.com/abCDe".url), title: "foo", visits: [.init(date: today)])
        ]
        await provider.refreshData()
        let batch = await provider.visitsBatch(for: .searchTerm("bCd"), source: .auto, limit: 4, offset: 0)
        XCTAssertEqual(batch.finished, true)
        XCTAssertEqual(batch.visits.count, 2)
    }

    func testThatVisitsBatchWithDomainFilterReturnsVisitsWithETLDPlusOneMatchingTheDomain() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24)
        let today = dateFormatter.currentDate().startOfDay

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example12.com".url), visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://abcd.example.com/foo".url), visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://example.com/bar".url), visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://duckduckgo.com".url), title: "abcd.example.com", visits: [.init(date: today)])
        ]
        await provider.refreshData()
        let batch = await provider.visitsBatch(for: .domainFilter(["example.com"]), source: .auto, limit: 4, offset: 0)
        XCTAssertEqual(batch.finished, true)
        XCTAssertEqual(batch.visits.count, 2)
        XCTAssertEqual(Set(batch.visits.map(\.url)), ["https://abcd.example.com/foo", "https://example.com/bar"])
    }

    func testThatVisitsBatchWithDomainFilterMatchesETLDPlusOne() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24)
        let today = dateFormatter.currentDate().startOfDay

        dataSource.history = [
            .make(url: try XCTUnwrap("https://abcd.example.com/foo".url), visits: [.init(date: today)])
        ]
        await provider.refreshData()
        let batch = await provider.visitsBatch(for: .domainFilter(["example.com"]), source: .auto, limit: 4, offset: 0)
        XCTAssertEqual(batch.finished, true)
        XCTAssertEqual(batch.visits.count, 1)
    }

    // MARK: - visits(matching:)

    func testThatCountVisibleVisitsReportsOneVisitPerDayPerURL() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24) // Monday
        let today = dateFormatter.currentDate().startOfDay
        let yesterday = today.daysAgo(1)
        let saturday = today.daysAgo(2)
        let friday = today.daysAgo(3)
        let thursday = today.daysAgo(4)
        let wednesday = today.daysAgo(5)
        let tuesday = today.daysAgo(6)
        let older1 = today.daysAgo(7)
        let older2 = today.daysAgo(8)
        let older3 = today.daysAgo(9)

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example1.com".url), visits: [
                .init(date: today),
                .init(date: yesterday),
                .init(date: saturday),
                .init(date: saturday),
                .init(date: saturday),
                .init(date: thursday),
                .init(date: wednesday),
                .init(date: tuesday),
                .init(date: older1),
                .init(date: older2),
                .init(date: older3)
            ]),
            .make(url: try XCTUnwrap("https://example2.com".url), visits: [
                .init(date: today),
                .init(date: yesterday),
                .init(date: friday),
                .init(date: wednesday),
                .init(date: older2)
            ]),
            .make(url: try XCTUnwrap("https://example3.com".url), visits: [
                .init(date: saturday),
                .init(date: thursday),
                .init(date: wednesday),
                .init(date: older1),
                .init(date: older3)
            ])
        ]
        await provider.refreshData()
        let allVisits = await provider.visits(matching: .rangeFilter(.all))
        let todayVisits = await provider.visits(matching: .rangeFilter(.today))
        let yesterdayVisits = await provider.visits(matching: .rangeFilter(.yesterday))
        let saturdayVisits = await provider.visits(matching: .rangeFilter(.saturday))
        let fridayVisits = await provider.visits(matching: .rangeFilter(.friday))
        let thursdayVisits = await provider.visits(matching: .rangeFilter(.thursday))
        let wednesdayVisits = await provider.visits(matching: .rangeFilter(.wednesday))
        let tuesdayVisits = await provider.visits(matching: .rangeFilter(.tuesday))
        let olderVisits = await provider.visits(matching: .rangeFilter(.older))
        XCTAssertEqual(allVisits.count, 21)
        XCTAssertEqual(todayVisits.count, 2)
        XCTAssertEqual(yesterdayVisits.count, 2)
        XCTAssertEqual(saturdayVisits.count, 4)
        XCTAssertEqual(fridayVisits.count, 1)
        XCTAssertEqual(thursdayVisits.count, 2)
        XCTAssertEqual(wednesdayVisits.count, 3)
        XCTAssertEqual(tuesdayVisits.count, 1)
        XCTAssertEqual(olderVisits.count, 6)
    }

    func testAllVisitsMatchingSearchTermReturnsMatchingEntries() async throws {
        let today = Date()
        dataSource.history = [
            .make(url: try XCTUnwrap("https://foo.com".url), title: "Foo Title", visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://bar.com".url), title: "Bar Title", visits: [.init(date: today)])
        ]
        await provider.refreshData()
        let matches = await provider.visits(matching: .searchTerm("Foo"))
        XCTAssertEqual(Set(matches.compactMap { $0.historyEntry?.url.host }), ["foo.com"])
    }

    func testAllVisitsMatchingDomainFilterReturnsETLDPlusOneMatches() async throws {
        let today = Date()
        dataSource.history = [
            .make(url: try XCTUnwrap("https://a.example.com/page".url), visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://b.example.com".url), visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://other.com".url), visits: [.init(date: today)])
        ]
        await provider.refreshData()
        let matches = await provider.visits(matching: .domainFilter(["example.com"]))
        XCTAssertEqual(Set(matches.compactMap { $0.historyEntry?.url.host }), ["a.example.com", "b.example.com"])
    }

    func testAllVisitsMatchingDateFilterReturnsVisitsOnThatDate() async throws {
        let base = Date().startOfDay
        dataSource.history = [
            .make(url: try XCTUnwrap("https://a.com".url), visits: [.init(date: base.addingTimeInterval(3600))]),
            .make(url: try XCTUnwrap("https://b.com".url), visits: [.init(date: base.daysAgo(1))])
        ]
        await provider.refreshData()
        let matches = await provider.visits(matching: .dateFilter(base))
        XCTAssertEqual(Set(matches.compactMap { $0.historyEntry?.url.host }), ["a.com"])
    }

    func testAllVisitsMatchingVisitsIdentifiersReturnsExactMatches() async throws {
        let base = Date().startOfDay
        let entryA = HistoryEntry.make(url: try XCTUnwrap("https://id-a.com".url), visits: [.init(date: base)])
        let entryB = HistoryEntry.make(url: try XCTUnwrap("https://id-b.com".url), visits: [.init(date: base)])
        dataSource.history = [entryA, entryB]
        await provider.refreshData()
        let ids: [VisitIdentifier] = [ .init(historyEntry: entryB, date: base) ]
        let matches = await provider.visits(matching: .visits(ids))
        XCTAssertEqual(Set(matches.compactMap { $0.historyEntry?.url.host }), ["id-b.com"])
    }

    // MARK: - deleteVisitsForIdentifiers

    func testThatDeleteVisitsForIdentifiersDeletesVisitsWithMatchingIdentifiers() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24) // Monday
        let today = dateFormatter.currentDate().startOfDay
        let yesterday = today.daysAgo(1)
        let saturday = today.daysAgo(2)
        let friday = today.daysAgo(3)
        let thursday = today.daysAgo(4)

        let entry1 = HistoryEntry.make(url: try XCTUnwrap("https://example1.com".url), visits: [
            .init(date: today),
            .init(date: yesterday)
        ])

        let entry2 = HistoryEntry.make(url: try XCTUnwrap("https://example2.com".url), visits: [
            .init(date: today),
            .init(date: yesterday),
            .init(date: friday)
        ])

        let entry3 = HistoryEntry.make(url: try XCTUnwrap("https://example3.com".url), visits: [
            .init(date: saturday),
            .init(date: thursday)
        ])

        dataSource.history = [entry1, entry2, entry3]

        let identifiers: [VisitIdentifier] =  [
            .init(historyEntry: entry2, date: yesterday),
            .init(historyEntry: entry3, date: saturday)
        ]
        await provider.refreshData()
        await provider.deleteVisits(matching: .visits(identifiers))
        XCTAssertEqual(dataSource.deleteCalls.count, 1)

        let deletedVisits = try XCTUnwrap(dataSource.deleteCalls.first)
        XCTAssertEqual(deletedVisits.count, 2)
        XCTAssertEqual(
            Set(deletedVisits.compactMap(\.historyEntry?.url.absoluteString)),
            ["https://example2.com", "https://example3.com"]
        )
    }

    func testThatDeleteVisitsForIdentifiersDeletesAllMatchingVisitsFromGivenDay() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24) // Monday
        let today = dateFormatter.currentDate().startOfDay
        let yesterday = today.daysAgo(1)

        let entry = HistoryEntry.make(url: try XCTUnwrap("https://example.com".url), visits: [
            .init(date: today),
            .init(date: yesterday),
            .init(date: yesterday.addingTimeInterval(1)),
            .init(date: yesterday.addingTimeInterval(2)),
            .init(date: yesterday.addingTimeInterval(3))
        ])

        dataSource.history = [entry]

        let identifiers: [VisitIdentifier] =  [
            .init(historyEntry: entry, date: yesterday)
        ]
        await provider.refreshData()
        await provider.deleteVisits(matching: .visits(identifiers))
        XCTAssertEqual(dataSource.deleteCalls.count, 1)

        let deletedVisits = try XCTUnwrap(dataSource.deleteCalls.first)
        XCTAssertEqual(deletedVisits.count, 4)
        XCTAssertEqual(
            Set(deletedVisits.compactMap(\.historyEntry?.url.absoluteString)),
            ["https://example.com"]
        )
        XCTAssertEqual(
            Set(deletedVisits.compactMap(\.date)),
            [
                yesterday,
                yesterday.addingTimeInterval(1),
                yesterday.addingTimeInterval(2),
                yesterday.addingTimeInterval(3)
            ]
        )
    }

    // MARK: - titlesForURLs

    func testThatTitlesForURLsReturnsTitlesMappingForMatchingURLs() async throws {
        dataSource.history = [
            .make(url: try XCTUnwrap("https://example1.com".url), title: "Example 1", visits: []),
            .make(url: try XCTUnwrap("https://example1.com/index2.html".url), title: "Example 1 Index 2", visits: []),
            .make(url: try XCTUnwrap("https://wikipedia.org".url), title: "Wikipedia", visits: []),
            .make(url: try XCTUnwrap("https://en.wikipedia.org".url), title: "English Wikipedia", visits: []),
            .make(url: try XCTUnwrap("https://duckduckgo.com".url), title: "DuckDuckGo", visits: [])
        ]

        XCTAssertEqual(
            provider.titles(for: [
                try XCTUnwrap("https://example1.com".url),
                try XCTUnwrap("https://example1.com/index2.html".url),
                try XCTUnwrap("https://en.wikipedia.org".url)
            ]),
            [
                try XCTUnwrap("https://example1.com".url): "Example 1",
                try XCTUnwrap("https://example1.com/index2.html".url): "Example 1 Index 2",
                try XCTUnwrap("https://en.wikipedia.org".url): "English Wikipedia"
            ]
        )
    }

    // MARK: - pixels

    func testWhenVisitsBatchIsCalledWithZeroOffsetAndUserSourceThenFilterUpdatedPixelIsFired() async throws {
        _ = await provider.visitsBatch(for: .rangeFilter(.all), source: .user, limit: 10, offset: 0)
        _ = await provider.visitsBatch(for: .rangeFilter(.today), source: .user, limit: 10, offset: 0)
        _ = await provider.visitsBatch(for: .searchTerm("foo"), source: .user, limit: 10, offset: 0)
        _ = await provider.visitsBatch(for: .domainFilter(["example.com"]), source: .user, limit: 10, offset: 0)

        XCTAssertEqual(pixelHandler.fireFilterUpdatedPixelCalls, [
            .rangeFilter(.all),
            .rangeFilter(.today),
            .searchTerm("foo"),
            .domainFilter(["example.com"])
        ])
    }

    func testWhenVisitsBatchIsCalledWithNonZeroOffsetOrNonUserSourceThenFilterUpdatedPixelIsNotFired() async throws {
        _ = await provider.visitsBatch(for: .rangeFilter(.all), source: .user, limit: 10, offset: 10)
        XCTAssertEqual(pixelHandler.fireFilterUpdatedPixelCalls, [])
        _ = await provider.visitsBatch(for: .rangeFilter(.all), source: .auto, limit: 10, offset: 10)
        XCTAssertEqual(pixelHandler.fireFilterUpdatedPixelCalls, [])
        _ = await provider.visitsBatch(for: .rangeFilter(.all), source: .initial, limit: 10, offset: 10)
        XCTAssertEqual(pixelHandler.fireFilterUpdatedPixelCalls, [])
        _ = await provider.visitsBatch(for: .rangeFilter(.all), source: .auto, limit: 10, offset: 0)
        XCTAssertEqual(pixelHandler.fireFilterUpdatedPixelCalls, [])
        _ = await provider.visitsBatch(for: .rangeFilter(.all), source: .initial, limit: 10, offset: 0)
        XCTAssertEqual(pixelHandler.fireFilterUpdatedPixelCalls, [])
    }

    // MARK: - Sites section and preferred URL

    @MainActor
    func testPreferredURLPrefersHttpsThenMostRecent() async throws {
        // Given entries for the same eTLD+1 with both http and https
        let httpsURL = try XCTUnwrap("https://example.com".url)
        let httpURL = try XCTUnwrap("http://example.com".url)
        let newer = Date()
        let older = newer.addingTimeInterval(-3600)

        let httpsEntry = HistoryEntry.make(url: httpsURL, visits: [.init(date: newer)])
        let httpEntry = HistoryEntry.make(url: httpURL, visits: [.init(date: older)])
        dataSource.history = [httpsEntry, httpEntry]
        await provider.refreshData()

        // When
        let preferred = provider.preferredURL(forSiteDomain: "example.com")

        // Then
        XCTAssertEqual(preferred, httpsURL)
    }

    @MainActor
    func testSitesSectionTitlePrefersIndexPageTitle() async throws {
        // Given: root index page and another page under the same domain
        let indexURL = try XCTUnwrap("https://example.com".url)
        let otherURL = try XCTUnwrap("https://example.com/page".url)
        let today = Date()

        let indexEntry = HistoryEntry.make(url: indexURL, title: "Home", visits: [.init(date: today)])
        let otherEntry = HistoryEntry.make(url: otherURL, title: "Other", visits: [.init(date: today)])
        dataSource.history = [indexEntry, otherEntry]
        await provider.refreshData()

        // When: requesting Sites items
        let batch = await provider.visitsBatch(for: .rangeFilter(.allSites), source: .auto, limit: 20, offset: 0)
        let items = batch.visits
        let siteItem = try XCTUnwrap(items.first(where: { $0.etldPlusOne == "example.com" }))

        // Then: title chosen from index page record
        XCTAssertEqual(siteItem.title, "Home")
        XCTAssertEqual(siteItem.domain, "example.com")
    }

    @MainActor
    func testAllSitesDeduplicatesByETLDPlusOne() async throws {
        // Given subdomains and base domain for the same eTLD+1 plus another domain
        let today = Date()
        dataSource.history = [
            .make(url: try XCTUnwrap("https://a.example.com".url), visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://b.example.com".url), visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://example.com".url), visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://other.com".url), visits: [.init(date: today)])
        ]
        await provider.refreshData()

        // When
        let ranges = provider.ranges

        // Then: allSites count equals unique eTLD+1 domains (example.com, other.com)
        // 4 visits from today, deduplicated to 2 unique domains
        XCTAssertEqual(ranges, [
            .init(id: .all, count: 4),
            .init(id: .today, count: 4),
            .init(id: .allSites, count: 2)
        ])
    }

    @MainActor
    func testSitesSectionTitleFallsBackToMostRecentVisitWhenNoIndexPage() async throws {
        // Given: no root page for example.com, two different pages with different visit dates
        let olderDate = Date().addingTimeInterval(-7200)
        let newerDate = Date().addingTimeInterval(-3600)
        let olderURL = try XCTUnwrap("https://example.com/older".url)
        let newerURL = try XCTUnwrap("https://example.com/newer".url)

        let olderEntry = HistoryEntry.make(url: olderURL, title: "Older Title", visits: [.init(date: olderDate)])
        let newerEntry = HistoryEntry.make(url: newerURL, title: "Newer Title", visits: [.init(date: newerDate)])
        dataSource.history = [olderEntry, newerEntry]

        await provider.refreshData()
        let batch = await provider.visitsBatch(for: .rangeFilter(.allSites), source: .auto, limit: 10, offset: 0)
        let items = batch.visits
        let siteItem = try XCTUnwrap(items.first(where: { $0.etldPlusOne == "example.com" }))
        XCTAssertEqual(siteItem.title, "Newer Title")
    }

    // MARK: - bestTitle(forSiteDomain:)

    func testWhenHistoryIsEmptyThenBestTitleReturnsDomain() {
        dataSource.history = nil
        let title = provider.bestTitle(forSiteDomain: "example.com")
        XCTAssertEqual(title, "example.com")
    }

    func testWhenNoEntriesMatchDomainThenBestTitleReturnsDomain() throws {
        dataSource.history = [
            .make(url: try XCTUnwrap("https://other.com".url), title: "Other Site", visits: [.init(date: Date())])
        ]
        let title = provider.bestTitle(forSiteDomain: "example.com")
        XCTAssertEqual(title, "example.com")
    }

    func testWhenRootIndexPageExistsThenBestTitleReturnsItsTitle() throws {
        let today = Date()
        dataSource.history = [
            .make(url: try XCTUnwrap("https://example.com/page1/page2".url), title: "Page 2", visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://example.com".url), title: "Example Home", visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://example.com/page".url), title: "Other Page", visits: [.init(date: today)]),
        ]
        let title = provider.bestTitle(forSiteDomain: "example.com")
        XCTAssertEqual(title, "Example Home")
    }

    func testWhenRootIndexPageHasEmptyTitleThenBestTitleReturnsURL() throws {
        let today = Date()
        dataSource.history = [
            .make(url: try XCTUnwrap("https://example.com".url), title: "", visits: [.init(date: today)])
        ]
        let title = provider.bestTitle(forSiteDomain: "example.com")
        XCTAssertEqual(title, "https://example.com")
    }

    func testWhenRootIndexPageHasNilTitleThenBestTitleReturnsURL() throws {
        let today = Date()
        dataSource.history = [
            .make(url: try XCTUnwrap("https://example.com".url), title: nil, visits: [.init(date: today)])
        ]
        let title = provider.bestTitle(forSiteDomain: "example.com")
        XCTAssertEqual(title, "https://example.com")
    }

    func testWhenWWWRootIndexPageExistsThenBestTitleReturnsItsTitle() throws {
        let today = Date()
        dataSource.history = [
            .make(url: try XCTUnwrap("https://www.example.com".url), title: "WWW Example", visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://example.com/page".url), title: "Other Page", visits: [.init(date: today)])
        ]
        let title = provider.bestTitle(forSiteDomain: "example.com")
        XCTAssertEqual(title, "WWW Example")
    }

    func testWhenRootIndexPageWithSlashExistsThenBestTitleReturnsItsTitle() throws {
        let today = Date()
        dataSource.history = [
            .make(url: try XCTUnwrap("https://example.com/".url), title: "Root Slash", visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://example.com/page".url), title: "Other Page", visits: [.init(date: today)])
        ]
        let title = provider.bestTitle(forSiteDomain: "example.com")
        XCTAssertEqual(title, "Root Slash")
    }

    func testWhenMultipleRootPagesThenBestTitlePrefersHTTPS() throws {
        let today = Date()
        dataSource.history = [
            .make(url: try XCTUnwrap("http://example.com".url), title: "HTTP Root", visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://example.com".url), title: "HTTPS Root", visits: [.init(date: today)])
        ]
        let title = provider.bestTitle(forSiteDomain: "example.com")
        XCTAssertEqual(title, "HTTPS Root")
    }

    func testWhenMultipleRootPagesWithSameSchemesThenBestTitlePrefersMostRecent() throws {
        let olderDate = Date().addingTimeInterval(-7200)
        let newerDate = Date().addingTimeInterval(-3600)
        dataSource.history = [
            .make(url: try XCTUnwrap("https://example.com".url), title: "Older Root", visits: [.init(date: olderDate)]),
            .make(url: try XCTUnwrap("https://www.example.com".url), title: "Newer Root", visits: [.init(date: newerDate)])
        ]
        let title = provider.bestTitle(forSiteDomain: "example.com")
        XCTAssertEqual(title, "Newer Root")
    }

    func testWhenNoRootPageThenBestTitleReturnsMostRecentPageTitle() throws {
        let olderDate = Date().addingTimeInterval(-7200)
        let newerDate = Date().addingTimeInterval(-3600)
        dataSource.history = [
            .make(url: try XCTUnwrap("https://example.com/older".url), title: "Older Page", visits: [.init(date: olderDate)]),
            .make(url: try XCTUnwrap("https://example.com/newer".url), title: "Newer Page", visits: [.init(date: newerDate)])
        ]
        let title = provider.bestTitle(forSiteDomain: "example.com")
        XCTAssertEqual(title, "Newer Page")
    }

    func testWhenNoRootPageAndMostRecentHasEmptyTitleThenBestTitleReturnsURL() throws {
        let olderDate = Date().addingTimeInterval(-7200)
        let newerDate = Date().addingTimeInterval(-3600)
        dataSource.history = [
            .make(url: try XCTUnwrap("https://example.com/older".url), title: "Older Page", visits: [.init(date: olderDate)]),
            .make(url: try XCTUnwrap("https://example.com/newer".url), title: "", visits: [.init(date: newerDate)])
        ]
        let title = provider.bestTitle(forSiteDomain: "example.com")
        XCTAssertEqual(title, "https://example.com/newer")
    }

    func testWhenMultipleSubdomainsThenBestTitleMatchesAllForDomain() throws {
        let today = Date()
        dataSource.history = [
            .make(url: try XCTUnwrap("https://a.example.com/page".url), title: "Subdomain A", visits: [.init(date: today.addingTimeInterval(-3600))]),
            .make(url: try XCTUnwrap("https://b.example.com/page".url), title: "Subdomain B", visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://other.com".url), title: "Other", visits: [.init(date: today)])
        ]
        let title = provider.bestTitle(forSiteDomain: "example.com")
        // Should return most recent from any subdomain
        XCTAssertEqual(title, "Subdomain B")
    }

    func testWhenRootPageExistsWithSubdomainPagesThenBestTitlePrefersRoot() throws {
        let today = Date()
        let olderDate = today.addingTimeInterval(-7200)
        dataSource.history = [
            .make(url: try XCTUnwrap("https://example.com".url), title: "Root Page", visits: [.init(date: olderDate)]),
            .make(url: try XCTUnwrap("https://subdomain.example.com/newer".url), title: "Subdomain Newer", visits: [.init(date: today)])
        ]
        let title = provider.bestTitle(forSiteDomain: "example.com")
        // Should prefer root even if subdomain is more recent
        XCTAssertEqual(title, "Root Page")
    }

    func testWhenHTTPSRootAndHTTPNonRootThenBestTitlePrefersHTTPSRoot() throws {
        let today = Date()
        dataSource.history = [
            .make(url: try XCTUnwrap("https://example.com".url), title: "HTTPS Root", visits: [.init(date: today.addingTimeInterval(-3600))]),
            .make(url: try XCTUnwrap("http://example.com/page".url), title: "HTTP Page", visits: [.init(date: today)])
        ]
        let title = provider.bestTitle(forSiteDomain: "example.com")
        XCTAssertEqual(title, "HTTPS Root")
    }

    func testWhenRootHTTPNewerThanRootHTTPSThenBestTitlePrefersHTTPS() throws {
        let olderDate = Date().addingTimeInterval(-7200)
        let newerDate = Date().addingTimeInterval(-3600)
        dataSource.history = [
            .make(url: try XCTUnwrap("https://example.com".url), title: "HTTPS Root", visits: [.init(date: olderDate)]),
            .make(url: try XCTUnwrap("http://example.com".url), title: "HTTP Root", visits: [.init(date: newerDate)])
        ]
        let title = provider.bestTitle(forSiteDomain: "example.com")
        XCTAssertEqual(title, "HTTPS Root")
    }

    // MARK: - helpers

    private func date(year: Int?, month: Int?, day: Int?, hour: Int? = nil, minute: Int? = nil, second: Int? = nil) throws -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return try XCTUnwrap(Calendar.autoupdatingCurrent.date(from: components))
    }
}

final class MockHistoryViewDateFormatter: HistoryViewDateFormatting {
    func currentDate() -> Date {
        date
    }

    func dayString(for date: Date) -> String {
        "Today"
    }

    func timeString(for date: Date) -> String {
        "10:08"
    }

    var date: Date = Date()
}

final class MockDomainFireproofStatusProvider: DomainFireproofStatusProviding {
    func isFireproof(fireproofDomain domain: String) -> Bool {
        isFireproof(domain)
    }

    var isFireproof: (String) -> Bool = { _ in false }
}

final class CapturingHistoryBurner: HistoryBurning {
    func burnAll() async {
        burnAllCallsCount += 1
    }

    func burn(_ visits: [Visit], animated: Bool) async {
        burnCalls.append(.init(visits, animated))
    }

    var burnCalls: [BurnCall] = []
    var burnAllCallsCount: Int = 0

    struct BurnCall: Equatable {
        let visits: [Visit]
        let animated: Bool

        init(_ visits: [Visit], _ animated: Bool) {
            self.visits = visits
            self.animated = animated
        }
    }
}

final class CapturingHistoryDataSource: HistoryDataSource {
    func delete(_ visits: [Visit]) async {
        deleteCalls.append(visits)
    }

    var history: BrowsingHistory? = []
    var historyDictionary: [URL: HistoryEntry]? {
        history?.reduce(into: [URL: HistoryEntry](), { partialResult, entry in
            partialResult[entry.url] = entry
        })
    }
    var deleteCalls: [[Visit]] = []
}

final class CapturingHistoryViewDataProviderPixelHandler: HistoryViewDataProviderPixelFiring {
    func fireFilterUpdatedPixel(_ query: DataModel.HistoryQueryKind) {
        fireFilterUpdatedPixelCalls.append(query)
    }

    var fireFilterUpdatedPixelCalls: [DataModel.HistoryQueryKind] = []
}

fileprivate extension HistoryEntry {
    static func make(identifier: UUID = UUID(), url: URL, title: String? = nil, visits: Set<Visit>) -> HistoryEntry {
        let entry = HistoryEntry(
            identifier: identifier,
            url: url,
            title: title,
            failedToLoad: false,
            numberOfTotalVisits: visits.count,
            lastVisit: visits.map(\.date).max() ?? Date(),
            visits: [],
            numberOfTrackersBlocked: 0,
            blockedTrackingEntities: [],
            trackersFound: false
        )
        entry.visits = Set(visits.map {
            Visit(date: $0.date, identifier: entry.url, historyEntry: entry)
        })
        return entry
    }
}
