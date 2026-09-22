//
//  SubscriptionFlowTypeTests.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import Common
import Subscription
import SubscriptionTestingUtilities
@testable import DuckDuckGo

final class SubscriptionFlowTypeTests: XCTestCase {

    // MARK: - Navigation Title Tests

    func testNavigationTitle_WhenFirstPurchase_ReturnsSubscriptionTitle() {
        // Given
        let flowType = SubscriptionFlowType.firstPurchase

        // Then
        XCTAssertEqual(flowType.navigationTitle, UserText.subscriptionTitle)
    }

    func testNavigationTitle_WhenPlanUpdate_ReturnsPlansTitle() {
        // Given
        let flowType = SubscriptionFlowType.planUpdate

        // Then
        XCTAssertEqual(flowType.navigationTitle, UserText.subscriptionPlansTitle)
    }

    // MARK: - Shows Dax Logo Tests

    func testShowsDaxLogo_WhenFirstPurchase_ReturnsTrue() {
        // Given
        let flowType = SubscriptionFlowType.firstPurchase

        // Then
        XCTAssertTrue(flowType.showsDaxLogo)
    }

    func testShowsDaxLogo_WhenPlanUpdate_ReturnsFalse() {
        // Given
        let flowType = SubscriptionFlowType.planUpdate

        // Then
        XCTAssertFalse(flowType.showsDaxLogo)
    }

    // MARK: - Impression Pixel Tests

    func testImpressionPixel_WhenFirstPurchase_ReturnsOfferScreenImpression() {
        // Given
        let flowType = SubscriptionFlowType.firstPurchase

        // Then
        XCTAssertEqual(flowType.impressionPixel, .subscriptionOfferScreenImpression)
    }

    func testImpressionPixel_WhenPlanUpdate_ReturnsNil() {
        // Given
        let flowType = SubscriptionFlowType.planUpdate

        // Then
        XCTAssertNil(flowType.impressionPixel)
    }
}

final class SubscribeFlowInitialURLBuilderTests: XCTestCase {

    private let purchaseURL = URL(string: "https://duckduckgo.com/subscriptions")!
    private let performanceOptimizedPaywallURL = URL(string: "https://duckduckgo.com/subscriptions/new/mobile/vpn?trial=false")!
    private let performanceOptimizedPaywalls = MockPerformanceOptimizedPaywallsProvider()

    func testWhenPerformanceOptimizedPaywallsAreEnabledAndUserIsNotSubscribedThenReturnsPerformanceOptimizedPaywallURL() {
        let subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.resultURL = purchaseURL

        let initialURL = SubscribeFlowInitialURLBuilder.makeInitialURL(
            redirectURLComponents: nil,
            landingURL: nil,
            subscriptionManager: subscriptionManager,
            tld: TLD(),
            performanceOptimizedPaywalls: performanceOptimizedPaywalls
        )

        XCTAssertEqual(initialURL, performanceOptimizedPaywallURL)
    }

    func testWhenPerformanceOptimizedPaywallsAreEnabledAndUserIsSubscribedThenReturnsLegacyPurchaseURL() {
        let subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.resultURL = purchaseURL
        subscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(status: .autoRenewable))

        let initialURL = SubscribeFlowInitialURLBuilder.makeInitialURL(
            redirectURLComponents: nil,
            landingURL: nil,
            subscriptionManager: subscriptionManager,
            tld: TLD(),
            performanceOptimizedPaywalls: performanceOptimizedPaywalls
        )

        XCTAssertEqual(initialURL, purchaseURL)
    }
}

private struct MockPerformanceOptimizedPaywallsProvider: PerformanceOptimizedPaywallsProviding {
    let isEnabled = true
    let paths = SubscriptionURL.PerformanceOptimizedPaywallPaths.default
}
