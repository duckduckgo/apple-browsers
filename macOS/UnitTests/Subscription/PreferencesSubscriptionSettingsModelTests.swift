//
//  PreferencesSubscriptionSettingsModelTests.swift
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
import Subscription
import SubscriptionTestingUtilities
import BrowserServicesKit
import Persistence
import PersistenceTestingUtils
@testable import SubscriptionUI
@testable import DuckDuckGo_Privacy_Browser

final class PreferencesSubscriptionSettingsModelTests: XCTestCase {

    var sut: PreferencesSubscriptionSettingsModel!
    var mockSubscriptionManager: SubscriptionManagerMock!
    var mockKeyValueStore: MockThrowingKeyValueStore!
    var mockWinBackOfferManager: MockWinBackOfferVisibilityManager!
    var mockBlackFridayCampaignProvider: MockBlackFridayCampaignProvider!
    var userEvents: [PreferencesSubscriptionSettingsModel.UserEvent] = []
    var subscriptionStateSubject: PassthroughSubject<PreferencesSidebarSubscriptionState, Never>!
    var cancellables: Set<AnyCancellable> = []
    var isProTierPurchaseEnabled: Bool = false

    override func setUp() {
        super.setUp()

        mockSubscriptionManager = SubscriptionManagerMock()
        mockKeyValueStore = MockThrowingKeyValueStore()
        mockWinBackOfferManager = MockWinBackOfferVisibilityManager()
        mockBlackFridayCampaignProvider = MockBlackFridayCampaignProvider()
        userEvents = []
        subscriptionStateSubject = PassthroughSubject<PreferencesSidebarSubscriptionState, Never>()
        isProTierPurchaseEnabled = false

        sut = makeSUT()
    }

    private func makeSUT(subscription: DuckDuckGoSubscription? = nil,
                         purchasePlatform: SubscriptionEnvironment.PurchasePlatform = .appStore) -> PreferencesSubscriptionSettingsModel {
        if let subscription {
            mockSubscriptionManager.resultSubscription = .success(subscription)
        } else {
            mockSubscriptionManager.resultSubscription = .failure(NSError(domain: "", code: 0, userInfo: nil))
        }
        mockSubscriptionManager.currentEnvironment = SubscriptionEnvironment(serviceEnvironment: .staging, purchasePlatform: purchasePlatform)
        return PreferencesSubscriptionSettingsModel(
            userEventHandler: { [weak self] event in
                self?.userEvents.append(event)
            },
            subscriptionManager: mockSubscriptionManager,
            subscriptionStateUpdate: subscriptionStateSubject.eraseToAnyPublisher(),
            keyValueStore: mockKeyValueStore,
            winBackOfferVisibilityManager: mockWinBackOfferManager,
            blackFridayCampaignProvider: mockBlackFridayCampaignProvider,
            isProTierPurchaseEnabled: { [weak self] in self?.isProTierPurchaseEnabled ?? false }
        )
    }

    override func tearDown() {
        sut = nil
        mockSubscriptionManager = nil
        mockKeyValueStore = nil
        mockWinBackOfferManager = nil
        mockBlackFridayCampaignProvider = nil
        userEvents = []
        subscriptionStateSubject = nil
        cancellables = []
        super.tearDown()
    }

    // MARK: - Expired Subscription Purchase Button Title Tests

    func testExpiredSubscriptionPurchaseButtonTitle_WhenWinBackOfferAvailable_ReturnsWinBackCTA() {
        // Given
        mockWinBackOfferManager.isOfferAvailable = true
        mockBlackFridayCampaignProvider.isCampaignEnabled = false

        // When
        let buttonTitle = sut.expiredSubscriptionPurchaseButtonTitle

        // Then
        XCTAssertEqual(buttonTitle, UserText.winBackCampaignLoggedInPreferencesCTA)
    }

    func testExpiredSubscriptionPurchaseButtonTitle_WhenBlackFridayEnabled_ReturnsBlackFridayCTA() {
        // Given
        mockWinBackOfferManager.isOfferAvailable = false
        mockBlackFridayCampaignProvider.isCampaignEnabled = true
        mockBlackFridayCampaignProvider.discountPercent = 40

        // When
        let buttonTitle = sut.expiredSubscriptionPurchaseButtonTitle

        // Then
        XCTAssertEqual(buttonTitle, UserText.blackFridayCampaignPreferencesCTA(discountPercent: 40))
    }

    func testExpiredSubscriptionPurchaseButtonTitle_WhenBlackFridayWithCustomDiscount_ReturnsCorrectCTA() {
        // Given
        mockWinBackOfferManager.isOfferAvailable = false
        mockBlackFridayCampaignProvider.isCampaignEnabled = true
        mockBlackFridayCampaignProvider.discountPercent = 75

        // When
        let buttonTitle = sut.expiredSubscriptionPurchaseButtonTitle

        // Then
        XCTAssertEqual(buttonTitle, UserText.blackFridayCampaignPreferencesCTA(discountPercent: 75))
    }

    func testExpiredSubscriptionPurchaseButtonTitle_WhenNoSpecialOffers_ReturnsDefaultCTA() {
        // Given
        mockWinBackOfferManager.isOfferAvailable = false
        mockBlackFridayCampaignProvider.isCampaignEnabled = false

        // When
        let buttonTitle = sut.expiredSubscriptionPurchaseButtonTitle

        // Then
        XCTAssertEqual(buttonTitle, UserText.viewPlansExpiredButtonTitle)
    }

    func testExpiredSubscriptionPurchaseButtonTitle_WhenBothOffersAvailable_PrefersWinBack() {
        // Given - Both offers available
        mockWinBackOfferManager.isOfferAvailable = true
        mockBlackFridayCampaignProvider.isCampaignEnabled = true
        mockBlackFridayCampaignProvider.discountPercent = 50

        // When
        let buttonTitle = sut.expiredSubscriptionPurchaseButtonTitle

        // Then
        XCTAssertEqual(buttonTitle, UserText.winBackCampaignLoggedInPreferencesCTA)
    }

    // MARK: - Tier Badge Display Tests

    func testTierBadgeToDisplay_WhenNoTier_ReturnsNil() {
        // Given
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(status: .autoRenewable, tier: nil))

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // Then
        XCTAssertNil(sut.tierBadgeToDisplay)
    }

    func testTierBadgeToDisplay_WhenProTier_AlwaysReturnsPro() {
        // Given - Pro tier with feature flag OFF
        isProTierPurchaseEnabled = false
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(status: .autoRenewable, tier: .pro))

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // Then
        XCTAssertEqual(sut.tierBadgeToDisplay, .pro)
    }

    func testTierBadgeToDisplay_WhenPlusTierAndFeatureFlagEnabled_ReturnsPlus() {
        // Given - Plus tier with feature flag ON
        isProTierPurchaseEnabled = true
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(status: .autoRenewable, tier: .plus))

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // Then
        XCTAssertEqual(sut.tierBadgeToDisplay, .plus)
    }

    func testTierBadgeToDisplay_WhenPlusTierAndFeatureFlagDisabled_ReturnsNil() {
        // Given - Plus tier with feature flag OFF
        isProTierPurchaseEnabled = false
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(status: .autoRenewable, tier: .plus))

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // Then
        XCTAssertNil(sut.tierBadgeToDisplay)
    }

    // MARK: - Should Show View All Plans Tests

    func testShouldShowViewAllPlans_WhenActiveSubscriptionAndFeatureFlagEnabled_ReturnsTrue() {
        // Given - Active subscription with feature flag ON
        isProTierPurchaseEnabled = true
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(status: .autoRenewable, tier: .plus))

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // Then
        XCTAssertTrue(sut.shouldShowViewAllPlans)
    }

    func testShouldShowViewAllPlans_WhenActiveProTierSubscription_ReturnsTrue() {
        // Given - Active Pro tier subscription with feature flag OFF
        isProTierPurchaseEnabled = false
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(status: .autoRenewable, tier: .pro))

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // Then
        XCTAssertTrue(sut.shouldShowViewAllPlans)
    }

    func testShouldShowViewAllPlans_WhenExpiredSubscription_ReturnsFalse() {
        // Given - Expired subscription
        isProTierPurchaseEnabled = true
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(status: .expired, tier: .plus))

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // Then
        XCTAssertFalse(sut.shouldShowViewAllPlans)
    }

    func testShouldShowViewAllPlans_WhenPlusTierAndFeatureFlagDisabled_ReturnsFalse() {
        // Given - Plus tier with feature flag OFF
        isProTierPurchaseEnabled = false
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(status: .autoRenewable, tier: .plus))

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // Then
        XCTAssertFalse(sut.shouldShowViewAllPlans)
    }

    // MARK: - View All Plans Action Tests

    @MainActor
    func testViewAllPlansAction_WhenAppleSubscriptionOnAppStoreApp_ReturnsNavigateToPlans() {
        // Given - Apple subscription on App Store app (platforms match)
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .apple, tier: .plus),
                      purchasePlatform: .appStore)

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // When
        let action = sut.viewAllPlansAction()

        // Then
        if case .navigateToPlans(let navigationAction) = action {
            navigationAction()
            XCTAssertTrue(userEvents.contains { event in
                if case .openURL(.plans) = event { return true }
                return false
            })
        } else {
            XCTFail("Expected navigateToPlans action")
        }
    }

    @MainActor
    func testViewAllPlansAction_WhenAppleSubscriptionOnStripeApp_PresentsAppleSheet() {
        // Given - Apple subscription on Stripe app (platforms don't match)
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .apple, tier: .plus),
                      purchasePlatform: .stripe)

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // When
        let action = sut.viewAllPlansAction()

        // Then - Should show Apple dialog with instructions
        if case .presentSheet(.apple) = action {
            // Success
        } else {
            XCTFail("Expected presentSheet(.apple) action")
        }
    }

    @MainActor
    func testViewAllPlansAction_WhenStripeSubscriptionOnStripeApp_ReturnsNavigateToPlans() {
        // Given - Stripe subscription on Stripe app (platforms match)
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .stripe, tier: .plus),
                      purchasePlatform: .stripe)

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // When
        let action = sut.viewAllPlansAction()

        // Then
        if case .navigateToPlans(let navigationAction) = action {
            navigationAction()
            XCTAssertTrue(userEvents.contains { event in
                if case .openURL(.plans) = event { return true }
                return false
            })
        } else {
            XCTFail("Expected navigateToPlans action")
        }
    }

    @MainActor
    func testViewAllPlansAction_WhenStripeSubscriptionOnAppStoreApp_ReturnsNavigateToManageSubscription() {
        // Given - Stripe subscription on App Store app (platforms don't match)
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .stripe, tier: .plus),
                      purchasePlatform: .appStore)

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // When
        let action = sut.viewAllPlansAction()

        // Then - Should navigate to Stripe portal
        if case .navigateToManageSubscription = action {
            // Success - Stripe subscriptions on App Store app redirect to Stripe portal
        } else {
            XCTFail("Expected navigateToManageSubscription action for Stripe portal")
        }
    }

    @MainActor
    func testViewAllPlansAction_WhenGooglePlatform_PresentsGoogleSheet() {
        // Given - Google platform subscription
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .google, tier: .plus))

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // When
        let action = sut.viewAllPlansAction()

        // Then
        if case .presentSheet(.google) = action {
            // Success
        } else {
            XCTFail("Expected presentSheet(.google) action")
        }
    }

    @MainActor
    func testViewAllPlansAction_WhenUnknownPlatform_ShowsInternalSubscriptionAlert() {
        // Given - Unknown platform subscription
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .unknown, tier: .plus))

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // When
        let action = sut.viewAllPlansAction()

        // Then
        if case .showInternalSubscriptionAlert = action {
            // Success
        } else {
            XCTFail("Expected showInternalSubscriptionAlert action")
        }
    }

    // MARK: - Should Show Upgrade Tests

    func testShouldShowUpgrade_WhenInactiveSubscription_ReturnsFalse() {
        // Given - Expired subscription with feature flag ON and upgrades available
        isProTierPurchaseEnabled = true
        let availableChanges = DuckDuckGoSubscription.AvailableChanges(
            upgrade: [DuckDuckGoSubscription.TierChange(tier: "pro", productIds: [], order: 1)],
            downgrade: []
        )
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(
            status: .expired,
            tier: .plus,
            availableChanges: availableChanges
        ))

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // Then
        XCTAssertFalse(sut.shouldShowUpgrade)
    }

    func testShouldShowUpgrade_WhenFeatureFlagDisabled_ReturnsFalse() {
        // Given - Active subscription with feature flag OFF and upgrades available
        isProTierPurchaseEnabled = false
        let availableChanges = DuckDuckGoSubscription.AvailableChanges(
            upgrade: [DuckDuckGoSubscription.TierChange(tier: "pro", productIds: [], order: 1)],
            downgrade: []
        )
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            tier: .plus,
            availableChanges: availableChanges
        ))

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // Then
        XCTAssertFalse(sut.shouldShowUpgrade)
    }

    func testShouldShowUpgrade_WhenNoAvailableUpgrades_ReturnsFalse() {
        // Given - Active subscription with feature flag ON but no upgrades available
        isProTierPurchaseEnabled = true
        let availableChanges = DuckDuckGoSubscription.AvailableChanges(
            upgrade: [],
            downgrade: [DuckDuckGoSubscription.TierChange(tier: "plus", productIds: [], order: 1)]
        )
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            tier: .pro,
            availableChanges: availableChanges
        ))

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // Then
        XCTAssertFalse(sut.shouldShowUpgrade)
    }

    func testShouldShowUpgrade_WhenAllConditionsMet_ReturnsTrue() {
        // Given - Active subscription with feature flag ON and upgrades available
        isProTierPurchaseEnabled = true
        let availableChanges = DuckDuckGoSubscription.AvailableChanges(
            upgrade: [DuckDuckGoSubscription.TierChange(tier: "pro", productIds: [], order: 1)],
            downgrade: []
        )
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            tier: .plus,
            availableChanges: availableChanges
        ))

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // Then
        XCTAssertTrue(sut.shouldShowUpgrade)
    }

    // MARK: - First Available Upgrade Tier Tests

    func testFirstAvailableUpgradeTier_WhenNoUpgrades_ReturnsNil() {
        // Given - No available upgrades
        let availableChanges = DuckDuckGoSubscription.AvailableChanges(
            upgrade: [],
            downgrade: []
        )
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            tier: .pro,
            availableChanges: availableChanges
        ))

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // Then
        XCTAssertNil(sut.firstAvailableUpgradeTier)
    }

    func testFirstAvailableUpgradeTier_ReturnsTierWithLowestOrder() {
        // Given - Multiple upgrades available
        let availableChanges = DuckDuckGoSubscription.AvailableChanges(
            upgrade: [
                DuckDuckGoSubscription.TierChange(tier: "ultimate", productIds: [], order: 2),
                DuckDuckGoSubscription.TierChange(tier: "pro", productIds: [], order: 1)
            ],
            downgrade: []
        )
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            tier: .plus,
            availableChanges: availableChanges
        ))

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // Then - Should return "pro" as it has the lowest order
        XCTAssertEqual(sut.firstAvailableUpgradeTier, "pro")
    }

    // MARK: - View All Plans Action with Upgrade URL Tests

    @MainActor
    func testViewAllPlansActionWithUpgradeURL_WhenAppleSubscriptionOnAppStoreApp_ReturnsNavigateToPlans() {
        // Given - Apple subscription on App Store app (platforms match)
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            platform: .apple,
            tier: .plus
        ),
        purchasePlatform: .appStore)

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // When
        let action = sut.viewAllPlansAction(url: .upgrade)

        // Then
        if case .navigateToPlans(let navigationAction) = action {
            navigationAction()
            XCTAssertTrue(userEvents.contains { event in
                if case .openURL(.upgrade) = event { return true }
                return false
            })
        } else {
            XCTFail("Expected navigateToPlans action")
        }
    }

    @MainActor
    func testViewAllPlansActionWithUpgradeURL_WhenStripeSubscriptionOnStripeApp_ReturnsNavigateToPlans() {
        // Given - Stripe subscription on Stripe app (platforms match)
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            platform: .stripe,
            tier: .plus
        ),
        purchasePlatform: .stripe)

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // When
        let action = sut.viewAllPlansAction(url: .upgrade)

        // Then
        if case .navigateToPlans(let navigationAction) = action {
            navigationAction()
            XCTAssertTrue(userEvents.contains { event in
                if case .openURL(.upgrade) = event { return true }
                return false
            })
        } else {
            XCTFail("Expected navigateToPlans action")
        }
    }

    // MARK: - Pending Plan Tests

    func testSubscriptionDetails_WhenPendingPlanExists_ShowsDowngradeCopy() {
        // Given - Subscription with a pending downgrade plan
        let pendingPlan = DuckDuckGoSubscription.PendingPlan(
            productId: "ddg-privacy-pro-monthly-plus",
            billingPeriod: .monthly,
            effectiveAt: Date(timeIntervalSince1970: 1711557633),
            status: "pending",
            tier: .plus
        )
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            tier: .pro,
            pendingPlans: [pendingPlan]
        ))

        // Wait
        let expectation = expectation(description: "Subscription details updated with pending plan")
        sut.$subscriptionDetails
            .compactMap { $0 }
            .filter { $0.contains("Plus") && $0.contains("Monthly") }
            .first()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 2.0)

        // Then - Should show pending downgrade message
        XCTAssertNotNil(sut.subscriptionDetails)
        XCTAssertTrue(sut.subscriptionDetails?.contains("Plus") == true)
        XCTAssertTrue(sut.subscriptionDetails?.contains("Monthly") == true)
    }

    func testSubscriptionDetails_WhenNoPendingPlan_ShowsRenewalCopy() {
        // Given - Subscription without pending plan
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            tier: .pro,
            pendingPlans: nil
        ))

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription details updated")
        sut.$subscriptionDetails
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // Then - Should show standard renewal message
        XCTAssertNotNil(sut.subscriptionDetails)
        XCTAssertTrue(sut.subscriptionDetails?.contains("renews") == true)
    }

    func testSubscriptionDetails_WhenEmptyPendingPlans_ShowsRenewalCopy() {
        // Given - Subscription with empty pending plans array
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            tier: .pro,
            pendingPlans: []
        ))

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription details updated")
        sut.$subscriptionDetails
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // Then - Should show standard renewal message (empty array = no pending plan)
        XCTAssertNotNil(sut.subscriptionDetails)
        XCTAssertTrue(sut.subscriptionDetails?.contains("renews") == true)
    }

    func testShouldShowUpgrade_WhenPendingPlanExists_ReturnsFalse() {
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
        isProTierPurchaseEnabled = true
        sut = makeSUT(subscription: SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            tier: .pro,
            availableChanges: availableChanges,
            pendingPlans: [pendingPlan]
        ))

        // Wait for async subscription update
        let expectation = expectation(description: "Subscription status updated")
        sut.$subscriptionStatus
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)

        // Then - Should NOT show upgrade when there's a pending plan
        XCTAssertFalse(sut.shouldShowUpgrade)
    }
}
