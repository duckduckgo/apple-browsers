//
//  SubscriptionManagerV2Tests+Redirect.swift
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

extension SubscriptionManagerV2Tests {

    func testWhenURLIsPrivacyProThenRedirectToSubscriptionBaseURL() throws {
        // GIVEN
        let redirectURLComponents = try XCTUnwrap(URLComponents(string: "https://www.duckduckgo.com/pro"))
        let expectedURL = SubscriptionURL.baseURL.subscriptionURL(environment: .production)

        // WHEN
        let result = subscriptionManager.urlForPurchaseFromRedirect(redirectURLComponents: redirectURLComponents, tld: Constants.tld)

        // THEN
        XCTAssertEqual(result, expectedURL)
    }

    func testWhenURLIsPrivacyProAndHasOriginQueryParameterThenRedirectToSubscriptionBaseURLAndAppendQueryParameter() throws {
        // GIVEN
        let redirectURLComponents = try XCTUnwrap(URLComponents(string: "https://www.duckduckgo.com/pro?origin=test"))
        let expectedURL = subscriptionManager.url(for: .purchase).appending(percentEncodedQueryItem: .init(name: "origin", value: "test"))

        // WHEN
        let result = subscriptionManager.urlForPurchaseFromRedirect(redirectURLComponents: redirectURLComponents, tld: Constants.tld)

        // THEN
        XCTAssertEqual(result, expectedURL)
    }

    func testWhenWhenUsingStagingAndURLHasOriginQueryParameterThenRedirectContainsAllQueryParameters() throws {
        // GIVEN
        let redirectURLComponents = try XCTUnwrap(URLComponents(string: "https://www.duckduckgo.com/pro?origin=test"))

        let stagingEnvironment = SubscriptionEnvironment(serviceEnvironment: .staging, purchasePlatform: .appStore)
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.\(#function)")!
        let stagingSubscriptionManager = DefaultSubscriptionManagerV2(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            userDefaults: userDefaults,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionEnvironment: stagingEnvironment,
            pixelHandler: MockPixelHandler(),
            tokenRecoveryHandler: {
                if let overrideTokenResponse = self.overrideTokenResponseInRecoveryHandler {
                    self.mockOAuthClient.getTokensResponse = overrideTokenResponse
                }
            }
        )

        // WHEN
        let result = stagingSubscriptionManager.urlForPurchaseFromRedirect(redirectURLComponents: redirectURLComponents, tld: Constants.tld)

        // THEN
        XCTAssertEqual(result.getParameter(named: "environment"), "staging")
        XCTAssertEqual(result.getParameter(named: "origin"), "test")
    }

    func testWhenURLIsPrivacyProWithSubdomainThenRedirectToSubscriptionBaseURLWithSubdomain() throws {
        // GIVEN
        let redirectURLComponents = try XCTUnwrap(URLComponents(string: "https://dev1.some-subdomain.duckduckgo.com/pro"))
        let expectedURL = try XCTUnwrap(URL(string: "https://dev1.some-subdomain.duckduckgo.com/subscriptions"))

        // WHEN
        let result = subscriptionManager.urlForPurchaseFromRedirect(redirectURLComponents: redirectURLComponents, tld: Constants.tld)

        // THEN
        XCTAssertEqual(result, expectedURL)
    }

    func testWhenURLIsPrivacyProWithSubdomainThenRedirectToSubscriptionBaseURLWithSubdomainAndPortAndHashFragmentAndParams() throws {
        // GIVEN
        let redirectURLComponents = try XCTUnwrap(URLComponents(string: "https://dev1.some-subdomain.duckduckgo.com:1234/pro?foo=bar#fragment"))
        let expectedURL = URL(string: "https://dev1.some-subdomain.duckduckgo.com:1234/subscriptions?foo=bar#fragment")!

        // WHEN
        let result = subscriptionManager.urlForPurchaseFromRedirect(redirectURLComponents: redirectURLComponents, tld: Constants.tld)

        // THEN
        XCTAssertEqual(result, expectedURL)
    }
}
