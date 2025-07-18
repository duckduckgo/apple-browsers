//
//  SubscriptionEndpointServiceMockV2.swift
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
import Networking

public final class SubscriptionEndpointServiceMockV2: SubscriptionEndpointServiceV2 {

    public var onSignOut: (() -> Void)?
    public var signOutCalled: Bool = false

    public init() { }

    public var updateCacheWithSubscriptionCalled: Bool = false
    public var onUpdateCache: ((PrivacyProSubscription) -> Void)?
    public func updateCache(with subscription: Subscription.PrivacyProSubscription) {
        onUpdateCache?(subscription)
        updateCacheWithSubscriptionCalled = true
    }

    public func clearSubscription() {}

    public var getProductsResult: Result<[GetProductsItem], APIRequestV2.Error>?
    public func getProducts() async throws -> [Subscription.GetProductsItem] {
        switch getProductsResult! {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }

    public var getSubscriptionCalled: Bool = false
    public var onGetSubscription: ((String?, SubscriptionCachePolicy) -> Void)?
    public var getSubscriptionResult: Result<PrivacyProSubscription, SubscriptionEndpointServiceError>?
    public func getSubscription(accessToken: String?, cachePolicy: Subscription.SubscriptionCachePolicy) async throws -> Subscription.PrivacyProSubscription {
        getSubscriptionCalled = true
        onGetSubscription?(accessToken, cachePolicy)
        switch getSubscriptionResult! {
        case .success(let subscription): return subscription
        case .failure(let error): throw error
        }
    }

    public var getCustomerPortalURLResult: Result<GetCustomerPortalURLResponse, APIRequestV2.Error>?
    public func getCustomerPortalURL(accessToken: String, externalID: String) async throws -> Subscription.GetCustomerPortalURLResponse {
        switch getCustomerPortalURLResult! {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }

    public var confirmPurchaseResult: Result<ConfirmPurchaseResponseV2, APIRequestV2.Error>?
    public func confirmPurchase(accessToken: String, signature: String, additionalParams: [String: String]?) async throws -> Subscription.ConfirmPurchaseResponseV2 {
        switch confirmPurchaseResult! {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }

    public var getSubscriptionFeaturesResult: Result<Subscription.GetSubscriptionFeaturesResponseV2, Error>?
    public func getSubscriptionFeatures(for subscriptionID: String) async throws -> Subscription.GetSubscriptionFeaturesResponseV2 {
        switch getSubscriptionFeaturesResult! {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }

    public func ingestSubscription(_ subscription: Subscription.PrivacyProSubscription) async throws {
        getSubscriptionResult = .success(subscription)
    }

    public func getCachedSubscription() -> Subscription.PrivacyProSubscription? {
        switch getSubscriptionResult! {
        case .success(let subscription): return subscription
        case .failure: return nil
        }
    }
}
