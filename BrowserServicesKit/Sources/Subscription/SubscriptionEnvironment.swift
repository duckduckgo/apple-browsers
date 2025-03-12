//
//  SubscriptionEnvironment.swift
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

import Foundation
import Networking

public struct SubscriptionEnvironment: Codable {

    public enum ServiceEnvironment: String, Codable {
        case production, staging

        public var url: URL {
            switch self {
            case .production:
                URL(string: "https://subscriptions.duckduckgo.com/api")!
            case .staging:
                URL(string: "https://subscriptions-dev.duckduckgo.com/api")!
            }
        }

        public var description: String {
            switch self {
            case .production: return "Production"
            case .staging: return "Staging"
            }
        }
    }

    public var authEnvironment: OAuthEnvironment { serviceEnvironment == .production ? .production : .staging }

    public enum PurchasePlatform: String, Codable {
        case appStore, stripe
    }

    /// Defines environment used by auth and subscription related APIs
    public var serviceEnvironment: SubscriptionEnvironment.ServiceEnvironment

    /// Defines platform used for purchasing the subscription
    public var purchasePlatform: SubscriptionEnvironment.PurchasePlatform

    /// Override for base subscription URL (only to be used during testing and development)
    public var customBaseSubscriptionURL: URL?

    public init(serviceEnvironment: SubscriptionEnvironment.ServiceEnvironment,
                purchasePlatform: SubscriptionEnvironment.PurchasePlatform,
                customBaseSubscriptionURL: URL? = nil) {
        self.serviceEnvironment = serviceEnvironment
        self.purchasePlatform = purchasePlatform
        self.customBaseSubscriptionURL = customBaseSubscriptionURL
    }

    public var description: String {
        "ServiceEnvironment: \(serviceEnvironment.rawValue), PurchasePlatform: \(purchasePlatform.rawValue), CustomBaseSubscriptionURL: \(customBaseSubscriptionURL?.absoluteString ?? "")"
    }
}
