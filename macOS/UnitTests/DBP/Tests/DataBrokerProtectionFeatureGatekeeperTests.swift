//
//  DataBrokerProtectionFeatureGatekeeperTests.swift
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
import Subscription
import SubscriptionTestingUtilities

@testable import DuckDuckGo_Privacy_Browser

final class DataBrokerProtectionFeatureGatekeeperTests: XCTestCase {

    private var sut: DefaultDataBrokerProtectionFeatureGatekeeper!
    private var mockFeatureDisabler: MockFeatureDisabler!
    private var mockFeatureAvailability: MockFeatureAvailability!
    private var mockSubscriptionBridge: SubscriptionAuthV1toV2BridgeMock!
    private var mockFreemiumDBPUserStateManager: MockFreemiumDBPUserStateManager!

    private func userDefaults() -> UserDefaults {
        UserDefaults(suiteName: "testing_\(UUID().uuidString)")!
    }

    override func setUp() {
        mockFeatureDisabler = MockFeatureDisabler()
        mockFeatureAvailability = MockFeatureAvailability()
        mockSubscriptionBridge = SubscriptionAuthV1toV2BridgeMock()
        mockFreemiumDBPUserStateManager = MockFreemiumDBPUserStateManager()
        mockFreemiumDBPUserStateManager.didActivate = false
    }

    override func tearDown() {
        mockFeatureAvailability = nil
        mockFeatureDisabler = nil
        mockFreemiumDBPUserStateManager = nil
        mockSubscriptionBridge = nil
    }

    func testWhenNoAccessTokenIsFound_butEntitlementIs_andIsNotActiveFreemiumUser_thenFeatureIsDisabled() async {
        // Given
        mockSubscriptionBridge.enabledFeatures = [.dataBrokerProtection]
        sut = DefaultDataBrokerProtectionFeatureGatekeeper(privacyConfigurationManager: MockPrivacyConfigurationManaging(),
                                                           featureDisabler: mockFeatureDisabler,
                                                           userDefaults: userDefaults(),
                                                           subscriptionAvailability: mockFeatureAvailability,
                                                           subscriptionManager: mockSubscriptionBridge,
                                                           freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        // When
        let result = (try? await sut.arePrerequisitesSatisfied()) ?? false

        // Then
        XCTAssertFalse(result)
    }

    func testWhenAccessTokenIsFound_butNoEntitlementIs_andIsNotActiveFreemiumUser_thenFeatureIsDisabled() async {
        // Given

        mockSubscriptionBridge.accessTokenResult = .success("token")
        mockFreemiumDBPUserStateManager.didActivate = false
        sut = DefaultDataBrokerProtectionFeatureGatekeeper(privacyConfigurationManager: MockPrivacyConfigurationManaging(),
                                                           featureDisabler: mockFeatureDisabler,
                                                           userDefaults: userDefaults(),
                                                           subscriptionAvailability: mockFeatureAvailability,
                                                           subscriptionManager: mockSubscriptionBridge,
                                                           freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        // When
        let result = (try? await sut.arePrerequisitesSatisfied()) ?? false

        // Then
        XCTAssertFalse(result)
    }

    func testWhenAccessTokenIsFound_butNoEntitlementIs_andIsActiveFreemiumUser_thenFeatureIsDisabled() async {
        // Given
        mockSubscriptionBridge.accessTokenResult = .success("token")
        mockFreemiumDBPUserStateManager.didActivate = true
        sut = DefaultDataBrokerProtectionFeatureGatekeeper(privacyConfigurationManager: MockPrivacyConfigurationManaging(),
                                                           featureDisabler: mockFeatureDisabler,
                                                           userDefaults: userDefaults(),
                                                           subscriptionAvailability: mockFeatureAvailability,
                                                           subscriptionManager: mockSubscriptionBridge,
                                                           freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        // When
        let result = (try? await sut.arePrerequisitesSatisfied()) ?? false

        // Then
        XCTAssertFalse(result)
    }

    func testWhenAccessTokenAndEntitlementAreNotFound_andIsNotActiveFreemiumUser_thenFeatureIsDisabled() async {
        // Given
        mockFreemiumDBPUserStateManager.didActivate = false
        sut = DefaultDataBrokerProtectionFeatureGatekeeper(privacyConfigurationManager: MockPrivacyConfigurationManaging(),
                                                           featureDisabler: mockFeatureDisabler,
                                                           userDefaults: userDefaults(),
                                                           subscriptionAvailability: mockFeatureAvailability,
                                                           subscriptionManager: mockSubscriptionBridge,
                                                           freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        // When
        let result = (try? await sut.arePrerequisitesSatisfied()) ?? false

        // Then
        XCTAssertFalse(result)
    }

    func testWhenAccessTokenAndEntitlementAreFound_andIsNotActiveFreemiumUser_thenFeatureIsEnabled() async {
        // Given
        mockSubscriptionBridge.accessTokenResult = .success("token")
        mockSubscriptionBridge.enabledFeatures = [.dataBrokerProtection]
        mockFreemiumDBPUserStateManager.didActivate = false
        sut = DefaultDataBrokerProtectionFeatureGatekeeper(privacyConfigurationManager: MockPrivacyConfigurationManaging(),
                                                           featureDisabler: mockFeatureDisabler,
                                                           userDefaults: userDefaults(),
                                                           subscriptionAvailability: mockFeatureAvailability,
                                                           subscriptionManager: mockSubscriptionBridge,
                                                           freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        // When
        let result = (try? await sut.arePrerequisitesSatisfied()) ?? false

        // Then
        XCTAssertTrue(result)
    }

    func testWhenAccessTokenAndEntitlementAreNotFound_andIsActiveFreemiumUser_thenFeatureIsEnabled() async {
        // Given
        mockFreemiumDBPUserStateManager.didActivate = true
        sut = DefaultDataBrokerProtectionFeatureGatekeeper(privacyConfigurationManager: MockPrivacyConfigurationManaging(),
                                                           featureDisabler: mockFeatureDisabler,
                                                           userDefaults: userDefaults(),
                                                           subscriptionAvailability: mockFeatureAvailability,
                                                           subscriptionManager: mockSubscriptionBridge,
                                                           freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        // When
        let result = (try? await sut.arePrerequisitesSatisfied()) ?? false

        // Then
        XCTAssertTrue(result)
    }
}

private enum MockError: Error {
    case someError
}

private class MockFeatureAvailability: SubscriptionFeatureAvailability {
    var mockFeatureAvailable: Bool = false
    var mockSubscriptionPurchaseAllowed: Bool = false

    var isSubscriptionPurchaseAllowed: Bool { mockSubscriptionPurchaseAllowed }
    var isPaidAIChatEnabled = false
    var isSupportsAlternateStripePaymentFlowEnabled = false
    var isSubscriptionPurchaseWidePixelMeasurementEnabled: Bool = false

    func reset() {
        mockFeatureAvailable = false
        mockSubscriptionPurchaseAllowed = false
        isPaidAIChatEnabled = false
        isSupportsAlternateStripePaymentFlowEnabled = false
        isSubscriptionPurchaseWidePixelMeasurementEnabled = false
    }
}
