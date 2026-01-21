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

    var mockSubscriptionManager: SubscriptionManagerMock!
    var mockStore: MockWinbackOfferStore!
    var mockFeatureFlagProvider: MockWinBackOfferFeatureFlagProvider!
    var manager: WinBackOfferVisibilityManager!

    override func setUp() {
        super.setUp()
        mockSubscriptionManager = SubscriptionManagerMock()
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
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.appleSubscription)

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

    func testWhenOfferNotYetPresented_TheOfferIsNotAvailable() {
        // Given
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        mockStore.churnDate = Date().addingTimeInterval(-4 * .day) // 4 days ago, enough time has passed
        mockStore.offerPresentationDate = nil // But modal has not been shown yet

        // When
        let isAvailable = manager.isOfferAvailable

        // Then
        XCTAssertFalse(isAvailable, "Offer should not be available until launch message is presented")
    }

    func testFourDaysAfterChurnDate_TheOfferIsAvailable() {
        // Given
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        mockStore.churnDate = Date().addingTimeInterval(-4 * .day) // 4 days ago, within the 3-8 day window
        mockStore.offerPresentationDate = Date().addingTimeInterval(-1 * .day) // Presented 1 day ago

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
        mockStore.churnDate = Date().addingTimeInterval(-7 * .day) // Churned 7 days ago
        mockStore.offerPresentationDate = Date().addingTimeInterval(-3 * .day) // Presented 3 days ago (urgency window)

        // When
        let shouldShow = manager.shouldShowUrgencyMessage

        // Then
        XCTAssertTrue(shouldShow)
    }

    func testUrgencyMessageShowsDuringFinalCalendarDay() {
        // Given
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        let now = Date()
        let presentationDate = now.addingTimeInterval(.days(-3) + .seconds(25))
        mockStore.offerPresentationDate = presentationDate
        manager = WinBackOfferVisibilityManager(
            subscriptionManager: mockSubscriptionManager,
            winbackOfferStore: mockStore,
            winbackOfferFeatureFlagProvider: mockFeatureFlagProvider,
            dateProvider: { now }
        )

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
        mockStore.offerPresentationDate = nil

        // When
        let shouldShow = manager.shouldShowLaunchMessage

        // Then
        XCTAssertTrue(shouldShow)
    }

    func testWhenOfferAvailable_AndModalAlreadyShown_TheLaunchMessageIsNotShown() {
        // Given
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        mockStore.churnDate = Date().addingTimeInterval(-4 * .day)
        mockStore.offerPresentationDate = Date().addingTimeInterval(-1 * .day) // Already presented

        // When
        let shouldShow = manager.shouldShowLaunchMessage

        // Then
        XCTAssertFalse(shouldShow)
    }

    func testWhenOfferNotAvailable_TheLaunchMessageIsNotShown() {
        // Given
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        mockStore.churnDate = nil

        // When
        let shouldShow = manager.shouldShowLaunchMessage

        // Then
        XCTAssertFalse(shouldShow)
    }

    func testWhenSettingLaunchMessagePresentedToTrue_TheLaunchMessageIsShown() {
        // When
        manager.setLaunchMessagePresented(true)

        // Then
        XCTAssertNotNil(mockStore.offerPresentationDate)
    }

    // MARK: - Offer start window

    func testWhenUserChurnedMoreThan3DaysAgo_ItStartsTheOfferWindow() async {
        // Given
        let expiryDate = Date().addingTimeInterval(-4 * .day)
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        let newSubscription = createMockSubscription(status: .expired, expiryDate: expiryDate)

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
        XCTAssertTrue(manager.shouldShowLaunchMessage)
    }

    func testWhenUserChurnedLessThan3DaysAgo_ItDoesNotStartOfferWindow() async {
        // Given
        let expiryDate = Date().addingTimeInterval(-2 * .day)
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        let newSubscription = createMockSubscription(status: .expired, expiryDate: expiryDate)

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
        XCTAssertFalse(manager.shouldShowLaunchMessage)
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
        let expiryDate = Date().addingTimeInterval(-100 * .day)
        mockFeatureFlagProvider.isWinBackOfferFeatureEnabled = true
        let newSubscription = createMockSubscription(status: .expired, expiryDate: expiryDate)

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
        XCTAssertEqual(mockStore.churnDate, expiryDate)
        XCTAssertFalse(mockStore.offerRedeemed)
        XCTAssertNil(mockStore.offerPresentationDate)
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
        mockStore.offerPresentationDate = Date().addingTimeInterval(-295 * .day)

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
        XCTAssertNil(mockStore.offerPresentationDate)
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
        guard let updatedChurnDate = mockStore.churnDate else {
            XCTFail("Churn date should be stored when churning within cooldown period")
            return
        }
        XCTAssertGreaterThan(updatedChurnDate, recentChurnDate)
        XCTAssertTrue(mockStore.offerRedeemed)
    }

    // MARK: - Helpers

    private func createMockSubscription(status: DuckDuckGoSubscription.Status, expiryDate: Date = Date().addingTimeInterval(30 * .day)) -> DuckDuckGoSubscription {
        DuckDuckGoSubscription(
            productId: "test-product",
            name: "Privacy Pro",
            billingPeriod: .monthly,
            startedAt: Date().addingTimeInterval(-30 * .day),
            expiresOrRenewsAt: expiryDate,
            platform: .apple,
            status: status,
            activeOffers: [],
            tier: nil,
            availableChanges: nil,
            pendingPlans: nil
        )
    }
}

// MARK: - Mocks

class MockWinbackOfferStore: WinbackOfferStoring {
    var churnDate: Date?
    var offerRedeemed: Bool = false
    var firstDayModalShown: Bool = false
    var didDismissUrgencyMessage: Bool = false
    var offerPresentationDate: Date?

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

    func storeOfferPresentationDate(_ date: Date?) {
        offerPresentationDate = date
    }

    func getOfferPresentationDate() -> Date? {
        return offerPresentationDate
    }

    func clearChurnDate() { }
}

class MockWinBackOfferFeatureFlagProvider: WinBackOfferFeatureFlagProvider {
    var isWinBackOfferFeatureEnabled: Bool = true
}
