//
//  AuthEndpointService.swift
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

import Foundation
import Common
import Networking

public struct AccessTokenResponse: Decodable {
    public let accessToken: String
}

public struct ValidateTokenResponse: Decodable {
    public let account: Account

    public struct Account: Decodable {
        public let email: String?
        public let entitlements: [Entitlement]
        public let externalID: String

        enum CodingKeys: String, CodingKey {
            case email, entitlements, externalID = "externalId" // no underscores due to keyDecodingStrategy = .convertFromSnakeCase
        }
    }
}

public struct CreateAccountResponse: Decodable {
    public let authToken: String
    public let externalID: String
    public let status: String

    enum CodingKeys: String, CodingKey {
        case authToken = "authToken", externalID = "externalId", status // no underscores due to keyDecodingStrategy = .convertFromSnakeCase
    }
}

public struct StoreLoginResponse: Decodable {
    public let authToken: String
    public let email: String
    public let externalID: String
    public let id: Int
    public let status: String

    enum CodingKeys: String, CodingKey {
        case authToken = "authToken", email, externalID = "externalId", id, status // no underscores due to keyDecodingStrategy = .convertFromSnakeCase
    }
}

public protocol AuthEndpointService {
    func getAccessToken(token: String) async -> Result<AccessTokenResponse, APIServiceError>
    func validateToken(accessToken: String) async -> Result<ValidateTokenResponse, APIServiceError>
    func createAccount(emailAccessToken: String?) async -> Result<CreateAccountResponse, APIServiceError>
    func storeLogin(signature: String) async -> Result<StoreLoginResponse, APIServiceError>
}

public struct DefaultAuthEndpointService: AuthEndpointService {
    private let currentServiceEnvironment: SubscriptionEnvironment.ServiceEnvironment
    private let apiService: SubscriptionAPIService

    public init(currentServiceEnvironment: SubscriptionEnvironment.ServiceEnvironment, apiService: SubscriptionAPIService) {
        self.currentServiceEnvironment = currentServiceEnvironment
        self.apiService = apiService
    }

    public init(currentServiceEnvironment: SubscriptionEnvironment.ServiceEnvironment) {
        self.currentServiceEnvironment = currentServiceEnvironment
        let baseURL = currentServiceEnvironment == .production ? URL(string: "https://quack.duckduckgo.com/api/auth")! : URL(string: "https://quackdev.duckduckgo.com/api/auth")!
        let session = URLSession(configuration: URLSessionConfiguration.ephemeral)
        self.apiService = DefaultSubscriptionAPIService(baseURL: baseURL, session: session)
    }

    public func getAccessToken(token: String) async -> Result<AccessTokenResponse, APIServiceError> {
        await apiService.executeAPICall(method: "GET", endpoint: "access-token", headers: apiService.makeAuthorizationHeader(for: token), body: nil)
    }

    public func validateToken(accessToken: String) async -> Result<ValidateTokenResponse, APIServiceError> {
        await apiService.executeAPICall(method: "GET", endpoint: "validate-token", headers: apiService.makeAuthorizationHeader(for: accessToken), body: nil)
    }

    public func createAccount(emailAccessToken: String?) async -> Result<CreateAccountResponse, APIServiceError> {
        var headers: [String: String]?

        if let emailAccessToken {
            headers = apiService.makeAuthorizationHeader(for: emailAccessToken)
        }

        return await apiService.executeAPICall(method: "POST", endpoint: "account/create", headers: headers, body: nil)
    }

    public func storeLogin(signature: String) async -> Result<StoreLoginResponse, APIServiceError> {
        let bodyDict = ["signature": signature,
                        "store": "apple_app_store"]

        guard let bodyData = try? JSONEncoder().encode(bodyDict) else { return .failure(.encodingError) }
        return await apiService.executeAPICall(method: "POST", endpoint: "store-login", headers: nil, body: bodyData)
    }
}
