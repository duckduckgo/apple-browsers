//
//  SubscriptionPagesUseSubscriptionFeatureV2Tests.swift
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
@testable import DuckDuckGo_Privacy_Browser
@testable import BrowserServicesKit
@testable import Common
@testable import UserScript
@testable import Subscription
@testable import PixelKit
@testable import Freemium
@testable import DataBrokerProtection_macOS
@testable import DataBrokerProtectionCore
@testable import Networking
import SubscriptionTestingUtilities
import JWTKit

@MainActor
final class SubscriptionPagesUseSubscriptionFeatureV2Tests: XCTestCase {

    var sut: SubscriptionPagesUseSubscriptionFeatureV2!
    var mockSubscriptionManager: SubscriptionManagerMockV2!
    var mockStripePurchaseFlow: StripePurchaseFlowMockV2!
    var mockUIHandler: SubscriptionUIHandlerMock!
    var mockSubscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock!
    var mockFreemiumDBPUserStateManager: MockFreemiumDBPUserStateManager!
    var mockFreemiumDBPPixelExperimentManager: MockFreemiumDBPPixelExperimentManager!
    var mockNotificationCenter: NotificationCenter!
    var mockFreemiumDBPExperimentPixelHandler: MockFreemiumDBPExperimentPixelHandler!

    override func setUp() {
        super.setUp()

        mockSubscriptionManager = SubscriptionManagerMockV2()
        mockStripePurchaseFlow = StripePurchaseFlowMockV2(subscriptionOptionsResult: .success(.empty), prepareSubscriptionPurchaseResult: .success(.completed))
        mockUIHandler = SubscriptionUIHandlerMock( didPerformActionCallback: { _ in })
        mockSubscriptionFeatureAvailability = SubscriptionFeatureAvailabilityMock(isSubscriptionPurchaseAllowed: true, usesUnifiedFeedbackForm: false)
        mockFreemiumDBPUserStateManager = MockFreemiumDBPUserStateManager()
        mockFreemiumDBPPixelExperimentManager = MockFreemiumDBPPixelExperimentManager()
        mockNotificationCenter = NotificationCenter()
        mockFreemiumDBPExperimentPixelHandler = MockFreemiumDBPExperimentPixelHandler()

        sut = SubscriptionPagesUseSubscriptionFeatureV2(
            subscriptionManager: mockSubscriptionManager,
            stripePurchaseFlow: mockStripePurchaseFlow,
            uiHandler: mockUIHandler,
            subscriptionFeatureAvailability: mockSubscriptionFeatureAvailability,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager,
            freemiumDBPPixelExperimentManager: mockFreemiumDBPPixelExperimentManager,
            notificationCenter: mockNotificationCenter,
            freemiumDBPExperimentPixelHandler: mockFreemiumDBPExperimentPixelHandler
        )
    }

    override func tearDown() {
        sut = nil
        mockSubscriptionManager = nil
        mockStripePurchaseFlow = nil
        mockUIHandler = nil
        mockSubscriptionFeatureAvailability = nil
        mockFreemiumDBPUserStateManager = nil
        mockFreemiumDBPPixelExperimentManager = nil
        mockNotificationCenter = nil
        mockFreemiumDBPExperimentPixelHandler = nil
        super.tearDown()
    }

    func testGetFeatureConfig_WhenPaidAIChatEnabled_ReturnsCorrectConfig() async throws {
        // Given
        mockSubscriptionFeatureAvailability.isPaidAIChatEnabled = true

        // When
        let result = try await sut.getFeatureConfig(params: "", original: MockWKScriptMessage(name: "", body: ""))

        // Then
        guard let featureValue = result as? GetFeatureValue else {
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
        guard let featureValue = result as? GetFeatureValue else {
            XCTFail("Expected GetFeatureValue type")
            return
        }

        XCTAssertTrue(featureValue.useUnifiedFeedback)
        XCTAssertTrue(featureValue.useSubscriptionsAuthV2)
        XCTAssertFalse(featureValue.useDuckAiPro)
    }
}
