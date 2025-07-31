//
//  SubscriptionUserScriptHandlerTests.swift
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

@testable import Subscription
import SubscriptionTestingUtilities
import UserScript
import WebKit
import XCTest

final class SubscriptionUserScriptHandlerTests: XCTestCase {

    var subscriptionManager: SubscriptionAuthV1toV2BridgeMock!
    var handler: SubscriptionUserScriptHandler!
    var mockNavigationDelegate: MockNavigationDelegate!

    override func setUp() async throws {
        subscriptionManager = SubscriptionAuthV1toV2BridgeMock()
        mockNavigationDelegate = await MockNavigationDelegate()
        handler = .init(platform: .ios,
                       subscriptionManager: subscriptionManager,
                       paidAIChatFlagStatusProvider: { false },
                       navigationDelegate: mockNavigationDelegate)
    }

    func testWhenInitializedForIOSThenHandshakeReportsIOS() async throws {
        handler = .init(platform: .ios,
                       subscriptionManager: subscriptionManager,
                       paidAIChatFlagStatusProvider: { false },
                       navigationDelegate: mockNavigationDelegate)
        let handshake = try await handler.handshake(params: [], message: WKScriptMessage())
        XCTAssertEqual(handshake.platform, .ios)
    }

    func testWhenInitializedForMacOSThenHandshakeReportsMacOS() async throws {
        handler = .init(platform: .macos,
                       subscriptionManager: subscriptionManager,
                       paidAIChatFlagStatusProvider: { false },
                       navigationDelegate: mockNavigationDelegate)
        let handshake = try await handler.handshake(params: [], message: WKScriptMessage())
        XCTAssertEqual(handshake.platform, .macos)
    }

    func testThatHandshakeReportsSupportForAllMessages() async throws {
        handler = .init(platform: .ios,
                       subscriptionManager: subscriptionManager,
                       paidAIChatFlagStatusProvider: { false },
                       navigationDelegate: mockNavigationDelegate)
        let handshake = try await handler.handshake(params: [], message: WKScriptMessage())
        XCTAssertEqual(handshake.availableMessages, [.subscriptionDetails, .getAuthAccessToken, .getFeatureConfig, .backToSettings, .openSubscriptionActivation, .openSubscriptionPurchase, .authUpdate])
    }

    func testWhenSubscriptionFailsToBeFetchedThenSubscriptionDetailsReturnsNotSubscribedState() async throws {
        struct SampleError: Error {}
        subscriptionManager.returnSubscription = .failure(SampleError())
        handler = .init(platform: .ios,
                       subscriptionManager: subscriptionManager,
                       paidAIChatFlagStatusProvider: { false },
                       navigationDelegate: mockNavigationDelegate)
        let subscriptionDetails = try await handler.subscriptionDetails(params: [], message: WKScriptMessage())
        XCTAssertEqual(subscriptionDetails, .init(isSubscribed: false, billingPeriod: nil, startedAt: nil, expiresOrRenewsAt: nil, paymentPlatform: nil, status: nil))
    }

    func testWhenSubscriptionIsActiveThenSubscriptionDetailsReturnsSubscriptionData() async throws {
        let startedAt = Date().startOfDay
        let expiresAt = Date().startOfDay.daysAgo(-10)
        let subscription = PrivacyProSubscription(
            productId: "test",
            name: "test",
            billingPeriod: .yearly,
            startedAt: startedAt,
            expiresOrRenewsAt: expiresAt,
            platform: .stripe,
            status: .autoRenewable,
            activeOffers: []
        )

        subscriptionManager.returnSubscription = .success(subscription)
        handler = .init(platform: .ios,
                       subscriptionManager: subscriptionManager,
                       paidAIChatFlagStatusProvider: { false },
                       navigationDelegate: mockNavigationDelegate)
        let subscriptionDetails = try await handler.subscriptionDetails(params: [], message: WKScriptMessage())
        XCTAssertEqual(subscriptionDetails, .init(
            isSubscribed: true,
            billingPeriod: subscription.billingPeriod.rawValue,
            startedAt: Int(startedAt.timeIntervalSince1970 * 1000),
            expiresOrRenewsAt: Int(expiresAt.timeIntervalSince1970 * 1000),
            paymentPlatform: subscription.platform.rawValue,
            status: subscription.status.rawValue
        ))
    }

    func testWhenSubscriptionIsExpiredThenSubscriptionDetailsReturnsSubscriptionData() async throws {
        let subscription = PrivacyProSubscription(status: .expired)

        subscriptionManager.returnSubscription = .success(subscription)
        handler = .init(platform: .ios,
                       subscriptionManager: subscriptionManager,
                       paidAIChatFlagStatusProvider: { false },
                       navigationDelegate: mockNavigationDelegate)
        let subscriptionDetails = try await handler.subscriptionDetails(params: [], message: WKScriptMessage())
        XCTAssertTrue(subscriptionDetails.isSubscribed)
    }

    func testWhenSubscriptionIsInactiveThenSubscriptionDetailsReturnsSubscriptionData() async throws {
        let subscription = PrivacyProSubscription(status: .inactive)

        subscriptionManager.returnSubscription = .success(subscription)
        handler = .init(platform: .ios,
                       subscriptionManager: subscriptionManager,
                       paidAIChatFlagStatusProvider: { false },
                       navigationDelegate: mockNavigationDelegate)
        let subscriptionDetails = try await handler.subscriptionDetails(params: [], message: WKScriptMessage())
        XCTAssertTrue(subscriptionDetails.isSubscribed)
    }

    func testWhenAccessTokenIsAvailableThenGetAuthAccessTokenReturnsToken() async throws {
        let expectedToken = "test_access_token"
        subscriptionManager.accessTokenResult = .success(expectedToken)

        let response = try await handler.getAuthAccessToken(params: [], message: WKScriptMessage())
        XCTAssertEqual(response.accessToken, expectedToken)
    }

    func testWhenAccessTokenIsNotAvailableThenGetAuthAccessTokenReturnsEmptyString() async throws {
        struct SampleError: Error {}
        subscriptionManager.accessTokenResult = .failure(SampleError())

        let response = try await handler.getAuthAccessToken(params: [], message: WKScriptMessage())
        XCTAssertEqual(response.accessToken, "")
    }

    func testWhenPaidAIChatIsEnabledThenGetFeatureConfigReturnsTrue() async throws {
        handler = .init(platform: .ios,
                       subscriptionManager: subscriptionManager,
                       paidAIChatFlagStatusProvider: { true },
                       navigationDelegate: mockNavigationDelegate)

        let response = try await handler.getFeatureConfig(params: [], message: WKScriptMessage())
        XCTAssertTrue(response.usePaidDuckAi)
    }

    func testWhenPaidAIChatIsDisabledThenGetFeatureConfigReturnsFalse() async throws {
        handler = .init(platform: .ios,
                       subscriptionManager: subscriptionManager,
                       paidAIChatFlagStatusProvider: { false },
                       navigationDelegate: mockNavigationDelegate)

        let response = try await handler.getFeatureConfig(params: [], message: WKScriptMessage())
        XCTAssertFalse(response.usePaidDuckAi)
    }

    @MainActor
    func testBackToSettingsCallsNavigationDelegate() async throws {
        let response = try await handler.backToSettings(params: [], message: WKScriptMessage())
        XCTAssertNil(response)
        XCTAssertTrue(mockNavigationDelegate.navigateToSettingsCalled)
    }

    @MainActor
    func testOpenSubscriptionActivationCallsNavigationDelegate() async throws {
        let response = try await handler.openSubscriptionActivation(params: [], message: WKScriptMessage())
        XCTAssertNil(response)
        XCTAssertTrue(mockNavigationDelegate.navigateToSubscriptionActivationCalled)
    }

    @MainActor
    func testOpenSubscriptionPurchaseCallsNavigationDelegate() async throws {
        let origin = "some_origin"
        let params = ["origin": origin]
        let response = try await handler.openSubscriptionPurchase(params: params, message: WKScriptMessage())
        XCTAssertNil(response)
        XCTAssertTrue(mockNavigationDelegate.navigateToSubscriptionPurchaseCalled)
        XCTAssertEqual(mockNavigationDelegate.purchaseOrigin, origin)
    }

    @MainActor
    func testOpenSubscriptionPurchaseWithoutOriginCallsNavigationDelegate() async throws {
        let response = try await handler.openSubscriptionPurchase(params: [:], message: WKScriptMessage())
        XCTAssertNil(response)
        XCTAssertTrue(mockNavigationDelegate.navigateToSubscriptionPurchaseCalled)
        XCTAssertNil(mockNavigationDelegate.purchaseOrigin)
    }

    // MARK: - Auth Update Push Tests

    func testThatSubscriptionDidChangeNotificationTriggersAuthUpdate() {
        let mockBroker = MockUserScriptMessagePusher()
        let mockWebView = WKWebView()
        let mockUserScript = SubscriptionUserScript(handler: handler, debugHost: nil)

        handler.setBroker(mockBroker)
        handler.setWebView(mockWebView)
        handler.setUserScript(mockUserScript)

        NotificationCenter.default.post(name: .subscriptionDidChange, object: nil)
        let result = XCTWaiter().wait(for: [mockBroker.pushExpectation], timeout: 1)
        XCTAssertEqual(result, .completed)

        XCTAssertEqual(mockBroker.lastPushedMethod, SubscriptionUserScript.MessageName.authUpdate.rawValue)
    }

    func testThatAccountDidSignInNotificationTriggersAuthUpdate() {
        let mockBroker = MockUserScriptMessagePusher()
        let mockWebView = WKWebView()
        let mockUserScript = SubscriptionUserScript(handler: handler, debugHost: nil)

        handler.setBroker(mockBroker)
        handler.setWebView(mockWebView)
        handler.setUserScript(mockUserScript)

        NotificationCenter.default.post(name: .accountDidSignIn, object: nil)
        let result = XCTWaiter().wait(for: [mockBroker.pushExpectation], timeout: 1)
        XCTAssertEqual(result, .completed)

        XCTAssertEqual(mockBroker.lastPushedMethod, SubscriptionUserScript.MessageName.authUpdate.rawValue)
    }

    func testThatAccountDidSignOutNotificationTriggersAuthUpdate() {
        let mockBroker = MockUserScriptMessagePusher()
        let mockWebView = WKWebView()
        let mockUserScript = SubscriptionUserScript(handler: handler, debugHost: nil)

        handler.setBroker(mockBroker)
        handler.setWebView(mockWebView)
        handler.setUserScript(mockUserScript)

        NotificationCenter.default.post(name: .accountDidSignOut, object: nil)
        let result = XCTWaiter().wait(for: [mockBroker.pushExpectation], timeout: 1)
        XCTAssertEqual(result, .completed)

        XCTAssertEqual(mockBroker.lastPushedMethod, SubscriptionUserScript.MessageName.authUpdate.rawValue)
    }

}

private extension PrivacyProSubscription {
    init(status: Status) {
        self.init(productId: "test", name: "test", billingPeriod: .monthly, startedAt: Date(), expiresOrRenewsAt: Date(), platform: .apple, status: status, activeOffers: [])
    }
}

@MainActor
class MockNavigationDelegate: SubscriptionUserScriptNavigationDelegate {
    var navigateToSettingsCalled = false
    var navigateToSubscriptionActivationCalled = false
    var navigateToSubscriptionPurchaseCalled = false
    var purchaseOrigin: String?

    func navigateToSettings() {
        navigateToSettingsCalled = true
    }

    func navigateToSubscriptionActivation() {
        navigateToSubscriptionActivationCalled = true
    }

    func navigateToSubscriptionPurchase(origin: String?) {
        navigateToSubscriptionPurchaseCalled = true
        purchaseOrigin = origin
    }
}

class MockUserScriptMessagePusher: UserScriptMessagePushing {
    var lastPushedMethod: String?
    let pushExpectation = XCTestExpectation(description: "Push method called")

    func push(method: String, params: Encodable?, for delegate: Subfeature, into webView: WKWebView) {
        lastPushedMethod = method
        pushExpectation.fulfill()
    }
}
