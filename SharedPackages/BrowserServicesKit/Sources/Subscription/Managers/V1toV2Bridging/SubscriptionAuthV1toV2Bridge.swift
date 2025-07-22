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
import os.log

/// Temporary bridge between auth v1 and v2, this is implemented by SubscriptionManager V1 and V2
public protocol SubscriptionAuthV1toV2Bridge: SubscriptionTokenProvider, SubscriptionAuthenticationStateProvider {

    /// Whether a feature is included in the Subscription.
    ///
    /// This allows us to know if a feature is included in the current subscription.
    ///
    func isFeatureIncludedInSubscription(_ feature: Entitlement.ProductName) async throws -> Bool

    /// Whether the feature is enabled for use.
    ///
    /// This is mostly useful post-purchases.
    ///
    func isFeatureEnabled(_ feature: Entitlement.ProductName) async throws -> Bool

    func currentSubscriptionFeatures() async throws -> [Entitlement.ProductName]
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
    func isUserEligibleForFreeTrial() -> Bool
}

extension DefaultSubscriptionManager: SubscriptionAuthV1toV2Bridge {

    public func isFeatureIncludedInSubscription(_ feature: Entitlement.ProductName) async throws -> Bool {
        try await currentSubscriptionFeatures().contains(feature)
    }

    public func isFeatureEnabled(_ feature: Entitlement.ProductName) async throws -> Bool {
        let result = await accountManager.hasEntitlement(forProductName: feature, cachePolicy: .returnCacheDataElseLoad)
        switch result {
        case .success(let hasEntitlements):
            return hasEntitlements
        case .failure(let error):
            switch error {
            case APIServiceError.invalidToken:
                return false
            default:
                throw error
            }
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
    /// Returns `true` for Stripe-based purchases (on all macOS versions)
    /// or delegates to the store purchase manager for App Store purchases (requires macOS 12.0+).
    ///
    /// - Returns: 
    ///   - `true` for Stripe platform regardless of macOS version
    ///   - `storePurchaseManager().isUserEligibleForFreeTrial()` for App Store on macOS 12.0+
    ///   - `false` for App Store on macOS < 12.0
    public func isUserEligibleForFreeTrial() -> Bool {
        if currentEnvironment.purchasePlatform == .stripe {
            return true
        }
        guard #available(macOS 12.0, *) else { return false }
        return storePurchaseManager().isUserEligibleForFreeTrial()
    }
}

extension DefaultSubscriptionManagerV2: SubscriptionAuthV1toV2Bridge {

    public func isFeatureIncludedInSubscription(_ feature: Entitlement.ProductName) async throws -> Bool {
        try await currentSubscriptionFeatures().contains(feature)
    }

    public func isFeatureEnabled(_ feature: Entitlement.ProductName) async throws -> Bool {
        do {
            guard isUserAuthenticated else { return false }
            let tokenContainer = try await getTokenContainer(policy: .localValid)
            return tokenContainer.decodedAccessToken.subscriptionEntitlements.contains(feature.subscriptionEntitlement)
        } catch {
            // Fallback to the cached user entitlements in case of keychain reading error
            Logger.subscription.debug("Failed to read user entitlements from keychain: \(error, privacy: .public)")
            return self.cachedUserEntitlements.contains(feature.subscriptionEntitlement)
        }
    }

    public func currentSubscriptionFeatures() async throws -> [Entitlement.ProductName] {
        try await currentSubscriptionFeatures(forceRefresh: false).compactMap { subscriptionFeatureV2 in
            subscriptionFeatureV2.entitlement.product
        }
    }

    public var email: String? { userEmail }

    /// Checks if the user is eligible for a free trial.
    ///
    /// Returns `true` for Stripe-based purchases (on all macOS versions)
    /// or delegates to the store purchase manager for App Store purchases (requires macOS 12.0+).
    ///
    /// - Returns: 
    ///   - `true` for Stripe platform regardless of macOS version
    ///   - `storePurchaseManager().isUserEligibleForFreeTrial()` for App Store on macOS 12.0+
    ///   - `false` for App Store on macOS < 12.0
    public func isUserEligibleForFreeTrial() -> Bool {
        if currentEnvironment.purchasePlatform == .stripe {
            return true
        }
        guard #available(macOS 12.0, *) else { return false }
        return storePurchaseManager().isUserEligibleForFreeTrial()
    }
}

public enum AuthVersion: String {
    case v1
    case v2

    public static let key = "auth_version"
}
