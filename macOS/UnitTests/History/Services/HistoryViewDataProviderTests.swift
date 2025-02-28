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
    func burn(_ visits: [Visit], animated: Bool) async {
        burnCalls.append(.init(visits, animated))
    }

    var burnCalls: [BurnCall] = []

    struct BurnCall: Equatable {
        let visits: [Visit]
        let animated: Bool

        init(_ visits: [Visit], _ animated: Bool) {
            self.visits = visits
            self.animated = animated
        }
    }
}

final class HistoryViewDataProviderTests: XCTestCase {
    var provider: HistoryViewDataProvider!
    var dataSource: CapturingHistoryGroupingDataSource!
    var burner: CapturingHistoryBurner!
    var dateFormatter: MockHistoryViewDateFormatter!
    var featureFlagger: MockFeatureFlagger!

    @MainActor
    override func setUp() async throws {
        dataSource = CapturingHistoryGroupingDataSource()
        burner = CapturingHistoryBurner()
        dateFormatter = MockHistoryViewDateFormatter()
        featureFlagger = MockFeatureFlagger()
        provider = HistoryViewDataProvider(
            historyGroupingDataSource: dataSource,
            historyBurner: burner,
            dateFormatter: dateFormatter,
            featureFlagger: featureFlagger
        )
        await provider.refreshData()
    }

    // MARK: - ranges

    func testThatRangesReturnsAllWhenHistoryIsEmpty() async {
        dataSource.history = nil
        await provider.refreshData()
        XCTAssertEqual(provider.ranges, [.all])

        dataSource.history = []
        await provider.refreshData()
        XCTAssertEqual(provider.ranges, [.all])
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
        XCTAssertEqual(provider.ranges, [.all, .today])
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
        XCTAssertEqual(provider.ranges, [.all, .today, .yesterday])
    }

    func testThatRangesIncludesOlderWhenHistoryContainsEntriesOlderThan5Days() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24)
        let today = dateFormatter.currentDate().startOfDay

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example.com".url), visits: [
                .init(date: today.daysAgo(5))
            ])
        ]
        await provider.refreshData()
        XCTAssertEqual(provider.ranges, [.all, .older])
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
        XCTAssertEqual(provider.ranges, [.all, .saturday, .friday, .thursday])

        try await populateHistory(for: date(year: 2025, month: 2, day: 25)) // Tuesday
        XCTAssertEqual(provider.ranges, [.all, .sunday, .saturday, .friday])

        try await populateHistory(for: date(year: 2025, month: 2, day: 26)) // Wednesday
        XCTAssertEqual(provider.ranges, [.all, .monday, .sunday, .saturday])

        try await populateHistory(for: date(year: 2025, month: 2, day: 27)) // Thursday
        XCTAssertEqual(provider.ranges, [.all, .tuesday, .monday, .sunday])

        try await populateHistory(for: date(year: 2025, month: 2, day: 28)) // Friday
        XCTAssertEqual(provider.ranges, [.all, .wednesday, .tuesday, .monday])

        try await populateHistory(for: date(year: 2025, month: 3, day: 1)) // Saturday
        XCTAssertEqual(provider.ranges, [.all, .thursday, .wednesday, .tuesday])

        try await populateHistory(for: date(year: 2025, month: 3, day: 2)) // Sunday
        XCTAssertEqual(provider.ranges, [.all, .friday, .thursday, .wednesday])
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
        var batch = await provider.visitsBatch(for: .rangeFilter(.all), limit: 3, offset: 0)
        XCTAssertEqual(batch.finished, false)
        XCTAssertEqual(batch.visits.count, 3)

        batch = await provider.visitsBatch(for: .rangeFilter(.all), limit: 3, offset: 3)
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
        let batch = await provider.visitsBatch(for: .rangeFilter(.all), limit: 6, offset: 0)
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
        let batch = await provider.visitsBatch(for: .rangeFilter(.yesterday), limit: 4, offset: 0)
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
        var batch = await provider.visitsBatch(for: .searchTerm(""), limit: 6, offset: 0)
        XCTAssertEqual(batch.finished, true)
        XCTAssertEqual(batch.visits.count, 5)

        batch = await provider.visitsBatch(for: .domainFilter(""), limit: 6, offset: 0)
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
        let batch = await provider.visitsBatch(for: .searchTerm("2"), limit: 4, offset: 0)
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
        let batch = await provider.visitsBatch(for: .searchTerm("bCd"), limit: 4, offset: 0)
        XCTAssertEqual(batch.finished, true)
        XCTAssertEqual(batch.visits.count, 2)
    }

    func testThatVisitsBatchWithDomainFilterReturnsVisitsWithURLMatchingTheDomain() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24)
        let today = dateFormatter.currentDate().startOfDay

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example12.com".url), visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://abcd.example.com/foo".url), visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://abcd.example.com/bar".url), visits: [.init(date: today)]),
            .make(url: try XCTUnwrap("https://duckduckgo.com".url), title: "abcd.example.com", visits: [.init(date: today)])
        ]
        await provider.refreshData()
        let batch = await provider.visitsBatch(for: .domainFilter("abcd.example.com"), limit: 4, offset: 0)
        XCTAssertEqual(batch.finished, true)
        XCTAssertEqual(batch.visits.count, 2)
        XCTAssertEqual(Set(batch.visits.map(\.url)), ["https://abcd.example.com/foo", "https://abcd.example.com/bar"])
    }

    func testThatVisitsBatchWithDomainFilterRequiresExactMatch() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24)
        let today = dateFormatter.currentDate().startOfDay

        dataSource.history = [
            .make(url: try XCTUnwrap("https://abcd.example.com/foo".url), visits: [.init(date: today)])
        ]
        await provider.refreshData()
        let batch = await provider.visitsBatch(for: .domainFilter("example.com"), limit: 4, offset: 0)
        XCTAssertEqual(batch.finished, true)
        XCTAssertEqual(batch.visits.count, 0)
    }

    // MARK: - countVisibleVisits

    func testThatCountVisibleVisitsReportsOneVisitPerDayPerURL() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24) // Monday
        let today = dateFormatter.currentDate().startOfDay
        let yesterday = today.daysAgo(1)
        let saturday = today.daysAgo(2)
        let friday = today.daysAgo(3)
        let thursday = today.daysAgo(4)
        let older1 = today.daysAgo(5)
        let older2 = today.daysAgo(6)
        let older3 = today.daysAgo(7)

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example1.com".url), visits: [
                .init(date: today),
                .init(date: yesterday),
                .init(date: saturday),
                .init(date: saturday),
                .init(date: saturday),
                .init(date: thursday),
                .init(date: older1),
                .init(date: older2),
                .init(date: older3)
            ]),
            .make(url: try XCTUnwrap("https://example2.com".url), visits: [
                .init(date: today),
                .init(date: yesterday),
                .init(date: friday),
                .init(date: older1)
            ]),
            .make(url: try XCTUnwrap("https://example3.com".url), visits: [
                .init(date: saturday),
                .init(date: thursday),
                .init(date: older1),
                .init(date: older3)
            ])
        ]
        await provider.refreshData()
        let allCount = await provider.countVisibleVisits(for: .all)
        let todayCount = await provider.countVisibleVisits(for: .today)
        let yesterdayCount = await provider.countVisibleVisits(for: .yesterday)
        let saturdayCount = await provider.countVisibleVisits(for: .saturday)
        let fridayCount = await provider.countVisibleVisits(for: .friday)
        let thursdayCount = await provider.countVisibleVisits(for: .thursday)
        let olderCount = await provider.countVisibleVisits(for: .older)
        XCTAssertEqual(allCount, 15)
        XCTAssertEqual(todayCount, 2)
        XCTAssertEqual(yesterdayCount, 2)
        XCTAssertEqual(saturdayCount, 2)
        XCTAssertEqual(fridayCount, 1)
        XCTAssertEqual(thursdayCount, 2)
        XCTAssertEqual(olderCount, 6)
    }

    // MARK: - deleteVisits

    func testThatDeleteVisitsDeletesAllVisitsInTheGivenRange() async throws {
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
                .init(date: yesterday),
            ]),
            .make(url: try XCTUnwrap("https://example3.com".url), visits: [
                .init(date: saturday),
                .init(date: thursday)
            ])
        ]
        await provider.refreshData()
        await provider.deleteVisits(for: .yesterday)
        XCTAssertEqual(dataSource.deleteCalls.count, 1)

        let deletedVisits = try XCTUnwrap(dataSource.deleteCalls.first)
        XCTAssertEqual(deletedVisits.count, 5)
        XCTAssertEqual(
            Set(deletedVisits.compactMap(\.historyEntry?.url.absoluteString)),
            ["https://example1.com", "https://example2.com"]
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
                .init(date: yesterday),
            ]),
            .make(url: try XCTUnwrap("https://example3.com".url), visits: [
                .init(date: saturday),
                .init(date: thursday)
            ])
        ]
        await provider.refreshData()
        await provider.deleteVisits(for: .all)
        XCTAssertEqual(dataSource.deleteCalls.count, 1)

        let deletedVisits = try XCTUnwrap(dataSource.deleteCalls.first)
        XCTAssertEqual(deletedVisits.count, 9)
    }

    // MARK: - burnVisits

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
                .init(date: yesterday),
            ]),
            .make(url: try XCTUnwrap("https://example3.com".url), visits: [
                .init(date: saturday),
                .init(date: thursday)
            ])
        ]
        await provider.refreshData()
        await provider.burnVisits(for: .yesterday)
        XCTAssertEqual(burner.burnCalls.count, 1)

        let burnVisitsCall = try XCTUnwrap(burner.burnCalls.first)
        XCTAssertEqual(burnVisitsCall.visits.count, 5)
        XCTAssertEqual(burnVisitsCall.animated, false)
        XCTAssertEqual(
            Set(burnVisitsCall.visits.compactMap(\.historyEntry?.url.absoluteString)),
            ["https://example1.com", "https://example2.com"]
        )
    }

    func testThatBurnAllVisitsBurnsAllVisitsAndAnimates() async throws {
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
                .init(date: yesterday),
            ]),
            .make(url: try XCTUnwrap("https://example3.com".url), visits: [
                .init(date: saturday),
                .init(date: thursday)
            ])
        ]
        await provider.refreshData()
        await provider.burnVisits(for: .all)
        XCTAssertEqual(burner.burnCalls.count, 1)

        let burnVisitsCall = try XCTUnwrap(burner.burnCalls.first)
        XCTAssertEqual(burnVisitsCall.visits.count, 9)
        XCTAssertEqual(burnVisitsCall.animated, true)
    }

    func testThatBurnVisitsFromTodayAnimates() async throws {
        dateFormatter.date = try date(year: 2025, month: 2, day: 24) // Monday
        let today = dateFormatter.currentDate().startOfDay

        dataSource.history = [
            .make(url: try XCTUnwrap("https://example1.com".url), visits: [.init(date: today)])
        ]
        await provider.refreshData()
        await provider.burnVisits(for: .today)
        XCTAssertEqual(burner.burnCalls.count, 1)

        let burnVisitsCall = try XCTUnwrap(burner.burnCalls.first)
        XCTAssertEqual(burnVisitsCall.visits.count, 1)
        XCTAssertEqual(burnVisitsCall.animated, true)
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
