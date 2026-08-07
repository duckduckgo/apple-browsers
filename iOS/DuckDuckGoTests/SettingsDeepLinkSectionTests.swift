//
//  SettingsDeepLinkSectionTests.swift
//  DuckDuckGo
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

import XCTest
import Subscription
@testable import DuckDuckGo

final class SettingsDeepLinkSectionTests: XCTestCase {

    private typealias DeepLink = SettingsViewModel.SettingsDeepLinkSection

    func testIsOnboardingSubscriptionFlow_whenSubscriptionFlowCarriesOnboardingOrigin() {
        let section = DeepLink.subscriptionFlow(redirectURLComponents: components(origin: SubscriptionFunnelOrigin.onboarding.rawValue))
        XCTAssertTrue(section.isOnboardingSubscriptionFlow)
    }

    func testIsNotOnboardingSubscriptionFlow_forNonOnboardingOrigin() {
        let section = DeepLink.subscriptionFlow(redirectURLComponents: components(origin: SubscriptionFunnelOrigin.appSettings.rawValue))
        XCTAssertFalse(section.isOnboardingSubscriptionFlow)
    }

    func testIsNotOnboardingSubscriptionFlow_whenComponentsAreNil() {
        let section = DeepLink.subscriptionFlow(redirectURLComponents: nil)
        XCTAssertFalse(section.isOnboardingSubscriptionFlow)
    }

    func testIsNotOnboardingSubscriptionFlow_whenOriginQueryItemIsMissing() {
        let section = DeepLink.subscriptionFlow(redirectURLComponents: components(origin: nil))
        XCTAssertFalse(section.isOnboardingSubscriptionFlow)
    }

    func testIsNotOnboardingSubscriptionFlow_forNonSubscriptionFlowSections() {
        XCTAssertFalse(DeepLink.subscriptionSettings.isOnboardingSubscriptionFlow)
        XCTAssertFalse(DeepLink.dbp.isOnboardingSubscriptionFlow)
        XCTAssertFalse(DeepLink.general.isOnboardingSubscriptionFlow)
    }

    func testIsNotOnboardingSubscriptionFlow_forPlanChangeFlowEvenWithOnboardingOrigin() {
        let section = DeepLink.subscriptionPlanChangeFlow(redirectURLComponents: components(origin: SubscriptionFunnelOrigin.onboarding.rawValue))
        XCTAssertFalse(section.isOnboardingSubscriptionFlow)
    }

    private func components(origin: String?) -> URLComponents {
        var components = URLComponents()
        if let origin {
            components.queryItems = [URLQueryItem(name: AttributionParameter.origin, value: origin)]
        }
        return components
    }
}
