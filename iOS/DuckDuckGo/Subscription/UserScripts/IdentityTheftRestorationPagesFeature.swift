//
//  IdentityTheftRestorationPagesFeature.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Foundation
import WebKit
import UserScript
import Combine
import Subscription

final class IdentityTheftRestorationPagesFeature: Subfeature, ObservableObject {
    
    struct Constants {
        static let featureName = "useIdentityTheftRestoration"
        static let os = "ios"
        static let token = "token"
    }
    
    struct OriginDomains {
        static let duckduckgo = "duckduckgo.com"
    }

    struct Handlers {
        static let getAccessToken = "getAccessToken"
        static let getAuthAccessToken = "getAuthAccessToken"
        static let getFeatureConfig = "getFeatureConfig"
    }
        
    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    private let isAuthV2Enabled: Bool

    init(subscriptionManager: any SubscriptionAuthV1toV2Bridge, isAuthV2Enabled: Bool) {
        self.subscriptionManager = subscriptionManager
        self.isAuthV2Enabled = isAuthV2Enabled
    }

    weak var broker: UserScriptMessageBroker?

    let featureName: String = Constants.featureName
    lazy var messageOriginPolicy: MessageOriginPolicy = .only(rules: [
        HostnameMatchingRule.makeExactRule(for: subscriptionManager.url(for: .identityTheftRestoration)) ?? .exact(hostname: OriginDomains.duckduckgo)
    ])

    var originalMessage: WKScriptMessage?

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch methodName {
        case Handlers.getAccessToken: return getAccessToken
        case Handlers.getAuthAccessToken: return getAuthAccessToken
        case Handlers.getFeatureConfig: return getFeatureConfig
        default:
            return nil
        }
    }
    
    func getAccessToken(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        if let accessToken = try? await subscriptionManager.getAccessToken() {
            return [Constants.token: accessToken]
        } else {
            return [String: String]()
        }
    }

    func getAuthAccessToken(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        let accessToken = try? await subscriptionManager.getAccessToken()
        return AccessTokenValue(accessToken: accessToken ?? "")
    }

    func getFeatureConfig(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        return GetFeatureConfigurationResponse(useSubscriptionsAuthV2: isAuthV2Enabled)
    }

    deinit {
        broker = nil
    }

}
