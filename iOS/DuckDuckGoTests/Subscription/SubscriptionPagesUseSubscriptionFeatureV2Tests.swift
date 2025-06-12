//
//  SubscriptionPagesUseSubscriptionFeatureV2Tests.swift
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
import WebKit
@testable import DuckDuckGo
@testable import BrowserServicesKit
@testable import Common
@testable import UserScript
@testable import Subscription
import SubscriptionTestingUtilities

final class SubscriptionPagesUseSubscriptionFeatureV2Tests: XCTestCase {
    
    var sut: DefaultSubscriptionPagesUseSubscriptionFeatureV2!
    var mockSubscriptionManager: SubscriptionManagerMockV2!
    var mockStripePurchaseFlow: StripePurchaseFlowMockV2!
    var mockSubscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock!
    var mockNotificationCenter: NotificationCenter!

    @MainActor
    override func setUp() {
        super.setUp()
        
        mockSubscriptionManager = SubscriptionManagerMockV2()
        mockStripePurchaseFlow = StripePurchaseFlowMockV2(subscriptionOptionsResult: .success(.empty), prepareSubscriptionPurchaseResult: .success(.completed))
        mockSubscriptionFeatureAvailability = SubscriptionFeatureAvailabilityMock(isSubscriptionPurchaseAllowed: true)
        mockNotificationCenter = NotificationCenter()

        sut = DefaultSubscriptionPagesUseSubscriptionFeatureV2(
            subscriptionManager: mockSubscriptionManager,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            subscriptionAttributionOrigin: "",
            appStorePurchaseFlow: AppStorePurchaseFlowMockV2(),
            appStoreRestoreFlow: AppStoreRestoreFlowMockV2(),
            privacyProDataReporter: nil,
            subscriptionFreeTrialsHelper: MockSubscriptionFreeTrialsHelping())
    }
    
    override func tearDown() {
        sut = nil
        mockSubscriptionManager = nil
        mockStripePurchaseFlow = nil
        mockSubscriptionFeatureAvailability = nil
        mockNotificationCenter = nil
        super.tearDown()
    }
    
    func testGetFeatureConfig_WhenPaidAIChatEnabled_ReturnsCorrectConfig() async throws {
        // Given
        mockSubscriptionFeatureAvailability.isPaidAIChatEnabled = true

        // When
        let result = try await sut.getFeatureConfig(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        guard let featureValue = result as? GetFeatureConfigurationResponse else {
            XCTFail("Expected GetFeatureValue type")
            return
        }
        
        XCTAssertTrue(featureValue.useUnifiedFeedback)
        XCTAssertTrue(featureValue.useSubscriptionsAuthV2)
        XCTAssertTrue(featureValue.useDuckAiPro)
    }
    
    func testGetFeatureConfig_WhenPaidAIChatDisabled_ReturnsCorrectConfig() async throws {
        // Given
        mockSubscriptionFeatureAvailability.isPaidAIChatEnabled = false

        // When
        let result = try await sut.getFeatureConfig(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        guard let featureValue = result as? GetFeatureConfigurationResponse else {
            XCTFail("Expected GetFeatureValue type")
            return
        }

        XCTAssertTrue(featureValue.useUnifiedFeedback)
        XCTAssertTrue(featureValue.useSubscriptionsAuthV2)
        XCTAssertFalse(featureValue.useDuckAiPro)
    }
}
