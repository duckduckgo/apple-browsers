//
//  SubscriptionURLTests.swift
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
@testable import Subscription
import SubscriptionTestingUtilities

final class SubscriptionURLTests: XCTestCase {

    func testExpectedDefaultBaseSubscriptionURLForProduction() throws {
        // Given
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions")!

        // When
        let url = SubscriptionURL.baseURL.subscriptionURL(environment: .production)

        // Then
        XCTAssertEqual(url, expectedURL)
    }

    func testExpectedDefaultBaseSubscriptionURLForStaging() throws {
        // Given
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions?environment=staging")!

        // When
        let url = SubscriptionURL.baseURL.subscriptionURL(environment: .staging)

        // Then
        XCTAssertEqual(url, expectedURL)
    }

    func testProductionURLs() throws {
        let allURLTypes: [SubscriptionURL] = [.baseURL,
                                              .purchase,
                                              .welcome,
                                              .activationFlow,
                                              .activationFlowAddEmailStep,
                                              .activationFlowLinkViaEmailStep,
                                              .activationFlowSuccess,
                                              .manageEmail,
                                              .identityTheftRestoration]

        for urlType in allURLTypes {
            // When
            let url = urlType.subscriptionURL(environment: .production)

            // Then
            let environmentParameter = url.getParameter(named: "environment")
            XCTAssertEqual (environmentParameter, nil, "Wrong environment parameter for \(url.absoluteString)")
        }
    }

    func testStagingURLs() throws {
        let allURLTypes: [SubscriptionURL] = [.baseURL,
                                              .purchase,
                                              .welcome,
                                              .activationFlow,
                                              .activationFlowAddEmailStep,
                                              .activationFlowLinkViaEmailStep,
                                              .activationFlowSuccess,
                                              .manageEmail,
                                              .identityTheftRestoration]

        for urlType in allURLTypes {
            // When
            let url = urlType.subscriptionURL(environment: .staging)

            // Then
            let environmentParameter = url.getParameter(named: "environment")
            XCTAssertEqual (environmentParameter, "staging", "Wrong environment parameter for \(url.absoluteString)")
        }
    }

    func testIdentityTheftRestorationURLForProduction() throws {
        // Given
        let expectedURL = URL(string: "https://duckduckgo.com/identity-theft-restoration")!

        // When
        let url = SubscriptionURL.identityTheftRestoration.subscriptionURL(environment: .production)

        // Then
        XCTAssertEqual(url, expectedURL)
    }

    func testStaticURLs() throws {
        let faqProductionURL = SubscriptionURL.faq.subscriptionURL(environment: .production)
        let faqStagingURL = SubscriptionURL.faq.subscriptionURL(environment: .staging)

        XCTAssertEqual(faqStagingURL, faqProductionURL)
        XCTAssertEqual(faqProductionURL.absoluteString, "https://duckduckgo.com/duckduckgo-help-pages/privacy-pro/")

        let manageSubscriptionsInAppStoreProductionURL = SubscriptionURL.manageSubscriptionsInAppStore.subscriptionURL(environment: .production)
        let manageSubscriptionsInAppStoreStagingURL = SubscriptionURL.manageSubscriptionsInAppStore.subscriptionURL(environment: .staging)

        XCTAssertEqual(manageSubscriptionsInAppStoreStagingURL, manageSubscriptionsInAppStoreProductionURL)
        XCTAssertEqual(manageSubscriptionsInAppStoreProductionURL.absoluteString, "macappstores://apps.apple.com/account/subscriptions")
    }

    func testURLForComparisonRemovingEnvironment() throws {
        let url = URL(string: "https://duckduckgo.com/subscriptions?environment=staging")!
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions")!

        XCTAssertEqual(url.forComparison(), expectedURL)
    }

    func testURLForComparisonRemovesOrigin() throws {
        let url = URL(string: "https://duckduckgo.com/subscriptions?origin=test")!
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions")!

        XCTAssertEqual(url.forComparison(), expectedURL)
    }

    func testURLForComparisonRemovesEnvironmentAndOrigin() throws {
        let url = URL(string: "https://duckduckgo.com/subscriptions?environment=staging&origin=test")!
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions")!

        XCTAssertEqual(url.forComparison(), expectedURL)
    }

    func testURLForComparisonRemovesEnvironmentAndOriginButRetainsOtherParameters() throws {
        let url = URL(string: "https://duckduckgo.com/subscriptions?environment=staging&foo=bar&origin=test")!
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions?foo=bar")!

        XCTAssertEqual(url.forComparison(), expectedURL)
    }

    func testCustomBaseSubscriptionURLForProduction() throws {
        // Given
        let customBaseURL = URL(string: "https://dax.duck.co/subscriptions-test")!

        // When
        let url = SubscriptionURL.baseURL.subscriptionURL(withCustomBaseURL: customBaseURL, environment: .production)

        // Then
        XCTAssertEqual(url, customBaseURL)
    }

    func testCustomBaseSubscriptionURLForActivationFlowURL() throws {
        // Given
        let customBaseURL = URL(string: "https://dax.duck.co/subscriptions")!
        let expectedURL = customBaseURL.appendingPathComponent("activation-flow")

        // When
        let url = SubscriptionURL.activationFlow.subscriptionURL(withCustomBaseURL: customBaseURL, environment: .production)

        // Then
        XCTAssertEqual(url, expectedURL)
    }

    func testCustomBaseSubscriptionURLForIdentityTheftRestorationURL() throws {
        // Given
        let customBaseURL = URL(string: "https://dax.duck.co/subscriptions")!
        let expectedURL = URL(string: "https://dax.duck.co/identity-theft-restoration")!

        // When
        let url = SubscriptionURL.identityTheftRestoration.subscriptionURL(withCustomBaseURL: customBaseURL, environment: .production)

        // Then
        XCTAssertEqual(url, expectedURL)
    }

    func testPurchaseURLComponentsWithOriginForProduction() throws {
        // Given
        let origin = "funnel_appsettings_ios"
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions?origin=funnel_appsettings_ios")!

        // When
        let components = SubscriptionURL.purchaseURLComponentsWithOrigin(origin, environment: .production)

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.url, expectedURL)
    }

    func testPurchaseURLComponentsWithOriginForStaging() throws {
        // Given
        let origin = "funnel_appsettings_ios"
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions?environment=staging&origin=funnel_appsettings_ios")!

        // When
        let components = SubscriptionURL.purchaseURLComponentsWithOrigin(origin, environment: .staging)

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.url, expectedURL)
    }

    func testPurchaseURLComponentsWithOriginWithEmptyOrigin() throws {
        // Given
        let origin = ""
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions?origin=")!

        // When
        let components = SubscriptionURL.purchaseURLComponentsWithOrigin(origin, environment: .production)

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.url, expectedURL)
    }
}
