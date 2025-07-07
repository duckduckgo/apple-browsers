//
//  MockOAuthClient.swift
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

public class MockOAuthClient: OAuthClient {

    public init() {}
    public var isUserAuthenticated: Bool {
        internalCurrentTokenContainer != nil
    }
    public var internalCurrentTokenContainer: Networking.TokenContainer?
    public func currentTokenContainer() throws -> TokenContainer? {
        internalCurrentTokenContainer
    }

    public func setCurrentTokenContainer(_ tokenContainer: TokenContainer?) throws {
        internalCurrentTokenContainer = tokenContainer
    }

    public var getTokensResponse: Result<Networking.TokenContainer, Error>!
    public func getTokens(policy: Networking.AuthTokensCachePolicy) async throws -> Networking.TokenContainer {
        switch getTokensResponse! {
        case .success(let success):
            return success
        case .failure(let failure):
            throw failure
        }
    }

    public var migrateV1TokenResponseError: Error?
    public func migrateV1Token() async throws {
        if let migrateV1TokenResponseError {
            throw migrateV1TokenResponseError
        }
    }

    public func adopt(tokenContainer: Networking.TokenContainer) {
        internalCurrentTokenContainer = tokenContainer
    }

    public var createAccountResponse: Result<Networking.TokenContainer, Error>!
    public func createAccount() async throws -> Networking.TokenContainer {
        switch createAccountResponse! {
        case .success(let success):
            return success
        case .failure(let failure):
            throw failure
        }
    }

    public var requestOTPResponse: Result<(authSessionID: String, codeVerifier: String), Error>!
    public func requestOTP(email: String) async throws -> (authSessionID: String, codeVerifier: String) {
        switch requestOTPResponse! {
        case .success(let success):
            return success
        case .failure(let failure):
            throw failure
        }
    }

    public var activateWithOTPError: Error?
    public func activate(withOTP otp: String, email: String, codeVerifier: String, authSessionID: String) async throws {
        if let activateWithOTPError {
            throw activateWithOTPError
        }
    }

    public var activateWithPlatformSignatureResponse: Result<Networking.TokenContainer, Error>!
    public func activate(withPlatformSignature signature: String) async throws -> Networking.TokenContainer {
        switch  activateWithPlatformSignatureResponse! {
        case .success(let success):
            return success
        case .failure(let failure):
            throw failure
        }
    }

    public var refreshTokensResponse: Result<Networking.TokenContainer, Error>!
    public func refreshTokens() async throws -> Networking.TokenContainer {
        switch refreshTokensResponse! {
        case .success(let success):
            return success
        case .failure(let failure):
            throw failure
        }
    }

    public var exchangeAccessTokenV1Response: Result<Networking.TokenContainer, Error>!
    public func exchange(accessTokenV1: String) async throws -> Networking.TokenContainer {
        switch exchangeAccessTokenV1Response! {
        case .success(let success):
            return success
        case .failure(let failure):
            throw failure
        }
    }

    public var logoutError: Error?
    public func logout() async throws {
        if let logoutError {
            throw logoutError
        }
    }

    public func removeLocalAccount() {}

    public var changeAccountEmailResponse: Result<String, Error>!
    public func changeAccount(email: String?) async throws -> String {
        switch changeAccountEmailResponse! {
        case .success(let success):
            return success
        case .failure(let failure):
            throw failure
        }
    }

    public var confirmChangeAccountEmailError: Error?
    public func confirmChangeAccount(email: String, otp: String, hash: String) async throws {
        if let confirmChangeAccountEmailError {
            throw confirmChangeAccountEmailError
        }
    }

    public var decodeResponse: Result<Networking.TokenContainer, Error>!
    public func decode(accessToken: String, refreshToken: String) async throws -> Networking.TokenContainer {
        switch decodeResponse! {
        case .success(let success):
            return success
        case .failure(let failure):
            throw failure
        }
    }
}
