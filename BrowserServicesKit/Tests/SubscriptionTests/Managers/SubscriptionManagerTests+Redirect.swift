//
//  SubscriptionManagerTests+Redirect.swift
//  BrowserServicesKit
//
//  Created by Michał Smaga on 18/02/2025.
//

import XCTest
import Common
@testable import Subscription
import SubscriptionTestingUtilities

extension SubscriptionManagerTests {

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

        let stagingSubscriptionManager = DefaultSubscriptionManager(storePurchaseManager: storePurchaseManager,
                                                                    accountManager: accountManager,
                                                                    subscriptionEndpointService: subscriptionService,
                                                                    authEndpointService: authService,
                                                                    subscriptionFeatureMappingCache: subscriptionFeatureMappingCache,
                                                                    subscriptionEnvironment: stagingEnvironment)

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
