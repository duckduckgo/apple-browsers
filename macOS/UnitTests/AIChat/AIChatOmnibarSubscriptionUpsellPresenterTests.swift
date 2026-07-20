//
//  AIChatOmnibarSubscriptionUpsellPresenterTests.swift
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

import Testing
import Foundation
import AIChat
@testable import DuckDuckGo_Privacy_Browser
import Subscription
import SubscriptionTestingUtilities

@MainActor
struct AIChatOmnibarSubscriptionUpsellPresenterTests {

    // MARK: - Test Setup

    private func createPresenter() -> (AIChatOmnibarSubscriptionUpsellPresenter, MockSubscriptionTabsShowing, SubscriptionManagerMock) {
        let mockTabShower = MockSubscriptionTabsShowing()
        let mockSubscriptionManager = SubscriptionManagerMock()
        let coordinator = SubscriptionNavigationCoordinator(
            tabShower: mockTabShower,
            subscriptionManager: mockSubscriptionManager
        )
        let presenter = AIChatOmnibarSubscriptionUpsellPresenter(coordinator: coordinator)
        return (presenter, mockTabShower, mockSubscriptionManager)
    }

    // MARK: - Tests

    @available(iOS 16, macOS 13, *)
    @Test("Free user gated to plus routes to the purchase flow", .timeLimit(.minutes(1)))
    func freeUserGatedToPlusRoutesToPurchase() async throws {
        let (presenter, mockTabShower, mockSubscriptionManager) = createPresenter()
        mockSubscriptionManager.resultURL = URL(string: "https://duckduckgo.com/pro/purchase")!

        let routed = presenter.routeGatedSelection(requiredTier: .plus, userTier: .free, origin: .addressBarModelPicker)

        #expect(routed == true)
        guard case let .subscription(url) = mockTabShower.capturedContent else {
            Issue.record("Expected .subscription tab content")
            return
        }
        #expect(url.absoluteString.contains("featurePage=duckai"))
        #expect(url.absoluteString.contains("origin=funnel_addressbar_macos__modelpicker"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Free user gated to pro also routes to the purchase flow", .timeLimit(.minutes(1)))
    func freeUserGatedToProRoutesToPurchase() async throws {
        let (presenter, mockTabShower, mockSubscriptionManager) = createPresenter()
        mockSubscriptionManager.resultURL = URL(string: "https://duckduckgo.com/pro/purchase")!

        let routed = presenter.routeGatedSelection(requiredTier: .pro, userTier: .free, origin: .addressBarReasoningPicker)

        #expect(routed == true)
        guard case let .subscription(url) = mockTabShower.capturedContent else {
            Issue.record("Expected .subscription tab content")
            return
        }
        #expect(url.absoluteString.contains("origin=funnel_addressbar_macos__reasoningpicker"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Plus user gated to pro routes to the upgrade (plans) flow", .timeLimit(.minutes(1)))
    func plusUserGatedToProRoutesToUpgrade() async throws {
        let (presenter, mockTabShower, mockSubscriptionManager) = createPresenter()
        mockSubscriptionManager.resultURL = URL(string: "https://duckduckgo.com/subscriptions")!

        let routed = presenter.routeGatedSelection(requiredTier: .pro, userTier: .plus, origin: .addressBarModelPicker)

        #expect(routed == true)
        guard case let .subscription(url) = mockTabShower.capturedContent else {
            Issue.record("Expected .subscription tab content")
            return
        }
        #expect(url.host == "duckduckgo.com")
        #expect(url.path == "/subscriptions")
        #expect(url.absoluteString.contains("featurePage=duckai"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Pro user has no gated flow and nothing is presented", .timeLimit(.minutes(1)))
    func proUserHasNoGatedFlow() async throws {
        let (presenter, mockTabShower, _) = createPresenter()

        let routed = presenter.routeGatedSelection(requiredTier: .plus, userTier: .pro, origin: .addressBarModelPicker)

        #expect(routed == false)
        #expect(mockTabShower.capturedContent == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Internal user has no gated flow and nothing is presented", .timeLimit(.minutes(1)))
    func internalUserHasNoGatedFlow() async throws {
        let (presenter, mockTabShower, _) = createPresenter()

        let routed = presenter.routeGatedSelection(requiredTier: .pro, userTier: .internal, origin: .addressBarReasoningPicker)

        #expect(routed == false)
        #expect(mockTabShower.capturedContent == nil)
    }
}
