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

///
/// This protocol describes the interface for `SubscriptionUserScript` message handler
///
protocol SubscriptionUserScriptHandling {

    /// Returns a handshake message reporting capabilities of the app.
    func handshake(params: Any, message: UserScriptMessage) async throws -> SubscriptionUserScript.DataModel.HandshakeResponse

    /// Returns the details of Privacy Pro subscription.
    func subscriptionDetails(params: Any, message: UserScriptMessage) async throws -> SubscriptionUserScript.DataModel.SubscriptionDetails
}

final class SubscriptionUserScriptHandler: SubscriptionUserScriptHandling {
    typealias DataModel = SubscriptionUserScript.DataModel

    let platform: DataModel.Platform
    let subscriptionManager: any SubscriptionAuthV1toV2Bridge

    init(platform: DataModel.Platform, subscriptionManager: any SubscriptionAuthV1toV2Bridge) {
        self.platform = platform
        self.subscriptionManager = subscriptionManager
    }

    func handshake(params: Any, message: any UserScriptMessage) async throws -> DataModel.HandshakeResponse {
        .init(availableMessages: [.subscriptionDetails], platform: platform)
    }

    func subscriptionDetails(params: Any, message: any UserScriptMessage) async throws -> DataModel.SubscriptionDetails {
        guard let subscription = try? await subscriptionManager.getSubscription(cachePolicy: .returnCacheDataElseLoad) else {
            return .notSubscribed
        }
        return .init(subscription)
    }
}

///
/// This user script is responsible for providing Privacy Pro subscription data to the calling website.
///
public final class SubscriptionUserScript: NSObject, Subfeature {

    public enum MessageName: String, CaseIterable, Codable {
        case handshake
        case subscriptionDetails
    }

    public let featureName: String = "subscriptions"
    public let messageOriginPolicy: MessageOriginPolicy = .only(rules: [.exact(hostname: "duckduckgo.com")])
    public weak var broker: UserScriptMessageBroker?

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

    public convenience init(platform: DataModel.Platform, subscriptionManager: any SubscriptionAuthV1toV2Bridge) {
        self.init(handler: SubscriptionUserScriptHandler(platform: platform, subscriptionManager: subscriptionManager))
    }

    init(handler: SubscriptionUserScriptHandling) {
        self.handler = handler
    }

    let handler: SubscriptionUserScriptHandling
}

extension SubscriptionUserScript {
    public enum DataModel {

        /// Describes the platform to be reported to the user script.
        /// This needs to be public as it's provided by the client app.
        public enum Platform: String, Codable {
            case ios, macos
        }

        /// This struct is returned in response to the `handshake` message
        struct HandshakeResponse: Codable, Equatable {
            let availableMessages: [SubscriptionUserScript.MessageName]
            let platform: Platform
        }

        /// This struct is returned in response to the `subscriptionDetails` message
        struct SubscriptionDetails: Codable, Equatable {
            let isSubscribed: Bool
            let billingPeriod: String?
            let startedAt: Int?
            let expiresOrRenewsAt: Int?
            let paymentPlatform: String?
            let status: String?

            static let notSubscribed: Self = .init(isSubscribed: false, billingPeriod: nil, startedAt: nil, expiresOrRenewsAt: nil, paymentPlatform: nil, status: nil)

            init(_ subscription: PrivacyProSubscription) {
                isSubscribed = true
                billingPeriod = subscription.billingPeriod.rawValue
                startedAt = Int(subscription.startedAt.timeIntervalSince1970 * 1000)
                expiresOrRenewsAt = Int(subscription.expiresOrRenewsAt.timeIntervalSince1970 * 1000)
                paymentPlatform = subscription.platform.rawValue
                status = subscription.status.rawValue
            }

            init(isSubscribed: Bool, billingPeriod: String?, startedAt: Int?, expiresOrRenewsAt: Int?, paymentPlatform: String?, status: String?) {
                self.isSubscribed = isSubscribed
                self.billingPeriod = billingPeriod
                self.startedAt = startedAt
                self.expiresOrRenewsAt = expiresOrRenewsAt
                self.paymentPlatform = paymentPlatform
                self.status = status
            }
        }
    }
}
