//
//  SubscriptionPromoCoordinatorTests.swift
//  DuckDuckGo
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
import Core
import SubscriptionTestingUtilities
@testable import DuckDuckGo

final class SubscriptionPromoCoordinatorTests: XCTestCase {

    private var sut: SubscriptionPromoCoordinator!
    private var mockSettings: MockDaxDialogsSettings!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockTutorialSettings: MockTutorialSettings!
    private var mockStatisticsStore: MockStatisticsStore!
    private var mockSubscriptionManager: SubscriptionManagerMock!

    override func setUpWithError() throws {
        mockSettings = MockDaxDialogsSettings()
        mockFeatureFlagger = MockFeatureFlagger()
        mockTutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        mockStatisticsStore = MockStatisticsStore()
        mockSubscriptionManager = SubscriptionManagerMock()

        sut = makeSUT()
    }

    override func tearDownWithError() throws {
        sut = nil
        mockSettings = nil
        mockFeatureFlagger = nil
        mockTutorialSettings = nil
        mockStatisticsStore = nil
        mockSubscriptionManager = nil
        PixelFiringMock.tearDown()
    }

    // MARK: - Eligibility

    func testShouldPresentWhenAllConditionsMet() {
        // Given
        configureEligible()

        // Then
        XCTAssertTrue(sut.shouldPresentLaunchPrompt())
    }

    func testShouldNotPresentWhenAlreadyShown() {
        // Given
        configureEligible()
        mockSettings.subscriptionPromotionDialogShown = true

        // Then
        XCTAssertFalse(sut.shouldPresentLaunchPrompt())
    }

    func testShouldNotPresentWhenReinstallersFlagDisabled() {
        // Given
        configureEligible()
        mockFeatureFlagger.enabledFeatureFlags = [.privacyProOnboardingPromotion]

        // Then
        XCTAssertFalse(sut.shouldPresentLaunchPrompt())
    }

    func testShouldNotPresentWhenPromoFlagDisabled() {
        // Given
        configureEligible()
        mockFeatureFlagger.enabledFeatureFlags = [.subscriptionPromoForReinstallers]

        // Then
        XCTAssertFalse(sut.shouldPresentLaunchPrompt())
    }

    func testShouldNotPresentWhenOnboardingNotSkipped() {
        // Given
        configureEligible()
        mockTutorialSettings.hasSkippedOnboarding = false

        // Then
        XCTAssertFalse(sut.shouldPresentLaunchPrompt())
    }

    func testShouldNotPresentWhenCooldownNotPassed() {
        // Given
        configureEligible()
        mockStatisticsStore.installDate = Calendar.current.date(byAdding: .day, value: -6, to: Date())

        // Then
        XCTAssertFalse(sut.shouldPresentLaunchPrompt())
    }

    func testShouldNotPresentWhenNotReturningUser() {
        // Given
        configureEligible()
        mockStatisticsStore.variant = nil

        // Then
        XCTAssertFalse(sut.shouldPresentLaunchPrompt())
    }

    func testShouldNotPresentWhenInstallDateNil() {
        // Given
        configureEligible()
        mockStatisticsStore.installDate = nil

        // Then
        XCTAssertFalse(sut.shouldPresentLaunchPrompt())
    }

    func testShouldPresentWhenCooldownExactly7Days() {
        // Given
        configureEligible()
        mockStatisticsStore.installDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())

        // Then
        XCTAssertTrue(sut.shouldPresentLaunchPrompt())
    }

    // MARK: - markLaunchPromptPresented

    func testMarkLaunchPromptPresentedSetsFlag() {
        // When
        sut.markLaunchPromptPresented()

        // Then
        XCTAssertTrue(mockSettings.subscriptionPromotionDialogShown)
    }

    func testMarkLaunchPromptPresentedFiresImpressionPixel() {
        // Given
        mockStatisticsStore.variant = VariantIOS.returningUser.name
        mockSubscriptionManager.isEligibleForFreeTrialResult = true
        sut = makeSUT()

        // When
        sut.markLaunchPromptPresented()

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.pixelName, Pixel.Event.subscriptionOnboardingPromotionImpression.name)
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.params?[PixelParameters.returningUser], "true")
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.params?[PixelParameters.freeTrial], "true")
    }

    // MARK: - handleCTAAction pixels

    func testHandleCTAFiresTapPixelWithReturningUserParams() {
        // Given
        mockStatisticsStore.variant = VariantIOS.returningUser.name
        mockSubscriptionManager.isEligibleForFreeTrialResult = false
        sut = makeSUT()

        // When
        sut.handleCTAAction()

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.pixelName, Pixel.Event.subscriptionOnboardingPromotionTap.name)
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.params?[PixelParameters.returningUser], "true")
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.params?[PixelParameters.freeTrial], "false")
    }

    func testHandleCTAFiresTapPixelWithNewUserParams() {
        // Given
        mockStatisticsStore.variant = nil
        mockSubscriptionManager.isEligibleForFreeTrialResult = true
        sut = makeSUT()

        // When
        sut.handleCTAAction()

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.params?[PixelParameters.returningUser], "false")
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.params?[PixelParameters.freeTrial], "true")
    }

    // MARK: - handleDismissAction pixels

    func testHandleDismissFiresDismissPixel() {
        // Given
        mockStatisticsStore.variant = VariantIOS.returningUser.name
        mockSubscriptionManager.isEligibleForFreeTrialResult = true
        sut = makeSUT()

        // When
        sut.handleDismissAction()

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.pixelName, Pixel.Event.subscriptionOnboardingPromotionDismiss.name)
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.params?[PixelParameters.returningUser], "true")
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.params?[PixelParameters.freeTrial], "true")
    }

    // MARK: - Content

    func testPromoTitleReturnsDelayedTitle() {
        XCTAssertEqual(sut.promoTitle(), UserText.SubscriptionPromotionOnboarding.Promo.delayedTitle)
    }

    func testProceedButtonTextShowsFreeTrialWhenEligible() {
        // Given
        mockSubscriptionManager.isEligibleForFreeTrialResult = true
        sut = makeSUT()

        // Then
        XCTAssertEqual(sut.proceedButtonText(), UserText.SubscriptionPromotionOnboarding.Buttons.tryItForFree)
    }

    func testProceedButtonTextShowsLearnMoreWhenNotEligible() {
        // Given
        mockSubscriptionManager.isEligibleForFreeTrialResult = false
        sut = makeSUT()

        // Then
        XCTAssertEqual(sut.proceedButtonText(), UserText.SubscriptionPromotionOnboarding.Buttons.learnMore)
    }

    // MARK: - Helpers

    private func makeSUT() -> SubscriptionPromoCoordinator {
        SubscriptionPromoCoordinator(
            daxDialogsSettings: mockSettings,
            featureFlagger: mockFeatureFlagger,
            tutorialSettings: mockTutorialSettings,
            statisticsStore: mockStatisticsStore,
            subscriptionManager: mockSubscriptionManager,
            pixelFiring: PixelFiringMock.self
        )
    }

    private func configureEligible() {
        mockSettings.subscriptionPromotionDialogShown = false
        mockFeatureFlagger.enabledFeatureFlags = [.subscriptionPromoForReinstallers, .privacyProOnboardingPromotion]
        mockTutorialSettings.hasSkippedOnboarding = true
        mockStatisticsStore.variant = VariantIOS.returningUser.name
        mockStatisticsStore.installDate = Calendar.current.date(byAdding: .day, value: -14, to: Date())
    }
}
