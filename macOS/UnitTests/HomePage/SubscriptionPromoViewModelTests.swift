//
//  SubscriptionPromoViewModelTests.swift
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
import PrivacyConfig
import SubscriptionTestingUtilities
@testable import FeatureFlags
@testable import Subscription
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class SubscriptionPromoViewModelTests: XCTestCase {

    var sut: SubscriptionPromoViewModel!
    var subscriptionManager: SubscriptionManagerMock!
    var persistor: MockSubscriptionPromoPersisting!
    var featureFlagger: MockFeatureFlagger!

    override func setUp() {
        super.setUp()
        subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.resultSubscription = .failure(SubscriptionManagerError.noTokenAvailable)
        persistor = MockSubscriptionPromoPersisting()
        featureFlagger = MockFeatureFlagger()
        featureFlagger.enableFeatures([.subscriptionPromoFireWindow])
    }

    override func tearDown() {
        sut = nil
        subscriptionManager = nil
        persistor = nil
        featureFlagger = nil
        super.tearDown()
    }

    // MARK: - Basic Display Conditions

    func testWhenAllConditionsMet_ThenShowsPromo() {
        persistor.fireTabVisitCount = 3
        sut = makeSUT()

        sut.updateForTab(.notEvaluated)

        XCTAssertTrue(sut.shouldShowPromo)
    }

    func testWhenNonUSLocale_ThenDoesNotShowPromo() {
        persistor.fireTabVisitCount = 3
        sut = makeSUT(locale: Locale(identifier: "en_GB"))

        sut.updateForTab(.notEvaluated)

        XCTAssertFalse(sut.shouldShowPromo)
    }

    func testWhenUserIsSubscriber_ThenDoesNotShowPromo() {
        persistor.fireTabVisitCount = 3
        subscriptionManager.resultSubscription = .success(makeSubscription())
        sut = makeSUT()

        sut.updateForTab(.notEvaluated)

        XCTAssertFalse(sut.shouldShowPromo)
    }

    func testWhenVisitCountBelowThreshold_ThenDoesNotShowPromo() {
        persistor.fireTabVisitCount = 2
        sut = makeSUT()

        sut.updateForTab(.notEvaluated)

        XCTAssertFalse(sut.shouldShowPromo)
    }

    func testWhenCtaActionedWithinCooldown_ThenDoesNotShowPromo() {
        persistor.fireTabVisitCount = 3
        persistor.promoDismissedDate = Date()
        sut = makeSUT()

        sut.updateForTab(.notEvaluated)

        XCTAssertFalse(sut.shouldShowPromo)
    }

    func testWhenCtaActionedAfterCooldown_ThenShowsPromo() {
        persistor.fireTabVisitCount = 3
        persistor.promoDismissedDate = Calendar.current.date(byAdding: .day, value: -29, to: Date())
        sut = makeSUT()

        sut.updateForTab(.notEvaluated)

        XCTAssertTrue(sut.shouldShowPromo)
    }

    // MARK: - Dismiss Cooldown

    func testWhenDismissedWithinCooldown_ThenDoesNotShowPromo() {
        persistor.fireTabVisitCount = 3
        persistor.promoDismissedDate = Date()
        sut = makeSUT()

        sut.updateForTab(.notEvaluated)

        XCTAssertFalse(sut.shouldShowPromo)
    }

    func testWhenDismissedAfterCooldown_ThenShowsPromo() {
        persistor.fireTabVisitCount = 3
        persistor.promoDismissedDate = Calendar.current.date(byAdding: .day, value: -29, to: Date())
        sut = makeSUT()

        sut.updateForTab(.notEvaluated)

        XCTAssertTrue(sut.shouldShowPromo)
    }

    // MARK: - Display Limit (4 times per 28-day rolling window)

    func testWhenDisplayCountBelowLimit_ThenShowsPromo() {
        persistor.fireTabVisitCount = 3
        persistor.promoDisplayCount = 3
        persistor.promoDisplayWindowStart = Date()
        sut = makeSUT()

        sut.updateForTab(.notEvaluated)

        XCTAssertTrue(sut.shouldShowPromo)
    }

    func testWhenDisplayCountReachesLimit_ThenDoesNotShowPromo() {
        persistor.fireTabVisitCount = 3
        persistor.promoDisplayCount = 4
        persistor.promoDisplayWindowStart = Date()
        sut = makeSUT()

        sut.updateForTab(.notEvaluated)

        XCTAssertFalse(sut.shouldShowPromo)
    }

    func testWhenDisplayCountExceedsLimitButWindowExpired_ThenShowsPromo() {
        persistor.fireTabVisitCount = 3
        persistor.promoDisplayCount = 4
        persistor.promoDisplayWindowStart = Calendar.current.date(byAdding: .day, value: -29, to: Date())
        sut = makeSUT()

        sut.updateForTab(.notEvaluated)

        XCTAssertTrue(sut.shouldShowPromo)
    }

    func testWhenDisplayWindowExpires_ThenResetsCountAndStartsNewWindow() {
        persistor.fireTabVisitCount = 3
        persistor.promoDisplayCount = 4
        persistor.promoDisplayWindowStart = Calendar.current.date(byAdding: .day, value: -29, to: Date())
        sut = makeSUT()

        sut.updateForTab(.notEvaluated)

        XCTAssertEqual(persistor.promoDisplayCount, 1)
        XCTAssertNotNil(persistor.promoDisplayWindowStart)
    }

    func testEachCallToUpdatePromoVisibilityIncrementsDisplayCount() {
        persistor.fireTabVisitCount = 3
        sut = makeSUT()

        sut.updateForTab(.notEvaluated)
        XCTAssertEqual(persistor.promoDisplayCount, 1)

        sut.updateForTab(.notEvaluated)
        XCTAssertEqual(persistor.promoDisplayCount, 2)

        sut.updateForTab(.notEvaluated)
        XCTAssertEqual(persistor.promoDisplayCount, 3)

        sut.updateForTab(.notEvaluated)
        XCTAssertEqual(persistor.promoDisplayCount, 4)

        sut.updateForTab(.notEvaluated)
        XCTAssertEqual(persistor.promoDisplayCount, 4)
        XCTAssertFalse(sut.shouldShowPromo)
    }

    // MARK: - Conflicting End Cases

    func testWhenDismissedOnFourthDisplay_ThenDismissCooldownAndDisplayLimitBothBlock() {
        persistor.fireTabVisitCount = 3
        sut = makeSUT()

        // Show promo 3 times
        sut.updateForTab(.notEvaluated)
        sut.updateForTab(.notEvaluated)
        sut.updateForTab(.notEvaluated)
        XCTAssertEqual(persistor.promoDisplayCount, 3)

        // 4th display — user dismisses
        sut.updateForTab(.notEvaluated)
        XCTAssertEqual(persistor.promoDisplayCount, 4)
        XCTAssertTrue(sut.shouldShowPromo)
        sut.dismiss()
        XCTAssertFalse(sut.shouldShowPromo)

        // Dismiss cooldown still active (same day) — blocked by cooldown
        sut.updateForTab(.notEvaluated)
        XCTAssertFalse(sut.shouldShowPromo)
    }

    func testWhenDismissedOnFourthDisplay_AfterDismissCooldownExpires_DisplayLimitStillBlocks() {
        persistor.fireTabVisitCount = 3
        let windowStart = Calendar.current.date(byAdding: .day, value: -20, to: Date())!
        persistor.promoDisplayWindowStart = windowStart
        persistor.promoDisplayCount = 3
        sut = makeSUT()

        // 4th display — user dismisses
        sut.updateForTab(.notEvaluated)
        XCTAssertEqual(persistor.promoDisplayCount, 4)
        sut.dismiss()

        // Simulate dismiss cooldown expiring (29 days ago) but display window still active (started 20 days ago)
        persistor.promoDismissedDate = Calendar.current.date(byAdding: .day, value: -29, to: Date())

        sut.updateForTab(.notEvaluated)
        XCTAssertFalse(sut.shouldShowPromo, "Display limit should still block even after dismiss cooldown expires")
        XCTAssertEqual(persistor.promoDisplayCount, 4)
    }

    func testWhenDismissedOnFourthDisplay_AfterBothCooldownAndWindowExpire_ThenShowsPromo() {
        persistor.fireTabVisitCount = 3
        persistor.promoDisplayWindowStart = Calendar.current.date(byAdding: .day, value: -29, to: Date())
        persistor.promoDisplayCount = 4
        persistor.promoDismissedDate = Calendar.current.date(byAdding: .day, value: -29, to: Date())
        sut = makeSUT()

        sut.updateForTab(.notEvaluated)

        XCTAssertTrue(sut.shouldShowPromo, "Both cooldown and display window expired — promo should show again")
        XCTAssertEqual(persistor.promoDisplayCount, 1, "Display count should reset for new window")
    }

    func testWhenDismissedOnThirdDisplay_AfterCooldownExpires_ThenStartsNewDisplayWindow() {
        persistor.fireTabVisitCount = 3
        sut = makeSUT()

        // Show promo 3 times, user dismisses on 3rd
        sut.updateForTab(.notEvaluated)
        sut.updateForTab(.notEvaluated)
        sut.updateForTab(.notEvaluated)
        XCTAssertEqual(persistor.promoDisplayCount, 3)
        sut.dismiss()

        // Simulate both dismiss cooldown and display window expiring
        persistor.promoDismissedDate = Calendar.current.date(byAdding: .day, value: -29, to: Date())
        persistor.promoDisplayWindowStart = Calendar.current.date(byAdding: .day, value: -29, to: Date())

        sut.updateForTab(.notEvaluated)

        XCTAssertTrue(sut.shouldShowPromo)
        XCTAssertEqual(persistor.promoDisplayCount, 1, "Should be first display in a new 28-day window")
    }

    // MARK: - Free Trial Eligibility

    func testWhenEligibleForFreeTrial_ThenSetsFlag() {
        persistor.fireTabVisitCount = 3
        subscriptionManager.isEligibleForFreeTrialResult = true
        sut = makeSUT()

        sut.updateForTab(.notEvaluated)

        XCTAssertTrue(sut.isEligibleForFreeTrial)
    }

    func testWhenNotEligibleForFreeTrial_ThenFlagIsFalse() {
        persistor.fireTabVisitCount = 3
        subscriptionManager.isEligibleForFreeTrialResult = false
        sut = makeSUT()

        sut.updateForTab(.notEvaluated)

        XCTAssertFalse(sut.isEligibleForFreeTrial)
    }

    // MARK: - Dismiss & Action

    func testDismissSetsDateAndHidesPromo() {
        persistor.fireTabVisitCount = 3
        sut = makeSUT()
        sut.updateForTab(.notEvaluated)
        XCTAssertTrue(sut.shouldShowPromo)

        sut.dismiss()

        XCTAssertFalse(sut.shouldShowPromo)
        XCTAssertNotNil(persistor.promoDismissedDate)
    }

    func testOnPromoButtonTappedSetsDismissedDateButKeepsPromoVisible() {
        persistor.fireTabVisitCount = 3
        sut = makeSUT()
        sut.updateForTab(.notEvaluated)
        XCTAssertTrue(sut.shouldShowPromo)

        sut.onPromoButtonTapped()

        XCTAssertTrue(sut.shouldShowPromo, "Promo stays visible on current tab after CTA tap")
        XCTAssertNotNil(persistor.promoDismissedDate)
    }

    func testAfterCtaTapped_NewTabDoesNotShowPromo() {
        persistor.fireTabVisitCount = 3
        sut = makeSUT()
        sut.updateForTab(.notEvaluated)
        sut.onPromoButtonTapped()

        sut.updateForTab(.notEvaluated)

        XCTAssertFalse(sut.shouldShowPromo, "Promo should not show on new tabs after CTA tap")
    }

    // MARK: - Helpers

    // MARK: - Feature Flag

    func testWhenFeatureFlagDisabled_ThenDoesNotShowPromo() {
        persistor.fireTabVisitCount = 3
        featureFlagger.enabledFeatureFlags = []
        sut = makeSUT()

        sut.updateForTab(.notEvaluated)

        XCTAssertFalse(sut.shouldShowPromo)
    }

    private func makeSUT(locale: Locale = Locale(identifier: "en_US")) -> SubscriptionPromoViewModel {
        SubscriptionPromoViewModel(
            subscriptionManager: subscriptionManager,
            featureFlagger: featureFlagger,
            persistor: persistor,
            locale: locale
        )
    }

    private func makeSubscription() -> DuckDuckGoSubscription {
        DuckDuckGoSubscription(
            productId: "test",
            name: "test",
            billingPeriod: .yearly,
            startedAt: Date(),
            expiresOrRenewsAt: Calendar.current.date(byAdding: .day, value: 30, to: Date())!,
            platform: .stripe,
            status: .autoRenewable,
            activeOffers: [],
            tier: nil,
            availableChanges: nil,
            pendingPlans: nil
        )
    }
}

// MARK: - Mock

final class MockSubscriptionPromoPersisting: SubscriptionPromoPersisting {
    var fireTabVisitCount: Int = 0
    var promoDismissedDate: Date?
    var promoDisplayCount: Int = 0
    var promoDisplayWindowStart: Date?
}
