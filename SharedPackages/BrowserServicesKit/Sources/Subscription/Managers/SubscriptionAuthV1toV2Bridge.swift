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
import Combine
import Common
import Networking

/// Temporary bridge between auth v1 and v2, this is implemented by SubscriptionManager V1 and V2
public protocol SubscriptionAuthV1toV2Bridge: SubscriptionTokenProvider, SubscriptionAuthenticationStateProvider {

    /// If the feature is enabled in the app, based on Subscription entitlements
    /// This is mostly used by the UI for showing features and their state
    func isFeatureAvailableAndEnabled(feature: Entitlement.ProductName, cachePolicy: APICachePolicy) async throws -> Bool
    /// If the user is allowed to use the feature, base on the TokenContainer entitlements
    /// This is used by VPN and PIR
    func isFeatureEnabledForUser(feature: Entitlement.ProductName) async -> Bool

    func currentSubscriptionFeatures() async -> [Entitlement.ProductName]
    func signOut(notifyUI: Bool) async
    var canPurchase: Bool { get }
    /// Publisher that emits a boolean value indicating whether the user can purchase.
    var canPurchasePublisher: AnyPublisher<Bool, Never> { get }
    @discardableResult func getSubscription(cachePolicy: SubscriptionCachePolicy) async throws -> PrivacyProSubscription
    func isSubscriptionPresent() -> Bool
    func url(for type: SubscriptionURL) -> URL
    var email: String? { get }
    var currentEnvironment: SubscriptionEnvironment { get }
    func urlForPurchaseFromRedirect(redirectURLComponents: URLComponents, tld: TLD) -> URL

    /// Checks if the user is eligible for a free trial.
    ///
    /// - Important: This method is part of a temporary bridge for the AuthV1 to AuthV2 migration.
    ///   Once the migration to AuthV2 is complete, callers should ideally access the `storePurchaseManager()`
    ///   on an instance of `DefaultSubscriptionManagerV2` (or the final AuthV2 manager) and then call
    ///   `storePurchaseManager().isUserEligibleForFreeTrial()` directly.
    func isUserEligibleForFreeTrial() -> Bool
}

extension SubscriptionAuthV1toV2Bridge {

    public func isEnabled(feature: Entitlement.ProductName) async throws -> Bool {
        try await isFeatureAvailableAndEnabled(feature: feature, cachePolicy: .returnCacheDataElseLoad)
    }
}

extension Entitlement.ProductName {

    public var subscriptionEntitlement: SubscriptionEntitlement {
        switch self {
        case .networkProtection:
            return .networkProtection
        case .dataBrokerProtection:
            return .dataBrokerProtection
        case .identityTheftRestoration:
            return .identityTheftRestoration
        case .identityTheftRestorationGlobal:
            return .identityTheftRestorationGlobal
        case .paidAIChat:
            return .paidAIChat
        case .unknown:
            return .unknown
        }
    }
}

extension SubscriptionEntitlement {

    public var product: Entitlement.ProductName {
        switch self {
        case .networkProtection:
            return .networkProtection
        case .dataBrokerProtection:
            return .dataBrokerProtection
        case .identityTheftRestoration:
            return .identityTheftRestoration
        case .identityTheftRestorationGlobal:
            return .identityTheftRestorationGlobal
        case .paidAIChat:
            return .paidAIChat
        case .unknown:
            return .unknown
        }
    }
}

extension DefaultSubscriptionManager: SubscriptionAuthV1toV2Bridge {

    public func isFeatureEnabledForUser(feature: Entitlement.ProductName) async -> Bool {
        let result = await accountManager.hasEntitlement(forProductName: feature, cachePolicy: .returnCacheDataDontLoad)
        switch result {
        case .success(let hasEntitlements):
            return hasEntitlements
        case .failure:
            return false
        }
    }

    public func isFeatureAvailableAndEnabled(feature: Entitlement.ProductName, cachePolicy: APICachePolicy) async throws -> Bool {

        let result = await accountManager.hasEntitlement(forProductName: feature, cachePolicy: cachePolicy)
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

    public func isSubscriptionPresent() -> Bool {
        accountManager.isUserAuthenticated
    }

    /// Checks if the user is eligible for a free trial.
    ///
    /// - Important: This method is part of a temporary bridge for the AuthV1 to AuthV2 migration.
    ///   Once the migration to AuthV2 is complete, callers should ideally access the `storePurchaseManager()`
    ///   on an instance of `DefaultSubscriptionManagerV2` (or the final AuthV2 manager) and then call
    ///   `storePurchaseManager().isUserEligibleForFreeTrial()` directly.
    public func isUserEligibleForFreeTrial() -> Bool {
        guard currentEnvironment.purchasePlatform != .stripe, #available(macOS 12.0, *) else { return false }
        return storePurchaseManager().isUserEligibleForFreeTrial()
    }
}

extension DefaultSubscriptionManagerV2: SubscriptionAuthV1toV2Bridge {

    public func isFeatureEnabledForUser(feature: Entitlement.ProductName) async -> Bool {
        do {
            guard let tokenContainer = try self.oAuthClient.currentTokenContainer() else {
                return false
            }
            return tokenContainer.decodedAccessToken.subscriptionEntitlements.contains(where: { $0.product == feature })
        } catch {
            // Fallback to the cached user entitlements in case of keychain reading error
            return self.cachedUserEntitlements.contains(where: { $0.product == feature })
        }
    }

    public func isFeatureAvailableAndEnabled(feature: Entitlement.ProductName, cachePolicy: APICachePolicy) async throws -> Bool {
        return try await isSubscriptionFeatureEnabled(feature.subscriptionEntitlement)
    }

    public func currentSubscriptionFeatures() async -> [Entitlement.ProductName] {
        let result = try? await currentSubscriptionFeatures(forceRefresh: false).compactMap { subscriptionFeatureV2 in
            subscriptionFeatureV2.entitlement.product
        }
        return result ?? []
    }

    public var email: String? { userEmail }

    /// Checks if the user is eligible for a free trial.
    ///
    /// - Important: This method is part of a temporary bridge for the AuthV1 to AuthV2 migration.
    ///   Once the migration to AuthV2 is complete, callers should ideally access the `storePurchaseManager()`
    ///   on an instance of `DefaultSubscriptionManagerV2` (or the final AuthV2 manager) and then call
    ///   `storePurchaseManager().isUserEligibleForFreeTrial()` directly.
    public func isUserEligibleForFreeTrial() -> Bool {
        guard currentEnvironment.purchasePlatform != .stripe, #available(macOS 12.0, *) else { return false }
        return storePurchaseManager().isUserEligibleForFreeTrial()
    }
}
