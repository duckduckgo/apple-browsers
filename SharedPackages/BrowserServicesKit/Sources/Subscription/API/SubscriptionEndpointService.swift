//
//  SubscriptionEndpointService.swift
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

import Common
import Foundation
import Networking

public struct GetSubscriptionFeaturesResponse: Decodable {
    public let features: [Entitlement.ProductName]
}

public struct ConfirmPurchaseResponse: Decodable {
    public let email: String?
    public let entitlements: [Entitlement]
    public let subscription: PrivacyProSubscription
}

public enum SubscriptionServiceError: Error {
    case noCachedData
    case apiError(APIServiceError)
}

public protocol SubscriptionEndpointService {
    func updateCache(with subscription: PrivacyProSubscription)
    func getSubscription(accessToken: String, cachePolicy: APICachePolicy) async -> Result<PrivacyProSubscription, SubscriptionServiceError>
    func signOut()
    func getProducts() async -> Result<[GetProductsItem], APIServiceError>
    func getSubscriptionFeatures(for subscriptionID: String) async -> Result<GetSubscriptionFeaturesResponse, APIServiceError>
    func getCustomerPortalURL(accessToken: String, externalID: String) async -> Result<GetCustomerPortalURLResponse, APIServiceError>

    /// Confirms a subscription purchase by validating the provided access token and signature with the backend service.
    ///
    /// This method sends the necessary data to the server to confirm the purchase,
    /// and optionally includes additional parameters for customization.
    ///
    /// - Parameters:
    ///   - accessToken: A string representing the user's access token, used for authentication.
    ///   - signature: A string representing the purchase signature.
    ///   - additionalParams: An optional dictionary of additional parameters to include in the request.
    /// - Returns: A `Result` containing either a `ConfirmPurchaseResponse` object on success or an `APIServiceError` on failure.
    func confirmPurchase(
        accessToken: String,
        signature: String,
        additionalParams: [String: String]?
    ) async -> Result<ConfirmPurchaseResponse, APIServiceError>
}

extension SubscriptionEndpointService {

    public func getSubscription(accessToken: String) async -> Result<PrivacyProSubscription, SubscriptionServiceError> {
        await getSubscription(accessToken: accessToken, cachePolicy: .returnCacheDataElseLoad)
    }
}

/// Communicates with our backend
public struct DefaultSubscriptionEndpointService: SubscriptionEndpointService {
    private let currentServiceEnvironment: SubscriptionEnvironment.ServiceEnvironment
    private let apiService: SubscriptionAPIService
    private let subscriptionCache = UserDefaultsCache<PrivacyProSubscription>(key: UserDefaultsCacheKey.subscription,
                                                                              settings: UserDefaultsCacheSettings(defaultExpirationInterval: .minutes(20)))

    public init(currentServiceEnvironment: SubscriptionEnvironment.ServiceEnvironment, apiService: SubscriptionAPIService) {
        self.currentServiceEnvironment = currentServiceEnvironment
        self.apiService = apiService
    }

    public init(currentServiceEnvironment: SubscriptionEnvironment.ServiceEnvironment, userAgent: String) {
        self.currentServiceEnvironment = currentServiceEnvironment
        let baseURL = currentServiceEnvironment == .production ? URL(string: "https://subscriptions.duckduckgo.com/api")! : URL(string: "https://subscriptions-dev.duckduckgo.com/api")!
        let session = URLSession(configuration: URLSessionConfiguration.ephemeral)
        self.apiService = DefaultSubscriptionAPIService(baseURL: baseURL, userAgent: userAgent, session: session)
    }

    // MARK: - Subscription fetching with caching

    private func getRemoteSubscription(accessToken: String) async -> Result<PrivacyProSubscription, SubscriptionServiceError> {

        let result: Result<PrivacyProSubscription, APIServiceError> = await apiService.executeAPICall(method: "GET", endpoint: "subscription", headers: apiService.makeAuthorizationHeader(for: accessToken), body: nil)
        switch result {
        case .success(let subscriptionResponse):
            updateCache(with: subscriptionResponse)
            return .success(subscriptionResponse)
        case .failure(let error):
            return .failure(.apiError(error))
        }
    }

    public func updateCache(with subscription: PrivacyProSubscription) {

        let cachedSubscription = subscriptionCache.get()
        if subscription != cachedSubscription {
            subscriptionCache.set(subscription)
            NotificationCenter.default.post(name: .subscriptionDidChange, object: self, userInfo: [UserDefaultsCacheKey.subscription: subscription])
        }
    }

    public func clearSubscription() {
        subscriptionCache.reset()
        NotificationCenter.default.post(name: .subscriptionDidChange, object: self, userInfo: nil)
    }

    public func getSubscription(accessToken: String, cachePolicy: APICachePolicy = .returnCacheDataElseLoad) async -> Result<PrivacyProSubscription, SubscriptionServiceError> {

        switch cachePolicy {
        case .reloadIgnoringLocalCacheData:
            return await getRemoteSubscription(accessToken: accessToken)

        case .returnCacheDataElseLoad:
            if let cachedSubscription = subscriptionCache.get() {
                return .success(cachedSubscription)
            } else {
                return await getRemoteSubscription(accessToken: accessToken)
            }

        case .returnCacheDataDontLoad:
            if let cachedSubscription = subscriptionCache.get() {
                return .success(cachedSubscription)
            } else {
                return .failure(.noCachedData)
            }
        }
    }

    public func signOut() {
        subscriptionCache.reset()
    }

    // MARK: -

    public func getProducts() async -> Result<[GetProductsItem], APIServiceError> {
        await apiService.executeAPICall(method: "GET", endpoint: "products", headers: nil, body: nil)
    }

    // MARK: -

    public func getSubscriptionFeatures(for subscriptionID: String) async -> Result<GetSubscriptionFeaturesResponse, APIServiceError> {
        await apiService.executeAPICall(method: "GET", endpoint: "products/\(subscriptionID)/features", headers: nil, body: nil)
    }

    // MARK: -

    public func getCustomerPortalURL(accessToken: String, externalID: String) async -> Result<GetCustomerPortalURLResponse, APIServiceError> {
        var headers = apiService.makeAuthorizationHeader(for: accessToken)
        headers["externalAccountId"] = externalID
        return await apiService.executeAPICall(method: "GET", endpoint: "checkout/portal", headers: headers, body: nil)
    }

    // MARK: -

    public func confirmPurchase(accessToken: String, signature: String, additionalParams: [String: String]?) async -> Result<ConfirmPurchaseResponse, APIServiceError> {
        let headers = apiService.makeAuthorizationHeader(for: accessToken)
        let bodyDict = ["signedTransactionInfo": signature]

        let finalBodyDict = bodyDict.merging(additionalParams ?? [:]) { (existing, _) in existing }

        guard let bodyData = try? JSONEncoder().encode(finalBodyDict) else { return .failure(.encodingError) }
        return await apiService.executeAPICall(method: "POST", endpoint: "purchase/confirm/apple", headers: headers, body: bodyData)
    }
}
