//
//  PreferencesPurchaseSubscriptionModelTests.swift
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

import PrivacyConfig
import Subscription
import SubscriptionTestingUtilities
import XCTest
@testable import SubscriptionUI
@testable import DuckDuckGo_Privacy_Browser

final class PreferencesPurchaseSubscriptionModelTests: XCTestCase {

    var sut: PreferencesPurchaseSubscriptionModel!
    var mockSubscriptionManager: SubscriptionManagerMock!
    var mockFeatureFlagger: MockFeatureFlagger!
    var mockWinBackOfferManager: MockWinBackOfferVisibilityManager!
    var mockBlackFridayCampaignProvider: MockBlackFridayCampaignProvider!
    var userEvents: [PreferencesPurchaseSubscriptionModel.UserEvent] = []
    var sheetActionHandler: SubscriptionAccessActionHandlers!

    override func setUp() {
        super.setUp()

        mockSubscriptionManager = SubscriptionManagerMock()
        mockFeatureFlagger = MockFeatureFlagger()
        mockWinBackOfferManager = MockWinBackOfferVisibilityManager()
        mockBlackFridayCampaignProvider = MockBlackFridayCampaignProvider()
        userEvents = []

        sheetActionHandler = SubscriptionAccessActionHandlers(
            openActivateViaEmailURL: { },
            restorePurchases: { }
        )

        sut = PreferencesPurchaseSubscriptionModel(
            subscriptionManager: mockSubscriptionManager,
            featureFlagger: mockFeatureFlagger,
            winBackOfferVisibilityManager: mockWinBackOfferManager,
            userEventHandler: { [weak self] event in
                self?.userEvents.append(event)
            },
            sheetActionHandler: sheetActionHandler,
            blackFridayCampaignProvider: mockBlackFridayCampaignProvider
        )
    }

    override func tearDown() {
        sut = nil
        mockSubscriptionManager = nil
        mockFeatureFlagger = nil
        mockWinBackOfferManager = nil
        mockBlackFridayCampaignProvider = nil
        userEvents = []
        sheetActionHandler = nil
        super.tearDown()
    }

    // MARK: - Purchase Section Header Tests

    func testPurchaseSectionHeader_WhenWinBackOfferAvailable_ReturnsWinBackText() {
        // Given
        mockWinBackOfferManager.isOfferAvailable = true
        mockFeatureFlagger.enabledFeatureFlags = [.paidAIChat]

        // When
        let header = sut.purchaseSectionHeader

        // Then
        XCTAssertEqual(header, UserText.winBackCampaignLoggedOutPreferencesTitle)
    }

    func testPurchaseSectionHeader_WhenWinBackOfferNotAvailable_ReturnsDefaultText() {
        // Given
        mockWinBackOfferManager.isOfferAvailable = false
        mockFeatureFlagger.enabledFeatureFlags = [.paidAIChat]

        // When
        let header = sut.purchaseSectionHeader

        // Then
        XCTAssertEqual(header, UserText.preferencesSubscriptionInactiveHeader(isPaidAIChatEnabled: false))
    }

    func testPurchaseSectionHeader_WhenWinBackOfferNotAvailableAndPaidAIChatEnabled_ReturnsAIChatText() {
        // Given
        mockWinBackOfferManager.isOfferAvailable = false
        mockFeatureFlagger.enabledFeatureFlags = [.paidAIChat]

        // When
        let header = sut.purchaseSectionHeader

        // Then
        XCTAssertEqual(header, UserText.preferencesSubscriptionInactiveHeader(isPaidAIChatEnabled: false))
    }

    // MARK: - Purchase Section Caption Tests

    func testPurchaseSectionCaption_WhenWinBackOfferAvailable_ReturnsWinBackCaption() {
        // Given
        mockWinBackOfferManager.isOfferAvailable = true

        // When
        let caption = sut.purchaseSectionCaption

        // Then
        XCTAssertEqual(caption, UserText.winBackCampaignLoggedInPreferencesMessage)
    }

    func testPurchaseSectionCaption_WhenWinBackOfferNotAvailable_ReturnsDefaultCaption() {
        // Given
        mockWinBackOfferManager.isOfferAvailable = false
        mockFeatureFlagger.enabledFeatureFlags = [.paidAIChat]

        // When
        let caption = sut.purchaseSectionCaption

        // Then
        XCTAssertEqual(caption, UserText.preferencesSubscriptionInactiveCaption(region: .usa, isPaidAIChatEnabled: false))
    }

    // MARK: - Purchase Button Title Tests

    func testPurchaseButtonTitle_WhenWinBackOfferAvailable_ReturnsWinBackCTA() {
        // Given
        mockWinBackOfferManager.isOfferAvailable = true

        // When
        let buttonTitle = sut.purchaseButtonTitle

        // Then
        XCTAssertEqual(buttonTitle, UserText.winBackCampaignLoggedOutPreferencesCTA)
    }

    func testPurchaseButtonTitle_WhenBlackFridayCampaignEnabled_ReturnsBlackFridayCTA() {
        // Given
        mockWinBackOfferManager.isOfferAvailable = false
        mockBlackFridayCampaignProvider.isCampaignEnabled = true
        mockBlackFridayCampaignProvider.discountPercent = 50

        // When
        let buttonTitle = sut.purchaseButtonTitle

        // Then
        XCTAssertEqual(buttonTitle, UserText.blackFridayCampaignPreferencesCTA(discountPercent: 50))
    }

    @MainActor
    func testPurchaseButtonTitle_WhenUserEligibleForFreeTrial_ReturnsFreeTrialCTA() {
        // Given
        mockWinBackOfferManager.isOfferAvailable = false
        mockBlackFridayCampaignProvider.isCampaignEnabled = false
        mockFeatureFlagger.enabledFeatureFlags = [.paidAIChat]
        mockSubscriptionManager.isEligibleForFreeTrialResult = true

        // Force update eligibility
        sut.didAppear()

        // When
        let buttonTitle = sut.purchaseButtonTitle

        // Then
        XCTAssertEqual(buttonTitle, UserText.purchaseFreeTrialButton)
    }

    func testPurchaseButtonTitle_WhenNoSpecialOffers_ReturnsDefaultCTA() {
        // Given
        mockWinBackOfferManager.isOfferAvailable = false
        mockBlackFridayCampaignProvider.isCampaignEnabled = false
        mockFeatureFlagger.enabledFeatureFlags = [.paidAIChat]

        // When
        let buttonTitle = sut.purchaseButtonTitle

        // Then
        XCTAssertEqual(buttonTitle, UserText.purchaseButton)
    }

    func testBlackFridayDiscountPercent_ReturnsCorrectValue() {
        // Given
        mockBlackFridayCampaignProvider.discountPercent = 25

        // When
        let discount = sut.blackFridayDiscountPercent

        // Then
        XCTAssertEqual(discount, 25)
    }
}
