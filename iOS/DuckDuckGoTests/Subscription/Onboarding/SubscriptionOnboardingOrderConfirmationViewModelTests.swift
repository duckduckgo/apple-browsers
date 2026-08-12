//
//  SubscriptionOnboardingOrderConfirmationViewModelTests.swift
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
@testable import Subscription

@MainActor
final class SubscriptionOnboardingOrderConfirmationViewModelTests: XCTestCase {

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

    // MARK: - Helpers

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func subscription(startedAt: Date, expiresOrRenewsAt: Date, hasTrial: Bool) -> DuckDuckGoSubscription {
        DuckDuckGoSubscription(
            productId: "ddg.privacy.pro.monthly.renews.us.freetrial",
            name: "Privacy Pro Monthly",
            billingPeriod: .monthly,
            startedAt: startedAt,
            expiresOrRenewsAt: expiresOrRenewsAt,
            platform: .apple,
            status: .autoRenewable,
            activeOffers: hasTrial ? [DuckDuckGoSubscription.Offer(type: .trial)] : [],
            tier: .plus,
            availableChanges: nil,
            pendingPlans: nil)
    }

    private func makeViewModel(subscription: DuckDuckGoSubscription?,
                               now: Date) -> SubscriptionOnboardingOrderConfirmationViewModel {
        SubscriptionOnboardingOrderConfirmationViewModel(
            subscriptionProvider: StubSubscriptionProvider(subscription: subscription),
            now: now,
            calendar: calendar)
    }

    // MARK: - Free trial

    func testWhenSubscriptionHasActiveTrialThenFreeTrialCardIsShown() async {
        let start = date(2026, 5, 7)
        let sut = makeViewModel(subscription: subscription(startedAt: start,
                                                           expiresOrRenewsAt: date(2026, 5, 14),
                                                           hasTrial: true),
                                now: start)

        await sut.load()

        XCTAssertNotNil(sut.freeTrialCard)
    }

    func testWhenSubscriptionHasActiveTrialThenTheCardUsesTheSubscriptionsTrialLength() async {
        let start = date(2026, 5, 7)
        let sut = makeViewModel(subscription: subscription(startedAt: start,
                                                           expiresOrRenewsAt: date(2026, 5, 17),
                                                           hasTrial: true),
                                now: start)

        await sut.load()

        // The subscription's own 10 days, not the card model's 7-day default.
        XCTAssertEqual(sut.freeTrialCard?.trialLength, 10)
        XCTAssertEqual(sut.freeTrialCard?.dayLabels.count, 10)
    }

    func testWhenTodayIsPartwayThroughTheTrialThenTheCardMarksThatDay() async {
        let start = date(2026, 5, 7)
        let sut = makeViewModel(subscription: subscription(startedAt: start,
                                                           expiresOrRenewsAt: date(2026, 5, 14),
                                                           hasTrial: true),
                                now: date(2026, 5, 10))

        await sut.load()

        XCTAssertEqual(sut.freeTrialCard?.currentTrialDay, 4)
    }

    // MARK: - Paid

    func testWhenSubscriptionHasNoActiveTrialThenNoCardIsShown() async {
        let start = date(2026, 5, 7)
        let sut = makeViewModel(subscription: subscription(startedAt: start,
                                                           expiresOrRenewsAt: date(2026, 6, 7),
                                                           hasTrial: false),
                                now: start)

        await sut.load()

        XCTAssertNil(sut.freeTrialCard)
    }

    func testWhenSubscriptionIsUnavailableThenScreenFallsBackToThePaidVariant() async {
        let sut = makeViewModel(subscription: nil, now: date(2026, 5, 7))

        await sut.load()

        XCTAssertNil(sut.freeTrialCard)
    }

    // MARK: - Trials the card cannot draw

    // Spans that aren't trials at all (zero-length, reversed dates) are rejected by
    // `DuckDuckGoSubscription.trialLengthInDays(calendar:)` and covered by its own tests.

    /// One day past the widest strip the card can draw, guarding the limit rather than an arbitrarily long span.
    func testWhenTheTrialIsLongerThanTheStripCanDrawThenNoCardIsShown() async {
        let start = date(2026, 5, 7)
        let sut = makeViewModel(subscription: subscription(startedAt: start,
                                                           expiresOrRenewsAt: date(2026, 5, 18),
                                                           hasTrial: true),
                                now: start)

        await sut.load()

        XCTAssertNil(sut.freeTrialCard)
    }

    // MARK: - Loading

    func testWhenStillLoadingThenNoTrialCardIsShown() {
        let sut = makeViewModel(subscription: nil, now: date(2026, 5, 7))

        XCTAssertNil(sut.freeTrialCard)
    }

    func testWhenLoadIsCalledAgainThenTheResolvedStateIsKept() async {
        let start = date(2026, 5, 7)
        let provider = StubSubscriptionProvider(subscription: subscription(startedAt: start,
                                                                           expiresOrRenewsAt: date(2026, 5, 14),
                                                                           hasTrial: true))
        let sut = SubscriptionOnboardingOrderConfirmationViewModel(subscriptionProvider: provider,
                                                                   now: start,
                                                                   calendar: calendar)

        await sut.load()
        await sut.load()

        XCTAssertNotNil(sut.freeTrialCard)
        XCTAssertEqual(provider.fetchCount, 1)
    }
}

// MARK: - Test doubles

@MainActor
private final class StubSubscriptionProvider: SubscriptionOnboardingSubscriptionProviding {
    private let subscription: DuckDuckGoSubscription?
    private(set) var fetchCount = 0

    init(subscription: DuckDuckGoSubscription?) {
        self.subscription = subscription
    }

    func fetchSubscription() async -> DuckDuckGoSubscription? {
        fetchCount += 1
        return subscription
    }
}
