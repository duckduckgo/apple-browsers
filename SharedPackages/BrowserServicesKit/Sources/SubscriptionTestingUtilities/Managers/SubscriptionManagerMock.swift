//
//  SubscriptionManagerMock.swift
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
import Combine
import Common
@testable import Networking
@testable import Subscription
import NetworkingTestingUtils

public final class SubscriptionManagerMock: SubscriptionManager {

    public var isEligibleForFreeTrialResult: Bool = false

    public init() {}

    public static var environment: SubscriptionEnvironment?
    public static func loadEnvironmentFrom(userDefaults: UserDefaults) -> SubscriptionEnvironment? {
        return environment
    }

    public static func save(subscriptionEnvironment: SubscriptionEnvironment, userDefaults: UserDefaults) {
        environment = subscriptionEnvironment
    }

    public var currentEnvironment: SubscriptionEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .appStore)

    public func loadInitialData() async {}

    public var resultSubscription: Result<DuckDuckGoSubscription, Error>?
    public func getSubscriptionFrom(lastTransactionJWSRepresentation: String) async throws -> DuckDuckGoSubscription? {
        switch resultSubscription {
        case .success(let success):
            return success
        case .failure(let failure):
            throw failure
        case nil:
            throw SubscriptionEndpointServiceError.noData
        }
    }

    private let hasAppStoreProductsAvailableSubject = PassthroughSubject<Bool, Never>()
    public var hasAppStoreProductsAvailablePublisher: AnyPublisher<Bool, Never> {
        hasAppStoreProductsAvailableSubject.eraseToAnyPublisher()
    }

    public var hasAppStoreProductsAvailable: Bool = true {
        didSet {
            self.hasAppStoreProductsAvailableSubject.send(hasAppStoreProductsAvailable)
        }
    }

    public var resultStorePurchaseManager: (any StorePurchaseManager)?
    public func storePurchaseManager() -> any StorePurchaseManager {
        return resultStorePurchaseManager!
    }

    public var resultURL: URL!
    public var subscriptionURL: SubscriptionURL?
    public func url(for type: SubscriptionURL) -> URL {
        subscriptionURL = type
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
                throw SubscriptionManagerError.noTokenAvailable
            }
            return resultTokenContainer
        case .createIfNeeded:
            guard let resultCreateAccountTokenContainer else {
                throw SubscriptionManagerError.noTokenAvailable
            }
            resultTokenContainer = resultCreateAccountTokenContainer
            return resultCreateAccountTokenContainer
        }
    }

    public func signOut(notifyUI: Bool, userInitiated: Bool) async {
        resultTokenContainer = nil
    }

    public func removeLocalAccount() throws {
        resultTokenContainer = nil
    }

    public func clearSubscriptionCache() {

    }

    public var confirmPurchaseResponse: Result<DuckDuckGoSubscription, Error>?
    public func confirmPurchase(signature: String, additionalParams: [String: String]?) async throws -> DuckDuckGoSubscription {
        switch confirmPurchaseResponse! {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    public func getSubscription(cachePolicy: SubscriptionCachePolicy) async throws -> DuckDuckGoSubscription {
        switch resultSubscription {
        case .success(let success):
            return success
        case .failure(let failure):
            throw failure
        case nil:
            throw SubscriptionEndpointServiceError.noData
        }
    }

    public var productsResponse: Result<[GetProductsItem], Error>?
    public func getProducts() async throws -> [GetProductsItem] {
        switch productsResponse! {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    public var tierProductsResponse: Result<GetTierProductsResponse, Error>?
    public func getTierProducts(region: String?, platform: String?) async throws -> GetTierProductsResponse {
        switch tierProductsResponse! {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    public func adopt(tokenContainer: Networking.TokenContainer) async throws {
        self.resultTokenContainer = tokenContainer
    }

    public var resultFeatures: [SubscriptionEntitlement] = []
    public func currentSubscriptionFeatures(forceRefresh: Bool) async throws -> [SubscriptionEntitlement] {
        resultFeatures
    }

    public func isFeatureIncludedInSubscription(_ feature: Networking.SubscriptionEntitlement) async throws -> Bool {
        resultFeatures.contains(feature)
    }

    public func isFeatureEnabled(_ feature: Networking.SubscriptionEntitlement) async throws -> Bool {
        resultFeatures.contains(feature)
    }

    public func getAllEntitlementStatus() async -> EntitlementStatus {
        EntitlementStatus(enabledEntitlements: resultFeatures)
    }

    // MARK: - Subscription Token Provider

    public func getAccessToken() async throws -> String {
        guard let accessToken = resultTokenContainer?.accessToken else {
            throw SubscriptionManagerError.noTokenAvailable
        }
        return accessToken
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
        switch resultSubscription {
        case .success(let success):
            return true
        case .failure(let failure):
            return false
        case nil:
            return false
        }
    }

    public func isUserEligibleForFreeTrial() -> Bool {
        isEligibleForFreeTrialResult
    }

    public var currentStorefrontRegion: SubscriptionRegion = .usa
}
