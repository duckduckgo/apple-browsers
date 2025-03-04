//
//  SubscriptionCookieManagerTests.swift
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

final class SubscriptionCookieManagerTests: XCTestCase {

    private struct Constants {
        static let authToken = UUID().uuidString
        static let accessToken = UUID().uuidString
    }

    var accountManager: AccountManagerMock!
    var subscriptionService: SubscriptionEndpointServiceMock!
    var authService: AuthEndpointServiceMock!
    var storePurchaseManager: StorePurchaseManagerMock!
    var subscriptionEnvironment: SubscriptionEnvironment!
    var subscriptionFeatureMappingCache: SubscriptionFeatureMappingCacheMock!
    var subscriptionManager: SubscriptionManagerMock!

    var cookieStore: HTTPCookieStore!
    var subscriptionCookieManager: SubscriptionCookieManager!

    override func setUp() async throws {
        accountManager = AccountManagerMock()
        subscriptionService = SubscriptionEndpointServiceMock()
        authService = AuthEndpointServiceMock()
        storePurchaseManager = StorePurchaseManagerMock()
        subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .production,
                                                           purchasePlatform: .appStore)
        subscriptionFeatureMappingCache = SubscriptionFeatureMappingCacheMock()

        subscriptionManager = SubscriptionManagerMock(accountManager: accountManager,
                                                      subscriptionEndpointService: subscriptionService,
                                                      authEndpointService: authService,
                                                      storePurchaseManager: storePurchaseManager,
                                                      currentEnvironment: subscriptionEnvironment,
                                                      canPurchase: true,
                                                      subscriptionFeatureMappingCache: subscriptionFeatureMappingCache)
        cookieStore = MockHTTPCookieStore()

        subscriptionCookieManager = SubscriptionCookieManager(tokenProvider: subscriptionManager,
                                                              currentCookieStore: { self.cookieStore },
                                                              eventMapping: MockSubscriptionCookieManageEventPixelMapping(),
                                                              refreshTimeInterval: .seconds(1))
    }

    override func tearDown() async throws {
        accountManager = nil
        subscriptionService = nil
        authService = nil
        storePurchaseManager = nil
        subscriptionEnvironment = nil

        subscriptionManager = nil
    }

    func testSubscriptionCookieIsAddedWhenSigningInToSubscription() async throws {
        // Given
        await ensureNoSubscriptionCookieInTheCookieStore()
        accountManager.accessToken = Constants.accessToken

        // When
        subscriptionCookieManager.enableSettingSubscriptionCookie()
        NotificationCenter.default.post(name: .accountDidSignIn, object: self, userInfo: nil)
        try await Task.sleep(seconds: 0.1)

        // Then
        await checkSubscriptionCookieIsPresent()
    }

    func testSubscriptionCookieIsDeletedWhenSigningInToSubscription() async throws {
        // Given
        await ensureSubscriptionCookieIsInTheCookieStore()

        // When
        subscriptionCookieManager.enableSettingSubscriptionCookie()
        NotificationCenter.default.post(name: .accountDidSignOut, object: self, userInfo: nil)
        try await Task.sleep(seconds: 0.1)

        // Then
        await checkSubscriptionCookieIsHasEmptyValue()
    }

    func testRefreshWhenSignedInButCookieIsMissing() async throws {
        // Given
        accountManager.accessToken = Constants.accessToken
        await ensureNoSubscriptionCookieInTheCookieStore()

        // When
        subscriptionCookieManager.enableSettingSubscriptionCookie()
        await subscriptionCookieManager.refreshSubscriptionCookie()
        try await Task.sleep(seconds: 0.1)

        // Then
        await checkSubscriptionCookieIsPresent()
    }

    func testRefreshWhenSignedOutButCookieIsPresent() async throws {
        // Given
        accountManager.accessToken = nil
        await ensureSubscriptionCookieIsInTheCookieStore()

        // When
        subscriptionCookieManager.enableSettingSubscriptionCookie()
        await subscriptionCookieManager.refreshSubscriptionCookie()
        try await Task.sleep(seconds: 0.1)

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

        try await Task.sleep(seconds: 0.5)

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

        try await Task.sleep(seconds: 1.1)

        await subscriptionCookieManager.refreshSubscriptionCookie()
        secondRefreshDate = subscriptionCookieManager.lastRefreshDate

        // Then
        XCTAssertTrue(firstRefreshDate! < secondRefreshDate!)
    }

    private func ensureSubscriptionCookieIsInTheCookieStore() async {
        let subscriptionCookie = HTTPCookie(properties: [
            .domain: SubscriptionCookieManager.cookieDomain,
            .path: "/",
            .expires: Date().addingTimeInterval(.days(365)),
            .name: SubscriptionCookieManager.cookieName,
            .value: Constants.accessToken,
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

    private func checkSubscriptionCookieIsPresent() async {
        guard let subscriptionCookie = await cookieStore.fetchSubscriptionCookie() else {
            XCTFail("No subscription cookie in the store")
            return
        }
        XCTAssertEqual(subscriptionCookie.value, Constants.accessToken)
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
        await allCookies().first { $0.domain == SubscriptionCookieManager.cookieDomain && $0.name == SubscriptionCookieManager.cookieName }
    }
}
