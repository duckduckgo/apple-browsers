//
//  OAuthClient.swift
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
import os.log

public enum OAuthClientError: Error, LocalizedError, Equatable {
    case internalError(String)
    case missingTokenContainer
    case unauthenticated
    case invalidTokenRequest
    case authMigrationNotPerformed
    case unknownAccount

    public var errorDescription: String? {
        switch self {
        case .internalError(let error):
            return "Internal error: \(error)"
        case .missingTokenContainer:
            return "No tokens available"
        case .unauthenticated:
            return "The account is not authenticated, please re-authenticate"
        case .invalidTokenRequest:
            return "Invalid token request"
        case .authMigrationNotPerformed:
            return "Auth migration not needed"
        case .unknownAccount:
            return "Unknown account"
        }
    }

    public var localizedDescription: String {
        errorDescription ?? "Unknown"
    }
}

/// Provides the locally stored tokens container
public protocol AuthTokenStoring {
    func getTokenContainer() throws -> TokenContainer?
    func saveTokenContainer(_ tokenContainer: TokenContainer?) throws
}

/// Provides the legacy AuthToken V1
public protocol LegacyAuthTokenStoring {
    var token: String? { get set }
}

public enum AuthTokensCachePolicy {
    /// The token container from the local storage
    case local
    /// The token container from the local storage, refreshed if needed
    case localValid
    /// A refreshed token
    case localForceRefresh
    /// Like `.localValid`,  if doesn't exist create a new one
    case createIfNeeded

    public var description: String {
        switch self {
        case .local:
            return "Local"
        case .localValid:
            return "Local valid"
        case .localForceRefresh:
            return "Local force refresh"
        case .createIfNeeded:
            return "Create if needed"
        }
    }
}

public protocol OAuthClient {

    var isUserAuthenticated: Bool { get }

    func currentTokenContainer() throws -> TokenContainer?

    func setCurrentTokenContainer(_ tokenContainer: TokenContainer?) throws

    /// Returns a tokens container based on the policy
    /// - `.local`: Returns what's in the storage, as it is, throws an error if no token is available
    /// - `.localValid`: Returns what's in the storage, refreshes it if needed. throws an error if no token is available
    /// - `.localForceRefresh`: Returns what's in the storage but forces a refresh first. throws an error if no refresh token is available.
    /// - `.createIfNeeded`: Returns what's in the storage, if the stored token is expired refreshes it, if not token is available creates a new account/token
    /// All options store new or refreshed tokens via the tokensStorage
    func getTokens(policy: AuthTokensCachePolicy) async throws -> TokenContainer

    /// Checks if the migration from V1 to V2 is possible
    /// - Returns: true is possible, false otherwise
    var isV1TokenPresent: Bool { get }

    /// Migrate access token v1 to auth token v2 if needed
    /// - Throws: An error in case of failures during the migration or a `OAuthClientError.authMigrationNotPerformed` if the migration is not needed or not possible
    func migrateV1Token() async throws

    /// Use the TokenContainer provided
    func adopt(tokenContainer: TokenContainer) throws

    // Creates a TokenContainer with the provided access token and refresh token, decodes them and returns the container
    func decode(accessToken: String, refreshToken: String) async throws -> TokenContainer

    /// Activate the account with a platform signature
    /// - Parameter signature: The platform signature
    /// - Returns: A container of tokens
    func activate(withPlatformSignature signature: String) async throws -> TokenContainer

    /// Exchange token v1 for tokens v2
    /// - Parameter accessTokenV1: The legacy auth token
    /// - Returns: A TokenContainer with access and refresh tokens
    @discardableResult func exchange(accessTokenV1: String) async throws -> TokenContainer

    // MARK: Logout

    /// Logout by invalidating the current access token
    func logout() async throws

    /// Remove the tokens container stored locally
    func removeLocalAccount() throws
}

final public actor DefaultOAuthClient: @preconcurrency OAuthClient {

    private struct Constants {
        /// https://app.asana.com/0/1205784033024509/1207979495854201/f
        static let clientID = "f4311287-0121-40e6-8bbd-85c36daf1837"
        static let redirectURI = "com.duckduckgo:/authcb"
        static let availableScopes = [ "privacypro" ]

        /// The seconds before the expiry date when we consider a token effectively expired
        static let tokenExpiryBufferInterval: TimeInterval = .seconds(45)
    }

    private let authService: any OAuthService
    private var tokenStorage: any AuthTokenStoring
    private var legacyTokenStorage: (any LegacyAuthTokenStoring)?
    private var migrationOngoingTask: Task<Void, Error>?

    public init(tokensStorage: any AuthTokenStoring,
                legacyTokenStorage: (any LegacyAuthTokenStoring)?,
                authService: OAuthService) {
        self.tokenStorage = tokensStorage
        self.legacyTokenStorage = legacyTokenStorage
        self.authService = authService
    }

    // MARK: - Internal

    @discardableResult
    func getTokens(authCode: String, codeVerifier: String) async throws -> TokenContainer {
        Logger.OAuthClient.log("Getting tokens")
        let getTokensResponse = try await authService.getAccessToken(clientID: Constants.clientID,
                                                             codeVerifier: codeVerifier,
                                                             code: authCode,
                                                             redirectURI: Constants.redirectURI)
        return try await decode(accessToken: getTokensResponse.accessToken, refreshToken: getTokensResponse.refreshToken)
    }

    func getVerificationCodes() async throws -> (codeVerifier: String, codeChallenge: String) {
        Logger.OAuthClient.log("Getting verification codes")
        let codeVerifier = try OAuthCodesGenerator.generateCodeVerifier()
        guard let codeChallenge = OAuthCodesGenerator.codeChallenge(codeVerifier: codeVerifier) else {
            Logger.OAuthClient.error("Failed to get verification codes")
            throw OAuthClientError.internalError("Failed to generate code challenge")
        }
        return (codeVerifier, codeChallenge)
    }

#if DEBUG
    func setTestingDecodedTokenContainer(_ container: TokenContainer) {
        testingDecodedTokenContainer = container
    }

    private var testingDecodedTokenContainer: TokenContainer?
#endif

    public func decode(accessToken: String, refreshToken: String) async throws -> TokenContainer {
        Logger.OAuthClient.log("Decoding tokens")

#if DEBUG
        if let testingDecodedTokenContainer {
            return testingDecodedTokenContainer
        }
#endif

        let jwtSigners = try await authService.getJWTSigners()
        let decodedAccessToken = try jwtSigners.verify(accessToken, as: JWTAccessToken.self)
        let decodedRefreshToken = try jwtSigners.verify(refreshToken, as: JWTRefreshToken.self)

        return TokenContainer(accessToken: accessToken,
                               refreshToken: refreshToken,
                               decodedAccessToken: decodedAccessToken,
                               decodedRefreshToken: decodedRefreshToken)
    }

    // MARK: - Public

    public var isUserAuthenticated: Bool {
        let tokenContainer = try? tokenStorage.getTokenContainer()
        return tokenContainer != nil
    }

    public func currentTokenContainer() throws -> TokenContainer? {
        try tokenStorage.getTokenContainer()
    }

    public func setCurrentTokenContainer(_ tokenContainer: TokenContainer?) throws {
        try tokenStorage.saveTokenContainer(tokenContainer)
    }

    public func getTokens(policy: AuthTokensCachePolicy) async throws -> TokenContainer {
        let localTokenContainer = try tokenStorage.getTokenContainer()

        switch policy {
        case .local:
            guard let localTokenContainer else {
                Logger.OAuthClient.log("Tokens not found")
                throw OAuthClientError.missingTokenContainer
            }
            Logger.OAuthClient.log("Local tokens found, expiry: \(localTokenContainer.decodedAccessToken.exp.value, privacy: .public)")
            return localTokenContainer

        case .localValid:
            guard let localTokenContainer else {
                Logger.OAuthClient.log("Tokens not found")
                throw OAuthClientError.missingTokenContainer
            }
            let tokenExpiryDate = localTokenContainer.decodedAccessToken.exp.value
            Logger.OAuthClient.log("Local tokens found, expiry: \(tokenExpiryDate, privacy: .public)")

            // If the token expires in less than `Constants.tokenExpiryBufferInterval` minutes we treat it as already expired
            let expirationInterval = tokenExpiryDate.timeIntervalSinceNow
            let expiresSoon = expirationInterval < Constants.tokenExpiryBufferInterval
            if localTokenContainer.decodedAccessToken.isExpired() || expiresSoon {
                Logger.OAuthClient.log("Refreshing local already expired token")
                return try await getTokens(policy: .localForceRefresh)
            } else {
                return localTokenContainer
            }

        case .localForceRefresh:
            guard let localTokenContainer else {
                Logger.OAuthClient.log("Tokens not found")
                throw OAuthClientError.missingTokenContainer
            }
            do {
                let refreshTokenResponse = try await authService.refreshAccessToken(clientID: Constants.clientID, refreshToken: localTokenContainer.refreshToken)
                let refreshedTokens = try await decode(accessToken: refreshTokenResponse.accessToken, refreshToken: refreshTokenResponse.refreshToken)
                Logger.OAuthClient.log("Tokens refreshed, expiry: \(refreshedTokens.decodedAccessToken.exp.value.description, privacy: .public)")
                try tokenStorage.saveTokenContainer(refreshedTokens)
                return refreshedTokens
            } catch OAuthServiceError.authAPIError(let code) where code == .invalidTokenRequest {
                Logger.OAuthClient.error("Failed to refresh token: invalidTokenRequest")
                throw OAuthClientError.invalidTokenRequest
            } catch OAuthServiceError.authAPIError(let code) where code == .unknownAccount {
                Logger.OAuthClient.error("Failed to refresh token: unknownAccount")
                throw OAuthClientError.unknownAccount
            } catch {
                Logger.OAuthClient.error("Failed to refresh token: \(error.localizedDescription, privacy: .public)")
                throw error
            }

        case .createIfNeeded:
            do {
                return try await getTokens(policy: .localValid)
            } catch {
                Logger.OAuthClient.log("Local token not found, creating a new account")
                do {
                    let tokenContainer = try await createAccount()
                    try tokenStorage.saveTokenContainer(tokenContainer)
                    return tokenContainer
                } catch {
                    Logger.OAuthClient.fault("Failed to create account: \(error.localizedDescription, privacy: .public)")
                    throw error
                }
            }
        }
    }

    public var isV1TokenPresent: Bool {
        guard let legacyTokenStorage,
              let legacyToken = legacyTokenStorage.token,
              !legacyToken.isEmpty else {
            return false
        }
        return true
    }

    /// Tries to retrieve the v1 auth token stored locally, if present performs a migration to v2
    public func migrateV1Token() async throws {

        if let task = migrationOngoingTask {
            return try await task.value
        }

        let task = Task {
            defer { migrationOngoingTask = nil }

            guard !isUserAuthenticated else {
                throw OAuthClientError.authMigrationNotPerformed
            }

            guard var legacyTokenStorage else {
                Logger.OAuthClient.fault("Auth migration attempted without a LegacyTokenStorage")
                throw OAuthClientError.authMigrationNotPerformed
            }

            guard let legacyToken = legacyTokenStorage.token,
                  !legacyToken.isEmpty else {
                throw OAuthClientError.authMigrationNotPerformed
            }

            Logger.OAuthClient.log("Migrating v1 token...")
            try await exchange(accessTokenV1: legacyToken)
            Logger.OAuthClient.log("Tokens migrated successfully")

            // After releasing Auth V2 at 100% we are now deleting the Auth V1 token.
            legacyTokenStorage.token = nil
        }

        migrationOngoingTask = task
        return try await task.value
    }

    public func adopt(tokenContainer: TokenContainer) throws {
        Logger.OAuthClient.log("Adopting TokenContainer")
        try tokenStorage.saveTokenContainer(tokenContainer)
    }

    // MARK: Create

    /// Create an accounts, stores all tokens and returns them
    func createAccount() async throws -> TokenContainer {
        Logger.OAuthClient.log("Creating new account")
        let (codeVerifier, codeChallenge) = try await getVerificationCodes()
        let authSessionID = try await authService.authorize(codeChallenge: codeChallenge)
        let authCode = try await authService.createAccount(authSessionID: authSessionID)
        let tokenContainer = try await getTokens(authCode: authCode, codeVerifier: codeVerifier)
        Logger.OAuthClient.log("New account created successfully")
        return tokenContainer
    }

    public func activate(withPlatformSignature signature: String) async throws -> TokenContainer {
        Logger.OAuthClient.log("Activating with platform signature")
        let (codeVerifier, codeChallenge) = try await getVerificationCodes()
        let authSessionID = try await authService.authorize(codeChallenge: codeChallenge)
        let authCode = try await authService.login(withSignature: signature, authSessionID: authSessionID)
        let tokenContainer = try await getTokens(authCode: authCode, codeVerifier: codeVerifier)
        try tokenStorage.saveTokenContainer(tokenContainer)
        Logger.OAuthClient.log("Activation completed")
        return tokenContainer
    }

    // MARK: Exchange V1 to V2 token

    @discardableResult public func exchange(accessTokenV1: String) async throws -> TokenContainer {
        Logger.OAuthClient.log("Exchanging access token V1 to V2")
        let (codeVerifier, codeChallenge) = try await getVerificationCodes()
        let authSessionID = try await authService.authorize(codeChallenge: codeChallenge)
        let authCode = try await authService.exchangeToken(accessTokenV1: accessTokenV1, authSessionID: authSessionID)
        let tokenContainer = try await getTokens(authCode: authCode, codeVerifier: codeVerifier)
        try tokenStorage.saveTokenContainer(tokenContainer)
        return tokenContainer
    }

    // MARK: Logout

    public func logout() async throws {
        let existingToken = try tokenStorage.getTokenContainer()?.accessToken
        try removeLocalAccount()

        // Also removing V1
        Logger.OAuthClient.log("Removing V1 token")
        legacyTokenStorage?.token = nil

        if let existingToken {
            Task { // Not waiting for an answer
                Logger.OAuthClient.log("Invalidating the V2 token")
                try? await authService.logout(accessToken: existingToken)
            }
        }
    }

    public func removeLocalAccount() throws {
        Logger.OAuthClient.log("Removing local account")
        try tokenStorage.saveTokenContainer(nil)
    }
}
