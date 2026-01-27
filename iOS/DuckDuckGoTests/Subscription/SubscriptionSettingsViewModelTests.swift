//
//  SubscriptionSettingsViewModelTests.swift
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

final class SubscriptionSettingsViewModelTests: XCTestCase {

    var sut: SubscriptionSettingsViewModel!
    var mockSubscriptionManager: SubscriptionManagerMock!
    var cancellables = Set<AnyCancellable>()
    var isProTierPurchaseEnabled: Bool = false
    var mockFeatureFlagger: MockFeatureFlagger!

    override func setUp() {
        super.setUp()
        mockSubscriptionManager = SubscriptionManagerMock()
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
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(status: .autoRenewable, tier: nil))
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()

        // When - trigger fetch
        await waitForSubscriptionUpdate()

        // Then
        XCTAssertNil(sut.tierBadgeToDisplay)
    }

    func testTierBadgeToDisplay_WhenProTier_AlwaysReturnsPro() async {
        // Given - Pro tier with feature flag OFF
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(status: .autoRenewable, tier: .pro))
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
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(status: .autoRenewable, tier: .plus))
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
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(status: .autoRenewable, tier: .plus))
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
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(status: .expired, tier: .plus))
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
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(status: .autoRenewable, tier: .plus))
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
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(status: .autoRenewable, tier: .pro))
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
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(status: .autoRenewable, tier: .plus))
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
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .apple, tier: .plus))
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()
        await waitForSubscriptionUpdate()

        // When
        sut.navigateToPlans()

        // Then
        XCTAssertTrue(sut.state.isShowingPlansView)
    }

    func testViewAllPlans_WhenGooglePlatform_SetsIsShowingGoogleViewTrue() async {
        // Given - Google platform subscription
        mockFeatureFlagger.enabledFeatureFlags = [.allowProTierPurchase]
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .google, tier: .plus))
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()
        await waitForSubscriptionUpdate()

        // When
        sut.navigateToPlans()

        // Then
        XCTAssertTrue(sut.state.isShowingGoogleView)
    }

    func testViewAllPlans_WhenStripePlatform_SetsIsShowingStripeViewTrue() async {
        // Given - Stripe platform subscription
        mockFeatureFlagger.enabledFeatureFlags = [.allowProTierPurchase]
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .stripe, tier: .plus))
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

        sut.navigateToPlans()

        // Then - Wait for isShowingStripeView to become true
        await fulfillment(of: [stripeViewExpectation], timeout: 2.0)
        XCTAssertTrue(sut.state.isShowingStripeView)
    }

    func testViewAllPlans_WhenUnknownPlatform_SetsIsShowingInternalSubscriptionNoticeTrue() async {
        // Given - Unknown platform subscription
        mockFeatureFlagger.enabledFeatureFlags = [.allowProTierPurchase]
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .unknown, tier: .plus))
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()
        await waitForSubscriptionUpdate()

        // When
        sut.navigateToPlans()

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

    // MARK: - Upgrade Section Visibility Tests

    func testShouldShowUpgrade_WhenNoSubscription_ReturnsFalse() {
        // Given - No subscription
        mockSubscriptionManager.resultSubscription = nil
        sut = makeSUT()

        // Then
        XCTAssertFalse(sut.shouldShowUpgrade)
    }

    func testShouldShowUpgrade_WhenSubscriptionInactive_ReturnsFalse() async {
        // Given - Inactive subscription with available upgrades
        let availableChanges = DuckDuckGoSubscription.AvailableChanges(
            upgrade: [DuckDuckGoSubscription.TierChange(tier: "pro", productIds: [], order: 1)],
            downgrade: []
        )
        mockFeatureFlagger.enabledFeatureFlags = [.allowProTierPurchase]
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(
            status: .expired,
            tier: .plus,
            availableChanges: availableChanges
        ))
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()

        // When
        await waitForSubscriptionUpdate()

        // Then
        XCTAssertFalse(sut.shouldShowUpgrade)
    }

    func testShouldShowUpgrade_WhenFeatureFlagDisabled_ReturnsFalse() async {
        // Given - Active subscription with available upgrades but feature flag OFF
        let availableChanges = DuckDuckGoSubscription.AvailableChanges(
            upgrade: [DuckDuckGoSubscription.TierChange(tier: "pro", productIds: [], order: 1)],
            downgrade: []
        )
        mockFeatureFlagger.enabledFeatureFlags = [] // Feature flag OFF
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            tier: .plus,
            availableChanges: availableChanges
        ))
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()

        // When
        await waitForSubscriptionUpdate()

        // Then
        XCTAssertFalse(sut.shouldShowUpgrade)
    }

    func testShouldShowUpgrade_WhenNoAvailableUpgrades_ReturnsFalse() async {
        // Given - Active subscription with feature flag ON but no available upgrades
        mockFeatureFlagger.enabledFeatureFlags = [.allowProTierPurchase]
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            tier: .plus,
            availableChanges: DuckDuckGoSubscription.AvailableChanges(upgrade: [], downgrade: [])
        ))
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()

        // When
        await waitForSubscriptionUpdate()

        // Then
        XCTAssertFalse(sut.shouldShowUpgrade)
    }

    func testShouldShowUpgrade_WhenAllConditionsMet_ReturnsTrue() async {
        // Given - Active subscription with feature flag ON and available upgrades
        let availableChanges = DuckDuckGoSubscription.AvailableChanges(
            upgrade: [DuckDuckGoSubscription.TierChange(tier: "pro", productIds: [], order: 1)],
            downgrade: []
        )
        mockFeatureFlagger.enabledFeatureFlags = [.allowProTierPurchase]
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            tier: .plus,
            availableChanges: availableChanges
        ))
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()

        // When
        await waitForSubscriptionUpdate()

        // Then
        XCTAssertTrue(sut.shouldShowUpgrade)
    }

    // MARK: - First Available Upgrade Tier Tests

    func testFirstAvailableUpgradeTier_WhenNoSubscription_ReturnsNil() {
        // Given
        mockSubscriptionManager.resultSubscription = nil
        sut = makeSUT()

        // Then
        XCTAssertNil(sut.firstAvailableUpgradeTier)
    }

    func testFirstAvailableUpgradeTier_WhenNoAvailableChanges_ReturnsNil() async {
        // Given
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            tier: .plus,
            availableChanges: nil
        ))
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()

        // When
        await waitForSubscriptionUpdate()

        // Then
        XCTAssertNil(sut.firstAvailableUpgradeTier)
    }

    func testFirstAvailableUpgradeTier_WhenEmptyUpgrades_ReturnsNil() async {
        // Given
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            tier: .plus,
            availableChanges: DuckDuckGoSubscription.AvailableChanges(upgrade: [], downgrade: [])
        ))
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()

        // When
        await waitForSubscriptionUpdate()

        // Then
        XCTAssertNil(sut.firstAvailableUpgradeTier)
    }

    func testFirstAvailableUpgradeTier_ReturnsTierWithLowestOrder() async {
        // Given - Multiple upgrades with different orders
        let availableChanges = DuckDuckGoSubscription.AvailableChanges(
            upgrade: [
                DuckDuckGoSubscription.TierChange(tier: "ultra", productIds: [], order: 3),
                DuckDuckGoSubscription.TierChange(tier: "pro", productIds: [], order: 1),
                DuckDuckGoSubscription.TierChange(tier: "premium", productIds: [], order: 2)
            ],
            downgrade: []
        )
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            tier: .plus,
            availableChanges: availableChanges
        ))
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()

        // When
        await waitForSubscriptionUpdate()

        // Then - Should return "pro" (lowest order = 1)
        XCTAssertEqual(sut.firstAvailableUpgradeTier, "pro")
    }

    // MARK: - Navigate To Plans (Upgrade) Action Tests

    func testNavigateToPlans_WithTier_WhenApplePlatform_SetsIsShowingUpgradeViewTrue() async {
        // Given - Apple platform subscription
        let availableChanges = DuckDuckGoSubscription.AvailableChanges(
            upgrade: [DuckDuckGoSubscription.TierChange(tier: "pro", productIds: [], order: 1)],
            downgrade: []
        )
        mockFeatureFlagger.enabledFeatureFlags = [.allowProTierPurchase]
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            platform: .apple,
            tier: .plus,
            availableChanges: availableChanges
        ))
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()
        await waitForSubscriptionUpdate()

        // When - pass tier to simulate upgrade button click
        sut.navigateToPlans(tier: "pro")

        // Then
        XCTAssertTrue(sut.state.isShowingUpgradeView)
        XCTAssertFalse(sut.state.isShowingPlansView)
        XCTAssertEqual(sut.state.pendingUpgradeTier, "pro")
    }

    func testNavigateToPlans_WithoutTier_WhenApplePlatform_SetsIsShowingPlansViewTrue() async {
        // Given - Apple platform subscription
        mockFeatureFlagger.enabledFeatureFlags = [.allowProTierPurchase]
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            platform: .apple,
            tier: .plus
        ))
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()
        await waitForSubscriptionUpdate()

        // When - no tier means "View All Plans" not upgrade
        sut.navigateToPlans()

        // Then
        XCTAssertTrue(sut.state.isShowingPlansView)
        XCTAssertFalse(sut.state.isShowingUpgradeView)
    }

    func testNavigateToPlans_WithTier_WhenGooglePlatform_SetsIsShowingGoogleViewTrue() async {
        // Given - Google platform subscription
        mockFeatureFlagger.enabledFeatureFlags = [.allowProTierPurchase]
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            platform: .google,
            tier: .plus
        ))
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()
        await waitForSubscriptionUpdate()

        // When - pass tier to simulate upgrade button click
        sut.navigateToPlans(tier: "pro")

        // Then - Google shows the same view regardless of tier
        XCTAssertTrue(sut.state.isShowingGoogleView)
    }

    func testDisplayUpgradeView_UpdatesState() {
        // Given
        sut = makeSUT()
        XCTAssertFalse(sut.state.isShowingUpgradeView)

        // When
        sut.displayUpgradeView(true)

        // Then
        XCTAssertTrue(sut.state.isShowingUpgradeView)

        // When
        sut.displayUpgradeView(false)

        // Then
        XCTAssertFalse(sut.state.isShowingUpgradeView)
    }

    // MARK: - Pending Plan Tests

    func testSubscriptionDetails_WhenPendingPlanExists_ShowsDowngradeCopy() async {
        // Given - Subscription with a pending downgrade plan
        let pendingPlan = DuckDuckGoSubscription.PendingPlan(
            productId: "ddg-privacy-pro-monthly-plus",
            billingPeriod: .monthly,
            effectiveAt: Date(timeIntervalSince1970: 1711557633),
            status: "pending",
            tier: .plus
        )
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            tier: .pro,
            pendingPlans: [pendingPlan]
        ))
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()

        // When
        let expectation = expectation(description: "Subscription details updated")
        sut.$state
            .map { $0.subscriptionDetails }
            .filter { !$0.isEmpty }
            .first()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        sut.onFirstAppear()
        await fulfillment(of: [expectation], timeout: 2.0)

        // Then - Should show pending downgrade message
        XCTAssertFalse(sut.state.subscriptionDetails.isEmpty)
        XCTAssertTrue(sut.state.subscriptionDetails.contains("Plus"))
        XCTAssertTrue(sut.state.subscriptionDetails.contains("Monthly"))
    }

    func testSubscriptionDetails_WhenNoPendingPlan_ShowsRenewalCopy() async {
        // Given - Subscription without pending plan
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            tier: .pro,
            pendingPlans: nil
        ))
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()

        // When
        await waitForSubscriptionUpdate()

        // Then - Should show standard renewal message
        XCTAssertNotNil(sut.state.subscriptionDetails)
        XCTAssertTrue(sut.state.subscriptionDetails.contains("renews") == true)
    }

    func testSubscriptionDetails_WhenEmptyPendingPlans_ShowsRenewalCopy() async {
        // Given - Subscription with empty pending plans array
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            tier: .pro,
            pendingPlans: []
        ))
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()

        // When
        await waitForSubscriptionUpdate()

        // Then - Should show standard renewal message (empty array = no pending plan)
        XCTAssertNotNil(sut.state.subscriptionDetails)
        XCTAssertTrue(sut.state.subscriptionDetails.contains("renews") == true)
    }

    func testShouldShowUpgrade_WhenPendingPlanExists_ReturnsFalse() async {
        // Given - Active subscription with pending plan and available upgrades
        let pendingPlan = DuckDuckGoSubscription.PendingPlan(
            productId: "ddg-privacy-pro-monthly-plus",
            billingPeriod: .monthly,
            effectiveAt: Date(),
            status: "pending",
            tier: .plus
        )
        let availableChanges = DuckDuckGoSubscription.AvailableChanges(
            upgrade: [DuckDuckGoSubscription.TierChange(tier: "pro", productIds: [], order: 1)],
            downgrade: []
        )
        mockFeatureFlagger.enabledFeatureFlags = [.allowProTierPurchase]
        mockSubscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            tier: .pro,
            availableChanges: availableChanges,
            pendingPlans: [pendingPlan]
        ))
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        sut = makeSUT()

        // When
        await waitForSubscriptionUpdate()

        // Then - Should NOT show upgrade when there's a pending plan
        XCTAssertFalse(sut.shouldShowUpgrade)
    }

    // MARK: - Helpers

    private func makeSUT() -> SubscriptionSettingsViewModel {
        SubscriptionSettingsViewModel(
            subscriptionManager: mockSubscriptionManager,
            featureFlagger: mockFeatureFlagger,
            keyValueStorage: MockKeyValueStorage(),
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock(),
        )
    }

    private func waitForSubscriptionUpdate() async {
        let expectation = expectation(description: "Subscription details updated")

        sut.$state
            .map { $0.subscriptionDetails }
            .filter { !$0.isEmpty }  // Wait for subscriptionDetails to be non-empty
            .first()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        sut.onFirstAppear()

        await fulfillment(of: [expectation], timeout: 15.0)
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
