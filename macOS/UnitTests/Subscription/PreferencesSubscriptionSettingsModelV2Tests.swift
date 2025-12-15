//
//  PreferencesSubscriptionSettingsModelV2Tests.swift
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

final class PreferencesSubscriptionSettingsModelV2Tests: XCTestCase {

    var sut: PreferencesSubscriptionSettingsModelV2!
    var mockSubscriptionManager: SubscriptionManagerMockV2!
    var mockKeyValueStore: MockThrowingKeyValueStore!
    var mockWinBackOfferManager: MockWinBackOfferVisibilityManager!
    var mockBlackFridayCampaignProvider: MockBlackFridayCampaignProvider!
    var userEvents: [PreferencesSubscriptionSettingsModelV2.UserEvent] = []
    var subscriptionStateSubject: PassthroughSubject<PreferencesSidebarSubscriptionState, Never>!
    var cancellables: Set<AnyCancellable> = []
    var isProTierPurchaseEnabled: Bool = false

    override func setUp() {
        super.setUp()

        mockSubscriptionManager = SubscriptionManagerMockV2()
        mockKeyValueStore = MockThrowingKeyValueStore()
        mockWinBackOfferManager = MockWinBackOfferVisibilityManager()
        mockBlackFridayCampaignProvider = MockBlackFridayCampaignProvider()
        userEvents = []
        subscriptionStateSubject = PassthroughSubject<PreferencesSidebarSubscriptionState, Never>()
        isProTierPurchaseEnabled = false

        sut = makeSUT()
    }

    private func makeSUT(subscription: DuckDuckGoSubscription? = nil) -> PreferencesSubscriptionSettingsModelV2 {
        mockSubscriptionManager.resultSubscription = subscription
        return PreferencesSubscriptionSettingsModelV2(
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
}
