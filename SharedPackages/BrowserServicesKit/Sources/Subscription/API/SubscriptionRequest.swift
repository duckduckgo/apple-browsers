//
//  SubscriptionRequest.swift
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
import Networking
import Common

struct SubscriptionRequest {
    let apiRequest: APIRequestV2

    // MARK: Get subscription

    static func getSubscription(baseURL: URL, accessToken: String) -> SubscriptionRequest? {
        let path = "/subscription"
        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         headers: APIRequestV2.HeadersV2(authToken: accessToken),
                                         timeoutInterval: 20,
                                         retryPolicy: APIRequestV2.RetryPolicy(maxRetries: 3, delay: .exponential(baseDelay: .seconds(2)))) else {
            return nil
        }
        return SubscriptionRequest(apiRequest: request)
    }

    static func getProducts(baseURL: URL) -> SubscriptionRequest? {
        let path = "/products"
        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .get) else {
            return nil
        }
        return SubscriptionRequest(apiRequest: request)
    }

    static func getCustomerPortalURL(baseURL: URL, accessToken: String, externalID: String) -> SubscriptionRequest? {
        let path = "/checkout/portal"
        let headers = [
            "externalAccountId": externalID
        ]
        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .get,
                                         headers: APIRequestV2.HeadersV2(authToken: accessToken,
                                                                         additionalHeaders: headers)) else {
            return nil
        }
        return SubscriptionRequest(apiRequest: request)
    }

    static func confirmPurchase(baseURL: URL, accessToken: String, signature: String, additionalParams: [String: String]?) -> SubscriptionRequest? {
        let path = "/purchase/confirm/apple"
        var bodyDict = ["signedTransactionInfo": signature]

        if let additionalParams {
            bodyDict.merge(additionalParams) { (_, new) in new }
        }

        guard let bodyData = CodableHelper.encode(bodyDict) else { return nil }
        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .post,
                                         headers: APIRequestV2.HeadersV2(authToken: accessToken),
                                         body: bodyData,
                                         retryPolicy: APIRequestV2.RetryPolicy(maxRetries: 3, delay: .fixed(.seconds(2)))) else {
            return nil
        }
        return SubscriptionRequest(apiRequest: request)
    }

    static func subscriptionFeatures(baseURL: URL, subscriptionID: String) -> SubscriptionRequest? {
        let path = "/products/\(subscriptionID)/features"
        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         cachePolicy: .returnCacheDataElseLoad) else { // Cached on purpose, the response never changes
            return nil
        }
        return SubscriptionRequest(apiRequest: request)
    }
}
