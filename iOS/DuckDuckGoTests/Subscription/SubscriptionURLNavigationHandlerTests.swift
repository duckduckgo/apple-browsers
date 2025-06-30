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

            // Check if it's subscriptionFlow with no redirect components
            if case .subscriptionFlow(let components) = deepLinkTarget {
                return components == nil
            }
            return false
        }

        // When
        handler.navigateToSubscriptionPurchase()

        // Then
        wait(for: [expectation], timeout: 1.0)
    }

}
