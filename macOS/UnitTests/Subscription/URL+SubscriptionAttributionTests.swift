//
//  URL+SubscriptionAttributionTests.swift
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

final class URLSubscriptionAttributionTests: XCTestCase {

    func testAppendingOriginParameterIfPresent_WhenOriginIsNil_ReturnsURLUnchanged() {
        let url = URL(string: "https://duckduckgo.com/subscriptions")!

        let result = url.appendingOriginParameterIfPresent(nil)

        XCTAssertEqual(result, url)
    }

    func testAppendingOriginParameterIfPresent_WhenOriginIsProvided_AppendsOriginQueryParameter() {
        let url = URL(string: "https://duckduckgo.com/subscriptions")!

        let result = url.appendingOriginParameterIfPresent("funnel_appmenu_macos")

        let components = URLComponents(url: result, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "origin" })?.value, "funnel_appmenu_macos")
    }

    func testAppendingOriginParameterIfPresent_WhenURLHasExistingQueryParameters_PreservesThem() {
        let url = URL(string: "https://duckduckgo.com/subscriptions?foo=bar")!

        let result = url.appendingOriginParameterIfPresent("funnel_appsettings_macos")

        let components = URLComponents(url: result, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "foo" })?.value, "bar")
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "origin" })?.value, "funnel_appsettings_macos")
    }
}
