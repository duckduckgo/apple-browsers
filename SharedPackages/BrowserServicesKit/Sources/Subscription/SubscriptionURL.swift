//
//  SubscriptionURL.swift
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

// MARK: - URLs, ex URL+Subscription

public enum SubscriptionURL {

    case baseURL
    case purchase
    case welcome
    case faq
    case activationFlow
    case activationFlowAddEmailStep
    case activationFlowLinkViaEmailStep
    case activationFlowSuccess
    case manageEmail
    case manageSubscriptionsInAppStore
    case identityTheftRestoration

    public enum StaticURLs {
        public static let defaultBaseSubscriptionURL = URL(string: "https://duckduckgo.com/subscriptions")!
        static let manageSubscriptionsInMacAppStoreURL = URL(string: "macappstores://apps.apple.com/account/subscriptions")!
        static let helpPagesURL = URL(string: "https://duckduckgo.com/duckduckgo-help-pages/privacy-pro/")!
    }

    public func subscriptionURL(withCustomBaseURL baseURL: URL = StaticURLs.defaultBaseSubscriptionURL, environment: SubscriptionEnvironment.ServiceEnvironment) -> URL {
        let url: URL = {
            switch self {
            case .baseURL:
                baseURL
            case .purchase:
                baseURL
            case .welcome:
                baseURL.appendingPathComponent("welcome")
            case .faq:
                StaticURLs.helpPagesURL
            case .activationFlow:
                baseURL.appendingPathComponent("activation-flow")
            case .activationFlowAddEmailStep:
                baseURL.appendingPathComponent("activation-flow/another-device/add-email")
            case .activationFlowLinkViaEmailStep:
                baseURL.appendingPathComponent("activation-flow/another-device/email")
            case .activationFlowSuccess:
                baseURL.appendingPathComponent("activation-flow/this-device/activate-by-email/success")
            case .manageEmail:
                baseURL.appendingPathComponent("manage")
            case .manageSubscriptionsInAppStore:
                StaticURLs.manageSubscriptionsInMacAppStoreURL
            case .identityTheftRestoration:
                baseURL.replacing(path: "identity-theft-restoration")
            }
        }()

        if environment == .staging, hasStagingVariant {
            return url.forStaging()
        }

        return url
    }

    private var hasStagingVariant: Bool {
        switch self {
        case .faq, .manageSubscriptionsInAppStore:
            false
        default:
            true
        }
    }
}

fileprivate extension URL {

    enum EnvironmentParameter {
        static let name = "environment"
        static let staging = "staging"
    }

    func forStaging() -> URL {
        self.appendingParameter(name: EnvironmentParameter.name, value: EnvironmentParameter.staging)
    }

}

extension URL {

    public func forComparison() -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }

        if let queryItems = components.queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems.filter { !["environment", "origin", "using"].contains($0.name) }
            if components.queryItems?.isEmpty ?? true {
                components.queryItems = nil
            }
        } else {
            components.queryItems = nil
        }
        return components.url ?? self
    }
}
