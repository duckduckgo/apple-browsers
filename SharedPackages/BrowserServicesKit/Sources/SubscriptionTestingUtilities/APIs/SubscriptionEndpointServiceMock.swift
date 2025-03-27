//
//  SubscriptionEndpointServiceMock.swift
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
import Subscription

public final class SubscriptionEndpointServiceMock: SubscriptionEndpointService {
    public var getSubscriptionResult: Result<PrivacyProSubscription, SubscriptionServiceError>?
    public var getProductsResult: Result<[GetProductsItem], APIServiceError>?
    public var getSubscriptionFeaturesResult: Result<GetSubscriptionFeaturesResponse, APIServiceError>?
    public var getCustomerPortalURLResult: Result<GetCustomerPortalURLResponse, APIServiceError>?
    public var confirmPurchaseResult: Result<ConfirmPurchaseResponse, APIServiceError>?

    public var onUpdateCache: ((PrivacyProSubscription) -> Void)?
    public var onConfirmPurchase: ((String, String, [String: String]?) -> Void)?
    public var onGetSubscription: ((String, APICachePolicy) -> Void)?
    public var onSignOut: (() -> Void)?

    public var updateCacheWithSubscriptionCalled: Bool = false
    public var getSubscriptionCalled: Bool = false
    public var signOutCalled: Bool = false

    public init() { }

    public func updateCache(with subscription: PrivacyProSubscription) {
        onUpdateCache?(subscription)
        updateCacheWithSubscriptionCalled = true
    }

    public func getSubscription(accessToken: String, cachePolicy: APICachePolicy) async -> Result<PrivacyProSubscription, SubscriptionServiceError> {
        getSubscriptionCalled = true
        onGetSubscription?(accessToken, cachePolicy)
        return getSubscriptionResult!
    }

    public func signOut() {
        signOutCalled = true
        onSignOut?()
    }

    public func getProducts() async -> Result<[GetProductsItem], APIServiceError> {
        getProductsResult!
    }

    public func getSubscriptionFeatures(for subscriptionID: String) async -> Result<GetSubscriptionFeaturesResponse, APIServiceError> {
        getSubscriptionFeaturesResult!
    }

    public func getCustomerPortalURL(accessToken: String, externalID: String) async -> Result<GetCustomerPortalURLResponse, APIServiceError> {
        getCustomerPortalURLResult!
    }

    public func confirmPurchase(accessToken: String, signature: String, additionalParams: [String: String]?) async -> Result<ConfirmPurchaseResponse, APIServiceError> {
        onConfirmPurchase?(accessToken, signature, additionalParams)
        return confirmPurchaseResult!
    }
}
