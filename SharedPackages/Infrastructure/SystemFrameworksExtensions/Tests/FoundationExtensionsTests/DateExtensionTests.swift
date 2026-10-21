//
//  DateExtensionTests.swift
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

import Foundation
import Testing
@testable import FoundationExtensions

final class DateExtensionTests {

    @Test("Date components are correctly extracted")
    func testComponents() {
        let date = Date()
        let components = date.components

        #expect(components.day != nil)
        #expect(components.month != nil)
        #expect(components.year != nil)
    }

    @Test("Week ago date is correctly calculated")
    func testWeekAgo() {
        let weekAgo = Date.weekAgo
        let expectedDate = Calendar.current.date(byAdding: .weekOfMonth, value: -1, to: Date())!

        #expect(weekAgo.startOfDay == expectedDate.startOfDay)
    }

    @Test("Month ago date is correctly calculated")
    func testMonthAgo() {
        let monthAgo = Date.monthAgo
        let expectedDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())!

        #expect(monthAgo.startOfDay == expectedDate.startOfDay)
    }

    @Test("Year ago date is correctly calculated")
    func testYearAgo() {
        let yearAgo = Date.yearAgo
        let expectedDate = Calendar.current.date(byAdding: .year, value: -1, to: Date())!

        #expect(yearAgo.startOfDay == expectedDate.startOfDay)
    }

    @Test("A year from now date is correctly calculated")
    func testAYearFromNow() {
        let aYearFromNow = Date.aYearFromNow
        let expectedDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!

        #expect(aYearFromNow.startOfDay == expectedDate.startOfDay)
    }

    @Test("Days ago date is correctly calculated")
    func testDaysAgo() {
        let daysAgo = Date.daysAgo(5)
        let expectedDate = Calendar.current.date(byAdding: .day, value: -5, to: Date())!

        #expect(daysAgo.startOfDay == expectedDate.startOfDay)
    }

    @Test("Same day comparison works correctly")
    func testIsSameDay() {
        let today = Date()
        let sameDay = today
        let differentDay = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        #expect(Date.isSameDay(today, sameDay))
        #expect(!Date.isSameDay(today, differentDay))
        #expect(!Date.isSameDay(today, nil))
    }

    @Test("Start of day tomorrow is correctly calculated")
    func testStartOfDayTomorrow() {
        let startOfDayTomorrow = Date.startOfDayTomorrow
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!

        #expect(abs(startOfDayTomorrow.timeIntervalSince1970 - Calendar.current.startOfDay(for: tomorrow).timeIntervalSince1970) < 5)
    }

    @Test("Start of day today is correctly calculated")
    func testStartOfDayToday() {
        let startOfDayToday = Date.startOfDayToday
        #expect(abs(startOfDayToday.timeIntervalSince1970 - Calendar.current.startOfDay(for: Date()).timeIntervalSince1970) < 5)
    }

    @Test("Start of day is correctly calculated")
    func testStartOfDay() {
        let date = Date()
        let startOfDay = date.startOfDay

        #expect(abs(startOfDay.timeIntervalSince1970 - Calendar.current.startOfDay(for: date).timeIntervalSince1970) < 5)
    }

    @Test("Days ago instance method works correctly")
    func testDaysAgoInstanceMethod() {
        let date = Date()
        let daysAgo = date.daysAgo(3)
        let expectedDate = Calendar.current.date(byAdding: .day, value: -3, to: date)!

        #expect(daysAgo.startOfDay == expectedDate.startOfDay)
    }

    @Test("Start of minute now is correctly calculated")
    func testStartOfMinuteNow() {
        let startOfMinuteNow = Date.startOfMinuteNow
        let now = Calendar.current.date(bySetting: .second, value: 0, of: Date())!
        let expectedStart = Calendar.current.date(byAdding: .minute, value: -1, to: now)!

        #expect(abs(startOfMinuteNow.timeIntervalSince1970 - expectedStart.timeIntervalSince1970) < 0.1)
    }

    @Test("Months with index are correctly calculated")
    func testMonthsWithIndex() {
        let monthsWithIndex = Date.monthsWithIndex
        let monthSymbols = Calendar.current.monthSymbols

        #expect(monthsWithIndex.count == 12)
        #expect(monthsWithIndex.first?.name == monthSymbols.first)
        #expect(monthsWithIndex.first?.index == 1)
    }

    @Test("Days in month are correctly calculated")
    func testDaysInMonth() {
        #expect(Date.daysInMonth == Array(1...31))
    }

    @Test("Next ten years are correctly calculated")
    func testNextTenYears() {
        let nextTenYears = Date.nextTenYears
        let currentYear = Calendar.current.component(.year, from: Date())

        #expect(nextTenYears.count == 11)
        #expect(nextTenYears.first == currentYear)
        #expect(nextTenYears.last == currentYear + 10)
    }

    @Test("Last hundred years are correctly calculated")
    func testLastHundredYears() {
        let lastHundredYears = Date.lastHundredYears
        let currentYear = Calendar.current.component(.year, from: Date())

        #expect(lastHundredYears.count == 101)
        #expect(lastHundredYears.first == currentYear)
        #expect(lastHundredYears.last == currentYear - 100)
    }

    @Test("Day since reference date is correctly calculated")
    func testDaySinceReferenceDate() {
        let date = Date()
        let daysSinceReference = Int(date.timeIntervalSinceReferenceDate / TimeInterval.day)

        #expect(date.daySinceReferenceDate == daysSinceReference)
    }

    @Test("Same day instance method works correctly")
    func testIsSameDayInstanceMethod() {
        let today = Date()
        let sameDay = today
        let differentDay = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        #expect(today.isSameDay(sameDay))
        #expect(!today.isSameDay(differentDay))
        #expect(!today.isSameDay(nil))
    }

    @Test("Is less than days ago works correctly")
    func testIsLessThanDaysAgo() {
        let recentDate = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let olderDate = Calendar.current.date(byAdding: .day, value: -5, to: Date())!

        #expect(recentDate.isLessThan(daysAgo: 3))
        #expect(!olderDate.isLessThan(daysAgo: 3))
    }

    @Test("Is less than minutes ago works correctly")
    func testIsLessThanMinutesAgo() {
        let recentDate = Calendar.current.date(byAdding: .minute, value: -10, to: Date())!
        let olderDate = Calendar.current.date(byAdding: .minute, value: -30, to: Date())!

        #expect(recentDate.isLessThan(minutesAgo: 15))
        #expect(!olderDate.isLessThan(minutesAgo: 15))
    }

    @Test("Seconds since now is correctly calculated")
    func testSecondsSinceNow() {
        let date = Calendar.current.date(byAdding: .second, value: -30, to: Date())!
        #expect(date.secondsSinceNow() == 30)
    }

    @Test("Minutes since now is correctly calculated")
    func testMinutesSinceNow() {
        let date = Calendar.current.date(byAdding: .minute, value: -10, to: Date())!
        #expect(date.minutesSinceNow() == 10)
    }

    @Test("Hours since now is correctly calculated")
    func testHoursSinceNow() {
        let date = Calendar.current.date(byAdding: .hour, value: -5, to: Date())!
        #expect(date.hoursSinceNow() == 5)
    }

    @Test("Days since now is correctly calculated")
    func testDaysSinceNow() {
        let date = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        #expect(date.daysSinceNow() == 7)
    }

    @Test("Months since now is correctly calculated")
    func testMonthsSinceNow() {
        let date = Calendar.current.date(byAdding: .month, value: -3, to: Date())!
        #expect(date.monthsSinceNow() == 3)
    }

    @Test("Years since now is correctly calculated")
    func testYearsSinceNow() {
        let date = Calendar.current.date(byAdding: .year, value: -2, to: Date())!
        #expect(date.yearsSinceNow() == 2)
    }

    @Test("Is in the past works correctly")
    func testIsInThePast() {
        let pastDate = Date(timeIntervalSinceNow: -100) // 100 seconds ago
        #expect(pastDate.isInThePast())

        let futureDate = Date(timeIntervalSinceNow: 100) // 100 seconds in the future
        #expect(!futureDate.isInThePast())
    }

    @Test("Is in the future works correctly")
    func testIsInTheFuture() {
        let futureDate = Date(timeIntervalSinceNow: 100) // 100 seconds in the future
        #expect(futureDate.isInTheFuture())

        let pastDate = Date(timeIntervalSinceNow: -100) // 100 seconds ago
        #expect(!pastDate.isInTheFuture())
    }
}
