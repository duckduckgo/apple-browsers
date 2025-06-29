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
        featureFlagger.enabledFeatureFlags = [.historyView]
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
        XCTAssertEqual(provider.ranges, [.init(id: .all, count: 0)])

        dataSource.history = []
        await provider.refreshData()
        XCTAssertEqual(provider.ranges, [.init(id: .all, count: 0)])
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
        XCTAssertEqual(provider.ranges, [.init(id: .all, count: 1), .init(id: .today, count: 1)])
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
        XCTAssertEqual(provider.ranges, [.init(id: .all, count: 2), .init(id: .today, count: 1), .init(id: .yesterday, count: 1)])
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
            .init(id: .wednesday, count: 1)
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
            .init(id: .older, count: 1)
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
            .init(id: .thursday, count: 1)
        ])

        try await populateHistory(for: date(year: 2025, month: 2, day: 25)) // Tuesday
        XCTAssertEqual(provider.ranges, [
            .init(id: .all, count: 3),
            .init(id: .today, count: 0),
            .init(id: .yesterday, count: 0),
            .init(id: .sunday, count: 1),
            .init(id: .saturday, count: 1),
            .init(id: .friday, count: 1)
        ])

        try await populateHistory(for: date(year: 2025, month: 2, day: 26)) // Wednesday
        XCTAssertEqual(provider.ranges, [
            .init(id: .all, count: 3),
            .init(id: .today, count: 0),
            .init(id: .yesterday, count: 0),
            .init(id: .monday, count: 1),
            .init(id: .sunday, count: 1),
            .init(id: .saturday, count: 1)
        ])

        try await populateHistory(for: date(year: 2025, month: 2, day: 27)) // Thursday
        XCTAssertEqual(provider.ranges, [
            .init(id: .all, count: 3),
            .init(id: .today, count: 0),
            .init(id: .yesterday, count: 0),
            .init(id: .tuesday, count: 1),
            .init(id: .monday, count: 1),
            .init(id: .sunday, count: 1)
        ])

        try await populateHistory(for: date(year: 2025, month: 2, day: 28)) // Friday
        XCTAssertEqual(provider.ranges, [
            .init(id: .all, count: 3),
            .init(id: .today, count: 0),
            .init(id: .yesterday, count: 0),
            .init(id: .wednesday, count: 1),
            .init(id: .tuesday, count: 1),
            .init(id: .monday, count: 1)
        ])

        try await populateHistory(for: date(year: 2025, month: 3, day: 1)) // Saturday
        XCTAssertEqual(provider.ranges, [
            .init(id: .all, count: 3),
            .init(id: .today, count: 0),
            .init(id: .yesterday, count: 0),
            .init(id: .thursday, count: 1),
            .init(id: .wednesday, count: 1),
            .init(id: .tuesday, count: 1)
        ])

        try await populateHistory(for: date(year: 2025, month: 3, day: 2)) // Sunday
        XCTAssertEqual(provider.ranges, [
            .init(id: .all, count: 3),
            .init(id: .today, count: 0),
            .init(id: .yesterday, count: 0),
            .init(id: .friday, count: 1),
            .init(id: .thursday, count: 1),
            .init(id: .wednesday, count: 1)
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

        batch = await provider.visitsBatch(for: .domainFilter(""), source: .auto, limit: 6, offset: 0)
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
        let batch = await provider.visitsBatch(for: .domainFilter("example.com"), source: .auto, limit: 4, offset: 0)
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
        let batch = await provider.visitsBatch(for: .domainFilter("example.com"), source: .auto, limit: 4, offset: 0)
        XCTAssertEqual(batch.finished, true)
        XCTAssertEqual(batch.visits.count, 1)
    }

    // MARK: - countVisibleVisits

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
        let allCount = await provider.countVisibleVisits(matching: .rangeFilter(.all))
        let todayCount = await provider.countVisibleVisits(matching: .rangeFilter(.today))
        let yesterdayCount = await provider.countVisibleVisits(matching: .rangeFilter(.yesterday))
        let saturdayCount = await provider.countVisibleVisits(matching: .rangeFilter(.saturday))
        let fridayCount = await provider.countVisibleVisits(matching: .rangeFilter(.friday))
        let thursdayCount = await provider.countVisibleVisits(matching: .rangeFilter(.thursday))
        let wednesdayCount = await provider.countVisibleVisits(matching: .rangeFilter(.wednesday))
        let tuesdayCount = await provider.countVisibleVisits(matching: .rangeFilter(.tuesday))
        let olderCount = await provider.countVisibleVisits(matching: .rangeFilter(.older))
        XCTAssertEqual(allCount, 19)
        XCTAssertEqual(todayCount, 2)
        XCTAssertEqual(yesterdayCount, 2)
        XCTAssertEqual(saturdayCount, 2)
        XCTAssertEqual(fridayCount, 1)
        XCTAssertEqual(thursdayCount, 2)
        XCTAssertEqual(wednesdayCount, 3)
        XCTAssertEqual(tuesdayCount, 1)
        XCTAssertEqual(olderCount, 6)
    }

    // MARK: - deleteVisitsMatchingQuery

    func testThatDeleteVisitsWithRangeFilterDeletesAllVisitsInTheGivenRange() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24) // Monday
        let today = dateFormatter.currentDate().startOfDay
        let yesterday = today.daysAgo(1)
        let saturday = today.daysAgo(2)
        let thursday = today.daysAgo(4)

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example1.com".url), visits: [
                .init(date: today),
                .init(date: yesterday)
            ]),
            .make(url: try XCTUnwrap("https://example2.com".url), visits: [
                .init(date: today),
                .init(date: yesterday),
                .init(date: yesterday),
                .init(date: yesterday),
                .init(date: yesterday)
            ]),
            .make(url: try XCTUnwrap("https://example3.com".url), visits: [
                .init(date: saturday),
                .init(date: thursday)
            ])
        ]
        await provider.refreshData()
        await provider.deleteVisits(matching: .rangeFilter(.yesterday))
        XCTAssertEqual(dataSource.deleteCalls.count, 1)

        let deletedVisits = try XCTUnwrap(dataSource.deleteCalls.first)
        XCTAssertEqual(deletedVisits.count, 5)
        XCTAssertEqual(
            Set(deletedVisits.compactMap(\.historyEntry?.url.absoluteString)),
            ["https://example1.com", "https://example2.com"]
        )
    }

    func testThatDeleteVisitsWithSearchFilterDeletesAllVisitsMatchingSearchTerm() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24) // Monday
        let today = dateFormatter.currentDate().startOfDay
        let yesterday = today.daysAgo(1)
        let saturday = today.daysAgo(2)
        let thursday = today.daysAgo(4)

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example1.com".url), visits: [
                .init(date: today),
                .init(date: yesterday)
            ]),
            .make(url: try XCTUnwrap("https://example12.com".url), visits: [
                .init(date: today),
                .init(date: yesterday),
                .init(date: yesterday),
                .init(date: yesterday),
                .init(date: yesterday)
            ]),
            .make(url: try XCTUnwrap("https://example3.com".url), visits: [
                .init(date: saturday),
                .init(date: thursday)
            ])
        ]
        await provider.refreshData()
        await provider.deleteVisits(matching: .searchTerm("example1"))
        XCTAssertEqual(dataSource.deleteCalls.count, 1)

        let deletedVisits = try XCTUnwrap(dataSource.deleteCalls.first)
        XCTAssertEqual(deletedVisits.count, 7)
        XCTAssertEqual(
            Set(deletedVisits.compactMap(\.historyEntry?.url.absoluteString)),
            ["https://example1.com", "https://example12.com"]
        )
    }

    func testThatDeleteVisitsWithDomainFilterDeletesAllVisitsMatchingDomain() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24) // Monday
        let today = dateFormatter.currentDate().startOfDay
        let yesterday = today.daysAgo(1)
        let saturday = today.daysAgo(2)
        let thursday = today.daysAgo(4)

        dataSource.history = [
            .make(url: try XCTUnwrap("https://www1.example.com".url), visits: [
                .init(date: today),
                .init(date: yesterday)
            ]),
            .make(url: try XCTUnwrap("https://www2.example.com".url), visits: [
                .init(date: today),
                .init(date: yesterday),
                .init(date: yesterday),
                .init(date: yesterday),
                .init(date: yesterday)
            ]),
            .make(url: try XCTUnwrap("https://example3.com".url), visits: [
                .init(date: saturday),
                .init(date: thursday)
            ])
        ]
        await provider.refreshData()
        await provider.deleteVisits(matching: .domainFilter("example.com"))
        XCTAssertEqual(dataSource.deleteCalls.count, 1)

        let deletedVisits = try XCTUnwrap(dataSource.deleteCalls.first)
        XCTAssertEqual(deletedVisits.count, 7)
        XCTAssertEqual(
            Set(deletedVisits.compactMap(\.historyEntry?.url.absoluteString)),
            ["https://www1.example.com", "https://www2.example.com"]
        )
    }

    func testThatDeleteAllVisitsDeletesAllVisits() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24) // Monday
        let today = dateFormatter.currentDate().startOfDay
        let yesterday = today.daysAgo(1)
        let saturday = today.daysAgo(2)
        let thursday = today.daysAgo(4)

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example1.com".url), visits: [
                .init(date: today),
                .init(date: yesterday)
            ]),
            .make(url: try XCTUnwrap("https://example2.com".url), visits: [
                .init(date: today),
                .init(date: yesterday),
                .init(date: yesterday),
                .init(date: yesterday),
                .init(date: yesterday)
            ]),
            .make(url: try XCTUnwrap("https://example3.com".url), visits: [
                .init(date: saturday),
                .init(date: thursday)
            ])
        ]
        await provider.refreshData()
        await provider.deleteVisits(matching: .rangeFilter(.all))
        XCTAssertEqual(dataSource.deleteCalls.count, 1)

        let deletedVisits = try XCTUnwrap(dataSource.deleteCalls.first)
        XCTAssertEqual(deletedVisits.count, 9)
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
        await provider.deleteVisits(for: identifiers)
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
        await provider.deleteVisits(for: identifiers)
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

    // MARK: - burnVisitsMatchingQuery

    func testThatBurnVisitsBurnsAllVisitsInTheGivenRange() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24) // Monday
        let today = dateFormatter.currentDate().startOfDay
        let yesterday = today.daysAgo(1)
        let saturday = today.daysAgo(2)
        let thursday = today.daysAgo(4)

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example1.com".url), visits: [
                .init(date: today),
                .init(date: yesterday)
            ]),
            .make(url: try XCTUnwrap("https://example2.com".url), visits: [
                .init(date: today),
                .init(date: yesterday),
                .init(date: yesterday),
                .init(date: yesterday),
                .init(date: yesterday)
            ]),
            .make(url: try XCTUnwrap("https://example3.com".url), visits: [
                .init(date: saturday),
                .init(date: thursday)
            ])
        ]
        await provider.refreshData()
        await provider.burnVisits(matching: .rangeFilter(.yesterday))
        XCTAssertEqual(burner.burnCalls.count, 1)

        let burnVisitsCall = try XCTUnwrap(burner.burnCalls.first)
        XCTAssertEqual(burnVisitsCall.visits.count, 5)
        XCTAssertEqual(burnVisitsCall.animated, false)
        XCTAssertEqual(
            Set(burnVisitsCall.visits.compactMap(\.historyEntry?.url.absoluteString)),
            ["https://example1.com", "https://example2.com"]
        )
    }

    func testThatBurnVisitsForAllHistoryBurnsAllVisits() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24) // Monday
        let today = dateFormatter.currentDate().startOfDay
        let yesterday = today.daysAgo(1)
        let saturday = today.daysAgo(2)

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example1.com".url), visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://example2.com".url), visits: [.init(date: yesterday)]),
            .make(url: try XCTUnwrap("https://example3.com".url), visits: [.init(date: saturday)])
        ]
        await provider.refreshData()
        await provider.burnVisits(matching: .rangeFilter(.all))
        XCTAssertEqual(burner.burnAllCallsCount, 1)
    }

    func testThatBurnVisitsDoesNothingWhenThereAreNoMatchingVisits() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24) // Monday
        let today = dateFormatter.currentDate().startOfDay
        let yesterday = today.daysAgo(1)
        let saturday = today.daysAgo(2)

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example1.com".url), visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://example2.com".url), visits: [.init(date: yesterday)]),
            .make(url: try XCTUnwrap("https://example3.com".url), visits: [.init(date: saturday)])
        ]
        await provider.refreshData()
        await provider.burnVisits(matching: .rangeFilter(.older))
        XCTAssertEqual(burner.burnAllCallsCount, 0)
        XCTAssertEqual(burner.burnCalls.count, 0)
    }

    func testThatBurnVisitsFromTodayAnimates() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24) // Monday
        let today = dateFormatter.currentDate().startOfDay

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example1.com".url), visits: [.init(date: today)])
        ]
        await provider.refreshData()
        await provider.burnVisits(matching: .rangeFilter(.today))
        XCTAssertEqual(burner.burnCalls.count, 1)

        let burnVisitsCall = try XCTUnwrap(burner.burnCalls.first)
        XCTAssertEqual(burnVisitsCall.visits.count, 1)
        XCTAssertEqual(burnVisitsCall.animated, true)
    }

    // MARK: - burnVisitsForIdentifiers

    func testThatBurnVisitsForIdentifiersBurnsVisitsWithMatchingIdentifiers() async throws {
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
        await provider.burnVisits(for: identifiers)
        XCTAssertEqual(burner.burnCalls.count, 1)

        let burnVisitsCall = try XCTUnwrap(burner.burnCalls.first)
        XCTAssertEqual(burnVisitsCall.visits.count, 2)
        XCTAssertEqual(burnVisitsCall.animated, false)
        XCTAssertEqual(
            Set(burnVisitsCall.visits.compactMap(\.historyEntry?.url.absoluteString)),
            ["https://example2.com", "https://example3.com"]
        )
    }

    func testThatBurnVisitsForIdentifiersBurnsAllMatchingVisitsFromGivenDay() async throws {
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
        await provider.burnVisits(for: identifiers)
        XCTAssertEqual(burner.burnCalls.count, 1)

        let burnVisitsCall = try XCTUnwrap(burner.burnCalls.first)
        XCTAssertEqual(burnVisitsCall.visits.count, 4)
        XCTAssertEqual(burnVisitsCall.animated, false)
        XCTAssertEqual(
            Set(burnVisitsCall.visits.compactMap(\.historyEntry?.url.absoluteString)),
            ["https://example.com"]
        )
        XCTAssertEqual(
            Set(burnVisitsCall.visits.compactMap(\.date)),
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
        _ = await provider.visitsBatch(for: .domainFilter("example.com"), source: .user, limit: 10, offset: 0)

        XCTAssertEqual(pixelHandler.fireFilterUpdatedPixelCalls, [
            .rangeFilter(.all),
            .rangeFilter(.today),
            .searchTerm("foo"),
            .domainFilter("example.com")
        ])
    }

    func testWhenVisitsBatchIsCalledWithNonZeroOffsetAndUserSourceThenFilterUpdatedPixelIsNotFired() async throws {
        _ = await provider.visitsBatch(for: .rangeFilter(.all), source: .user, limit: 10, offset: 10)
        XCTAssertEqual(pixelHandler.fireFilterUpdatedPixelCalls, [])
    }

    func testWhenVisitsBatchIsCalledWithNonZeroOffsetAndAutoSourceThenFilterUpdatedPixelIsNotFired() async throws {
        _ = await provider.visitsBatch(for: .rangeFilter(.all), source: .auto, limit: 10, offset: 10)
        XCTAssertEqual(pixelHandler.fireFilterUpdatedPixelCalls, [])
    }

    func testWhenVisitsBatchIsCalledWithNonZeroOffsetAndInitialSourceThenFilterUpdatedPixelIsNotFired() async throws {
        _ = await provider.visitsBatch(for: .rangeFilter(.all), source: .initial, limit: 10, offset: 10)
        XCTAssertEqual(pixelHandler.fireFilterUpdatedPixelCalls, [])
    }

    func testWhenVisitsBatchIsCalledWithZeroOffsetAndAutoSourceThenFilterUpdatedPixelIsNotFired() async throws {
        _ = await provider.visitsBatch(for: .rangeFilter(.all), source: .auto, limit: 10, offset: 0)
        XCTAssertEqual(pixelHandler.fireFilterUpdatedPixelCalls, [])
    }

    func testWhenVisitsBatchIsCalledWithZeroOffsetAndInitialSourceThenFilterUpdatedPixelIsNotFired() async throws {
        _ = await provider.visitsBatch(for: .rangeFilter(.all), source: .initial, limit: 10, offset: 0)
        XCTAssertEqual(pixelHandler.fireFilterUpdatedPixelCalls, [])
    }

    // MARK: - helpers

    private func date(year: Int?, month: Int?, day: Int?, hour: Int? = nil, minute: Int? = nil, second: Int? = nil) throws -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return try XCTUnwrap(Calendar.autoupdatingCurrent.date(from: components))
    }
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
