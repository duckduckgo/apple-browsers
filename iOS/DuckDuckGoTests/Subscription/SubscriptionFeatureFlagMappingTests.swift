//
//  SubscriptionFeatureFlagMappingTests.swift
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
@testable import Core
@testable import DuckDuckGo
@testable import Subscription
import BrowserServicesKit
import Combine

final class SubscriptionFeatureFlagMappingTests: XCTestCase {

    let internalUserDecider = MockInternalUserDecider()
    let userDefaults = UserDefaults(suiteName: "SubscriptionFeatureFlagMappingTests")!

    func testWhenInternalUserOnSandboxButNoOverrideThenItIsNotUsed() {
        // Given
        internalUserDecider.isInternalUser = true
        let subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .staging, purchasePlatform: .appStore)
        userDefaults.storefrontRegionOverride = .none

        // When
        let subscriptionFeatureFlagMapping = SubscriptionFeatureFlagMapping(internalUserDecider: internalUserDecider,
                                                                            subscriptionEnvironment: subscriptionEnvironment,
                                                                            subscriptionUserDefaults: userDefaults)

        // Then
        XCTAssertFalse(subscriptionFeatureFlagMapping.isFeatureOn(.useSubscriptionUSARegionOverride))
        XCTAssertFalse(subscriptionFeatureFlagMapping.isFeatureOn(.useSubscriptionROWRegionOverride))
    }

    func testWhenInternalUserOnSandboxAndOverrideSetToUSAThenItIsUsed() {
        // Given
        internalUserDecider.isInternalUser = true
        let subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .staging, purchasePlatform: .appStore)
        userDefaults.storefrontRegionOverride = .usa

        // When
        let subscriptionFeatureFlagMapping = SubscriptionFeatureFlagMapping(internalUserDecider: internalUserDecider,
                                                                            subscriptionEnvironment: subscriptionEnvironment,
                                                                            subscriptionUserDefaults: userDefaults)

        // Then
        XCTAssertTrue(subscriptionFeatureFlagMapping.isFeatureOn(.useSubscriptionUSARegionOverride))
        XCTAssertFalse(subscriptionFeatureFlagMapping.isFeatureOn(.useSubscriptionROWRegionOverride))
    }

    func testWhenInternalUserOnSandboxAndOverrideSetToROWThenItIsUsed() {
        // Given
        internalUserDecider.isInternalUser = true
        let subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .staging, purchasePlatform: .appStore)
        userDefaults.storefrontRegionOverride = .restOfWorld

        // When
        let subscriptionFeatureFlagMapping = SubscriptionFeatureFlagMapping(internalUserDecider: internalUserDecider,
                                                                            subscriptionEnvironment: subscriptionEnvironment,
                                                                            subscriptionUserDefaults: userDefaults)

        // Then
        XCTAssertFalse(subscriptionFeatureFlagMapping.isFeatureOn(.useSubscriptionUSARegionOverride))
        XCTAssertTrue(subscriptionFeatureFlagMapping.isFeatureOn(.useSubscriptionROWRegionOverride))
    }

    func testWhenOnSandboxAndWithOverrideSetButInternalUserDisabledThenOverrideIsNotUsed() {
        // Given
        internalUserDecider.isInternalUser = false
        let subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .staging, purchasePlatform: .appStore)
        userDefaults.storefrontRegionOverride = .usa

        // When
        let subscriptionFeatureFlagMapping = SubscriptionFeatureFlagMapping(internalUserDecider: internalUserDecider,
                                                                            subscriptionEnvironment: subscriptionEnvironment,
                                                                            subscriptionUserDefaults: userDefaults)

        // Then
        XCTAssertFalse(subscriptionFeatureFlagMapping.isFeatureOn(.useSubscriptionUSARegionOverride))
        XCTAssertFalse(subscriptionFeatureFlagMapping.isFeatureOn(.useSubscriptionROWRegionOverride))
    }

    func testWhenInternalUserAndOverrideSetButOnProductionThenOverrideIsNotUsed() {
        // Given
        internalUserDecider.isInternalUser = true
        let subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)
        userDefaults.storefrontRegionOverride = .restOfWorld

        // When
        let subscriptionFeatureFlagMapping = SubscriptionFeatureFlagMapping(internalUserDecider: internalUserDecider,
                                                                            subscriptionEnvironment: subscriptionEnvironment,
                                                                            subscriptionUserDefaults: userDefaults)

        // Then
        XCTAssertFalse(subscriptionFeatureFlagMapping.isFeatureOn(.useSubscriptionUSARegionOverride))
        XCTAssertFalse(subscriptionFeatureFlagMapping.isFeatureOn(.useSubscriptionROWRegionOverride))
    }
}
