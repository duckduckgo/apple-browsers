//
//  SubscriptionURLNavigationHandlerTests.swift
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
@testable import DuckDuckGo

@MainActor
final class SubscriptionURLNavigationHandlerTests: XCTestCase {

    var handler: SubscriptionURLNavigationHandler!
    var notificationCenter: NotificationCenter!

    override func setUp() {
        super.setUp()
        handler = SubscriptionURLNavigationHandler()
        notificationCenter = NotificationCenter.default
    }

    override func tearDown() {
        handler = nil
        notificationCenter = nil
        super.tearDown()
    }

    func testNavigateToSettings_PostsCorrectNotification() {
        // Given
        let expectation = expectation(forNotification: .settingsDeepLinkNotification,
                                    object: nil) { notification in
            // Verify the notification contains the correct deep link target
            guard let deepLinkTarget = notification.object as? SettingsViewModel.SettingsDeepLinkSection else {
                XCTFail("Notification object should be SettingsDeepLinkSection")
                return false
            }
            return deepLinkTarget == .subscriptionSettings
        }

        // When
        handler.navigateToSettings()

        // Then
        wait(for: [expectation], timeout: 1.0)
    }

    func testNavigateToSubscriptionActivation_PostsCorrectNotification() {
        // Given
        let expectation = expectation(forNotification: .settingsDeepLinkNotification,
                                    object: nil) { notification in
            // Verify the notification contains the correct deep link target
            guard let deepLinkTarget = notification.object as? SettingsViewModel.SettingsDeepLinkSection else {
                XCTFail("Notification object should be SettingsDeepLinkSection")
                return false
            }

            return deepLinkTarget == .restoreFlow
        }

        // When
        handler.navigateToSubscriptionActivation()

        // Then
        wait(for: [expectation], timeout: 1.0)
    }

    func testNavigateToSubscriptionPurchase_PostsCorrectNotification() {
        // Given
        let expectation = expectation(forNotification: .settingsDeepLinkNotification,
                                    object: nil) { notification in
            // Verify the notification contains the correct deep link target
            guard let deepLinkTarget = notification.object as? SettingsViewModel.SettingsDeepLinkSection else {
                XCTFail("Notification object should be SettingsDeepLinkSection")
                return false
            }

            // Check if it's subscriptionFlow with redirect components containing query items
            if case .subscriptionFlow(let components) = deepLinkTarget {
                guard let urlComponents = components,
                      let queryItems = urlComponents.queryItems else {
                    XCTFail("URLComponents should contain query items")
                    return false
                }
                // Verify the featurePage=duckai parameter is present in query items
                let hasFeaturePage = queryItems.contains { $0.name == "featurePage" && $0.value == "duckai" }
                return hasFeaturePage
            }
            return false
        }

        // When
        handler.navigateToSubscriptionPurchase(origin: nil, featurePage: "duckai")

        // Then
        wait(for: [expectation], timeout: 1.0)
    }

    func testNavigateToSubscriptionPurchaseWithOrigin_PostsCorrectNotificationWithOriginParameter() {
        // Given
        let testOrigin = "some_origin"
        let expectation = expectation(forNotification: .settingsDeepLinkNotification,
                                      object: nil) { notification in
            // Verify the notification contains the correct deep link target
            guard let deepLinkTarget = notification.object as? SettingsViewModel.SettingsDeepLinkSection else {
                XCTFail("Notification object should be SettingsDeepLinkSection")
                return false
            }

            // Check if it's subscriptionFlow with redirect components containing query items
            if case .subscriptionFlow(let components) = deepLinkTarget {
                guard let urlComponents = components,
                      let queryItems = urlComponents.queryItems else {
                    XCTFail("URLComponents should contain query items")
                    return false
                }

                // Verify the origin parameter is present in query items
                let hasOriginParameter = queryItems.contains { $0.name == "origin" && $0.value == testOrigin }
                // Verify the featurePage=duckai parameter is present in query items
                let hasFeaturePage = queryItems.contains { $0.name == "featurePage" && $0.value == "duckai" }
                return hasOriginParameter && hasFeaturePage
            }
            return false
        }

        // When
        handler.navigateToSubscriptionPurchase(origin: testOrigin, featurePage: "duckai")

        // Then
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - navigateToSubscriptionPlans Tests

    func testNavigateToSubscriptionPlans_WithNoParameters_PostsNotificationWithNilComponents() {
        // Given
        let expectation = expectation(forNotification: .settingsDeepLinkNotification,
                                      object: nil) { notification in
            guard let deepLinkTarget = notification.object as? SettingsViewModel.SettingsDeepLinkSection else {
                XCTFail("Notification object should be SettingsDeepLinkSection")
                return false
            }

            return deepLinkTarget == .subscriptionPlanChangeFlow(redirectURLComponents: nil)
        }

        // When
        handler.navigateToSubscriptionPlans(origin: nil, featurePage: nil)

        // Then
        wait(for: [expectation], timeout: 1.0)
    }

    func testNavigateToSubscriptionPlans_PostsSubscriptionPlanChangeFlowNotification() {
        // Given
        let expectation = expectation(forNotification: .settingsDeepLinkNotification,
                                      object: nil) { notification in
            guard let deepLinkTarget = notification.object as? SettingsViewModel.SettingsDeepLinkSection else {
                XCTFail("Notification object should be SettingsDeepLinkSection")
                return false
            }

            // Verify it's subscriptionPlanChangeFlow (not subscriptionFlow)
            if case .subscriptionPlanChangeFlow(let components) = deepLinkTarget {
                guard let urlComponents = components,
                      let queryItems = urlComponents.queryItems else {
                    XCTFail("URLComponents should contain query items")
                    return false
                }
                let hasFeaturePage = queryItems.contains { $0.name == "featurePage" && $0.value == "duckai" }
                return hasFeaturePage
            }
            return false
        }

        // When
        handler.navigateToSubscriptionPlans(origin: nil, featurePage: "duckai")

        // Then
        wait(for: [expectation], timeout: 1.0)
    }

    func testNavigateToSubscriptionPlansWithOrigin_PostsNotificationWithOriginParameter() {
        // Given
        let testOrigin = "funnel_duckai_ios"
        let expectation = expectation(forNotification: .settingsDeepLinkNotification,
                                      object: nil) { notification in
            guard let deepLinkTarget = notification.object as? SettingsViewModel.SettingsDeepLinkSection else {
                XCTFail("Notification object should be SettingsDeepLinkSection")
                return false
            }

            if case .subscriptionPlanChangeFlow(let components) = deepLinkTarget {
                guard let urlComponents = components,
                      let queryItems = urlComponents.queryItems else {
                    XCTFail("URLComponents should contain query items")
                    return false
                }

                let hasOriginParameter = queryItems.contains { $0.name == "origin" && $0.value == testOrigin }
                let hasFeaturePage = queryItems.contains { $0.name == "featurePage" && $0.value == "duckai" }
                return hasOriginParameter && hasFeaturePage
            }
            return false
        }

        // When
        handler.navigateToSubscriptionPlans(origin: testOrigin, featurePage: "duckai")

        // Then
        wait(for: [expectation], timeout: 1.0)
    }

}
