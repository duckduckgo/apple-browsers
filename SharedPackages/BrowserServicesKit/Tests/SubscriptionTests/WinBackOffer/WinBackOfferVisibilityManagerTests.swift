//
//  WinBackOfferVisibilityManagerTests.swift
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
import Combine
import Common
import SubscriptionTestingUtilities
@testable import Subscription

final class WinBackOfferVisibilityManagerTests: XCTestCase {

    var mockSubscriptionManager: SubscriptionManagerMockV2!
    var mockStore: MockWinbackOfferStore!
    var mockFeatureFlagProvider: MockWinBackOfferFeatureFlagProvider!
    var manager: WinBackOfferVisibilityManager!

    override func setUp() {
        super.setUp()
        mockSubscriptionManager = SubscriptionManagerMockV2()
        mockStore = MockWinbackOfferStore()
        mockFeatureFlagProvider = MockWinBackOfferFeatureFlagProvider()
        manager = WinBackOfferVisibilityManager(
            subscriptionManager: mockSubscriptionManager,
            winbackOfferStore: mockStore,
            winbackOfferFeatureFlagProvider: mockFeatureFlagProvider
        )
    }

    override func tearDown() {
        manager = nil
        mockFeatureFlagProvider = nil
        mockStore = nil
        mockSubscriptionManager = nil
        super.tearDown()
    }

    func testWhenFeatureDisabled_TheOfferIsNotAvailable() {
        // Given
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = false
        mockStore.churnDate = Date().addingTimeInterval(-4 * .day) // 4 days ago

        // When
        let isAvailable = manager.isOfferAvailable

        // Then
        XCTAssertFalse(isAvailable)
    }

    func testWhenUserHasActiveSubscription_TheOfferIsNotAvailable() async {
        // Given
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        mockStore.churnDate = Date().addingTimeInterval(-4 * .day)
        mockSubscriptionManager.resultSubscription = SubscriptionMockFactory.appleSubscription

        manager = WinBackOfferVisibilityManager(
            subscriptionManager: mockSubscriptionManager,
            winbackOfferStore: mockStore,
            winbackOfferFeatureFlagProvider: mockFeatureFlagProvider
        )

        // Wait for subscription check
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second

        // When
        let isAvailable = manager.isOfferAvailable

        // Then
        XCTAssertFalse(isAvailable)
    }

    func testWhenNoChurnDateIsStored_TheOfferIsNotAvailable() {
        // Given
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        mockStore.churnDate = nil

        // When
        let isAvailable = manager.isOfferAvailable

        // Then
        XCTAssertFalse(isAvailable)
    }

    func testTwoDaysAfterChurnDate_TheOfferIsNotAvailable() {
        // Given
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        mockStore.churnDate = Date().addingTimeInterval(-2 * .day) // Only 2 days ago, offer starts after 3 days

        // When
        let isAvailable = manager.isOfferAvailable

        // Then
        XCTAssertFalse(isAvailable)
    }

    func testFourDaysAfterChurnDate_TheOfferIsAvailable() {
        // Given
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        mockStore.churnDate = Date().addingTimeInterval(-4 * .day) // 4 days ago, within the 3-8 day window

        // When
        let isAvailable = manager.isOfferAvailable

        // Then
        XCTAssertTrue(isAvailable)
    }

    func testTenDaysAfterChurnDate_TheOfferIsNotAvailable() {
        // Given
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        mockStore.churnDate = Date().addingTimeInterval(-10 * .day) // 10 days ago, beyond the 5-day window

        // When
        let isAvailable = manager.isOfferAvailable

        // Then
        XCTAssertFalse(isAvailable)
    }

    func testWhenOfferAlreadyRedeemed_TheOfferIsNotAvailable() {
        // Given
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        mockStore.churnDate = Date().addingTimeInterval(-4 * .day)
        mockStore.offerRedeemed = true

        // When
        let isAvailable = manager.isOfferAvailable

        // Then
        XCTAssertFalse(isAvailable)
    }

    // MARK: - Urgency message

    func testWhenLastDayOfOffer_TheUrgencyMessageIsShown() {
        // Given
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        // Offer starts at day 3, lasts 5 days, so last day is at day 7 (3 + 5 - 1)
        mockStore.churnDate = Date().addingTimeInterval(-7 * .day)

        // When
        let shouldShow = manager.shouldShowUrgencyMessage

        // Then
        XCTAssertTrue(shouldShow)
    }

    func testWhenFirstDayOfOffer_TheUrgencyMessageIsNotShown() {
        // Given
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        mockStore.churnDate = Date().addingTimeInterval(-3 * .day) // First day of offer

        // When
        let shouldShow = manager.shouldShowUrgencyMessage

        // Then
        XCTAssertFalse(shouldShow)
    }

    func testWhenOfferNotAvailable_TheUrgencyMessageIsNotShown() {
        // Given
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        mockStore.churnDate = Date().addingTimeInterval(-10 * .day) // Beyond availability window

        // When
        let shouldShow = manager.shouldShowUrgencyMessage

        // Then
        XCTAssertFalse(shouldShow)
    }

    // MARK: - Launch message

    func testWhenOfferAvailable_AndModalNotShown_TheLaunchMessageIsShown() {
        // Given
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        mockStore.churnDate = Date().addingTimeInterval(-4 * .day)
        mockStore.firstDayModalShown = false

        // When
        let shouldShow = manager.shouldShowLaunchMessage

        // Then
        XCTAssertTrue(shouldShow)
    }

    func testWhenOfferAvailable_AndModalAlreadyShown_TheLaunchMessageIsNotShown() {
        // Given
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        mockStore.churnDate = Date().addingTimeInterval(-4 * .day)
        mockStore.firstDayModalShown = true

        // When
        let shouldShow = manager.shouldShowLaunchMessage

        // Then
        XCTAssertFalse(shouldShow)
    }

    func testWhenOfferNotAvailable_TheLaunchMessageIsNotShown() {
        // Given
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        mockStore.churnDate = nil
        mockStore.firstDayModalShown = false

        // When
        let shouldShow = manager.shouldShowLaunchMessage

        // Then
        XCTAssertFalse(shouldShow)
    }

    func testWhenSettingLaunchMessagePresentedToTrue_TheLaunchMessageIsShown() {
        // When
        manager.setLaunchMessagePresented(true)

        // Then
        XCTAssertTrue(mockStore.firstDayModalShown)
    }

    // MARK: - Offer redemption

    func testWhenSettingOfferRedeemedToTrue_ItStoresTheRedemption() {
        // When
        manager.setOfferRedeemed(true)

        // Then
        XCTAssertTrue(mockStore.offerRedeemed)
    }

    // MARK: - Subscription change observer

    func testWhenSubscriptionExpires_ItStoresChurnDate() async {
        // Given
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        let newSubscription = createMockSubscription(status: .expired)

        // When
        NotificationCenter.default.post(
            name: .subscriptionDidChange,
            object: nil,
            userInfo: [
                UserDefaultsCacheKey.subscription: newSubscription
            ]
        )

        // Give time for async notification handling
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertNotNil(mockStore.churnDate)
        XCTAssertFalse(mockStore.offerRedeemed)
        XCTAssertFalse(mockStore.firstDayModalShown)
    }

    func testWhenSubscriptionStillActive_ItDoesNotStoreChurnDate() async {
        // Given
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        let newSubscription = createMockSubscription(status: .gracePeriod)

        // When
        NotificationCenter.default.post(
            name: .subscriptionDidChange,
            object: nil,
            userInfo: [
                UserDefaultsCacheKey.subscription: newSubscription
            ]
        )

        // Give time for async notification handling
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertNil(mockStore.churnDate)
    }

    func testWhenChurningAfterCooldownPeriod_ItResetsOffer() async {
        // Given
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        let oldChurnDate = Date().addingTimeInterval(-300 * .day) // 300 days ago, beyond 270-day cooldown
        mockStore.churnDate = oldChurnDate
        mockStore.offerRedeemed = true
        mockStore.firstDayModalShown = true

        let newSubscription = createMockSubscription(status: .expired)

        // When
        NotificationCenter.default.post(
            name: .subscriptionDidChange,
            object: nil,
            userInfo: [
                UserDefaultsCacheKey.subscription: newSubscription
            ]
        )

        // Give time for async notification handling
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertNotNil(mockStore.churnDate)
        XCTAssertNotEqual(mockStore.churnDate, oldChurnDate)
        XCTAssertFalse(mockStore.offerRedeemed)
        XCTAssertFalse(mockStore.firstDayModalShown)
    }

    func testWhenChurningWithinCooldownPeriod_ItDoesNotResetOffer() async {
        // Given
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        let recentChurnDate = Date().addingTimeInterval(-100 * .day) // 100 days ago, within 270-day cooldown
        mockStore.churnDate = recentChurnDate
        mockStore.offerRedeemed = true

        let newSubscription = createMockSubscription(status: .expired)

        // When
        NotificationCenter.default.post(
            name: .subscriptionDidChange,
            object: nil,
            userInfo: [
                UserDefaultsCacheKey.subscription: newSubscription
            ]
        )

        // Give time for async notification handling
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertEqual(mockStore.churnDate, recentChurnDate)
        XCTAssertTrue(mockStore.offerRedeemed)
    }

    // MARK: - Helpers

    private func createMockSubscription(status: DuckDuckGoSubscription.Status) -> DuckDuckGoSubscription {
        DuckDuckGoSubscription(
            productId: "test-product",
            name: "Privacy Pro",
            billingPeriod: .monthly,
            startedAt: Date().addingTimeInterval(-30 * .day),
            expiresOrRenewsAt: Date().addingTimeInterval(30 * .day),
            platform: .apple,
            status: status,
            activeOffers: []
        )
    }
}

// MARK: - Mocks

class MockWinbackOfferStore: WinbackOfferStoring {
    var churnDate: Date?
    var offerRedeemed: Bool = false
    var firstDayModalShown: Bool = false
    var didDismissUrgencyMessage: Bool = false

    func storeChurnDate(_ churnDate: Date) {
        self.churnDate = churnDate
    }

    func getChurnDate() -> Date? {
        return churnDate
    }

    func setHasRedeemedOffer(_ didRedeem: Bool) {
        offerRedeemed = didRedeem
    }

    func hasRedeemedOffer() -> Bool {
        return offerRedeemed
    }
}

class MockWinBackOfferFeatureFlagProvider: WinBackOfferFeatureFlagProvider {
    var isWinBackOfferFeatureEnabled: Bool = true
}
