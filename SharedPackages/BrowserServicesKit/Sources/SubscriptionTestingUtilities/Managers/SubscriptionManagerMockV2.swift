//
//  SubscriptionManagerMockV2.swift
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
import Common
@testable import Networking
@testable import Subscription
import NetworkingTestingUtils

public final class SubscriptionManagerMockV2: SubscriptionManagerV2 {

    public var email: String?

    public var isEligibleForFreeTrialResult: Bool = false

    public init() {}

    public static var environment: Subscription.SubscriptionEnvironment?
    public static func loadEnvironmentFrom(userDefaults: UserDefaults) -> Subscription.SubscriptionEnvironment? {
        return environment
    }

    public static func save(subscriptionEnvironment: Subscription.SubscriptionEnvironment, userDefaults: UserDefaults) {
        environment = subscriptionEnvironment
    }

    public var currentEnvironment: Subscription.SubscriptionEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .appStore)

    public func loadInitialData() async {}

    public func refreshCachedSubscription(completion: @escaping (Bool) -> Void) {}

    public var resultSubscription: Subscription.PrivacyProSubscription?

    public func getSubscriptionFrom(lastTransactionJWSRepresentation: String) async throws -> Subscription.PrivacyProSubscription? {
        guard let resultSubscription else {
            throw OAuthClientError.missingTokenContainer
        }
        return resultSubscription
    }

    public var canPurchase: Bool = true

    public var resultStorePurchaseManager: (any Subscription.StorePurchaseManagerV2)?
    public func storePurchaseManager() -> any Subscription.StorePurchaseManagerV2 {
        return resultStorePurchaseManager!
    }

    public var resultURL: URL!
    public func url(for type: Subscription.SubscriptionURL) -> URL {
        return resultURL
    }

    public var urlForPurchaseFromRedirect: URL!
    public func urlForPurchaseFromRedirect(redirectURLComponents: URLComponents, tld: TLD) -> URL {
        return urlForPurchaseFromRedirect
    }

    public var customerPortalURL: URL?
    public func getCustomerPortalURL() async throws -> URL {
        guard let customerPortalURL else {
            throw SubscriptionEndpointServiceError.noData
        }
        return customerPortalURL
    }

    public var isUserAuthenticated: Bool {
        resultTokenContainer != nil
    }

    public var userEmail: String? {
        resultTokenContainer?.decodedAccessToken.email
    }

    public var resultTokenContainer: Networking.TokenContainer?
    public var resultCreateAccountTokenContainer: Networking.TokenContainer?
    public func getTokenContainer(policy: Networking.AuthTokensCachePolicy) async throws -> Networking.TokenContainer {
        switch policy {
        case .local, .localValid, .localForceRefresh:
            guard let resultTokenContainer else {
                throw OAuthClientError.missingTokenContainer
            }
            return resultTokenContainer
        case .createIfNeeded:
            guard let resultCreateAccountTokenContainer else {
                throw OAuthClientError.missingTokenContainer
            }
            resultTokenContainer = resultCreateAccountTokenContainer
            return resultCreateAccountTokenContainer
        }
    }

    public var resultExchangeTokenContainer: Networking.TokenContainer?
    public func exchange(tokenV1: String) async throws -> Networking.TokenContainer {
        guard let resultExchangeTokenContainer else {
           throw OAuthClientError.missingTokenContainer
        }
        resultTokenContainer = resultExchangeTokenContainer
        return resultExchangeTokenContainer
    }

    public func signOut(notifyUI: Bool) {
        resultTokenContainer = nil
    }

    public func removeLocalAccount() {
        resultTokenContainer = nil
    }

    public func clearSubscriptionCache() {

    }

    public var confirmPurchaseResponse: Result<Subscription.PrivacyProSubscription, Error>?
    public func confirmPurchase(signature: String, additionalParams: [String: String]?) async throws -> Subscription.PrivacyProSubscription {
        switch confirmPurchaseResponse! {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    public func refreshAccount() async {}

    public var confirmPurchaseError: Error?
    public func confirmPurchase(signature: String) async throws {
        if let confirmPurchaseError {
            throw confirmPurchaseError
        }
    }

    public func getSubscription(cachePolicy: Subscription.SubscriptionCachePolicy) async throws -> Subscription.PrivacyProSubscription {
        guard let resultSubscription else {
            throw SubscriptionEndpointServiceError.noData
        }
        return resultSubscription
    }

    public var productsResponse: Result<[Subscription.GetProductsItem], Error>?
    public func getProducts() async throws -> [Subscription.GetProductsItem] {
        switch productsResponse! {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    public func adopt(tokenContainer: Networking.TokenContainer) async throws {
        self.resultTokenContainer = tokenContainer
    }

    public var resultFeatures: [Subscription.SubscriptionFeatureV2] = []
    public func currentSubscriptionFeatures(forceRefresh: Bool) async -> [Subscription.SubscriptionFeatureV2] {
        resultFeatures
    }

    public func isFeatureAvailableForUser(_ entitlement: Networking.SubscriptionEntitlement) async -> Bool {
        resultFeatures.contains { $0.entitlement == entitlement }
    }

    // MARK: - Subscription Token Provider

    public func getAccessToken() async throws -> String {
        guard let accessToken = resultTokenContainer?.accessToken else {
            throw SubscriptionManagerError.tokenUnavailable(error: nil)
        }
        return accessToken
    }

    public func removeAccessToken() {
        resultTokenContainer = nil
    }

    public func isEnabled(feature: Subscription.Entitlement.ProductName, cachePolicy: Subscription.APICachePolicy) async throws -> Bool {
        switch feature {
        case .networkProtection:
            return await isFeatureAvailableForUser(.networkProtection)
        case .dataBrokerProtection:
            return await isFeatureAvailableForUser(.dataBrokerProtection)
        case .identityTheftRestoration:
            return await isFeatureAvailableForUser(.identityTheftRestoration)
        case .identityTheftRestorationGlobal:
            return await isFeatureAvailableForUser(.identityTheftRestorationGlobal)
        case .paidAIChat:
            return await isFeatureAvailableForUser(.paidAIChat)
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
            case .paidAIChat:
                return .paidAIChat
            case .unknown:
                return nil
            }
        }
    }

    public var adoptResult: Result<Networking.TokenContainer, Error>?
    public func adopt(accessToken: String, refreshToken: String) async throws {
        switch adoptResult! {
        case .success(let result):
            self.resultTokenContainer = result
        case .failure(let error):
            throw error
        }
    }

    public func isSubscriptionPresent() -> Bool {
        resultSubscription != nil
    }

    public func isUserEligibleForFreeTrial() -> Bool {
        isEligibleForFreeTrialResult
    }
}
