//
//  SubscriptionAPIMockResponseFactory.swift
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
@testable import Subscription
@testable import Networking
import NetworkingTestingUtils

public struct SubscriptionAPIMockResponseFactory {

    static let authCookieHeaders = [ HTTPHeaderKey.setCookie: "ddg_auth_session_id=kADeCPMmCIHIV5uD6AFoB7Fk7pRiXFzlmQE4gW9r7FRKV8OGC1rRnZcTXoa7iIa8qgjiQCqZYq6Caww6k5HJl3; domain=duckduckgo.com; path=/api/auth/v2/; max-age=600; SameSite=Strict; secure; HttpOnly"]

    static let someAPIBodyErrorJSON = "{\"error\":\"invalid_authorization_request\"}"
    static var someAPIBodyErrorJSONData: Data {
        someAPIBodyErrorJSON.data(using: .utf8)!
    }

    static func setErrorResponse(forRequest request: APIRequestV2, apiService: MockAPIService) {
        let httpResponse = HTTPURLResponse(url: request.urlRequest.url!,
                                           statusCode: HTTPStatusCode.badRequest.rawValue,
                                           httpVersion: nil,
                                           headerFields: [:])!
        let response = APIResponseV2(data: someAPIBodyErrorJSONData, httpResponse: httpResponse)
        apiService.set(response: response, forRequest: request)
    }

    public static func mockConfirmPurchase(destinationMockAPIService apiService: MockAPIService, success: Bool) {
        let request = SubscriptionRequest.confirmPurchase(baseURL: SubscriptionEnvironment.ServiceEnvironment.staging.url,
                                                          accessToken: "somAccessToken",
                                                          signature: "someSignature",
                                                          additionalParams: nil)!
        if success {
            let jsonString = """
{"email":"","entitlements":[{"product":"Data Broker Protection","name":"subscriber"},{"product":"Identity Theft Restoration","name":"subscriber"},{"product":"Network Protection","name":"subscriber"}],"subscription":{"productId":"ios.subscription.1month","name":"Monthly Subscription","billingPeriod":"Monthly","startedAt":1730991734000,"expiresOrRenewsAt":1730992034000,"platform":"apple","status":"Auto-Renewable", "activeOffers": [] }}
"""
            let httpResponse = HTTPURLResponse(url: request.apiRequest.urlRequest.url!,
                                               statusCode: HTTPStatusCode.ok.rawValue,
                                               httpVersion: nil,
                                               headerFields: [:])!
            let response = APIResponseV2(data: jsonString.data(using: .utf8), httpResponse: httpResponse)
            apiService.set(response: response, forRequest: request.apiRequest)
        } else {
            setErrorResponse(forRequest: request.apiRequest, apiService: apiService)
        }
    }

    public static func mockGetProducts(destinationMockAPIService apiService: MockAPIService, success: Bool) {
        let request = SubscriptionRequest.getProducts(baseURL: SubscriptionEnvironment.ServiceEnvironment.staging.url)!
        if success {
            let jsonString = """
[{"productId":"ddg-privacy-pro-sandbox-monthly-renews-us","productLabel":"Monthly Subscription","billingPeriod":"Monthly","price":"9.99","currency":"USD"},{"productId":"ddg-privacy-pro-sandbox-yearly-renews-us","productLabel":"Yearly Subscription","billingPeriod":"Yearly","price":"99.99","currency":"USD"}]
"""
            let httpResponse = HTTPURLResponse(url: request.apiRequest.urlRequest.url!,
                                               statusCode: HTTPStatusCode.ok.rawValue,
                                               httpVersion: nil,
                                               headerFields: [:])!
            let response = APIResponseV2(data: jsonString.data(using: .utf8), httpResponse: httpResponse)
            apiService.set(response: response, forRequest: request.apiRequest)
        } else {
            let httpResponse = HTTPURLResponse(url: request.apiRequest.urlRequest.url!,
                                               statusCode: HTTPStatusCode.badRequest.rawValue,
                                               httpVersion: nil,
                                               headerFields: [:])!
            let response = APIResponseV2(data: someAPIBodyErrorJSONData, httpResponse: httpResponse)
            apiService.set(response: response, forRequest: request.apiRequest)
        }
    }

    public static func mockGetFeatures(destinationMockAPIService apiService: MockAPIService, success: Bool, subscriptionID: String) {
        let request = SubscriptionRequest.subscriptionFeatures(baseURL: SubscriptionEnvironment.ServiceEnvironment.staging.url, subscriptionID: subscriptionID)!
        if success {
            let jsonString = """
{"features":["Data Broker Protection","Identity Theft Restoration","Network Protection"]}
"""
            let httpResponse = HTTPURLResponse(url: request.apiRequest.urlRequest.url!,
                                               statusCode: HTTPStatusCode.ok.rawValue,
                                               httpVersion: nil,
                                               headerFields: [:])!
            let response = APIResponseV2(data: jsonString.data(using: .utf8), httpResponse: httpResponse)
            apiService.set(response: response, forRequest: request.apiRequest)
        } else {
            setErrorResponse(forRequest: request.apiRequest, apiService: apiService)
        }
    }
}
