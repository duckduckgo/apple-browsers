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
import os.log

public struct GetCustomerPortalURLResponse: Codable, Equatable {
    public let customerPortalUrl: String
}

public struct ConfirmPurchaseResponse: Codable, Equatable {
    public let email: String?
    public let subscription: DuckDuckGoSubscription
}

public struct GetSubscriptionTierFeaturesResponse: Codable {
    public let features: [String: [TierFeature]]
}

public struct GetTierProductsResponse: Codable {
    public let products: [TierProduct]
}

public struct TierProduct: Codable, Equatable {
    public let productName: String
    public let tier: TierName
    public let regions: [String]
    public let entitlements: [TierFeature]
    public let billingCycles: [BillingCycle]
}

public struct BillingCycle: Codable, Equatable {
    public let productId: String
    public let period: String  // "Monthly", "Yearly"
    public let price: String
    public let currency: String
}

public enum SubscriptionEndpointServiceError: DDGError {
    case noData
    case invalidRequest
    case invalidResponseCode(HTTPStatusCode)

    public var description: String {
        switch self {
        case .noData: "No data returned from the server."
        case .invalidRequest: "Invalid request."
        case .invalidResponseCode(let code): "Invalid response code: \(code)"
        }
    }

    public static var errorDomain: String { "com.duckduckgo.subscription.SubscriptionEndpointServiceError" }

    public var errorCode: Int {
        switch self {
        case .noData: 12300
        case .invalidRequest: 12301
        case .invalidResponseCode: 12302
        }
    }
}

public protocol SubscriptionEndpointService {

    /// Fetches the subscription from the remote backend.
    /// - Parameter accessToken: The user's access token for authentication
    /// - Returns: The subscription as returned by the server
    func getSubscription(accessToken: String) async throws -> DuckDuckGoSubscription

    /// Fetches products using the new /api/v2/products endpoint with tier information.
    /// - Parameters:
    ///   - region: Optional region filter ("us", "row")
    ///   - platform: Optional platform filter ("apple", "stripe")
    /// - Returns: A response containing products with tier and entitlement information
    func getTierProducts(region: String?, platform: String?) async throws -> GetTierProductsResponse

    /// Fetches subscription features for multiple SKUs in a single API call.
    /// This uses the new /api/v2/features endpoint that returns features with tier information.
    /// - Parameter subscriptionIDs: Array of subscription identifiers (SKUs)
    /// - Returns: A response containing features keyed by SKU, with tier information included
    func getSubscriptionTierFeatures(for subscriptionIDs: [String]) async throws -> GetSubscriptionTierFeaturesResponse
    func getCustomerPortalURL(accessToken: String, externalID: String) async throws -> GetCustomerPortalURLResponse

    /// Confirms a subscription purchase by validating the provided access token and signature with the backend service.
    ///
    /// This method sends the necessary data to the server to confirm the purchase,
    /// and optionally includes additional parameters for customization.
    ///
    /// - Parameters:
    ///   - accessToken: A string representing the user's access token, used for authentication.
    ///   - signature: A string representing the purchase signature.
    ///   - additionalParams: An optional dictionary of additional parameters to include in the request.
    /// - Returns: A `ConfirmPurchaseResponse` object on success
    func confirmPurchase(accessToken: String, signature: String, additionalParams: [String: String]?) async throws -> ConfirmPurchaseResponse
}

/// Communicates with our backend
public struct DefaultSubscriptionEndpointService: SubscriptionEndpointService {

    private let apiService: APIService
    private let baseURL: URL

    public init(apiService: APIService,
                baseURL: URL) {
        self.apiService = apiService
        self.baseURL = baseURL
    }

    // MARK: - Subscription

    public func getSubscription(accessToken: String) async throws -> DuckDuckGoSubscription {

        Logger.subscriptionEndpointService.log("Requesting subscription details")
        guard let request = SubscriptionRequest.getSubscription(baseURL: baseURL, accessToken: accessToken) else {
            throw SubscriptionEndpointServiceError.invalidRequest
        }
        let response = try await apiService.fetch(request: request.apiRequest)
        let statusCode = response.httpResponse.httpStatus

        if statusCode.isSuccess {
            let subscription: DuckDuckGoSubscription = try response.decodeBody()
            Logger.subscriptionEndpointService.log("Subscription details retrieved successfully: \(subscription.debugDescription, privacy: .public)")
            return subscription
        } else {
            if statusCode == .badRequest || statusCode == .notFound {
                Logger.subscriptionEndpointService.log("No subscription found")
                throw SubscriptionEndpointServiceError.noData
            } else {
                let bodyString: String = try response.decodeBody()
                Logger.subscriptionEndpointService.log("(\(statusCode.description) Failed to retrieve Subscription details: \(bodyString, privacy: .public)")
                throw SubscriptionEndpointServiceError.invalidResponseCode(statusCode)
            }
        }
    }

    // MARK: - Products

    public func getTierProducts(region: String?, platform: String?) async throws -> GetTierProductsResponse {
        guard let request = SubscriptionRequest.getTierProducts(baseURL: baseURL, region: region, platform: platform) else {
            throw SubscriptionEndpointServiceError.invalidRequest
        }
        let response = try await apiService.fetch(request: request.apiRequest)
        let statusCode = response.httpResponse.httpStatus

        if statusCode.isSuccess {
            Logger.subscriptionEndpointService.log("\(#function) request completed")
            return try response.decodeBody()
        } else {
            throw SubscriptionEndpointServiceError.invalidResponseCode(statusCode)
        }
    }

    // MARK: - Customer Portal

    public func getCustomerPortalURL(accessToken: String, externalID: String) async throws -> GetCustomerPortalURLResponse {
        guard let request = SubscriptionRequest.getCustomerPortalURL(baseURL: baseURL, accessToken: accessToken, externalID: externalID) else {
            throw SubscriptionEndpointServiceError.invalidRequest
        }
        let response = try await apiService.fetch(request: request.apiRequest)
        let statusCode = response.httpResponse.httpStatus
        if statusCode.isSuccess {
            Logger.subscriptionEndpointService.log("\(#function) request completed")
            return try response.decodeBody()
        } else {
            throw SubscriptionEndpointServiceError.invalidResponseCode(statusCode)
        }
    }

    // MARK: - Purchase Confirmation

    public func confirmPurchase(accessToken: String, signature: String, additionalParams: [String: String]?) async throws -> ConfirmPurchaseResponse {
        guard let request = SubscriptionRequest.confirmPurchase(baseURL: baseURL,
                                                                accessToken: accessToken,
                                                                signature: signature,
                                                                additionalParams: additionalParams) else {
            throw SubscriptionEndpointServiceError.invalidRequest
        }
        let response = try await apiService.fetch(request: request.apiRequest)
        let statusCode = response.httpResponse.httpStatus
        if statusCode.isSuccess {
            Logger.subscriptionEndpointService.log("\(#function) request completed")
            return try response.decodeBody()
        } else {
            throw SubscriptionEndpointServiceError.invalidResponseCode(statusCode)
        }
    }

    public func getSubscriptionTierFeatures(for subscriptionIDs: [String]) async throws -> GetSubscriptionTierFeaturesResponse {
        guard !subscriptionIDs.isEmpty else {
            return GetSubscriptionTierFeaturesResponse(features: [:])
        }

        guard let request = SubscriptionRequest.subscriptionTierFeatures(baseURL: baseURL, subscriptionIDs: subscriptionIDs) else {
            throw SubscriptionEndpointServiceError.invalidRequest
        }
        let response = try await apiService.fetch(request: request.apiRequest)
        let statusCode = response.httpResponse.httpStatus
        if statusCode.isSuccess {
            Logger.subscriptionEndpointService.log("\(#function) request completed for \(subscriptionIDs.count) SKUs")
            return try response.decodeBody()
        } else {
            throw SubscriptionEndpointServiceError.invalidResponseCode(statusCode)
        }
    }
}
