//
//  EnvironmentResolvingOAuthService.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import JWTKit

/// An `OAuthService` that sends each request to the auth environment `resolveEnvironment` returns when the request is made.
public struct EnvironmentResolvingOAuthService: OAuthService {

    private let production: DefaultOAuthService
    private let staging: DefaultOAuthService
    private let resolveEnvironment: () -> OAuthEnvironment

    /// - Parameters:
    ///   - apiService: Performs the requests for both environments.
    ///   - resolveEnvironment: Returns the auth environment to use. Called for every request.
    public init(apiService: any APIService, resolveEnvironment: @escaping () -> OAuthEnvironment) {
        self.production = DefaultOAuthService(baseURL: OAuthEnvironment.production.url, apiService: apiService)
        self.staging = DefaultOAuthService(baseURL: OAuthEnvironment.staging.url, apiService: apiService)
        self.resolveEnvironment = resolveEnvironment
    }

    private var current: DefaultOAuthService {
        switch resolveEnvironment() {
        case .production: return production
        case .staging: return staging
        }
    }

    public func authorize(codeChallenge: String) async throws -> OAuthSessionID {
        try await current.authorize(codeChallenge: codeChallenge)
    }

    public func createAccount(authSessionID: String) async throws -> AuthorisationCode {
        try await current.createAccount(authSessionID: authSessionID)
    }

    public func login(withSignature signature: String, authSessionID: String) async throws -> AuthorisationCode {
        try await current.login(withSignature: signature, authSessionID: authSessionID)
    }

    public func getAccessToken(clientID: String, codeVerifier: String, code: String, redirectURI: String) async throws -> OAuthTokenResponse {
        try await current.getAccessToken(clientID: clientID, codeVerifier: codeVerifier, code: code, redirectURI: redirectURI)
    }

    public func refreshAccessToken(clientID: String, refreshToken: String) async throws -> OAuthTokenResponse {
        try await current.refreshAccessToken(clientID: clientID, refreshToken: refreshToken)
    }

    public func logout(accessToken: String) async throws {
        try await current.logout(accessToken: accessToken)
    }

    public func getJWTSigners() async throws -> JWTSigners {
        try await current.getJWTSigners()
    }
}
