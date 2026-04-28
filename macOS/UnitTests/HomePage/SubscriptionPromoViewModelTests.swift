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

    func testWhenNonEnglishUSLocale_ThenDoesNotShowPromo() {
        persistor.fireTabVisitCount = 3
        sut = makeSUT(locale: Locale(identifier: "es_US"))

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

    // MARK: - Dismiss Cooldown (fallback when PromoQueue is off)

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

    func testWhenPromoQueueOn_ThenCooldownStillEnforced() {
        let delegate = FireWindowSubscriptionPromoDelegate()
        persistor.fireTabVisitCount = 3
        persistor.promoDismissedDate = Date()
        sut = makeSUT(promoDelegate: delegate)

        sut.updateForTab(.notEvaluated)

        XCTAssertFalse(sut.shouldShowPromo, "ViewModel always enforces cooldown since PromoQueue cooldown does not gate external promos")
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

    // MARK: - Display Limit After Dismiss

    func testWhenDismissedOnFourthDisplay_DisplayLimitBlocks() {
        persistor.fireTabVisitCount = 3
        sut = makeSUT()

        sut.updateForTab(.notEvaluated)
        sut.updateForTab(.notEvaluated)
        sut.updateForTab(.notEvaluated)
        sut.updateForTab(.notEvaluated)
        XCTAssertEqual(persistor.promoDisplayCount, 4)
        sut.dismiss()

        sut.updateForTab(.notEvaluated)
        XCTAssertFalse(sut.shouldShowPromo)
        XCTAssertEqual(persistor.promoDisplayCount, 4)
    }

    func testWhenDisplayWindowExpiredAfterDismiss_ThenShowsPromo() {
        persistor.fireTabVisitCount = 3
        persistor.promoDisplayWindowStart = Calendar.current.date(byAdding: .day, value: -29, to: Date())
        persistor.promoDisplayCount = 4
        sut = makeSUT()

        sut.updateForTab(.notEvaluated)

        XCTAssertTrue(sut.shouldShowPromo)
        XCTAssertEqual(persistor.promoDisplayCount, 1, "Display count should reset for new window")
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

    func testDismissHidesPromoAndSetsDismissedDate() {
        persistor.fireTabVisitCount = 3
        sut = makeSUT()
        sut.updateForTab(.notEvaluated)
        XCTAssertTrue(sut.shouldShowPromo)

        sut.dismiss()

        XCTAssertFalse(sut.shouldShowPromo)
        XCTAssertNotNil(persistor.promoDismissedDate)
    }

    func testOnPromoButtonTappedKeepsPromoVisibleAndSetsDismissedDate() {
        persistor.fireTabVisitCount = 3
        sut = makeSUT()
        sut.updateForTab(.notEvaluated)
        XCTAssertTrue(sut.shouldShowPromo)

        sut.onPromoButtonTapped()

        XCTAssertTrue(sut.shouldShowPromo, "Promo stays visible on current tab after CTA tap")
        XCTAssertNotNil(persistor.promoDismissedDate)
    }

    // MARK: - Promo Delegate Visibility Reporting

    func testWhenPromoShows_ThenDelegateVisibilityUpdatedToTrue() {
        let delegate = FireWindowSubscriptionPromoDelegate()
        persistor.fireTabVisitCount = 3
        sut = makeSUT(promoDelegate: delegate)

        sut.updateForTab(.notEvaluated)

        XCTAssertTrue(sut.shouldShowPromo)
        XCTAssertTrue(delegate.isVisible)
    }

    func testWhenPromoDismissed_ThenDelegateVisibilityUpdatedToFalse() {
        let delegate = FireWindowSubscriptionPromoDelegate()
        persistor.fireTabVisitCount = 3
        sut = makeSUT(promoDelegate: delegate)

        sut.updateForTab(.notEvaluated)
        XCTAssertTrue(delegate.isVisible)

        sut.dismiss()

        XCTAssertFalse(sut.shouldShowPromo)
        XCTAssertFalse(delegate.isVisible)
    }

    func testWhenPromoConditionsNotMet_ThenDelegateNotUpdated() {
        let delegate = FireWindowSubscriptionPromoDelegate()
        persistor.fireTabVisitCount = 0
        sut = makeSUT(promoDelegate: delegate)

        sut.updateForTab(.notEvaluated)

        XCTAssertFalse(sut.shouldShowPromo)
        XCTAssertFalse(delegate.isVisible)
    }

    // MARK: - Feature Flag

    func testWhenFeatureFlagDisabled_ThenDoesNotShowPromo() {
        persistor.fireTabVisitCount = 3
        featureFlagger.enabledFeatureFlags = []
        sut = makeSUT()

        sut.updateForTab(.notEvaluated)

        XCTAssertFalse(sut.shouldShowPromo)
    }

    // MARK: - Date Provider

    func testWhenDateProviderOverridesPastCooldown_ThenShowsPromo() {
        persistor.fireTabVisitCount = 3
        persistor.promoDismissedDate = Date()
        let futureDate = Calendar.current.date(byAdding: .day, value: 29, to: Date())!
        sut = makeSUT(dateProvider: { futureDate })

        sut.updateForTab(.notEvaluated)

        XCTAssertTrue(sut.shouldShowPromo)
    }

    func testWhenDateProviderWithinCooldown_ThenDoesNotShowPromo() {
        persistor.fireTabVisitCount = 3
        persistor.promoDismissedDate = Date()
        let nearFutureDate = Calendar.current.date(byAdding: .day, value: 10, to: Date())!
        sut = makeSUT(dateProvider: { nearFutureDate })

        sut.updateForTab(.notEvaluated)

        XCTAssertFalse(sut.shouldShowPromo)
    }

    func testWhenDateProviderOverridesExpiredDisplayWindow_ThenResetsCount() {
        persistor.fireTabVisitCount = 3
        persistor.promoDisplayCount = 4
        persistor.promoDisplayWindowStart = Date()
        let futureDate = Calendar.current.date(byAdding: .day, value: 29, to: Date())!
        sut = makeSUT(dateProvider: { futureDate })

        sut.updateForTab(.notEvaluated)

        XCTAssertTrue(sut.shouldShowPromo)
        XCTAssertEqual(persistor.promoDisplayCount, 1)
    }

    // MARK: - Purchase Eligibility

    func testWhenAppStoreProductsNotAvailable_ThenDoesNotShowPromo() {
        persistor.fireTabVisitCount = 3
        subscriptionManager.hasAppStoreProductsAvailable = false
        sut = makeSUT(purchasePlatform: .appStore)

        sut.updateForTab(.notEvaluated)

        XCTAssertFalse(sut.shouldShowPromo)
    }

    func testWhenAppStoreProductsAvailable_ThenShowsPromoAfterPublisher() {
        persistor.fireTabVisitCount = 3
        subscriptionManager.hasAppStoreProductsAvailable = false
        sut = makeSUT(purchasePlatform: .appStore)

        sut.updateForTab(.notEvaluated)
        XCTAssertFalse(sut.shouldShowPromo, "Promo waits for purchase eligibility")

        subscriptionManager.hasAppStoreProductsAvailable = true

        let expectation = expectation(description: "Publisher delivers value")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)

        sut.updateForTab(.notEvaluated)
        XCTAssertTrue(sut.shouldShowPromo)
    }

    func testWhenPlatformIsStripe_ThenPurchaseAlwaysEligible() {
        persistor.fireTabVisitCount = 3
        subscriptionManager.hasAppStoreProductsAvailable = false
        sut = makeSUT(purchasePlatform: .stripe)

        sut.updateForTab(.notEvaluated)

        XCTAssertTrue(sut.shouldShowPromo)
    }

    private func makeSUT(locale: Locale = Locale(identifier: "en_US"),
                         purchasePlatform: SubscriptionEnvironment.PurchasePlatform = .stripe,
                         dateProvider: @escaping () -> Date = Date.init,
                         promoDelegate: FireWindowSubscriptionPromoDelegate? = nil) -> SubscriptionPromoViewModel {
        subscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: purchasePlatform)
        return SubscriptionPromoViewModel(
            subscriptionManager: subscriptionManager,
            featureFlagger: featureFlagger,
            persistor: persistor,
            locale: locale,
            dateProvider: dateProvider,
            promoDelegate: promoDelegate
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
