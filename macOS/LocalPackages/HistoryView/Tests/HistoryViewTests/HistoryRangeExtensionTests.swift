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

    func testThatRangeIsOlderForDate5DaysAgo() throws {
        let monday = try date(year: 2025, month: 2, day: 24) // Monday
        let wednesday = try date(year: 2025, month: 2, day: 19)
        XCTAssertEqual(DataModel.HistoryRange(date: wednesday, referenceDate: monday), .older)
    }

    private func date(year: Int?, month: Int?, day: Int?, hour: Int? = nil, minute: Int? = nil, second: Int? = nil) throws -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return try XCTUnwrap(Calendar.autoupdatingCurrent.date(from: components))
    }
}
