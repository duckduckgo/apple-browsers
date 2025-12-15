//
//  SubscriptionSettingsViewModelV2Tests.swift
//  DuckDuckGo
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
@testable import DuckDuckGo
@testable import Subscription
import SubscriptionTestingUtilities
import Networking
import NetworkingTestingUtils
import Persistence

final class SubscriptionSettingsViewModelV2Tests: XCTestCase {

    var sut: SubscriptionSettingsViewModelV2!
    var mockSubscriptionManager: SubscriptionManagerMockV2!
    var cancellables = Set<AnyCancellable>()
    var isProTierPurchaseEnabled: Bool = false
    var mockFeatureFlagger: MockFeatureFlagger!

    override func setUp() {
        super.setUp()
        mockSubscriptionManager = SubscriptionManagerMockV2()
        mockSubscriptionManager.resultURL = URL(string: "https://example.com")!
        mockFeatureFlagger = MockFeatureFlagger()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        sut = nil
        mockSubscriptionManager = nil
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Tier Badge Display Tests

    func testTierBadgeToDisplay_WhenNoSubscriptionInfo_ReturnsNil() {
        // Given - No subscription set
        mockSubscriptionManager.resultSubscription = nil
        sut = makeSUT()

        // Then
        XCTAssertNil(sut.tierBadgeToDisplay)
    }

    func testTierBadgeToDisplay_WhenSubscriptionHasNoTier_ReturnsNil() async {
        // Given - Subscription without tier
        mockSubscriptionManager.resultSubscription = SubscriptionMockFactory.subscription(status: .autoRenewable, tier: nil)
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()

        // When - trigger fetch
        await waitForSubscriptionUpdate()

        // Then
        XCTAssertNil(sut.tierBadgeToDisplay)
    }

    func testTierBadgeToDisplay_WhenProTier_AlwaysReturnsPro() async {
        // Given - Pro tier with feature flag OFF
        mockSubscriptionManager.resultSubscription = SubscriptionMockFactory.subscription(status: .autoRenewable, tier: .pro)
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()

        // When - trigger fetch
        await waitForSubscriptionUpdate()

        // Then - Pro tier always shows regardless of feature flag
        XCTAssertEqual(sut.tierBadgeToDisplay, .pro)
    }

    func testTierBadgeToDisplay_WhenPlusTierAndFeatureFlagEnabled_ReturnsPlus() async {
        // Given - Plus tier with feature flag ON
        mockFeatureFlagger.enabledFeatureFlags = [.allowProTierPurchase]
        mockSubscriptionManager.resultSubscription = SubscriptionMockFactory.subscription(status: .autoRenewable, tier: .plus)
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()

        // When - trigger fetch
        await waitForSubscriptionUpdate()

        // Then
        XCTAssertEqual(sut.tierBadgeToDisplay, .plus)
    }

    func testTierBadgeToDisplay_WhenPlusTierAndFeatureFlagDisabled_ReturnsNil() async {
        // Given - Plus tier with feature flag OFF
        isProTierPurchaseEnabled = false
        mockSubscriptionManager.resultSubscription = SubscriptionMockFactory.subscription(status: .autoRenewable, tier: .plus)
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()

        // When - trigger fetch
        await waitForSubscriptionUpdate()

        // Then - Plus tier hidden when feature flag is off
        XCTAssertNil(sut.tierBadgeToDisplay)
    }

    // MARK: - View All Plans Visibility Tests

    func testShouldShowViewAllPlans_WhenNoSubscription_ReturnsFalse() {
        // Given - No subscription
        mockSubscriptionManager.resultSubscription = nil
        sut = makeSUT()

        // Then
        XCTAssertFalse(sut.shouldShowViewAllPlans)
    }

    func testShouldShowViewAllPlans_WhenSubscriptionInactive_ReturnsFalse() async {
        // Given - Inactive subscription
        mockSubscriptionManager.resultSubscription = SubscriptionMockFactory.subscription(status: .expired, tier: .plus)
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()

        // When
        await waitForSubscriptionUpdate()

        // Then
        XCTAssertFalse(sut.shouldShowViewAllPlans)
    }

    func testShouldShowViewAllPlans_WhenActiveSubscriptionAndFeatureFlagEnabled_ReturnsTrue() async {
        // Given - Active subscription with feature flag ON
        mockFeatureFlagger.enabledFeatureFlags = [.allowProTierPurchase]
        mockSubscriptionManager.resultSubscription = SubscriptionMockFactory.subscription(status: .autoRenewable, tier: .plus)
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()

        // When
        await waitForSubscriptionUpdate()

        // Then
        XCTAssertTrue(sut.shouldShowViewAllPlans)
    }

    func testShouldShowViewAllPlans_WhenActiveProTierSubscriptionAndFeatureFlagDisabled_ReturnsTrue() async {
        // Given - Active Pro tier subscription with feature flag OFF
        mockFeatureFlagger.enabledFeatureFlags = []
        mockSubscriptionManager.resultSubscription = SubscriptionMockFactory.subscription(status: .autoRenewable, tier: .pro)
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()

        // When
        await waitForSubscriptionUpdate()

        // Then - Pro tier shows View All Plans even without feature flag
        XCTAssertTrue(sut.shouldShowViewAllPlans)
    }

    func testShouldShowViewAllPlans_WhenActivePlusTierSubscriptionAndFeatureFlagDisabled_ReturnsFalse() async {
        // Given - Active Plus tier subscription with feature flag OFF
        mockFeatureFlagger.enabledFeatureFlags = []
        mockSubscriptionManager.resultSubscription = SubscriptionMockFactory.subscription(status: .autoRenewable, tier: .plus)
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()

        // When
        await waitForSubscriptionUpdate()

        // Then - Plus tier doesn't show View All Plans when feature flag is off
        XCTAssertFalse(sut.shouldShowViewAllPlans)
    }

    // MARK: - View All Plans Action Tests

    func testViewAllPlans_WhenApplePlatform_SetsIsShowingPlansViewTrue() async {
        // Given - Apple platform subscription
        mockFeatureFlagger.enabledFeatureFlags = [.allowProTierPurchase]
        mockSubscriptionManager.resultSubscription = SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .apple, tier: .plus)
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()
        await waitForSubscriptionUpdate()

        // When
        sut.viewAllPlans()

        // Then
        XCTAssertTrue(sut.state.isShowingPlansView)
    }

    func testViewAllPlans_WhenGooglePlatform_SetsIsShowingGoogleViewTrue() async {
        // Given - Google platform subscription
        mockFeatureFlagger.enabledFeatureFlags = [.allowProTierPurchase]
        mockSubscriptionManager.resultSubscription = SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .google, tier: .plus)
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()
        await waitForSubscriptionUpdate()

        // When
        sut.viewAllPlans()

        // Then
        XCTAssertTrue(sut.state.isShowingGoogleView)
    }

    func testViewAllPlans_WhenStripePlatform_SetsIsShowingStripeViewTrue() async {
        // Given - Stripe platform subscription
        mockFeatureFlagger.enabledFeatureFlags = [.allowProTierPurchase]
        mockSubscriptionManager.resultSubscription = SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .stripe, tier: .plus)
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockSubscriptionManager.customerPortalURL = URL(string: "https://stripe.com/portal")!
        sut = makeSUT()
        await waitForSubscriptionUpdate()

        // When
        let stripeViewExpectation = expectation(description: "Stripe view shown")
        sut.$state
            .map { $0.isShowingStripeView }
            .filter { $0 == true }
            .first()
            .sink { _ in stripeViewExpectation.fulfill() }
            .store(in: &cancellables)

        sut.viewAllPlans()

        // Then - Wait for isShowingStripeView to become true
        await fulfillment(of: [stripeViewExpectation], timeout: 2.0)
        XCTAssertTrue(sut.state.isShowingStripeView)
    }

    func testViewAllPlans_WhenUnknownPlatform_SetsIsShowingInternalSubscriptionNoticeTrue() async {
        // Given - Unknown platform subscription
        mockFeatureFlagger.enabledFeatureFlags = [.allowProTierPurchase]
        mockSubscriptionManager.resultSubscription = SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .unknown, tier: .plus)
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()
        await waitForSubscriptionUpdate()

        // When
        sut.viewAllPlans()

        // Then
        XCTAssertTrue(sut.state.isShowingInternalSubscriptionNotice)
    }

    func testDisplayPlansView_UpdatesState() {
        // Given
        sut = makeSUT()
        XCTAssertFalse(sut.state.isShowingPlansView)

        // When
        sut.displayPlansView(true)

        // Then
        XCTAssertTrue(sut.state.isShowingPlansView)

        // When
        sut.displayPlansView(false)

        // Then
        XCTAssertFalse(sut.state.isShowingPlansView)
    }

    // MARK: - Helpers

    private func makeSUT() -> SubscriptionSettingsViewModelV2 {
        SubscriptionSettingsViewModelV2(
            subscriptionManager: mockSubscriptionManager,
            featureFlagger: mockFeatureFlagger,
            keyValueStorage: MockKeyValueStorage(),
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock(),
        )
    }

    private func waitForSubscriptionUpdate() async {
        let expectation = expectation(description: "Subscription info updated")

        sut.$state
            .compactMap { $0.subscriptionInfo }
            .first()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        sut.onFirstAppear()

        await fulfillment(of: [expectation], timeout: 2.0)
    }
}

// MARK: - Mock KeyValueStorage

private final class MockKeyValueStorage: KeyValueStoring {
    private var storage: [String: Any] = [:]

    func object(forKey defaultName: String) -> Any? {
        storage[defaultName]
    }

    func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }

    func removeObject(forKey defaultName: String) {
        storage.removeValue(forKey: defaultName)
    }
}
