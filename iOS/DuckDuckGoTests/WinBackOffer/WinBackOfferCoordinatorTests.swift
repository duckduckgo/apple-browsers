//
//  WinBackOfferCoordinatorTests.swift
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
@testable import DuckDuckGo
@testable import BrowserServicesKit
@testable import Subscription
import Core

final class WinBackOfferCoordinatorTests: XCTestCase {

    private var sut: WinBackOfferCoordinator!
    private var mockVisibilityManager: MockWinBackOfferVisibilityManager!
    private var isOnboardingCompleted: Bool!

    override func setUp() {
        super.setUp()
        mockVisibilityManager = MockWinBackOfferVisibilityManager()
        isOnboardingCompleted = true

        sut = WinBackOfferCoordinator(
            visibilityManager: mockVisibilityManager,
            isOnboardingCompleted: { [weak self] in
                self?.isOnboardingCompleted ?? false
            }
        )
    }

    override func tearDown() {
        sut = nil
        mockVisibilityManager = nil
        isOnboardingCompleted = nil
        super.tearDown()
    }

    // MARK: - shouldPresentLaunchPrompt Tests

    func testShouldPresentLaunchPrompt_WhenOnboardingNotCompleted_ReturnsFalse() {
        // Given
        isOnboardingCompleted = false
        mockVisibilityManager.shouldShowLaunchMessage = true

        // When
        let result = sut.shouldPresentLaunchPrompt()

        // Then
        XCTAssertFalse(result, "Should not present launch prompt when onboarding is not completed")
    }

    func testShouldPresentLaunchPrompt_WhenOnboardingCompletedButVisibilityManagerReturnsFalse_ReturnsFalse() {
        // Given
        isOnboardingCompleted = true
        mockVisibilityManager.shouldShowLaunchMessage = false

        // When
        let result = sut.shouldPresentLaunchPrompt()

        // Then
        XCTAssertFalse(result, "Should not present launch prompt when visibility manager returns false")
    }

    func testShouldPresentLaunchPrompt_WhenOnboardingCompletedAndVisibilityManagerReturnsTrue_ReturnsTrue() {
        // Given
        isOnboardingCompleted = true
        mockVisibilityManager.shouldShowLaunchMessage = true

        // When
        let result = sut.shouldPresentLaunchPrompt()

        // Then
        XCTAssertTrue(result, "Should present launch prompt when onboarding is completed and visibility manager returns true")
    }

    // MARK: - markLaunchPromptPresented Tests

    func testMarkLaunchPromptPresented_CallsVisibilityManagerSetLaunchMessagePresented() {
        // Given
        XCTAssertFalse(mockVisibilityManager.lastReceivedLaunchMessagePresented, "Should not have been called yet")

        // When
        sut.markLaunchPromptPresented()

        // Then
        XCTAssertTrue(mockVisibilityManager.lastReceivedLaunchMessagePresented, "Should call setLaunchMessagePresented on visibility manager")
    }

    // MARK: - handleCTAAction Tests

    func testHandleCTAAction_PostsCorrectNotification() {
        // Given
        let notificationExpectation = expectation(forNotification: .settingsDeepLinkNotification, object: nil) { notification in
            // Verify the notification contains the correct deep link
            if let deepLink = notification.object as? SettingsViewModel.SettingsDeepLinkSection {
                switch deepLink {
                case .subscriptionFlow(let redirectURLComponents):
                    // Verify URL components contain correct origin and feature page
                    guard let components = redirectURLComponents else {
                        XCTFail("Redirect URL components should not be nil")
                        return false
                    }

                    let queryItems = components.queryItems ?? []
                    let originItem = queryItems.first { $0.name == "origin" }
                    let featurePageItem = queryItems.first { $0.name == "featurePage" }

                    XCTAssertEqual(originItem?.value, SubscriptionFunnelOrigin.winBackLaunch.rawValue, "Origin should be winBackLaunch")
                    XCTAssertEqual(featurePageItem?.value, SubscriptionURL.FeaturePage.winback, "Feature page should be winback")
                    return true
                default:
                    XCTFail("Expected subscriptionFlow deep link")
                    return false
                }
            }
            XCTFail("Notification object should be a SettingsDeepLinkSection")
            return false
        }

        // When
        sut.handleCTAAction()

        // Then
        wait(for: [notificationExpectation], timeout: 1.0)
    }

    func testHandleCTAAction_CreatesCorrectURLComponents() {
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

        XCTAssertNotNil(capturedDeepLink, "Deep link should be captured")

        // Verify the deep link structure
        if case let .subscriptionFlow(redirectURLComponents) = capturedDeepLink {
            XCTAssertNotNil(redirectURLComponents, "Redirect URL components should not be nil")

            // Verify the URL components contain the expected parameters
            let queryItems = redirectURLComponents?.queryItems ?? []
            XCTAssertTrue(queryItems.contains { $0.name == "origin" && $0.value == SubscriptionFunnelOrigin.winBackLaunch.rawValue },
                         "Should contain origin parameter with value 'winBackLaunch'")
            XCTAssertTrue(queryItems.contains { $0.name == "featurePage" && $0.value == SubscriptionURL.FeaturePage.winback },
                         "Should contain featurePage parameter with value 'winback'")
        } else {
            XCTFail("Deep link should be a subscriptionFlow")
        }
    }
}
