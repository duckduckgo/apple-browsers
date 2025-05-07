//
//  SubscriptionUserScript.swift
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

import Common
import UserScript
import WebKit

public struct HandshakeResponse: Codable, Equatable {
    public let availableMessages: [SubscriptionUserScript.MessageName]
    public let platform: Platform

    public init(availableMessages: [SubscriptionUserScript.MessageName], platform: Platform) {
        self.availableMessages = availableMessages
        self.platform = platform
    }

    public enum Platform: String, Codable {
        case ios, macos
    }
}

public struct SubscriptionDetails: Codable, Equatable {
    public let isSubscribed: Bool
    public let billingPeriod: String?
    public let startedAt: Int?
    public let expiresOrRenewsAt: Int?
    public let paymentPlatform: String?
    public let status: String?

    static let unsubscribed: Self = .init(isSubscribed: false, billingPeriod: nil, startedAt: nil, expiresOrRenewsAt: nil, paymentPlatform: nil, status: nil)

    public init(isSubscribed: Bool, billingPeriod: String?, startedAt: Int?, expiresOrRenewsAt: Int?, paymentPlatform: String?, status: String?) {
        self.isSubscribed = isSubscribed
        self.billingPeriod = billingPeriod
        self.startedAt = startedAt
        self.expiresOrRenewsAt = expiresOrRenewsAt
        self.paymentPlatform = paymentPlatform
        self.status = status
    }
}

public protocol SubscriptionUserScriptHandling {
    func handshake(params: Any, message: UserScriptMessage) async throws -> HandshakeResponse
    func subscriptionDetails(params: Any, message: UserScriptMessage) async throws -> SubscriptionDetails
}

public final class SubscriptionUserScriptHandler: SubscriptionUserScriptHandling {
    let platform: HandshakeResponse.Platform
    let subscriptionManager: any SubscriptionAuthV1toV2Bridge

    public init(platform: HandshakeResponse.Platform, subscriptionManager: any SubscriptionAuthV1toV2Bridge) {
        self.platform = platform
        self.subscriptionManager = subscriptionManager
    }

    public func handshake(params: Any, message: any UserScriptMessage) async throws -> HandshakeResponse {
        .init(availableMessages: [.subscriptionDetails], platform: platform)
    }

    public func subscriptionDetails(params: Any, message: any UserScriptMessage) async throws -> SubscriptionDetails {
        let subscription = try await subscriptionManager.getSubscription(cachePolicy: .returnCacheDataElseLoad)

        guard subscription.isActive else {
            return .unsubscribed
        }

        return SubscriptionDetails(
            isSubscribed: true,
            billingPeriod: subscription.billingPeriod.rawValue,
            startedAt: Int(subscription.startedAt.timeIntervalSince1970),
            expiresOrRenewsAt: Int(subscription.expiresOrRenewsAt.timeIntervalSince1970),
            paymentPlatform: subscription.platform.rawValue,
            status: subscription.status.rawValue
        )
    }
}

public final class SubscriptionUserScript: NSObject, Subfeature {

    public enum MessageName: String, CaseIterable, Codable {
        case handshake
        case subscriptionDetails
    }

    public let featureName: String = "subscriptions"

    public weak var broker: UserScriptMessageBroker?
    public private(set) var messageOriginPolicy: MessageOriginPolicy
    private let handler: SubscriptionUserScriptHandling

    public init(handler: SubscriptionUserScriptHandling) {
        self.handler = handler
        var rules = [HostnameMatchingRule]()

        /// Default rule for DuckDuckGo Subscriptions
        rules.append(.exact(hostname: "duckduckgo.com"))
        rules.append(.exact(hostname: "abrown.duckduckgo.com"))

        self.messageOriginPolicy = .only(rules: rules)
    }

    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageName(rawValue: methodName) {
        case .handshake:
            return handler.handshake
        case .subscriptionDetails:
            return handler.subscriptionDetails
        default:
            return nil
        }
    }
}
