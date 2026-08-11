//
//  DuckDuckGoSubscriptionTests.swift
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
@testable import Subscription

final class DuckDuckGoSubscriptionTests: XCTestCase {

    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
    }

    override func tearDown() {
        calendar = nil
        super.tearDown()
    }

    // MARK: - trialLengthInDays

    func testWhenThereIsNoTrialOfferThenTrialLengthIsNil() {
        let sut = subscription(startedAt: date(2026, 5, 7),
                               expiresOrRenewsAt: date(2026, 6, 7),
                               hasTrial: false)

        XCTAssertNil(sut.trialLengthInDays(calendar: calendar))
    }

    func testWhenTrialRunsForSevenDaysThenTrialLengthIsSeven() {
        let sut = subscription(startedAt: date(2026, 5, 7),
                               expiresOrRenewsAt: date(2026, 5, 14),
                               hasTrial: true)

        XCTAssertEqual(sut.trialLengthInDays(calendar: calendar), 7)
    }

    func testWhenTrialRunsForFourteenDaysThenTrialLengthIsFourteen() {
        let sut = subscription(startedAt: date(2026, 5, 7),
                               expiresOrRenewsAt: date(2026, 5, 21),
                               hasTrial: true)

        XCTAssertEqual(sut.trialLengthInDays(calendar: calendar), 14)
    }

    func testWhenTrialStartAndBillingAreTheSameDayThenTrialLengthIsNil() {
        let start = date(2026, 5, 7)
        let sut = subscription(startedAt: start, expiresOrRenewsAt: start, hasTrial: true)

        XCTAssertNil(sut.trialLengthInDays(calendar: calendar))
    }

    func testWhenBillingPrecedesTheTrialStartThenTrialLengthIsNil() {
        let sut = subscription(startedAt: date(2026, 5, 7),
                               expiresOrRenewsAt: date(2026, 5, 1),
                               hasTrial: true)

        XCTAssertNil(sut.trialLengthInDays(calendar: calendar))
    }

    /// The model reports the real length. Whether a given UI can render it is the caller's business.
    func testWhenTrialIsLongerThanAMonthThenTheFullLengthIsStillReturned() {
        let sut = subscription(startedAt: date(2026, 5, 7),
                               expiresOrRenewsAt: date(2026, 8, 7),
                               hasTrial: true)

        XCTAssertEqual(sut.trialLengthInDays(calendar: calendar), 92)
    }

    /// Whole calendar days, not elapsed time: this trial spans just over six 24-hour periods but seven days.
    func testWhenTrialStartsLateAndEndsEarlyThenWholeCalendarDaysAreCounted() {
        let sut = subscription(startedAt: date(2026, 5, 7, hour: 23),
                               expiresOrRenewsAt: date(2026, 5, 14, hour: 1),
                               hasTrial: true)

        XCTAssertEqual(sut.trialLengthInDays(calendar: calendar), 7)
    }

    func testWhenCalendarTimeZoneShiftsTheDayBoundaryThenTheCountFollowsThatCalendar() {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(secondsFromGMT: 3 * 60 * 60)!

        // 23:00 UTC on the 7th is already the 8th in UTC+3, so the span loses a whole day there.
        let sut = subscription(startedAt: date(2026, 5, 7, hour: 23),
                               expiresOrRenewsAt: date(2026, 5, 14, hour: 12),
                               hasTrial: true)

        XCTAssertEqual(sut.trialLengthInDays(calendar: calendar), 7)
        XCTAssertEqual(sut.trialLengthInDays(calendar: eastern), 6)
    }

    // MARK: - Helpers

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func subscription(startedAt: Date,
                              expiresOrRenewsAt: Date,
                              hasTrial: Bool) -> DuckDuckGoSubscription {
        DuckDuckGoSubscription(
            productId: "ddg.privacy.pro.monthly.renews.us.freetrial",
            name: "Privacy Pro Monthly",
            billingPeriod: .monthly,
            startedAt: startedAt,
            expiresOrRenewsAt: expiresOrRenewsAt,
            platform: .apple,
            status: .autoRenewable,
            activeOffers: hasTrial ? [DuckDuckGoSubscription.Offer(type: .trial)] : [],
            tier: nil,
            availableChanges: nil,
            pendingPlans: nil)
    }
}
