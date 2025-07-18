//
//  SubscriptionAuthV1toV2BridgeMock.swift
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

import Combine
import Foundation
import Common
@testable import Subscription

public final class SubscriptionAuthV1toV2BridgeMock: SubscriptionAuthV1toV2Bridge {

    public var isEligibleForFreeTrialResult: Bool = false

    public init() {}

    public var enabledFeatures: [Entitlement.ProductName] = []
    public func isFeatureIncludedInSubscription(_ feature: Entitlement.ProductName) async throws -> Bool {
        enabledFeatures.contains(feature)
    }
    public func isFeatureEnabled(_ feature: Entitlement.ProductName) async -> Bool {
        enabledFeatures.contains(feature)
    }

    public var subscriptionFeatures: [Entitlement.ProductName] = []
    public func currentSubscriptionFeatures() async -> [Entitlement.ProductName] {
        subscriptionFeatures
    }

    public func signOut(notifyUI: Bool) async {
        accessTokenResult = .failure(SubscriptionManagerError.noTokenAvailable)
    }

    public var canPurchase: Bool = true
    public var canPurchasePublisher: AnyPublisher<Bool, Never> = .init(Empty())
    public var returnSubscription: Result<PrivacyProSubscription, Error>!
    public func getSubscription(cachePolicy: SubscriptionCachePolicy) async throws -> PrivacyProSubscription {
        switch returnSubscription! {
        case .success(let subscription):
            return subscription
        case .failure(let error):
            throw error
        }
    }

    public var urls: [SubscriptionURL: URL] = [:]
    public func url(for type: SubscriptionURL) -> URL {
        urls[type]!
    }

    public var email: String?

    public var currentEnvironment: SubscriptionEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .appStore)

    public var urlForPurchaseFromRedirectResult: URL!
    public func urlForPurchaseFromRedirect(redirectURLComponents: URLComponents, tld: Common.TLD) -> URL {
        urlForPurchaseFromRedirectResult
    }

    public var accessTokenResult: Result<String, Error> = .failure(SubscriptionManagerError.noTokenAvailable)
    public func getAccessToken() async throws -> String {
        switch accessTokenResult {
        case .success(let token):
            return token
        case .failure(let error):
            throw error
        }
    }

    public func removeAccessToken() {
        accessTokenResult = .failure(SubscriptionManagerError.noTokenAvailable)
    }

    public var isUserAuthenticated: Bool {
        switch accessTokenResult {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    public func isSubscriptionPresent() -> Bool {
        switch returnSubscription! {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    public func isUserEligibleForFreeTrial() -> Bool {
        isEligibleForFreeTrialResult
    }
}
