//
//  WKHTTPCookieStoreProviderTests.swift
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
import AIChat
import BrowserServicesKitTestsUtils

@MainActor
final class WKHTTPCookieStoreProviderTests: XCTestCase {

    private func makeCookie(name: String, domain: String) -> HTTPCookie {
        HTTPCookie(properties: [
            .name: name,
            .value: "value",
            .domain: domain,
            .path: "/"
        ])!
    }

    func testWhenCookieDomainExactlyMatchesHost_ThenCookieIsReturned() async {
        let cookie = makeCookie(name: "a", domain: "duck.ai")
        let store = MockHTTPCookieStore(allCookiesReturnValue: [cookie])
        let provider = WKHTTPCookieStoreProvider(cookieStore: store)

        let result = await provider.cookies(for: URL(string: "https://duck.ai/chat")!)

        XCTAssertEqual(result.map(\.name), ["a"])
    }

    func testWhenCookieDomainHasLeadingDot_ThenSubdomainMatches() async {
        let cookie = makeCookie(name: "a", domain: ".duck.ai")
        let store = MockHTTPCookieStore(allCookiesReturnValue: [cookie])
        let provider = WKHTTPCookieStoreProvider(cookieStore: store)

        let result = await provider.cookies(for: URL(string: "https://chat.duck.ai/")!)

        XCTAssertEqual(result.map(\.name), ["a"])
    }

    func testWhenCookieDomainDoesNotMatchHost_ThenCookieIsFilteredOut() async {
        let cookie = makeCookie(name: "a", domain: "example.com")
        let store = MockHTTPCookieStore(allCookiesReturnValue: [cookie])
        let provider = WKHTTPCookieStoreProvider(cookieStore: store)

        let result = await provider.cookies(for: URL(string: "https://duck.ai/")!)

        XCTAssertTrue(result.isEmpty)
    }

    func testWhenStoreHasMixOfMatchingAndNonMatchingCookies_ThenOnlyMatchingAreReturned() async {
        let matching = makeCookie(name: "matching", domain: "duck.ai")
        let matchingSubdomain = makeCookie(name: "matchingSubdomain", domain: ".duck.ai")
        let nonMatching = makeCookie(name: "nonMatching", domain: "example.com")
        let store = MockHTTPCookieStore(allCookiesReturnValue: [matching, matchingSubdomain, nonMatching])
        let provider = WKHTTPCookieStoreProvider(cookieStore: store)

        let result = await provider.cookies(for: URL(string: "https://duck.ai/")!)

        XCTAssertEqual(result.map(\.name), ["matching", "matchingSubdomain"])
    }

    func testWhenStoreIsEmpty_ThenNoCookiesAreReturned() async {
        let store = MockHTTPCookieStore(allCookiesReturnValue: [])
        let provider = WKHTTPCookieStoreProvider(cookieStore: store)

        let result = await provider.cookies(for: URL(string: "https://duck.ai/")!)

        XCTAssertTrue(result.isEmpty)
    }
}
