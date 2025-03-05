//
//  SubscriptionAuthV1toV2Bridge.swift
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

import Foundation

/// Temporary bridge between auth v1 and v2, this is implemented by SubscriptionManager V1 and V2
public protocol SubscriptionAuthV1toV2Bridge: SubscriptionTokenProvider, SubscriptionAuthenticationStateProvider {
    func isEnabled(feature: Entitlement.ProductName, cachePolicy: APICachePolicy) async throws -> Bool
    func currentSubscriptionFeatures() async -> [Entitlement.ProductName]
    func signOut(notifyUI: Bool) async
    var canPurchase: Bool { get }
    @discardableResult func getSubscription(cachePolicy: SubscriptionCachePolicy) async throws -> PrivacyProSubscription
    func url(for type: SubscriptionURL) -> URL
    var email: String? { get }
}

extension SubscriptionAuthV1toV2Bridge {
    public func isEnabled(feature: Entitlement.ProductName) async throws -> Bool {
        try await isEnabled(feature: feature, cachePolicy: .returnCacheDataElseLoad)
    }
}

extension DefaultSubscriptionManager: SubscriptionAuthV1toV2Bridge {

    public func isEnabled(feature: Entitlement.ProductName, cachePolicy: APICachePolicy) async throws -> Bool {

        let result = await accountManager.hasEntitlement(forProductName: .networkProtection, cachePolicy: cachePolicy)
        switch result {
        case .success(let hasEntitlements):
            return hasEntitlements
        case .failure(let error):
            throw error
        }
    }

    public func signOut(notifyUI: Bool) async {
        accountManager.signOut(skipNotification: !notifyUI)
    }

    public func getSubscription(cachePolicy: SubscriptionCachePolicy) async throws -> PrivacyProSubscription {
        if let accessToken = accountManager.accessToken {
            let subscriptionResult = await subscriptionEndpointService.getSubscription(accessToken: accessToken, cachePolicy: cachePolicy.apiCachePolicy)
            if case let .success(subscription) = subscriptionResult {
                return subscription
            } else {
                throw SubscriptionEndpointServiceError.noData
            }
        } else {
            throw SubscriptionEndpointServiceError.noData
        }
    }

    public var email: String? {
        accountManager.email
    }
}

extension DefaultSubscriptionManagerV2: SubscriptionAuthV1toV2Bridge {

    public func isEnabled(feature: Entitlement.ProductName, cachePolicy: APICachePolicy) async throws -> Bool {
        switch feature { // todo Check what happens if fails to fetch current features
        case .networkProtection:
            return await isFeatureAvailableForUser(.networkProtection)
        case .dataBrokerProtection:
            return await isFeatureAvailableForUser(.dataBrokerProtection)
        case .identityTheftRestoration:
            return await isFeatureAvailableForUser(.identityTheftRestoration)
        case .identityTheftRestorationGlobal:
            return await isFeatureAvailableForUser(.identityTheftRestorationGlobal)
        case .unknown:
            return false
        }
    }

    public func currentSubscriptionFeatures() async -> [Entitlement.ProductName] {
        await currentSubscriptionFeatures(forceRefresh: false).compactMap { subscriptionFeatureV2 in
            switch subscriptionFeatureV2.entitlement {
            case .networkProtection:
                return .networkProtection
            case .dataBrokerProtection:
                return .dataBrokerProtection
            case .identityTheftRestoration:
                return .identityTheftRestoration
            case .identityTheftRestorationGlobal:
                return .identityTheftRestorationGlobal
            case .unknown:
                return nil
            }
        }
    }

    public var email: String? { userEmail }
}
