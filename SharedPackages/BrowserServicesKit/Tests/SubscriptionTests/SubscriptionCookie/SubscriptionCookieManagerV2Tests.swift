//
//  SubscriptionCookieManagerV2Tests.swift
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
import Common
@testable import Subscription
import SubscriptionTestingUtilities
import NetworkingTestingUtils

final class SubscriptionCookieManagerV2Tests: XCTestCase {
    var subscriptionManager: SubscriptionManagerMockV2!

    var cookieStore: HTTPCookieStore!
    var subscriptionCookieManager: SubscriptionCookieManagerV2!

    override func setUp() async throws {
        subscriptionManager = SubscriptionManagerMockV2()
        cookieStore = MockHTTPCookieStore()

        subscriptionCookieManager = SubscriptionCookieManagerV2(subscriptionManager: subscriptionManager,
                                                              currentCookieStore: { self.cookieStore },
                                                              eventMapping: MockSubscriptionCookieManageEventPixelMapping(),
                                                              refreshTimeInterval: .seconds(1))
    }

    override func tearDown() async throws {
        subscriptionManager = nil
        subscriptionCookieManager = nil
    }

    func testSubscriptionCookieIsAddedWhenSigningInToSubscription() async throws {
        // Given
        await ensureNoSubscriptionCookieInTheCookieStore()
        subscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()

        // When
        subscriptionCookieManager.enableSettingSubscriptionCookie()
        NotificationCenter.default.post(name: .accountDidSignIn, object: self, userInfo: nil)
        try await Task.sleep(interval: 0.1)

        // Then
        await checkSubscriptionCookieIsPresent(token: subscriptionManager.resultTokenContainer!.accessToken)
    }

    func testSubscriptionCookieIsDeletedWhenSigningInToSubscription() async throws {
        // Given
        await ensureSubscriptionCookieIsInTheCookieStore()

        // When
        subscriptionCookieManager.enableSettingSubscriptionCookie()
        NotificationCenter.default.post(name: .accountDidSignOut, object: self, userInfo: nil)
        try await Task.sleep(interval: 0.1)

        // Then
        await checkSubscriptionCookieIsHasEmptyValue()
    }

    func testRefreshWhenSignedInButCookieIsMissing() async throws {
        // Given
        subscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        await ensureNoSubscriptionCookieInTheCookieStore()

        // When
        subscriptionCookieManager.enableSettingSubscriptionCookie()
        await subscriptionCookieManager.refreshSubscriptionCookie()
        try await Task.sleep(interval: 0.1)

        // Then
        await checkSubscriptionCookieIsPresent(token: subscriptionManager.resultTokenContainer!.accessToken)
    }

    func testRefreshWhenSignedOutButCookieIsPresent() async throws {
        // Given
        subscriptionManager.resultTokenContainer = nil
        await ensureSubscriptionCookieIsInTheCookieStore()

        // When
        subscriptionCookieManager.enableSettingSubscriptionCookie()
        await subscriptionCookieManager.refreshSubscriptionCookie()
        try await Task.sleep(interval: 0.1)

        // Then
        await checkSubscriptionCookieIsHasEmptyValue()
    }

    func testRefreshNotTriggeredTwiceWithinSetRefreshInterval() async throws {
        // Given
        let firstRefreshDate: Date?
        let secondRefreshDate: Date?

        // When
        subscriptionCookieManager.enableSettingSubscriptionCookie()
        await subscriptionCookieManager.refreshSubscriptionCookie()
        firstRefreshDate = subscriptionCookieManager.lastRefreshDate

        try await Task.sleep(interval: 0.5)

        await subscriptionCookieManager.refreshSubscriptionCookie()
        secondRefreshDate = subscriptionCookieManager.lastRefreshDate

        // Then
        XCTAssertEqual(firstRefreshDate!, secondRefreshDate!)
    }

    func testRefreshNotTriggeredSecondTimeAfterSetRefreshInterval() async throws {
        // Given
        let firstRefreshDate: Date?
        let secondRefreshDate: Date?

        // When
        subscriptionCookieManager.enableSettingSubscriptionCookie()
        await subscriptionCookieManager.refreshSubscriptionCookie()
        firstRefreshDate = subscriptionCookieManager.lastRefreshDate

        try await Task.sleep(interval: 1.1)

        await subscriptionCookieManager.refreshSubscriptionCookie()
        secondRefreshDate = subscriptionCookieManager.lastRefreshDate

        // Then
        XCTAssertTrue(firstRefreshDate! < secondRefreshDate!)
    }

    private func ensureSubscriptionCookieIsInTheCookieStore() async {
        let validTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        let subscriptionCookie = HTTPCookie(properties: [
            .domain: SubscriptionCookieManagerV2.cookieDomain,
            .path: "/",
            .expires: Date().addingTimeInterval(.days(365)),
            .name: SubscriptionCookieManagerV2.cookieName,
            .value: validTokenContainer.accessToken,
            .secure: true,
            .init(rawValue: "HttpOnly"): true
        ])!
        await cookieStore.setCookie(subscriptionCookie)

        let cookieStoreCookies = await cookieStore.allCookies()
        XCTAssertEqual(cookieStoreCookies.count, 1)
    }

    private func ensureNoSubscriptionCookieInTheCookieStore() async {
        let cookieStoreCookies = await cookieStore.allCookies()
        XCTAssertTrue(cookieStoreCookies.isEmpty)
    }

    private func checkSubscriptionCookieIsPresent(token: String) async {
        guard let subscriptionCookie = await cookieStore.fetchSubscriptionCookie() else {
            XCTFail("No subscription cookie in the store")
            return
        }
        XCTAssertEqual(subscriptionCookie.value, token)
    }

    private func checkSubscriptionCookieIsHasEmptyValue() async {
        guard let subscriptionCookie = await cookieStore.fetchSubscriptionCookie() else {
            XCTFail("No subscription cookie in the store")
            return
        }
        XCTAssertEqual(subscriptionCookie.value, "")
    }

}

private extension HTTPCookieStore {

    func fetchSubscriptionCookie() async -> HTTPCookie? {
        await allCookies().first { $0.domain == SubscriptionCookieManagerV2.cookieDomain && $0.name == SubscriptionCookieManagerV2.cookieName }
    }
}

class MockHTTPCookieStore: HTTPCookieStore {

    var cookies: [HTTPCookie]

    init(cookies: [HTTPCookie] = []) {
        self.cookies = cookies
    }

    func allCookies() async -> [HTTPCookie] {
        return cookies
    }

    func setCookie(_ cookie: HTTPCookie) async {
        cookies.removeAll { $0.domain == cookie.domain }
        cookies.append(cookie)
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        cookies.removeAll { $0.domain == cookie.domain }
    }

}

class MockSubscriptionCookieManageEventPixelMapping: EventMapping<SubscriptionCookieManagerEvent> {

    public init() {
        super.init { event, _, _, _ in

        }
    }

    override init(mapping: @escaping EventMapping<SubscriptionCookieManagerEvent>.Mapping) {
        fatalError("Use init()")
    }
}
