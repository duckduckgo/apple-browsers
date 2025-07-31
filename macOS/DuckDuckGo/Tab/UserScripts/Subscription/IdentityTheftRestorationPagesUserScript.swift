//
//  IdentityTheftRestorationPagesUserScript.swift
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

import BrowserServicesKit
import Common
import Combine
import Foundation
import WebKit
import Subscription
import UserScript

///
/// The user script that will be the broker for all subscription features
///
public final class IdentityTheftRestorationPagesUserScript: NSObject, UserScript, UserScriptMessaging {
    public var source: String = ""

    public static let context = "identityTheftRestorationPages"

    // special pages messaging cannot be isolated as we'll want regular page-scripts to be able to communicate
    public let broker = UserScriptMessageBroker(context: IdentityTheftRestorationPagesUserScript.context, requiresRunInPageContentWorld: true )

    public let messageNames: [String] = [
        IdentityTheftRestorationPagesUserScript.context
    ]

    public let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    public let forMainFrameOnly = true
    public let requiresRunInPageContentWorld = true
}

extension IdentityTheftRestorationPagesUserScript: WKScriptMessageHandlerWithReply {
    @MainActor
    public func userContentController(_ userContentController: WKUserContentController,
                                      didReceive message: WKScriptMessage) async -> (Any?, String?) {
        let action = broker.messageHandlerFor(message)
        do {
            let json = try await broker.execute(action: action, original: message)
            return (json, nil)
        } catch {
            // forward uncaught errors to the client
            return (nil, error.localizedDescription)
        }
    }
}

// MARK: - Fallback for macOS 10.15
extension IdentityTheftRestorationPagesUserScript: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // unsupported
    }
}

///
/// Use Subscription sub-feature
///
final class IdentityTheftRestorationPagesFeature: Subfeature {

    private enum OriginDomains {
        static let duckduckgo = "duckduckgo.com"
    }

    weak var broker: UserScriptMessageBroker?
    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    private let subscriptionFeatureAvailability: SubscriptionFeatureAvailability
    private let isAuthV2Enabled: Bool

    let featureName = "useIdentityTheftRestoration"
    lazy var messageOriginPolicy: MessageOriginPolicy = .only(rules: [
        HostnameMatchingRule.makeExactRule(for: subscriptionManager.url(for: .baseURL)) ?? .exact(hostname: OriginDomains.duckduckgo)
    ])

    init(subscriptionManager: any SubscriptionAuthV1toV2Bridge,
         subscriptionFeatureAvailability: SubscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(),
         isAuthV2Enabled: Bool) {
        self.subscriptionManager = subscriptionManager
        self.subscriptionFeatureAvailability = subscriptionFeatureAvailability
        self.isAuthV2Enabled = isAuthV2Enabled
    }

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch methodName {
        case "getAccessToken": return getAccessToken
        case "getAuthAccessToken": return getAuthAccessToken
        case "getFeatureConfig": return getFeatureConfig
        case "openSendFeedbackModal": return openSendFeedbackModal
        default:
            return nil
        }
    }

    func getAccessToken(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        if let accessToken = try? await Application.appDelegate.subscriptionAuthV1toV2Bridge.getAccessToken() {
            return ["token": accessToken]
        } else {
            return [String: String]()
        }
    }

    func getAuthAccessToken(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        let accessToken = try? await subscriptionManager.getAccessToken()
        return AccessTokenValue(accessToken: accessToken ?? "")
    }

    func getFeatureConfig(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        /// Note that the `useAlternateStripePaymentFlow` value is not used on the IDTR page, and so we can set the value to false here.
        return GetFeatureValue(useSubscriptionsAuthV2: isAuthV2Enabled, usePaidDuckAi: false, useAlternateStripePaymentFlow: false)
    }

    func openSendFeedbackModal(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        NotificationCenter.default.post(name: .OpenUnifiedFeedbackForm, object: nil, userInfo: UnifiedFeedbackSource.userInfo(source: .itr))
        return nil
    }
}
