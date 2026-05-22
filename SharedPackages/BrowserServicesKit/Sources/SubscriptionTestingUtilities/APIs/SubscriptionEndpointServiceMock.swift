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
import Networking

public final class SubscriptionEndpointServiceMock: SubscriptionEndpointService {

    public init() { }

    // MARK: - Subscription

    public var getSubscriptionCalled: Bool = false
    public var onGetSubscription: ((String) -> Void)?
    public var getSubscriptionResult: Result<DuckDuckGoSubscription, SubscriptionEndpointServiceError>?
    public func getSubscription(accessToken: String) async throws -> DuckDuckGoSubscription {
        getSubscriptionCalled = true
        onGetSubscription?(accessToken)
        switch getSubscriptionResult! {
        case .success(let subscription): return subscription
        case .failure(let error): throw error
        }
    }

    // MARK: - Products

    public var getTierProductsResult: Result<GetTierProductsResponse, APIRequestV2Error>?
    public func getTierProducts(region: String?, platform: String?) async throws -> GetTierProductsResponse {
        switch getTierProductsResult! {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }

    // MARK: - Customer Portal

    public var getCustomerPortalURLResult: Result<GetCustomerPortalURLResponse, APIRequestV2Error>?
    public func getCustomerPortalURL(accessToken: String, externalID: String) async throws -> GetCustomerPortalURLResponse {
        switch getCustomerPortalURLResult! {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }

    // MARK: - Purchase Confirmation

    public var confirmPurchaseResult: Result<ConfirmPurchaseResponse, APIRequestV2Error>?
    public func confirmPurchase(accessToken: String, signature: String, additionalParams: [String: String]?) async throws -> ConfirmPurchaseResponse {
        switch confirmPurchaseResult! {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }

    // MARK: - Tier Features

    public var getSubscriptionTierFeaturesResult: Result<GetSubscriptionTierFeaturesResponse, Error>?
    public func getSubscriptionTierFeatures(for subscriptionIDs: [String]) async throws -> GetSubscriptionTierFeaturesResponse {
        switch getSubscriptionTierFeaturesResult! {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }
}
