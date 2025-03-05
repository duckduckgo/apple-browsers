//
//  HistoryRangeExtensionTests.swift
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

import XCTest
@testable import HistoryView

final class HistoryRangeExtensionTests: XCTestCase {

    // MARK: - init(date:referenceDate:)

    func testDateInitializerForToday() throws {
        let monday = try date(year: 2025, month: 2, day: 24, hour: 7) // Monday
        let yesterday = try date(year: 2025, month: 2, day: 24, hour: 5)
        XCTAssertEqual(DataModel.HistoryRange(date: yesterday, referenceDate: monday), .today)
    }

    func testDateInitializerForYesterday() throws {
        let monday = try date(year: 2025, month: 2, day: 24) // Monday
        let yesterday = try date(year: 2025, month: 2, day: 23)
        XCTAssertEqual(DataModel.HistoryRange(date: yesterday, referenceDate: monday), .yesterday)
    }

    func testDateInitializerFor2DaysAgo() throws {
        let monday = try date(year: 2025, month: 2, day: 24) // Monday
        let saturday = try date(year: 2025, month: 2, day: 22)
        XCTAssertEqual(DataModel.HistoryRange(date: saturday, referenceDate: monday), .saturday)
    }

    func testDateInitializerFor3DaysAgo() throws {
        let monday = try date(year: 2025, month: 2, day: 24) // Monday
        let friday = try date(year: 2025, month: 2, day: 21)
        XCTAssertEqual(DataModel.HistoryRange(date: friday, referenceDate: monday), .friday)
    }

    func testDateInitializerFor4DaysAgo() throws {
        let monday = try date(year: 2025, month: 2, day: 24) // Monday
        let thursday = try date(year: 2025, month: 2, day: 20)
        XCTAssertEqual(DataModel.HistoryRange(date: thursday, referenceDate: monday), .thursday)
    }

    func testDateInitializerFor5DaysAgo() throws {
        let monday = try date(year: 2025, month: 2, day: 24) // Monday
        let thursday = try date(year: 2025, month: 2, day: 19)
        XCTAssertEqual(DataModel.HistoryRange(date: thursday, referenceDate: monday), .wednesday)
    }

    func testDateInitializerFor6DaysAgo() throws {
        let monday = try date(year: 2025, month: 2, day: 24) // Monday
        let thursday = try date(year: 2025, month: 2, day: 18)
        XCTAssertEqual(DataModel.HistoryRange(date: thursday, referenceDate: monday), .tuesday)
    }

    func testThatRangeIsOlderForDate7DaysAgo() throws {
        let monday = try date(year: 2025, month: 2, day: 24) // Monday
        let wednesday = try date(year: 2025, month: 2, day: 17)
        XCTAssertEqual(DataModel.HistoryRange(date: wednesday, referenceDate: monday), .older)
    }

    // MARK: - displayedRanges

    func testDisplayedRanges() throws {
        let sun = try date(year: 2025, month: 2, day: 23)
        let mon = try date(year: 2025, month: 2, day: 24)
        let tue = try date(year: 2025, month: 2, day: 25)
        let wed = try date(year: 2025, month: 2, day: 26)
        let thu = try date(year: 2025, month: 2, day: 27)
        let fri = try date(year: 2025, month: 2, day: 28)
        let sat = try date(year: 2025, month: 3, day: 1)
        let sub = try date(year: 2025, month: 3, day: 2)

        XCTAssertEqual(DataModel.HistoryRange.displayedRanges(for: sun), [.today, .yesterday, .friday, .thursday, .wednesday, .tuesday, .monday, .older])
        XCTAssertEqual(DataModel.HistoryRange.displayedRanges(for: mon), [.today, .yesterday, .saturday, .friday, .thursday, .wednesday, .tuesday, .older])
        XCTAssertEqual(DataModel.HistoryRange.displayedRanges(for: tue), [.today, .yesterday, .sunday, .saturday, .friday, .thursday, .wednesday, .older])
        XCTAssertEqual(DataModel.HistoryRange.displayedRanges(for: wed), [.today, .yesterday, .monday, .sunday, .saturday, .friday, .thursday, .older])
        XCTAssertEqual(DataModel.HistoryRange.displayedRanges(for: thu), [.today, .yesterday, .tuesday, .monday, .sunday, .saturday, .friday, .older])
        XCTAssertEqual(DataModel.HistoryRange.displayedRanges(for: fri), [.today, .yesterday, .wednesday, .tuesday, .monday, .sunday, .saturday, .older])
        XCTAssertEqual(DataModel.HistoryRange.displayedRanges(for: sat), [.today, .yesterday, .thursday, .wednesday, .tuesday, .monday, .sunday, .older])
    }

    // MARK: - Private

    private func date(year: Int?, month: Int?, day: Int?, hour: Int? = nil, minute: Int? = nil, second: Int? = nil) throws -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return try XCTUnwrap(Calendar.autoupdatingCurrent.date(from: components))
    }
}
