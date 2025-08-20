//
//  MockSubscriptionUserScriptHandler.swift
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
import UserScript
import WebKit

public final class MockSubscriptionUserScriptHandler: SubscriptionUserScriptHandling {

    public init() {}

    public var handshakeCallCount = 0
    public var subscriptionDetailsCallCount = 0
    public var getAuthAccessTokenCallCount = 0
    public var getFeatureConfigCallCount = 0
    public var backToSettingsCallCount = 0
    public var openSubscriptionActivationCallCount = 0
    public var openSubscriptionPurchaseCallCount = 0

    // Parameter tracking
    public var lastOpenSubscriptionPurchaseParams: Any?
    public var lastOpenSubscriptionPurchaseMessage: (any UserScriptMessage)?

    // Setter method tracking
    public var lastSetBroker: UserScriptMessagePushing?
    public var lastSetWebView: WKWebView?
    public var lastSetUserScript: SubscriptionUserScript?

    public var handshake: (Any, any UserScriptMessage) async throws -> SubscriptionUserScript.DataModel.HandshakeResponse = { _, _ in .init(availableMessages: [.subscriptionDetails, .getAuthAccessToken, .getFeatureConfig, .backToSettings, .openSubscriptionActivation, .openSubscriptionPurchase, .authUpdate], platform: .ios) }
    public var subscriptionDetails: (Any, any UserScriptMessage) async throws -> SubscriptionUserScript.DataModel.SubscriptionDetails = { _, _ in .notSubscribed }
    public var getAuthAccessToken: (Any, any UserScriptMessage) async throws -> SubscriptionUserScript.DataModel.GetAuthAccessTokenResponse = { _, _ in .init(accessToken: "mock_token") }
    public var getFeatureConfig: (Any, any UserScriptMessage) async throws -> SubscriptionUserScript.DataModel.GetFeatureConfigurationResponse = { _, _ in .init(usePaidDuckAi: false) }
    public var backToSettings: (Any, any UserScriptMessage) async throws -> Encodable? = { _, _ in nil }
    public var openSubscriptionActivation: (Any, any UserScriptMessage) async throws -> Encodable? = { _, _ in nil }
    public var openSubscriptionPurchase: (Any, any UserScriptMessage) async throws -> Encodable? = { _, _ in nil }

    public func handshake(params: Any, message: any UserScriptMessage) async throws -> SubscriptionUserScript.DataModel.HandshakeResponse {
        handshakeCallCount += 1
        return try await handshake(params, message)
    }

    public func subscriptionDetails(params: Any, message: any UserScriptMessage) async throws -> SubscriptionUserScript.DataModel.SubscriptionDetails {
        subscriptionDetailsCallCount += 1
        return try await subscriptionDetails(params, message)
    }

    public func getAuthAccessToken(params: Any, message: any UserScriptMessage) async throws -> SubscriptionUserScript.DataModel.GetAuthAccessTokenResponse {
        getAuthAccessTokenCallCount += 1
        return try await getAuthAccessToken(params, message)
    }

    public func getFeatureConfig(params: Any, message: any UserScriptMessage) async throws -> SubscriptionUserScript.DataModel.GetFeatureConfigurationResponse {
        getFeatureConfigCallCount += 1
        return try await getFeatureConfig(params, message)
    }

    public func backToSettings(params: Any, message: any UserScriptMessage) async throws -> Encodable? {
        backToSettingsCallCount += 1
        return try await backToSettings(params, message)
    }

    public func openSubscriptionActivation(params: Any, message: any UserScriptMessage) async throws -> Encodable? {
        openSubscriptionActivationCallCount += 1
        return try await openSubscriptionActivation(params, message)
    }

    public func openSubscriptionPurchase(params: Any, message: any UserScriptMessage) async throws -> Encodable? {
        openSubscriptionPurchaseCallCount += 1
        lastOpenSubscriptionPurchaseParams = params
        lastOpenSubscriptionPurchaseMessage = message
        return try await openSubscriptionPurchase(params, message)
    }

    public func setBroker(_ broker: any Subscription.UserScriptMessagePushing) {
        lastSetBroker = broker
    }

    public func setWebView(_ webView: WKWebView?) {
        lastSetWebView = webView
    }

    public func setUserScript(_ userScript: Subscription.SubscriptionUserScript) {
        lastSetUserScript = userScript
    }
}
