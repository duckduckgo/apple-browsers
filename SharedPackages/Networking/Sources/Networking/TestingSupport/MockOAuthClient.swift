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

@_spi(Testing)
public class MockOAuthClient: OAuthClient {

    public init() {}
    public var isUserAuthenticated: Bool {
        internalCurrentTokenContainer != nil
    }
    public var internalCurrentTokenContainer: Networking.TokenContainer?
    public var currentTokenContainerError: Error?
    public func currentTokenContainer() throws -> TokenContainer? {
        if let currentTokenContainerError {
            throw currentTokenContainerError
        }
        return internalCurrentTokenContainer
    }

    public func setCurrentTokenContainer(_ tokenContainer: TokenContainer?) throws {
        internalCurrentTokenContainer = tokenContainer
    }

    public var getTokensResponse: Result<Networking.TokenContainer, Error>!
    public private(set) var getTokensTriggers: [Networking.TokenRefreshTrigger] = []
    /// The policies of every `getTokens` call, in order.
    public private(set) var getTokensPolicies: [Networking.AuthTokensCachePolicy] = []
    /// Called at the start of every `getTokens` call, before `getTokensResponse` is returned.
    public var onGetTokens: (() -> Void)?

    public func getTokens(policy: Networking.AuthTokensCachePolicy, trigger: Networking.TokenRefreshTrigger) async throws -> Networking.TokenContainer {
        getTokensTriggers.append(trigger)
        getTokensPolicies.append(policy)
        onGetTokens?()
        switch getTokensResponse! {
        case .success(let success):
            return success
        case .failure(let failure):
            throw failure
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

    /// The names of the session-ending calls received, in order: `logout`, `removeLocalAccount`, `removeBackup`.
    public private(set) var callOrder: [String] = []

    public private(set) var logoutCallCount = 0
    public var logoutError: Error?
    public func logout() async throws {
        logoutCallCount += 1
        callOrder.append("logout")
        if let logoutError {
            throw logoutError
        }
        try removeLocalAccount()
    }

    public private(set) var removeLocalAccountCallCount = 0
    public var removeLocalAccountError: Error?
    public func removeLocalAccount() throws {
        removeLocalAccountCallCount += 1
        callOrder.append("removeLocalAccount")
        if let removeLocalAccountError {
            throw removeLocalAccountError
        }
        internalCurrentTokenContainer = nil
    }

    /// The result of `restoreFromBackup`. When nil, it throws `TokenBackupError.unavailable`. On success the container also becomes the current one.
    public var restoreFromBackupResponse: Result<Networking.TokenContainer, Error>?
    /// The `(expectedExternalID, notIssuedBefore)` arguments of every `restoreFromBackup` call, in order.
    public private(set) var restoreFromBackupCalls: [(expectedExternalID: String?, notIssuedBefore: Date?)] = []
    /// Called at the start of every `restoreFromBackup` call, before `restoreFromBackupResponse` is returned.
    public var onRestoreFromBackup: (() -> Void)?
    public func restoreFromBackup(expectedExternalID: String?, notIssuedBefore: Date?) async throws -> Networking.TokenContainer {
        restoreFromBackupCalls.append((expectedExternalID, notIssuedBefore))
        onRestoreFromBackup?()
        switch restoreFromBackupResponse {
        case .success(let tokenContainer):
            internalCurrentTokenContainer = tokenContainer
            return tokenContainer
        case .failure(let error):
            throw error
        case nil:
            throw TokenBackupError.unavailable
        }
    }

    public private(set) var removeBackupCallCount = 0
    public func removeBackup() {
        removeBackupCallCount += 1
        callOrder.append("removeBackup")
    }

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
    public func decode(accessToken: String, refreshToken: String, refreshID: String?) async throws -> Networking.TokenContainer {
        switch decodeResponse! {
        case .success(let success):
            return success
        case .failure(let failure):
            throw failure
        }
    }
}
