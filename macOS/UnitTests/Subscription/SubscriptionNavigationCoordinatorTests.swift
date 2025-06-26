//
//  SubscriptionNavigationCoordinatorTests.swift
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

import Testing
import Foundation
import Combine
@testable import DuckDuckGo_Privacy_Browser
import BrowserServicesKit
import Subscription
import SubscriptionTestingUtilities

@MainActor
struct SubscriptionNavigationCoordinatorTests {

    // MARK: - Test Setup

    private func createCoordinator() -> (SubscriptionNavigationCoordinator, MockSubscriptionTabsShowing, SubscriptionAuthV1toV2BridgeMock) {
        let mockTabShower = MockSubscriptionTabsShowing()
        let mockSubscriptionManager = SubscriptionAuthV1toV2BridgeMock()
        let coordinator = SubscriptionNavigationCoordinator(
            tabShower: mockTabShower,
            subscriptionManager: mockSubscriptionManager
        )
        return (coordinator, mockTabShower, mockSubscriptionManager)
    }

    // MARK: - Tests

    @Test("navigateToSettings calls showPreferencesTab with subscriptionSettings pane")
    func navigateToSettings() async throws {
        let (coordinator, mockTabShower, _) = createCoordinator()

        coordinator.navigateToSettings()

        #expect(mockTabShower.capturedSettingsPane == .subscriptionSettings)
    }

    @Test("navigateToSubscriptionActivation fetches activation URL and shows subscription tab")
    func navigateToSubscriptionActivation() async throws {
        let (coordinator, mockTabShower, mockSubscriptionManager) = createCoordinator()
        let expectedURL = URL(string: "https://duckduckgo.com/pro/activate")!
        mockSubscriptionManager.urls[.activationFlow] = expectedURL

        coordinator.navigateToSubscriptionActivation()

        // Verify tab shower was called to show tab with subscription content
        #expect(mockTabShower.capturedContent != nil)

        guard case let .subscription(url) = mockTabShower.capturedContent else {
            Issue.record("Expected .subscription tab content")
            return
        }
        #expect(url == expectedURL)
    }

    @Test("navigateToSubscriptionPurchase fetches purchase URL and shows subscription tab")
    func navigateToSubscriptionPurchase() async throws {
        let (coordinator, mockTabShower, mockSubscriptionManager) = createCoordinator()
        let expectedURL = URL(string: "https://duckduckgo.com/pro/purchase")!
        mockSubscriptionManager.urls[.purchase] = expectedURL

        coordinator.navigateToSubscriptionPurchase()

        // Verify tab shower was called to show tab with subscription content
        #expect(mockTabShower.capturedContent != nil)

        guard case let .subscription(url) = mockTabShower.capturedContent else {
            Issue.record("Expected .subscription tab content")
            return
        }

        // Verify the URL matches exactly what was returned from subscription manager
        #expect(url == expectedURL)
    }

}
