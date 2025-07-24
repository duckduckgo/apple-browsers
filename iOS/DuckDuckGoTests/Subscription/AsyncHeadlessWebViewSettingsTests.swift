//
//  AsyncHeadlessWebViewSettingsTests.swift
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
@testable import DuckDuckGo
@testable import Subscription
import SubscriptionTestingUtilities

final class AsyncHeadlessWebViewSettingsTests: XCTestCase {

    func testAllowedDomainsOnlyContainsBaseURLHostWhenInternalUserModeDisabled() async throws {
        // Given
        let baseURL = try XCTUnwrap(URL(string: "https://duckduckgo.com/subscriptions"))
        let isInternalUser = false

        // When
        let result = AsyncHeadlessWebViewSettings.makeAllowedDomains(baseURL: baseURL, isInternalUser: isInternalUser)

        // Then
        XCTAssertTrue(result.contains(baseURL.host!))
        XCTAssertTrue(result.contains("checkout.stripe.com"))
        XCTAssertEqual(2, result.count)
    }

    func testAllowedDomainsContainsCustomBaseURLHostWhenInternalUserModeDisabled() async throws {
        // Given
        let baseURL = try XCTUnwrap(URL(string: "https://use-devtesting2.duckduckgo.comc/subscriptions"))
        let isInternalUser = false

        // When
        let result = AsyncHeadlessWebViewSettings.makeAllowedDomains(baseURL: baseURL, isInternalUser: isInternalUser)

        // Then
        XCTAssertTrue(result.contains(baseURL.host!))
        XCTAssertTrue(result.contains("checkout.stripe.com"))
        XCTAssertEqual(2, result.count)
    }

    func testAllowedDomainsContainsBaseURLHostAndDUORequiredHostsWhenInternalUserModeEnabled() async throws {
        // Given
        let baseURL = try XCTUnwrap(URL(string: "https://duck.co/subscriptions"))
        let isInternalUser = true
        let domainsRequiredForDUOAuthentication = ["duckduckgo.com", "duosecurity.com", "login.microsoftonline.com"]

        // When
        let result = AsyncHeadlessWebViewSettings.makeAllowedDomains(baseURL: baseURL, isInternalUser: isInternalUser)

        // Then
        XCTAssertTrue(result.contains(baseURL.host!))
        XCTAssertTrue(result.contains("checkout.stripe.com"))

        domainsRequiredForDUOAuthentication.forEach { duoDomain in
            XCTAssertTrue(result.contains(duoDomain))
        }
    }
}
