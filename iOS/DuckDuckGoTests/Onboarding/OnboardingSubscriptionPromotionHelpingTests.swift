//
//  OnboardingSubscriptionPromotionHelpingTests.swift
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
import Core
import SubscriptionTestingUtilities
@testable import DuckDuckGo

final class OnboardingSubscriptionPromotionHelpingTests: XCTestCase {

    private var sut: OnboardingSubscriptionPromotionHelping!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockSubscriptionManager: SubscriptionManagerMock!
    private var mockPixelFiring: PixelFiringMock!
    private var mockTutorialSettings: MockTutorialSettings!
    private var mockStatisticsStore: MockStatisticsStore!
    private var currentDate: Date!

    override func setUpWithError() throws {
        mockFeatureFlagger = MockFeatureFlagger()
        mockSubscriptionManager = SubscriptionManagerMock()
        mockTutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        mockStatisticsStore = MockStatisticsStore()
        currentDate = Date()

        sut = OnboardingSubscriptionPromotionHelper(
            featureFlagger: mockFeatureFlagger,
            subscriptionManager: mockSubscriptionManager,
            pixelFiring: PixelFiringMock.self,
            tutorialSettings: mockTutorialSettings,
            statisticsStore: mockStatisticsStore,
            currentDateProvider: { [unowned self] in self.currentDate }
        )
    }

    override func tearDownWithError() throws {
        sut = nil
        mockFeatureFlagger = nil
        mockSubscriptionManager = nil
        mockTutorialSettings = nil
        mockStatisticsStore = nil
        currentDate = nil
        PixelFiringMock.tearDown()
    }

    // MARK: - proceedButtonText Tests

    func testReturnsFreeTrialTextWhenUserIsEligibleForFreeTrial() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [FeatureFlag.privacyProOnboardingPromotion]
        mockSubscriptionManager.isEligibleForFreeTrialResult = true

        // When
        let result = sut.proceedButtonText

        // Then
        XCTAssertEqual(result, UserText.SubscriptionPromotionOnboarding.Buttons.tryItForFree)
    }

    func testReturnsNonFreeTrialTextWhenUserIsNotEligibleForFreeTrial() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [FeatureFlag.privacyProOnboardingPromotion]
        mockSubscriptionManager.isEligibleForFreeTrialResult = false

        // When
        let result = sut.proceedButtonText

        // Then
        XCTAssertEqual(result, UserText.SubscriptionPromotionOnboarding.Buttons.learnMore)
    }

    // MARK: - isFeatureEnabled Tests

    func testIsFeatureEnabledWhenFeatureFlagEnabledAndCanPurchase() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [FeatureFlag.privacyProOnboardingPromotion]
        mockSubscriptionManager.hasAppStoreProductsAvailable = true

        // When
        let result = sut.isFeatureEnabled

        // Then
        XCTAssertTrue(result)
    }

    func testIsFeatureNotEnabledWhenFeatureFlagDisabled() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []
        mockSubscriptionManager.hasAppStoreProductsAvailable = true

        // When
        let result = sut.isFeatureEnabled

        // Then
        XCTAssertFalse(result)
    }

    func testIsFeatureNotEnabledWhenCannotPurchase() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [FeatureFlag.privacyProOnboardingPromotion]
        mockSubscriptionManager.hasAppStoreProductsAvailable = false

        // When
        let result = sut.isFeatureEnabled

        // Then
        XCTAssertFalse(result)
    }

    // MARK: - shouldDisplay Tests

    func testShouldNotDisplayAfterSkipWhenInstallDateIsNil() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.privacyProOnboardingPromotion, .subscriptionPromoForReinstallers]
        mockSubscriptionManager.hasAppStoreProductsAvailable = true
        mockTutorialSettings.hasSkippedOnboarding = true
        mockStatisticsStore.installDate = nil

        // When
        let result = sut.shouldDisplay

        // Then
        XCTAssertFalse(result)
    }

    func testShouldNotDisplayAfterSkipWhenInstalledLessThan7DaysAgo() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.privacyProOnboardingPromotion, .subscriptionPromoForReinstallers]
        mockSubscriptionManager.hasAppStoreProductsAvailable = true
        mockTutorialSettings.hasSkippedOnboarding = true
        mockStatisticsStore.installDate = Calendar.current.date(byAdding: .day, value: -6, to: currentDate)

        // When
        let result = sut.shouldDisplay

        // Then
        XCTAssertFalse(result)
    }

    func testShouldDisplayAfterSkipWhenInstalledExactly7DaysAgo() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.privacyProOnboardingPromotion, .subscriptionPromoForReinstallers]
        mockSubscriptionManager.hasAppStoreProductsAvailable = true
        mockTutorialSettings.hasSkippedOnboarding = true
        mockStatisticsStore.installDate = Calendar.current.date(byAdding: .day, value: -7, to: currentDate)

        // When
        let result = sut.shouldDisplay

        // Then
        XCTAssertTrue(result)
    }

    func testShouldDisplayAfterSkipWhenInstalledMoreThan7DaysAgo() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.privacyProOnboardingPromotion, .subscriptionPromoForReinstallers]
        mockSubscriptionManager.hasAppStoreProductsAvailable = true
        mockTutorialSettings.hasSkippedOnboarding = true
        mockStatisticsStore.installDate = Calendar.current.date(byAdding: .day, value: -14, to: currentDate)

        // When
        let result = sut.shouldDisplay

        // Then
        XCTAssertTrue(result)
    }

    func testShouldNotDisplayAfterSkipWhenNotSkipped() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.privacyProOnboardingPromotion, .subscriptionPromoForReinstallers]
        mockSubscriptionManager.hasAppStoreProductsAvailable = true
        mockTutorialSettings.hasSkippedOnboarding = false

        // When
        let result = sut.shouldDisplay

        // Then
        XCTAssertFalse(result)
    }

    func testShouldNotDisplayAfterSkipWhenReinstallerPromoFlagDisabled() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.privacyProOnboardingPromotion]
        mockSubscriptionManager.hasAppStoreProductsAvailable = true
        mockTutorialSettings.hasSkippedOnboarding = true
        mockStatisticsStore.installDate = Calendar.current.date(byAdding: .day, value: -30, to: currentDate)

        // When
        let result = sut.shouldDisplay

        // Then
        XCTAssertFalse(result)
    }

    func testShouldNotDisplayAfterSkipWhenBaseEligibilityFalse() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []
        mockSubscriptionManager.hasAppStoreProductsAvailable = true
        mockTutorialSettings.hasSkippedOnboarding = true
        mockStatisticsStore.installDate = Calendar.current.date(byAdding: .day, value: -30, to: currentDate)

        // When
        let result = sut.shouldDisplay

        // Then
        XCTAssertFalse(result)
    }

    // MARK: - Pixel Firing Tests

    func testFireImpressionPixelIncludesReturningUserAndFreeTrialParams() {
        // Given
        mockStatisticsStore.variant = VariantIOS.returningUser.name
        mockSubscriptionManager.isEligibleForFreeTrialResult = true

        // When
        sut.fireImpressionPixel()

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.pixelName, Pixel.Event.subscriptionOnboardingPromotionImpression.name)
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.params?[PixelParameters.returningUser], "true")
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.params?[PixelParameters.freeTrial], "true")
    }

    func testFireImpressionPixelForNewUserNotEligibleForFreeTrial() {
        // Given
        mockStatisticsStore.variant = nil
        mockSubscriptionManager.isEligibleForFreeTrialResult = false

        // When
        sut.fireImpressionPixel()

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.params?[PixelParameters.returningUser], "false")
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.params?[PixelParameters.freeTrial], "false")
    }

    func testFireTapPixelIncludesReturningUserAndFreeTrialParams() {
        // Given
        mockStatisticsStore.variant = nil
        mockSubscriptionManager.isEligibleForFreeTrialResult = true

        // When
        sut.fireTapPixel()

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.pixelName, Pixel.Event.subscriptionOnboardingPromotionTap.name)
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.params?[PixelParameters.returningUser], "false")
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.params?[PixelParameters.freeTrial], "true")
    }

    func testFireDismissPixelIncludesReturningUserAndFreeTrialParams() {
        // Given
        mockStatisticsStore.variant = VariantIOS.returningUser.name
        mockSubscriptionManager.isEligibleForFreeTrialResult = true

        // When
        sut.fireDismissPixel()

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.pixelName, Pixel.Event.subscriptionOnboardingPromotionDismiss.name)
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.params?[PixelParameters.returningUser], "true")
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.params?[PixelParameters.freeTrial], "true")
    }

    // MARK: - Redirect URL Tests

    func testRedirectURLReturningUserFreeTrial() {
        // Given
        mockStatisticsStore.variant = VariantIOS.returningUser.name
        mockSubscriptionManager.isEligibleForFreeTrialResult = true

        // When
        let components = sut.redirectURLComponents()

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "origin" })?.value, SubscriptionFunnelOrigin.onboardingReinstallFreeTrial.rawValue)
    }

    func testRedirectURLReturningUserSubscribe() {
        // Given
        mockStatisticsStore.variant = VariantIOS.returningUser.name
        mockSubscriptionManager.isEligibleForFreeTrialResult = false

        // When
        let components = sut.redirectURLComponents()

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "origin" })?.value, SubscriptionFunnelOrigin.onboardingReinstallSubscribe.rawValue)
    }

    func testRedirectURLNewUserFreeTrial() {
        // Given
        mockStatisticsStore.variant = nil
        mockSubscriptionManager.isEligibleForFreeTrialResult = true

        // When
        let components = sut.redirectURLComponents()

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "origin" })?.value, SubscriptionFunnelOrigin.onboardingNewInstallFreeTrial.rawValue)
    }

    func testRedirectURLNewUserSubscribe() {
        // Given
        mockStatisticsStore.variant = nil
        mockSubscriptionManager.isEligibleForFreeTrialResult = false

        // When
        let components = sut.redirectURLComponents()

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "origin" })?.value, SubscriptionFunnelOrigin.onboardingNewInstallSubscribe.rawValue)
    }
}
