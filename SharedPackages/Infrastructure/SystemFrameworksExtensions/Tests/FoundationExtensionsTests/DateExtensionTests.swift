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

    @available(iOS 16, macOS 13, *)
    @Test("Date components are correctly extracted", .timeLimit(.minutes(1)))
    func testComponents() {
        let date = Date()
        let components = date.components

        #expect(components.day != nil)
        #expect(components.month != nil)
        #expect(components.year != nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Week ago date is correctly calculated", .timeLimit(.minutes(1)))
    func testWeekAgo() {
        let weekAgo = Date.weekAgo
        let expectedDate = Calendar.current.date(byAdding: .weekOfMonth, value: -1, to: Date())!

        #expect(weekAgo.startOfDay == expectedDate.startOfDay)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Month ago date is correctly calculated", .timeLimit(.minutes(1)))
    func testMonthAgo() {
        let monthAgo = Date.monthAgo
        let expectedDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())!

        #expect(monthAgo.startOfDay == expectedDate.startOfDay)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Year ago date is correctly calculated", .timeLimit(.minutes(1)))
    func testYearAgo() {
        let yearAgo = Date.yearAgo
        let expectedDate = Calendar.current.date(byAdding: .year, value: -1, to: Date())!

        #expect(yearAgo.startOfDay == expectedDate.startOfDay)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A year from now date is correctly calculated", .timeLimit(.minutes(1)))
    func testAYearFromNow() {
        let aYearFromNow = Date.aYearFromNow
        let expectedDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!

        #expect(aYearFromNow.startOfDay == expectedDate.startOfDay)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Days ago date is correctly calculated", .timeLimit(.minutes(1)))
    func testDaysAgo() {
        let daysAgo = Date.daysAgo(5)
        let expectedDate = Calendar.current.date(byAdding: .day, value: -5, to: Date())!

        #expect(daysAgo.startOfDay == expectedDate.startOfDay)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Same day comparison works correctly", .timeLimit(.minutes(1)))
    func testIsSameDay() {
        let today = Date()
        let sameDay = today
        let differentDay = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        #expect(Date.isSameDay(today, sameDay))
        #expect(!Date.isSameDay(today, differentDay))
        #expect(!Date.isSameDay(today, nil))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Start of day tomorrow is correctly calculated", .timeLimit(.minutes(1)))
    func testStartOfDayTomorrow() {
        let startOfDayTomorrow = Date.startOfDayTomorrow
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!

        #expect(abs(startOfDayTomorrow.timeIntervalSince1970 - Calendar.current.startOfDay(for: tomorrow).timeIntervalSince1970) < 5)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Start of day today is correctly calculated", .timeLimit(.minutes(1)))
    func testStartOfDayToday() {
        let startOfDayToday = Date.startOfDayToday
        #expect(abs(startOfDayToday.timeIntervalSince1970 - Calendar.current.startOfDay(for: Date()).timeIntervalSince1970) < 5)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Start of day is correctly calculated", .timeLimit(.minutes(1)))
    func testStartOfDay() {
        let date = Date()
        let startOfDay = date.startOfDay

        #expect(abs(startOfDay.timeIntervalSince1970 - Calendar.current.startOfDay(for: date).timeIntervalSince1970) < 5)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Days ago instance method works correctly", .timeLimit(.minutes(1)))
    func testDaysAgoInstanceMethod() {
        let date = Date()
        let daysAgo = date.daysAgo(3)
        let expectedDate = Calendar.current.date(byAdding: .day, value: -3, to: date)!

        #expect(daysAgo.startOfDay == expectedDate.startOfDay)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Start of minute now is correctly calculated", .timeLimit(.minutes(1)))
    func testStartOfMinuteNow() {
        let startOfMinuteNow = Date.startOfMinuteNow
        let now = Calendar.current.date(bySetting: .second, value: 0, of: Date())!
        let expectedStart = Calendar.current.date(byAdding: .minute, value: -1, to: now)!

        #expect(abs(startOfMinuteNow.timeIntervalSince1970 - expectedStart.timeIntervalSince1970) < 0.1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Months with index are correctly calculated", .timeLimit(.minutes(1)))
    func testMonthsWithIndex() {
        let monthsWithIndex = Date.monthsWithIndex
        let monthSymbols = Calendar.current.monthSymbols

        #expect(monthsWithIndex.count == 12)
        #expect(monthsWithIndex.first?.name == monthSymbols.first)
        #expect(monthsWithIndex.first?.index == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Days in month are correctly calculated", .timeLimit(.minutes(1)))
    func testDaysInMonth() {
        #expect(Date.daysInMonth == Array(1...31))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Next ten years are correctly calculated", .timeLimit(.minutes(1)))
    func testNextTenYears() {
        let nextTenYears = Date.nextTenYears
        let currentYear = Calendar.current.component(.year, from: Date())

        #expect(nextTenYears.count == 11)
        #expect(nextTenYears.first == currentYear)
        #expect(nextTenYears.last == currentYear + 10)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Last hundred years are correctly calculated", .timeLimit(.minutes(1)))
    func testLastHundredYears() {
        let lastHundredYears = Date.lastHundredYears
        let currentYear = Calendar.current.component(.year, from: Date())

        #expect(lastHundredYears.count == 101)
        #expect(lastHundredYears.first == currentYear)
        #expect(lastHundredYears.last == currentYear - 100)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Day since reference date is correctly calculated", .timeLimit(.minutes(1)))
    func testDaySinceReferenceDate() {
        let date = Date()
        let daysSinceReference = Int(date.timeIntervalSinceReferenceDate / TimeInterval.day)

        #expect(date.daySinceReferenceDate == daysSinceReference)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Same day instance method works correctly", .timeLimit(.minutes(1)))
    func testIsSameDayInstanceMethod() {
        let today = Date()
        let sameDay = today
        let differentDay = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        #expect(today.isSameDay(sameDay))
        #expect(!today.isSameDay(differentDay))
        #expect(!today.isSameDay(nil))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Is less than days ago works correctly", .timeLimit(.minutes(1)))
    func testIsLessThanDaysAgo() {
        let recentDate = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let olderDate = Calendar.current.date(byAdding: .day, value: -5, to: Date())!

        #expect(recentDate.isLessThan(daysAgo: 3))
        #expect(!olderDate.isLessThan(daysAgo: 3))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Is less than minutes ago works correctly", .timeLimit(.minutes(1)))
    func testIsLessThanMinutesAgo() {
        let recentDate = Calendar.current.date(byAdding: .minute, value: -10, to: Date())!
        let olderDate = Calendar.current.date(byAdding: .minute, value: -30, to: Date())!

        #expect(recentDate.isLessThan(minutesAgo: 15))
        #expect(!olderDate.isLessThan(minutesAgo: 15))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Seconds since now is correctly calculated", .timeLimit(.minutes(1)))
    func testSecondsSinceNow() {
        let date = Calendar.current.date(byAdding: .second, value: -30, to: Date())!
        #expect(date.secondsSinceNow() == 30)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Minutes since now is correctly calculated", .timeLimit(.minutes(1)))
    func testMinutesSinceNow() {
        let date = Calendar.current.date(byAdding: .minute, value: -10, to: Date())!
        #expect(date.minutesSinceNow() == 10)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Hours since now is correctly calculated", .timeLimit(.minutes(1)))
    func testHoursSinceNow() {
        let date = Calendar.current.date(byAdding: .hour, value: -5, to: Date())!
        #expect(date.hoursSinceNow() == 5)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Days since now is correctly calculated", .timeLimit(.minutes(1)))
    func testDaysSinceNow() {
        let date = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        #expect(date.daysSinceNow() == 7)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Months since now is correctly calculated", .timeLimit(.minutes(1)))
    func testMonthsSinceNow() {
        let date = Calendar.current.date(byAdding: .month, value: -3, to: Date())!
        #expect(date.monthsSinceNow() == 3)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Years since now is correctly calculated", .timeLimit(.minutes(1)))
    func testYearsSinceNow() {
        let date = Calendar.current.date(byAdding: .year, value: -2, to: Date())!
        #expect(date.yearsSinceNow() == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Is in the past works correctly", .timeLimit(.minutes(1)))
    func testIsInThePast() {
        let pastDate = Date(timeIntervalSinceNow: -100) // 100 seconds ago
        #expect(pastDate.isInThePast())

        let futureDate = Date(timeIntervalSinceNow: 100) // 100 seconds in the future
        #expect(!futureDate.isInThePast())
    }

    @available(iOS 16, macOS 13, *)
    @Test("Is in the future works correctly", .timeLimit(.minutes(1)))
    func testIsInTheFuture() {
        let futureDate = Date(timeIntervalSinceNow: 100) // 100 seconds in the future
        #expect(futureDate.isInTheFuture())

        let pastDate = Date(timeIntervalSinceNow: -100) // 100 seconds ago
        #expect(!pastDate.isInTheFuture())
    }
}
