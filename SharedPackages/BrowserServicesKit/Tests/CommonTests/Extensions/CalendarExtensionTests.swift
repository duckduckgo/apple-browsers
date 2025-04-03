//
//  CalendarExtensionTests.swift
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
@testable import Common

final class CalendarExtensionTests: XCTestCase {

    let calendar = Calendar.autoupdatingCurrent

    func testFirstWeekdayBeforeSunday() throws {
        let sunday = try date(year: 2025, month: 1, day: 5) // Sunday (weekday: 1)

        assertDate(sun(before: sunday), referenceDate: sunday, isWeekday: 1, daysDiff: 7)
        assertDate(sat(before: sunday), referenceDate: sunday, isWeekday: 7, daysDiff: 1)
        assertDate(fri(before: sunday), referenceDate: sunday, isWeekday: 6, daysDiff: 2)
        assertDate(thu(before: sunday), referenceDate: sunday, isWeekday: 5, daysDiff: 3)
        assertDate(wed(before: sunday), referenceDate: sunday, isWeekday: 4, daysDiff: 4)
        assertDate(tue(before: sunday), referenceDate: sunday, isWeekday: 3, daysDiff: 5)
        assertDate(mon(before: sunday), referenceDate: sunday, isWeekday: 2, daysDiff: 6)
    }

    func testFirstWeekdayBeforeMonday() throws {
        let monday = try date(year: 2025, month: 2, day: 24) // Monday (weekday: 2)

        assertDate(sun(before: monday), referenceDate: monday, isWeekday: 1, daysDiff: 1)
        assertDate(sat(before: monday), referenceDate: monday, isWeekday: 7, daysDiff: 2)
        assertDate(fri(before: monday), referenceDate: monday, isWeekday: 6, daysDiff: 3)
        assertDate(thu(before: monday), referenceDate: monday, isWeekday: 5, daysDiff: 4)
        assertDate(wed(before: monday), referenceDate: monday, isWeekday: 4, daysDiff: 5)
        assertDate(tue(before: monday), referenceDate: monday, isWeekday: 3, daysDiff: 6)
        assertDate(mon(before: monday), referenceDate: monday, isWeekday: 2, daysDiff: 7)
    }

    func testFirstWeekdayBeforeTuesday() throws {
        let tuesday = try date(year: 2024, month: 10, day: 29) // Tuesday (weekday: 3)

        assertDate(sun(before: tuesday), referenceDate: tuesday, isWeekday: 1, daysDiff: 2)
        assertDate(sat(before: tuesday), referenceDate: tuesday, isWeekday: 7, daysDiff: 3)
        assertDate(fri(before: tuesday), referenceDate: tuesday, isWeekday: 6, daysDiff: 4)
        assertDate(thu(before: tuesday), referenceDate: tuesday, isWeekday: 5, daysDiff: 5)
        assertDate(wed(before: tuesday), referenceDate: tuesday, isWeekday: 4, daysDiff: 6)
        assertDate(tue(before: tuesday), referenceDate: tuesday, isWeekday: 3, daysDiff: 7)
        assertDate(mon(before: tuesday), referenceDate: tuesday, isWeekday: 2, daysDiff: 1)
    }

    func testFirstWeekdayBeforeWednesday() throws {
        let wednesday = try date(year: 2024, month: 11, day: 6) // Wednesday (weekday: 4)

        assertDate(sun(before: wednesday), referenceDate: wednesday, isWeekday: 1, daysDiff: 3)
        assertDate(sat(before: wednesday), referenceDate: wednesday, isWeekday: 7, daysDiff: 4)
        assertDate(fri(before: wednesday), referenceDate: wednesday, isWeekday: 6, daysDiff: 5)
        assertDate(thu(before: wednesday), referenceDate: wednesday, isWeekday: 5, daysDiff: 6)
        assertDate(wed(before: wednesday), referenceDate: wednesday, isWeekday: 4, daysDiff: 7)
        assertDate(tue(before: wednesday), referenceDate: wednesday, isWeekday: 3, daysDiff: 1)
        assertDate(mon(before: wednesday), referenceDate: wednesday, isWeekday: 2, daysDiff: 2)
    }

    func testFirstWeekdayBeforeThursday() throws {
        let thursday = try date(year: 2025, month: 3, day: 20) // Thursday (weekday: 5)

        assertDate(sun(before: thursday), referenceDate: thursday, isWeekday: 1, daysDiff: 4)
        assertDate(sat(before: thursday), referenceDate: thursday, isWeekday: 7, daysDiff: 5)
        assertDate(fri(before: thursday), referenceDate: thursday, isWeekday: 6, daysDiff: 6)
        assertDate(thu(before: thursday), referenceDate: thursday, isWeekday: 5, daysDiff: 7)
        assertDate(wed(before: thursday), referenceDate: thursday, isWeekday: 4, daysDiff: 1)
        assertDate(tue(before: thursday), referenceDate: thursday, isWeekday: 3, daysDiff: 2)
        assertDate(mon(before: thursday), referenceDate: thursday, isWeekday: 2, daysDiff: 3)
    }

    func testFirstWeekdayBeforeFriday() throws {
        let friday = try date(year: 2025, month: 4, day: 4) // Friday (weekday: 6)

        assertDate(sun(before: friday), referenceDate: friday, isWeekday: 1, daysDiff: 5)
        assertDate(sat(before: friday), referenceDate: friday, isWeekday: 7, daysDiff: 6)
        assertDate(fri(before: friday), referenceDate: friday, isWeekday: 6, daysDiff: 7)
        assertDate(thu(before: friday), referenceDate: friday, isWeekday: 5, daysDiff: 1)
        assertDate(wed(before: friday), referenceDate: friday, isWeekday: 4, daysDiff: 2)
        assertDate(tue(before: friday), referenceDate: friday, isWeekday: 3, daysDiff: 3)
        assertDate(mon(before: friday), referenceDate: friday, isWeekday: 2, daysDiff: 4)
    }

    func testFirstWeekdayBeforeSaturday() throws {
        let saturday = try date(year: 2025, month: 3, day: 8) // Saturday (weekday: 7)

        assertDate(sun(before: saturday), referenceDate: saturday, isWeekday: 1, daysDiff: 6)
        assertDate(sat(before: saturday), referenceDate: saturday, isWeekday: 7, daysDiff: 7)
        assertDate(fri(before: saturday), referenceDate: saturday, isWeekday: 6, daysDiff: 1)
        assertDate(thu(before: saturday), referenceDate: saturday, isWeekday: 5, daysDiff: 2)
        assertDate(wed(before: saturday), referenceDate: saturday, isWeekday: 4, daysDiff: 3)
        assertDate(tue(before: saturday), referenceDate: saturday, isWeekday: 3, daysDiff: 4)
        assertDate(mon(before: saturday), referenceDate: saturday, isWeekday: 2, daysDiff: 5)
    }

    func sun(before date: Date) -> Date { calendar.firstWeekday(1, before: date) }
    func mon(before date: Date) -> Date { calendar.firstWeekday(2, before: date) }
    func tue(before date: Date) -> Date { calendar.firstWeekday(3, before: date) }
    func wed(before date: Date) -> Date { calendar.firstWeekday(4, before: date) }
    func thu(before date: Date) -> Date { calendar.firstWeekday(5, before: date) }
    func fri(before date: Date) -> Date { calendar.firstWeekday(6, before: date) }
    func sat(before date: Date) -> Date { calendar.firstWeekday(7, before: date) }

    func assertDate(_ date: Date, referenceDate: Date, isWeekday weekday: Int, daysDiff: Int, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(calendar.dateComponents([.weekday], from: date).weekday, weekday, file: file, line: line)
        XCTAssertEqual(calendar.numberOfDaysBetween(date, and: referenceDate), daysDiff, file: file, line: line)
    }

    func date(year: Int?, month: Int?, day: Int?, hour: Int? = nil, minute: Int? = nil, second: Int? = nil) throws -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return try XCTUnwrap(Calendar.autoupdatingCurrent.date(from: components))
    }
}
