//
//  DateExtensionTest.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

final class DateExtensionTests: XCTestCase {

    func testComponents() {
        let date = Date()
        let components = date.components

        XCTAssertNotNil(components.day)
        XCTAssertNotNil(components.month)
        XCTAssertNotNil(components.year)
    }

    func testWeekAgo() {
        let weekAgo = Date.weekAgo
        let expectedDate = Calendar.current.date(byAdding: .weekOfMonth, value: -1, to: Date())!

        XCTAssertEqual(weekAgo.startOfDay, expectedDate.startOfDay)
    }

    func testMonthAgo() {
        let monthAgo = Date.monthAgo
        let expectedDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())!

        XCTAssertEqual(monthAgo.startOfDay, expectedDate.startOfDay)
    }

    func testYearAgo() {
        let yearAgo = Date.yearAgo
        let expectedDate = Calendar.current.date(byAdding: .year, value: -1, to: Date())!

        XCTAssertEqual(yearAgo.startOfDay, expectedDate.startOfDay)
    }

    func testAYearFromNow() {
        let aYearFromNow = Date.aYearFromNow
        let expectedDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!

        XCTAssertEqual(aYearFromNow.startOfDay, expectedDate.startOfDay)
    }

    func testDaysAgo() {
        let daysAgo = Date.daysAgo(5)
        let expectedDate = Calendar.current.date(byAdding: .day, value: -5, to: Date())!

        XCTAssertEqual(daysAgo.startOfDay, expectedDate.startOfDay)
    }

    func testIsSameDay() {
        let today = Date()
        let sameDay = today
        let differentDay = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        XCTAssertTrue(Date.isSameDay(today, sameDay))
        XCTAssertFalse(Date.isSameDay(today, differentDay))
        XCTAssertFalse(Date.isSameDay(today, nil))
    }

    func testStartOfDayTomorrow() {
        let startOfDayTomorrow = Date.startOfDayTomorrow
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!

        XCTAssertEqual(startOfDayTomorrow, Calendar.current.startOfDay(for: tomorrow))
    }

    func testStartOfDayToday() {
        let startOfDayToday = Date.startOfDayToday
        XCTAssertEqual(startOfDayToday, Calendar.current.startOfDay(for: Date()))
    }

    func testStartOfDay() {
        let date = Date()
        let startOfDay = date.startOfDay

        XCTAssertEqual(startOfDay, Calendar.current.startOfDay(for: date))
    }

    func testDaysAgoInstanceMethod() {
        let date = Date()
        let daysAgo = date.daysAgo(3)
        let expectedDate = Calendar.current.date(byAdding: .day, value: -3, to: date)!

        XCTAssertEqual(daysAgo.startOfDay, expectedDate.startOfDay)
    }

    func testStartOfMinuteNow() {
        let startOfMinuteNow = Date.startOfMinuteNow
        let now = Calendar.current.date(bySetting: .second, value: 0, of: Date())!
        let expectedStart = Calendar.current.date(byAdding: .minute, value: -1, to: now)!

        XCTAssertEqual(startOfMinuteNow, expectedStart)
    }

    func testMonthsWithIndex() {
        let monthsWithIndex = Date.monthsWithIndex
        let monthSymbols = Calendar.current.monthSymbols

        XCTAssertEqual(monthsWithIndex.count, 12)
        XCTAssertEqual(monthsWithIndex.first?.name, monthSymbols.first)
        XCTAssertEqual(monthsWithIndex.first?.index, 1)
    }

    func testDaysInMonth() {
        XCTAssertEqual(Date.daysInMonth, Array(1...31))
    }

    func testNextTenYears() {
        let nextTenYears = Date.nextTenYears
        let currentYear = Calendar.current.component(.year, from: Date())

        XCTAssertEqual(nextTenYears.count, 11)
        XCTAssertEqual(nextTenYears.first, currentYear)
        XCTAssertEqual(nextTenYears.last, currentYear + 10)
    }

    func testLastHundredYears() {
        let lastHundredYears = Date.lastHundredYears
        let currentYear = Calendar.current.component(.year, from: Date())

        XCTAssertEqual(lastHundredYears.count, 101)
        XCTAssertEqual(lastHundredYears.first, currentYear)
        XCTAssertEqual(lastHundredYears.last, currentYear - 100)
    }

    func testDaySinceReferenceDate() {
        let date = Date()
        let daysSinceReference = Int(date.timeIntervalSinceReferenceDate / TimeInterval.day)

        XCTAssertEqual(date.daySinceReferenceDate, daysSinceReference)
    }

    func testIsSameDayInstanceMethod() {
        let today = Date()
        let sameDay = today
        let differentDay = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        XCTAssertTrue(today.isSameDay(sameDay))
        XCTAssertFalse(today.isSameDay(differentDay))
        XCTAssertFalse(today.isSameDay(nil))
    }

    func testIsLessThanDaysAgo() {
        let recentDate = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let olderDate = Calendar.current.date(byAdding: .day, value: -5, to: Date())!

        XCTAssertTrue(recentDate.isLessThan(daysAgo: 3))
        XCTAssertFalse(olderDate.isLessThan(daysAgo: 3))
    }

    func testIsLessThanMinutesAgo() {
        let recentDate = Calendar.current.date(byAdding: .minute, value: -10, to: Date())!
        let olderDate = Calendar.current.date(byAdding: .minute, value: -30, to: Date())!

        XCTAssertTrue(recentDate.isLessThan(minutesAgo: 15))
        XCTAssertFalse(olderDate.isLessThan(minutesAgo: 15))
    }

    func testSecondsSinceNow() {
        let date = Calendar.current.date(byAdding: .second, value: -30, to: Date())!
        XCTAssertEqual(date.secondsSinceNow(), 30)
    }

    func testMinutesSinceNow() {
        let date = Calendar.current.date(byAdding: .minute, value: -10, to: Date())!
        XCTAssertEqual(date.minutesSinceNow(), 10)
    }

    func testHoursSinceNow() {
        let date = Calendar.current.date(byAdding: .hour, value: -5, to: Date())!
        XCTAssertEqual(date.hoursSinceNow(), 5)
    }

    func testDaysSinceNow() {
        let date = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        XCTAssertEqual(date.daysSinceNow(), 7)
    }

    func testMonthsSinceNow() {
        let date = Calendar.current.date(byAdding: .month, value: -3, to: Date())!
        XCTAssertEqual(date.monthsSinceNow(), 3)
    }

    func testYearsSinceNow() {
        let date = Calendar.current.date(byAdding: .year, value: -2, to: Date())!
        XCTAssertEqual(date.yearsSinceNow(), 2)
    }

    func testIsInThePast() {
        let pastDate = Date(timeIntervalSinceNow: -100) // 100 seconds ago
        XCTAssertTrue(pastDate.isInThePast())

        let futureDate = Date(timeIntervalSinceNow: 100) // 100 seconds in the future
        XCTAssertFalse(futureDate.isInThePast())

        XCTAssertFalse(Date().isInThePast()) // Edge case: exact current time
    }

    func testIsInTheFuture() {
        let futureDate = Date(timeIntervalSinceNow: 100) // 100 seconds in the future
        XCTAssertTrue(futureDate.isInTheFuture())

        let pastDate = Date(timeIntervalSinceNow: -100) // 100 seconds ago
        XCTAssertFalse(pastDate.isInTheFuture())

        XCTAssertFalse(Date().isInTheFuture()) // Edge case: exact current time
    }
}
