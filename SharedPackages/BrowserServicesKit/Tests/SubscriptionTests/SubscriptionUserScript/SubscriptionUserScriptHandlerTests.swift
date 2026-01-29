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
import NetworkingTestingUtils

final class SubscriptionUserScriptHandlerTests: XCTestCase {

    var subscriptionManager: SubscriptionManagerMock!
    var handler: SubscriptionUserScriptHandler!
    var mockNavigationDelegate: MockNavigationDelegate!

    override func setUp() async throws {
        subscriptionManager = SubscriptionManagerMock()
        mockNavigationDelegate = await MockNavigationDelegate()
        handler = .init(platform: .ios,
                       subscriptionManager: subscriptionManager,
                       featureFlagProvider: MockFeatureFlagProvider(),
                       navigationDelegate: mockNavigationDelegate)
    }

    func testWhenInitializedForIOSThenHandshakeReportsIOS() async throws {
        handler = .init(platform: .ios,
                       subscriptionManager: subscriptionManager,
                       featureFlagProvider: MockFeatureFlagProvider(),
                       navigationDelegate: mockNavigationDelegate)
        let handshake = try await handler.handshake(params: [], message: MockUserScriptMessage())
        XCTAssertEqual(handshake.platform, .ios)
    }

    func testWhenInitializedForMacOSThenHandshakeReportsMacOS() async throws {
        handler = .init(platform: .macos,
                       subscriptionManager: subscriptionManager,
                       featureFlagProvider: MockFeatureFlagProvider(),
                       navigationDelegate: mockNavigationDelegate)
        let handshake = try await handler.handshake(params: [], message: MockUserScriptMessage())
        XCTAssertEqual(handshake.platform, .macos)
    }

    func testThatHandshakeReportsSupportForAllMessages() async throws {
        handler = .init(platform: .ios,
                       subscriptionManager: subscriptionManager,
                       featureFlagProvider: MockFeatureFlagProvider(),
                       navigationDelegate: mockNavigationDelegate)
        let handshake = try await handler.handshake(params: [], message: MockUserScriptMessage())
        XCTAssertEqual(handshake.availableMessages, [.subscriptionDetails, .getAuthAccessToken, .getFeatureConfig, .backToSettings, .openSubscriptionActivation, .openSubscriptionPurchase, .openSubscriptionUpgrade, .authUpdate])
    }

    func testWhenSubscriptionFailsToBeFetchedThenSubscriptionDetailsReturnsNotSubscribedState() async throws {
        struct SampleError: Error {}
        subscriptionManager.resultSubscription = .failure(SampleError())
        handler = .init(platform: .ios,
                       subscriptionManager: subscriptionManager,
                       featureFlagProvider: MockFeatureFlagProvider(),
                       navigationDelegate: mockNavigationDelegate)
        let subscriptionDetails = try await handler.subscriptionDetails(params: [], message: MockUserScriptMessage())
        XCTAssertEqual(subscriptionDetails, .init(isSubscribed: false, billingPeriod: nil, startedAt: nil, expiresOrRenewsAt: nil, paymentPlatform: nil, status: nil))
    }

    func testWhenSubscriptionIsActiveThenSubscriptionDetailsReturnsSubscriptionData() async throws {
        let startedAt = Date().startOfDay
        let expiresAt = Date().startOfDay.daysAgo(-10)
        let subscription = DuckDuckGoSubscription(
            productId: "test",
            name: "test",
            billingPeriod: .yearly,
            startedAt: startedAt,
            expiresOrRenewsAt: expiresAt,
            platform: .stripe,
            status: .autoRenewable,
            activeOffers: [],
            tier: nil,
            availableChanges: nil,
            pendingPlans: nil
        )

        subscriptionManager.resultSubscription = .success(subscription)
        handler = .init(platform: .ios,
                       subscriptionManager: subscriptionManager,
                       featureFlagProvider: MockFeatureFlagProvider(),
                       navigationDelegate: mockNavigationDelegate)
        let subscriptionDetails = try await handler.subscriptionDetails(params: [], message: MockUserScriptMessage())
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
        let subscription = DuckDuckGoSubscription(status: .expired)

        subscriptionManager.resultSubscription = .success(subscription)
        handler = .init(platform: .ios,
                       subscriptionManager: subscriptionManager,
                       featureFlagProvider: MockFeatureFlagProvider(),
                       navigationDelegate: mockNavigationDelegate)
        let subscriptionDetails = try await handler.subscriptionDetails(params: [], message: MockUserScriptMessage())
        XCTAssertTrue(subscriptionDetails.isSubscribed)
    }

    func testWhenSubscriptionIsInactiveThenSubscriptionDetailsReturnsSubscriptionData() async throws {
        let subscription = DuckDuckGoSubscription(status: .inactive)

        subscriptionManager.resultSubscription = .success(subscription)
        handler = .init(platform: .ios,
                       subscriptionManager: subscriptionManager,
                       featureFlagProvider: MockFeatureFlagProvider(),
                       navigationDelegate: mockNavigationDelegate)
        let subscriptionDetails = try await handler.subscriptionDetails(params: [], message: MockUserScriptMessage())
        XCTAssertTrue(subscriptionDetails.isSubscribed)
    }

    func testWhenAccessTokenIsAvailableThenGetAuthAccessTokenReturnsToken() async throws {
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        subscriptionManager.resultTokenContainer = tokenContainer

        let response = try await handler.getAuthAccessToken(params: [], message: MockUserScriptMessage())
        XCTAssertEqual(response.accessToken, tokenContainer.accessToken)
    }

    func testWhenAccessTokenIsNotAvailableThenGetAuthAccessTokenReturnsEmptyString() async throws {
        struct SampleError: Error {}
        subscriptionManager.resultTokenContainer = nil

        let response = try await handler.getAuthAccessToken(params: [], message: MockUserScriptMessage())
        XCTAssertEqual(response.accessToken, "")
    }

    func testWhenPaidAIChatIsEnabledThenGetFeatureConfigReturnsTrue() async throws {
        handler = .init(platform: .ios,
                       subscriptionManager: subscriptionManager,
                       featureFlagProvider: MockFeatureFlagProvider(usePaidDuckAi: true),
                       navigationDelegate: mockNavigationDelegate)

        let response = try await handler.getFeatureConfig(params: [], message: MockUserScriptMessage())
        XCTAssertTrue(response.usePaidDuckAi)
    }

    func testWhenPaidAIChatIsDisabledThenGetFeatureConfigReturnsFalse() async throws {
        handler = .init(platform: .ios,
                       subscriptionManager: subscriptionManager,
                    featureFlagProvider: MockFeatureFlagProvider(usePaidDuckAi: false),
                       navigationDelegate: mockNavigationDelegate)

        let response = try await handler.getFeatureConfig(params: [], message: MockUserScriptMessage())
        XCTAssertFalse(response.usePaidDuckAi)
    }

    func testWhenProTierIsEnabledThenGetFeatureConfigReturnsTrue() async throws {
        handler = .init(platform: .ios,
                       subscriptionManager: subscriptionManager,
                       featureFlagProvider: MockFeatureFlagProvider(useProTier: true),
                       navigationDelegate: mockNavigationDelegate)

        let response = try await handler.getFeatureConfig(params: [], message: MockUserScriptMessage())
        XCTAssertTrue(response.useProTier)
    }

    func testWhenProTierIsDisabledThenGetFeatureConfigReturnsFalse() async throws {
        handler = .init(platform: .ios,
                       subscriptionManager: subscriptionManager,
                       featureFlagProvider: MockFeatureFlagProvider(useProTier: false),
                       navigationDelegate: mockNavigationDelegate)

        let response = try await handler.getFeatureConfig(params: [], message: MockUserScriptMessage())
        XCTAssertFalse(response.useProTier)
    }

    @MainActor
    func testBackToSettingsCallsNavigationDelegate() async throws {
        let response = try await handler.backToSettings(params: [], message: MockUserScriptMessage())
        XCTAssertNil(response)
        XCTAssertTrue(mockNavigationDelegate.navigateToSettingsCalled)
    }

    @MainActor
    func testOpenSubscriptionActivationCallsNavigationDelegate() async throws {
        let response = try await handler.openSubscriptionActivation(params: [], message: MockUserScriptMessage())
        XCTAssertNil(response)
        XCTAssertTrue(mockNavigationDelegate.navigateToSubscriptionActivationCalled)
    }

    @MainActor
    func testOpenSubscriptionPurchaseCallsNavigationDelegate() async throws {
        let origin = "some_origin"
        let params = ["origin": origin]
        let response = try await handler.openSubscriptionPurchase(params: params, message: MockUserScriptMessage())
        XCTAssertNil(response)
        XCTAssertTrue(mockNavigationDelegate.navigateToSubscriptionPurchaseCalled)
        XCTAssertEqual(mockNavigationDelegate.purchaseOrigin, origin)
        XCTAssertEqual(mockNavigationDelegate.purchaseFeaturePage, "duckai")
    }

    @MainActor
    func testOpenSubscriptionPurchaseWithoutOriginCallsNavigationDelegate() async throws {
        let response = try await handler.openSubscriptionPurchase(params: [:], message: MockUserScriptMessage())
        XCTAssertNil(response)
        XCTAssertTrue(mockNavigationDelegate.navigateToSubscriptionPurchaseCalled)
        XCTAssertNil(mockNavigationDelegate.purchaseOrigin)
        XCTAssertEqual(mockNavigationDelegate.purchaseFeaturePage, "duckai")
    }

    @MainActor
    func testOpenSubscriptionUpgradeCallsNavigationDelegate() async throws {
        let origin = "some_origin"
        let params = ["origin": origin]
        let response = try await handler.openSubscriptionUpgrade(params: params, message: MockUserScriptMessage())
        XCTAssertNil(response)
        XCTAssertTrue(mockNavigationDelegate.navigateToSubscriptionUpgradeCalled)
        XCTAssertEqual(mockNavigationDelegate.purchaseOrigin, origin)
        XCTAssertEqual(mockNavigationDelegate.purchaseFeaturePage, "duckai")
    }

    @MainActor
    func testOpenSubscriptionUpgradeWithoutOriginCallsNavigationDelegate() async throws {
        let response = try await handler.openSubscriptionUpgrade(params: [:], message: MockUserScriptMessage())
        XCTAssertNil(response)
        XCTAssertTrue(mockNavigationDelegate.navigateToSubscriptionUpgradeCalled)
        XCTAssertNil(mockNavigationDelegate.purchaseOrigin)
        XCTAssertEqual(mockNavigationDelegate.purchaseFeaturePage, "duckai")
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

private extension DuckDuckGoSubscription {
    init(status: Status) {
        self.init(productId: "test", name: "test", billingPeriod: .monthly, startedAt: Date(), expiresOrRenewsAt: Date(), platform: .apple, status: status, activeOffers: [], tier: nil, availableChanges: nil, pendingPlans: nil)
    }
}

@MainActor
class MockNavigationDelegate: SubscriptionUserScriptNavigationDelegate {
    var navigateToSettingsCalled = false
    var navigateToSubscriptionActivationCalled = false
    var navigateToSubscriptionPurchaseCalled = false
    var navigateToSubscriptionUpgradeCalled = false
    var purchaseOrigin: String?
    var purchaseFeaturePage: String?

    func navigateToSettings() {
        navigateToSettingsCalled = true
    }

    func navigateToSubscriptionActivation() {
        navigateToSubscriptionActivationCalled = true
    }

    func navigateToSubscriptionPurchase(origin: String?, featurePage: String?) {
        navigateToSubscriptionPurchaseCalled = true
        purchaseOrigin = origin
        purchaseFeaturePage = featurePage
    }

    func navigateToSubscriptionPlans(origin: String?, featurePage: String?) {
        navigateToSubscriptionUpgradeCalled = true
        purchaseOrigin = origin
        purchaseFeaturePage = featurePage
    }
}

struct MockFeatureFlagProvider: SubscriptionUserScriptFeatureFlagProviding {
    var usePaidDuckAi: Bool = false
    var useProTier: Bool = false
}

class MockUserScriptMessagePusher: UserScriptMessagePushing {
    var lastPushedMethod: String?
    let pushExpectation = XCTestExpectation(description: "Push method called")

    func push(method: String, params: Encodable?, for delegate: Subfeature, into webView: WKWebView) {
        lastPushedMethod = method
        pushExpectation.fulfill()
    }
}
