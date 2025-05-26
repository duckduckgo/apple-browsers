//
//  MockOAuthService.swift
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
import JWTKit

public final class MockOAuthService: OAuthService {

    public init() {}

    public var authorizeResponse: Result<Networking.OAuthSessionID, Error>?
    public func authorize(codeChallenge: String) async throws -> Networking.OAuthSessionID {
        switch authorizeResponse! {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    public var createAccountResponse: Result<Networking.AuthorisationCode, Error>?
    public func createAccount(authSessionID: String) async throws -> Networking.AuthorisationCode {
        switch createAccountResponse! {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    public var loginWithSignatureResponse: Result<Networking.AuthorisationCode, Error>?
    public func login(withSignature signature: String, authSessionID: String) async throws -> Networking.AuthorisationCode {
        switch loginWithSignatureResponse! {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    public var getAccessTokenResponse: Result<Networking.OAuthTokenResponse, Error>?
    public func getAccessToken(clientID: String, codeVerifier: String, code: String, redirectURI: String) async throws -> Networking.OAuthTokenResponse {
        switch getAccessTokenResponse! {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    public var refreshAccessTokenResponse: Result<Networking.OAuthTokenResponse, Error>?
    public func refreshAccessToken(clientID: String, refreshToken: String) async throws -> Networking.OAuthTokenResponse {
        switch refreshAccessTokenResponse! {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    public var logoutError: Error?
    public func logout(accessToken: String) async throws {
        if let logoutError {
            throw logoutError
        }
    }

    public var exchangeTokenResponse: Result<Networking.AuthorisationCode, Error>?
    public func exchangeToken(accessTokenV1: String, authSessionID: String) async throws -> Networking.AuthorisationCode {
        switch exchangeTokenResponse! {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    public var getJWTSignersResponse: Result<JWTKit.JWTSigners, Error>?
    public func getJWTSigners() async throws -> JWTKit.JWTSigners {
        switch getJWTSignersResponse! {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}
