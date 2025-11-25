//
//  QuantisedTimePastTests.swift
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
@testable import AttributedMetric

final class QuantisedTimePastTests: XCTestCase {

    let testDate = Date(timeIntervalSince1970: 434720061)

    func testTimePastCalculation() {

/*
 Install day is day 0
 week 1 (week of install): days 1-7 after install → count 1 user_retention_week
 They open the app on day [8,14]: count 2 user_retention_week
 They open the app on day [15,21]: count 3 user_retention_week
 They open the app on day [22,28]: count 4 user_retention_week
 They open the app on day [29,56]: count 2 user_retention_month
 ...
 They open the app on day [141,168]: count 6 user_retention_month
 Stop here
 */

        let installDate = testDate

        // Install date
        XCTAssertEqual(QuantisedTimePast.timePastFrom(date: installDate, andInstallationDate: installDate), .none)

        // Week 1
        let day2 = Calendar.current.date(byAdding: .day, value: 1, to: installDate)!
        XCTAssertEqual(QuantisedTimePast.timePastFrom(date: day2, andInstallationDate: installDate), .weeks(1))

        let day7 = Calendar.current.date(byAdding: .day, value: 7, to: installDate)!
        XCTAssertEqual(QuantisedTimePast.timePastFrom(date: day7, andInstallationDate: installDate), .weeks(1))

        // Week 2 boundary tests
        let day8 = Calendar.current.date(byAdding: .day, value: 8, to: installDate)!
        XCTAssertEqual(QuantisedTimePast.timePastFrom(date: day8, andInstallationDate: installDate), .weeks(2))

        let day14 = Calendar.current.date(byAdding: .day, value: 14, to: installDate)!
        XCTAssertEqual(QuantisedTimePast.timePastFrom(date: day14, andInstallationDate: installDate), .weeks(2))

        // Week 3 boundary tests
        let day15 = Calendar.current.date(byAdding: .day, value: 15, to: installDate)!
        XCTAssertEqual(QuantisedTimePast.timePastFrom(date: day15, andInstallationDate: installDate), .weeks(3))

        let day21 = Calendar.current.date(byAdding: .day, value: 21, to: installDate)!
        XCTAssertEqual(QuantisedTimePast.timePastFrom(date: day21, andInstallationDate: installDate), .weeks(3))

        // Week 4 boundary tests
        let day22 = Calendar.current.date(byAdding: .day, value: 22, to: installDate)!
        XCTAssertEqual(QuantisedTimePast.timePastFrom(date: day22, andInstallationDate: installDate), .weeks(4))

        let day28 = Calendar.current.date(byAdding: .day, value: 28, to: installDate)!
        XCTAssertEqual(QuantisedTimePast.timePastFrom(date: day28, andInstallationDate: installDate), .weeks(4))

        // Month 2 boundary tests
        let day29 = Calendar.current.date(byAdding: .day, value: 29, to: installDate)!
        XCTAssertEqual(QuantisedTimePast.timePastFrom(date: day29, andInstallationDate: installDate), .months(2))

        let day56 = Calendar.current.date(byAdding: .day, value: 56, to: installDate)!
        XCTAssertEqual(QuantisedTimePast.timePastFrom(date: day56, andInstallationDate: installDate), .months(2))

        // Month 3 boundary tests
        let day57 = Calendar.current.date(byAdding: .day, value: 57, to: installDate)!
        XCTAssertEqual(QuantisedTimePast.timePastFrom(date: day57, andInstallationDate: installDate), .months(3))

        let day84 = Calendar.current.date(byAdding: .day, value: 84, to: installDate)!
        XCTAssertEqual(QuantisedTimePast.timePastFrom(date: day84, andInstallationDate: installDate), .months(3))

        // Month 4 boundary tests
        let day85 = Calendar.current.date(byAdding: .day, value: 85, to: installDate)!
        XCTAssertEqual(QuantisedTimePast.timePastFrom(date: day85, andInstallationDate: installDate), .months(4))

        let day112 = Calendar.current.date(byAdding: .day, value: 112, to: installDate)!
        XCTAssertEqual(QuantisedTimePast.timePastFrom(date: day112, andInstallationDate: installDate), .months(4))

        // Month 5 boundary tests
        let day113 = Calendar.current.date(byAdding: .day, value: 113, to: installDate)!
        XCTAssertEqual(QuantisedTimePast.timePastFrom(date: day113, andInstallationDate: installDate), .months(5))

        let day140 = Calendar.current.date(byAdding: .day, value: 140, to: installDate)!
        XCTAssertEqual(QuantisedTimePast.timePastFrom(date: day140, andInstallationDate: installDate), .months(5))

        // Month 6 boundary tests
        let day141 = Calendar.current.date(byAdding: .day, value: 141, to: installDate)!
        XCTAssertEqual(QuantisedTimePast.timePastFrom(date: day141, andInstallationDate: installDate), .months(6))

        let day168 = Calendar.current.date(byAdding: .day, value: 168, to: installDate)!
        XCTAssertEqual(QuantisedTimePast.timePastFrom(date: day168, andInstallationDate: installDate), .months(6))

        // Month 7 boundary test (first day after month 6 ends)
        let day169 = Calendar.current.date(byAdding: .day, value: 169, to: installDate)!
        XCTAssertEqual(QuantisedTimePast.timePastFrom(date: day169, andInstallationDate: installDate), .months(7))
    }

    func testNegativeTimeInterval() {
        let installDate = testDate
        let beforeInstall = Calendar.current.date(byAdding: .day, value: -1, to: installDate)!
        XCTAssertEqual(QuantisedTimePast.timePastFrom(date: beforeInstall, andInstallationDate: installDate), .none)
    }

    func testDaysBetween() {
        let calendar = Calendar.current
        let baseDate = Date(timeIntervalSince1970: 0)

        let sameDayStart = calendar.startOfDay(for: baseDate)
        let sameDayEnd = calendar.date(byAdding: .hour, value: 12, to: sameDayStart)!
        XCTAssertEqual(QuantisedTimePast.daysBetween(from: sameDayStart, to: sameDayEnd), 0)

        let oneDayLater = calendar.date(byAdding: .day, value: 1, to: sameDayStart)!
        XCTAssertEqual(QuantisedTimePast.daysBetween(from: sameDayStart, to: oneDayLater), 1)

        let threeDaysLater = calendar.date(byAdding: .day, value: 3, to: sameDayStart)!
        XCTAssertEqual(QuantisedTimePast.daysBetween(from: sameDayStart, to: threeDaysLater), 3)

        let sevenDaysLater = calendar.date(byAdding: .day, value: 7, to: sameDayStart)!
        XCTAssertEqual(QuantisedTimePast.daysBetween(from: sameDayStart, to: sevenDaysLater), 7)

        let futureDate = calendar.date(byAdding: .day, value: -1, to: sameDayStart)!
        XCTAssertEqual(QuantisedTimePast.daysBetween(from: sameDayStart, to: futureDate), -1)

        let startDate = calendar.date(from: DateComponents(year: 2024, month: 1, day: 15))!
        let endDate = calendar.date(from: DateComponents(year: 2024, month: 1, day: 20))!
        XCTAssertEqual(QuantisedTimePast.daysBetween(from: startDate, to: endDate), 5)

        let acrossMonths = calendar.date(from: DateComponents(year: 2024, month: 1, day: 30))!
        let nextMonth = calendar.date(from: DateComponents(year: 2024, month: 2, day: 2))!
        XCTAssertEqual(QuantisedTimePast.daysBetween(from: acrossMonths, to: nextMonth), 3)
    }
}
