//
//  SubscriptionManagerTests+CustomURL.swift
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
import Common
@testable import Subscription
import SubscriptionTestingUtilities

extension SubscriptionManagerTests {

    func testWhenCustomBaseURLIsSetAndInternalUserModeEnabledThenBaseURLIsOverriden() throws {
        // GIVEN
        let customBaseSubscriptionURL = try XCTUnwrap(URL(string: "https://custom.duckduckgo.com/test"))
        let isInternalUserEnabled = { true }

        let subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .production,
                                                              purchasePlatform: .appStore,
                                                              customBaseSubscriptionURL: customBaseSubscriptionURL)

        let subscriptionManager = DefaultSubscriptionManager(storePurchaseManager: storePurchaseManager,
                                                             accountManager: accountManager,
                                                             subscriptionEndpointService: subscriptionService,
                                                             authEndpointService: authService,
                                                             subscriptionFeatureMappingCache: subscriptionFeatureMappingCache,
                                                             subscriptionEnvironment: subscriptionEnvironment,
                                                             isInternalUserEnabled: isInternalUserEnabled)

        // WHEN
        let result = subscriptionManager.url(for: SubscriptionURL.baseURL)

        // THEN
        XCTAssertEqual(result, customBaseSubscriptionURL)
    }

    func testWhenCustomBaseURLIsSetAndInternalUserModeDisabledThenBaseURLIsDefault() throws {
        // GIVEN
        let customBaseSubscriptionURL = try XCTUnwrap(URL(string: "https://custom.duckduckgo.com/test"))
        let isInternalUserEnabled = { false }

        let subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .production,
                                                              purchasePlatform: .appStore,
                                                              customBaseSubscriptionURL: customBaseSubscriptionURL)

        let subscriptionManager = DefaultSubscriptionManager(storePurchaseManager: storePurchaseManager,
                                                             accountManager: accountManager,
                                                             subscriptionEndpointService: subscriptionService,
                                                             authEndpointService: authService,
                                                             subscriptionFeatureMappingCache: subscriptionFeatureMappingCache,
                                                             subscriptionEnvironment: subscriptionEnvironment,
                                                             isInternalUserEnabled: isInternalUserEnabled)

        // WHEN
        let result = subscriptionManager.url(for: SubscriptionURL.baseURL)

        // THEN
        XCTAssertEqual(result, SubscriptionURL.baseURL.subscriptionURL(environment: .production))
    }

    func testWhenCustomBaseURLIsNotSetAndInternalUserModeEnabledThenBaseURLIsDefault() throws {
        // GIVEN
        let isInternalUserEnabled = { true }

        let subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .production,
                                                              purchasePlatform: .appStore)

        let subscriptionManager = DefaultSubscriptionManager(storePurchaseManager: storePurchaseManager,
                                                             accountManager: accountManager,
                                                             subscriptionEndpointService: subscriptionService,
                                                             authEndpointService: authService,
                                                             subscriptionFeatureMappingCache: subscriptionFeatureMappingCache,
                                                             subscriptionEnvironment: subscriptionEnvironment,
                                                             isInternalUserEnabled: isInternalUserEnabled)

        // WHEN
        let result = subscriptionManager.url(for: SubscriptionURL.baseURL)

        // THEN
        XCTAssertEqual(result, SubscriptionURL.baseURL.subscriptionURL(environment: .production))
    }
}
