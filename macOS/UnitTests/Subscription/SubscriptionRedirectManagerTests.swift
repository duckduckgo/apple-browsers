//
//  SubscriptionRedirectManagerTests.swift
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
import Common
import BrowserServicesKit
@testable import DuckDuckGo_Privacy_Browser

final class SubscriptionRedirectManagerTests: XCTestCase {

    private struct Constants {
        static let environment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)
        static let redirectURL = SubscriptionURL.baseURL.subscriptionURL(environment: .production)
    }

    var subscriptionManager: SubscriptionManagerMock!

    private var canPurchase: Bool = true
    private var mockInternalUserStoring: MockInternalUserStoring! = MockInternalUserStoring()

    private var sut: PrivacyProSubscriptionRedirectManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.currentEnvironment = Constants.environment

        mockInternalUserStoring.isInternalUser = false

        sut = PrivacyProSubscriptionRedirectManager(subscriptionManager: subscriptionManager,
                                                    baseURL: Constants.redirectURL,
                                                    tld: TLD(),
                                                    featureFlagger: MockFeatureFlagger(internalUserDecider: DefaultInternalUserDecider(store: mockInternalUserStoring)))
    }

    override func tearDownWithError() throws {
        sut = nil
        mockInternalUserStoring = nil
        subscriptionManager = nil
    }

    func testWhenURLIsPrivacyProThenRedirectToSubscriptionBaseURL() throws {
        // GIVEN
        let url = try XCTUnwrap(URL(string: "https://www.duckduckgo.com/pro"))
        let expectedURL = SubscriptionURL.baseURL.subscriptionURL(environment: .production)

        // WHEN
        subscriptionManager.urlForPurchaseFromRedirect = expectedURL
        subscriptionManager.canPurchase = true
        let result = sut.redirectURL(for: url)

        // THEN
        XCTAssertEqual(result, expectedURL)
    }

    func testWhenURLIsPrivacyProAndPurchaseIsNotAllowedThenRedirectReturnsNil() throws {
        // GIVEN
        let url = try XCTUnwrap(URL(string: "https://www.duckduckgo.com/pro?origin=test"))

        // WHEN
        self.canPurchase = false
        let result = sut.redirectURL(for: url)

        // THEN
        XCTAssertNil(result)
    }

    func testWhenURLBelongsToTestDomainAndInternalModeIsDisabledThenNoRedirectTriggers() throws {
        // GIVEN
        let url = try XCTUnwrap(URL(string: "https://www.duck.co/pro"))
        let expectedURL = SubscriptionURL.baseURL.subscriptionURL(environment: .production)
        mockInternalUserStoring.isInternalUser = false

        // WHEN
        subscriptionManager.urlForPurchaseFromRedirect = expectedURL
        let result = sut.redirectURL(for: url)

        // THEN
        XCTAssertNotEqual(result, expectedURL)
        XCTAssertNotEqual(result, url)
    }

    func testWhenURLBelongsToTestDomainAndInternalModeIsEnabledThenRedirectTriggers() throws {
        // GIVEN
        let url = try XCTUnwrap(URL(string: "https://www.duck.co/pro"))
        let expectedURL = SubscriptionURL.baseURL.subscriptionURL(environment: .production)
        mockInternalUserStoring.isInternalUser = true

        // WHEN
        subscriptionManager.urlForPurchaseFromRedirect = expectedURL
        subscriptionManager.canPurchase = true
        let result = sut.redirectURL(for: url)

        // THEN
        XCTAssertEqual(result, expectedURL)
    }
}
