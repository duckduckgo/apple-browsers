//
//  SubscriptionOnboardingFreeTrialCalendarCardModelTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
@testable import DuckDuckGo

final class SubscriptionOnboardingFreeTrialCalendarCardModelTests: XCTestCase {

    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
    }

    override func tearDown() {
        calendar = nil
        super.tearDown()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeModel(start: Date, now: Date, billing: Date? = nil, length: Int = 7) -> SubscriptionOnboardingFreeTrialCalendarCardModel {
        SubscriptionOnboardingFreeTrialCalendarCardModel(freeTrialStartDate: start,
                                   billingStartDate: billing ?? start,
                                   trialLength: length,
                                   now: now,
                                   calendar: calendar)
    }

    // MARK: - currentTrialDay / markerIndex

    func testWhenTodayIsTheStartDateThenCurrentTrialDayIsOne() {
        let start = date(2026, 5, 7)
        let sut = makeModel(start: start, now: start)

        XCTAssertEqual(sut.currentTrialDay, 1)
        XCTAssertEqual(sut.markerIndex, 0)
    }

    func testWhenThreeDaysHaveElapsedThenCurrentTrialDayIsFour() {
        let start = date(2026, 5, 7)
        let sut = makeModel(start: start, now: date(2026, 5, 10))

        XCTAssertEqual(sut.currentTrialDay, 4)
        XCTAssertEqual(sut.markerIndex, 3)
    }

    func testCurrentTrialDayTextRendersTheTrialDayInTheCalendarLocale() {
        let start = date(2026, 5, 7)
        let sut = makeModel(start: start, now: date(2026, 5, 10))

        XCTAssertEqual(sut.currentTrialDayText, "4")
    }

    func testWhenTodayIsBeforeTheStartDateThenCurrentTrialDayClampsToOne() {
        let start = date(2026, 5, 7)
        let sut = makeModel(start: start, now: date(2026, 5, 5))

        XCTAssertEqual(sut.currentTrialDay, 1)
        XCTAssertEqual(sut.markerIndex, 0)
    }

    func testWhenTodayIsAfterTheTrialEndThenCurrentTrialDayClampsToLength() {
        let start = date(2026, 5, 7)
        let sut = makeModel(start: start, now: date(2026, 5, 30), length: 7)

        XCTAssertEqual(sut.currentTrialDay, 7)
        XCTAssertEqual(sut.markerIndex, 6)
    }

    func testWhenTodayIsLaterInTheStartDayThenDayMathUsesStartOfDay() {
        let start = date(2026, 5, 7)
        let laterSameDay = calendar.date(byAdding: .hour, value: 20, to: start)!
        let sut = makeModel(start: start, now: laterSameDay)

        XCTAssertEqual(sut.currentTrialDay, 1)
    }

    // MARK: - dayLabels

    func testDayLabelsAreDayOfMonthAcrossTheTrialWindow() {
        let start = date(2026, 5, 7)
        let sut = makeModel(start: start, now: start, length: 7)

        XCTAssertEqual(sut.dayLabels, ["7", "8", "9", "10", "11", "12", "13"])
    }

    func testDayLabelsRollOverTheMonthBoundary() {
        let start = date(2026, 5, 31)
        let sut = makeModel(start: start, now: start, length: 7)

        XCTAssertEqual(sut.dayLabels, ["31", "1", "2", "3", "4", "5", "6"])
    }

    func testDayLabelsCountMatchesCustomTrialLength() {
        let start = date(2026, 5, 7)
        let sut = makeModel(start: start, now: start, length: 5)

        XCTAssertEqual(sut.dayLabels.count, 5)
        XCTAssertEqual(sut.dayLabels, ["7", "8", "9", "10", "11"])
    }

    // MARK: - trialLength

    func testWhenTrialLengthIsBelowOneThenItIsClampedToOne() {
        let start = date(2026, 5, 7)
        let sut = makeModel(start: start, now: start, length: 0)

        XCTAssertEqual(sut.trialLength, 1)
        XCTAssertEqual(sut.dayLabels, ["7"])
    }

    // MARK: - billingText

    func testBillingTextContainsTheFormattedBillingDate() {
        let start = date(2026, 5, 7)
        let billing = date(2026, 5, 14)
        let sut = makeModel(start: start, now: start, billing: billing)

        XCTAssertTrue(sut.billingText.contains("May 14, 2026"), "Unexpected billing text: \(sut.billingText)")
    }

    // MARK: - Localization

    func testDayNumeralsRenderInTheCalendarsNumberingSystem() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "ar_EG@numbers=arab")
        let start = calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 10))!
        let sut = SubscriptionOnboardingFreeTrialCalendarCardModel(freeTrialStartDate: start,
                                                                   billingStartDate: start,
                                                                   trialLength: 7,
                                                                   now: now,
                                                                   calendar: calendar)

        // Day 4 of 7, and the day-of-month strip, rendered in Arabic-Indic numerals.
        XCTAssertEqual(sut.currentTrialDayText, "٤", "Unexpected trial-day text: \(sut.currentTrialDayText)")
        XCTAssertEqual(sut.dayLabels, ["٧", "٨", "٩", "١٠", "١١", "١٢", "١٣"], "Unexpected day labels: \(sut.dayLabels)")
    }

    func testBillingTextFormatsInTheInjectedCalendarsTimeZone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.locale = Locale(identifier: "en_US")
        let start = calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!
        // 01:00 on May 14 in Tokyo (UTC+9) is still May 13 in UTC; the billing line must use the
        // calendar's own time zone and render May 14, not the UTC-shifted May 13.
        let billing = calendar.date(from: DateComponents(year: 2026, month: 5, day: 14, hour: 1))!
        let sut = SubscriptionOnboardingFreeTrialCalendarCardModel(freeTrialStartDate: start,
                                                                   billingStartDate: billing,
                                                                   trialLength: 7,
                                                                   now: start,
                                                                   calendar: calendar)

        XCTAssertTrue(sut.billingText.contains("May 14, 2026"), "Unexpected billing text: \(sut.billingText)")
    }
}
