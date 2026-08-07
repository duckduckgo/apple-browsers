//
//  SubscriptionPromoExistingUserCoordinatorTests.swift
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

final class SubscriptionPromoExistingUserCoordinatorTests: XCTestCase {

    private var sut: SubscriptionPromoExistingUserCoordinator!
    private var mockDaxDialogs: MockDaxOnboardingGating!
    private var mockSettings: MockDaxDialogsSettings!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockTutorialSettings: MockTutorialSettings!
    private var mockStatisticsStore: MockStatisticsStore!
    private var mockSubscriptionManager: SubscriptionManagerMock!

    override func setUpWithError() throws {
        mockDaxDialogs = MockDaxOnboardingGating()
        mockSettings = MockDaxDialogsSettings()
        mockFeatureFlagger = MockFeatureFlagger()
        mockTutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        mockStatisticsStore = MockStatisticsStore()
        mockSubscriptionManager = SubscriptionManagerMock()

        sut = makeSUT()
    }

    override func tearDownWithError() throws {
        sut = nil
        mockDaxDialogs = nil
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
        mockDaxDialogs.subscriptionPromotionDialogSeen = true

        // Then
        XCTAssertFalse(sut.shouldPresentLaunchPrompt())
    }

    func testShouldNotPresentWhenExistingUsersFlagDisabled() {
        // Given
        configureEligible()
        mockFeatureFlagger.enabledFeatureFlags = [.privacyProOnboardingPromotion]

        // Then
        XCTAssertFalse(sut.shouldPresentLaunchPrompt())
    }

    func testShouldNotPresentWhenPromoFlagDisabled() {
        // Given
        configureEligible()
        mockFeatureFlagger.enabledFeatureFlags = [.subscriptionPromoForExistingUsers]

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

    func testShouldPresentRegardlessOfOnboardingSkipState() {
        // Given
        configureEligible()
        mockStatisticsStore.variant = nil

        // Then
        XCTAssertTrue(sut.shouldPresentLaunchPrompt())
    }

    // MARK: - Onboarding gating (per-coordinator gate via isEligibleToPresent)

    func testIsEligibleToPresentWhenOnboardingComplete() {
        XCTAssertTrue(sut.isEligibleToPresent(isOnboardingComplete: true))
    }

    func testIsEligibleToPresentWhenOnboardingNotCompleteAndNoDialogVisible() {
        mockDaxDialogs.isShowingContextualOnboardingDialog = false

        XCTAssertTrue(sut.isEligibleToPresent(isOnboardingComplete: false))
    }

    func testIsNotEligibleWhenContextualDialogCurrentlyVisible() {
        mockDaxDialogs.isShowingContextualOnboardingDialog = true

        XCTAssertFalse(sut.isEligibleToPresent(isOnboardingComplete: false))
    }

    func testIsEligibleToPresentWhenOnboardingCompleteEvenIfContextualDialogVisible() {
        // isOnboardingComplete=true short-circuits the || regardless of dialog state
        mockDaxDialogs.isShowingContextualOnboardingDialog = true

        XCTAssertTrue(sut.isEligibleToPresent(isOnboardingComplete: true))
    }

    // MARK: - markLaunchPromptPresented

    func testMarkLaunchPromptPresentedSetsFlag() {
        // When
        sut.markLaunchPromptPresented()

        // Then
        XCTAssertTrue(mockDaxDialogs.subscriptionPromotionDialogSeen)
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
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.pixelName, Pixel.Event.subscriptionExistingUserPromotionImpression.name)
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.params?[PixelParameters.returningUser], "true")
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.params?[PixelParameters.freeTrial], "true")
    }

    // MARK: - handleCTAAction origin

    func testHandleCTAPostsNotificationWithExistingUserPromoOrigin() {
        // Given
        var capturedDeepLink: SettingsViewModel.SettingsDeepLinkSection?
        let notificationExpectation = expectation(forNotification: .settingsDeepLinkNotification, object: nil) { notification in
            capturedDeepLink = notification.object as? SettingsViewModel.SettingsDeepLinkSection
            return true
        }

        // When
        sut.handleCTAAction()

        // Then
        wait(for: [notificationExpectation], timeout: 1.0)
        if case let .subscriptionFlow(redirectURLComponents) = capturedDeepLink {
            let originValue = redirectURLComponents?.queryItems?.first(where: { $0.name == "origin" })?.value
            XCTAssertEqual(originValue, SubscriptionFunnelOrigin.existingUserPromo.rawValue)
        } else {
            XCTFail("Expected subscriptionFlow deep link")
        }
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
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.pixelName, Pixel.Event.subscriptionExistingUserPromotionTap.name)
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
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.pixelName, Pixel.Event.subscriptionExistingUserPromotionDismiss.name)
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
        XCTAssertEqual(sut.proceedButtonText(), UserText.SubscriptionPromotionOnboarding.Buttons.Rebranding.tryItFree)
    }

    func testProceedButtonTextShowsLearnMoreWhenNotEligible() {
        // Given
        mockSubscriptionManager.isEligibleForFreeTrialResult = false
        sut = makeSUT()

        // Then
        XCTAssertEqual(sut.proceedButtonText(), UserText.SubscriptionPromotionOnboarding.Buttons.learnMore)
    }

    // MARK: - Helpers

    private func makeSUT() -> SubscriptionPromoExistingUserCoordinator {
        SubscriptionPromoExistingUserCoordinator(
            daxDialogs: mockDaxDialogs,
            daxDialogsSettings: mockSettings,
            featureFlagger: mockFeatureFlagger,
            tutorialSettings: mockTutorialSettings,
            statisticsStore: mockStatisticsStore,
            subscriptionManager: mockSubscriptionManager,
            pixelFiring: PixelFiringMock.self
        )
    }

    private func configureEligible() {
        mockDaxDialogs.subscriptionPromotionDialogSeen = false
        mockDaxDialogs.hasSeenOnboarding = true
        mockDaxDialogs.subscriptionPromotionPending = false
        mockFeatureFlagger.enabledFeatureFlags = [.subscriptionPromoForExistingUsers, .privacyProOnboardingPromotion]
        mockSubscriptionManager.hasAppStoreProductsAvailable = true
        mockStatisticsStore.variant = VariantIOS.returningUser.name
        mockStatisticsStore.installDate = Calendar.current.date(byAdding: .day, value: -14, to: Date())
    }
}

// MARK: - Mock

private final class MockDaxOnboardingGating: ContextualDaxDialogStatusProvider & SubscriptionPromotionCoordinating {
    var hasSeenOnboarding: Bool = true
    var isShowingContextualOnboardingDialog: Bool = false
    var isShowingSubscriptionPromotion: Bool = false
    var subscriptionPromotionDialogSeen: Bool = false
    var subscriptionPromotionPending: Bool = false
}
