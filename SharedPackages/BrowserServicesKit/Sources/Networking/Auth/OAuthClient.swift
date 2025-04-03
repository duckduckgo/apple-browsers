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
    case missingTokens
    case missingRefreshToken
    case unauthenticated
    /// When both access token and refresh token are expired
    case refreshTokenExpired
    case invalidTokenRequest

    public var errorDescription: String? {
        switch self {
        case .internalError(let error):
            return "Internal error: \(error)"
        case .missingTokens:
            return "No token available"
        case .missingRefreshToken:
            return "No refresh token available, please re-authenticate"
        case .unauthenticated:
            return "The account is not authenticated, please re-authenticate"
        case .refreshTokenExpired:
            return "The refresh token is expired, the token is unrecoverable please re-authenticate"
        case .invalidTokenRequest:
            return "Invalid token request"
        }
    }
}

/// Provides the locally stored tokens container
public protocol AuthTokenStoring {
    var tokenContainer: TokenContainer? { get set }
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

    var currentTokenContainer: TokenContainer? { get set }

    /// Returns a tokens container based on the policy
    /// - `.local`: Returns what's in the storage, as it is, throws an error if no token is available
    /// - `.localValid`: Returns what's in the storage, refreshes it if needed. throws an error if no token is available
    /// - `.localForceRefresh`: Returns what's in the storage but forces a refresh first. throws an error if no refresh token is available.
    /// - `.createIfNeeded`: Returns what's in the storage, if the stored token is expired refreshes it, if not token is available creates a new account/token
    /// All options store new or refreshed tokens via the tokensStorage
    func getTokens(policy: AuthTokensCachePolicy) async throws -> TokenContainer

    /// Migrate access token v1 to auth token v2 if needed
    /// - Returns: A valid TokenContainer if a token v1 is found in the LegacyTokenContainer, nil if no v1 token is available. Throws an error in case of failures during the migration
    func migrateV1Token() async throws -> TokenContainer?

    /// Use the TokenContainer provided
    func adopt(tokenContainer: TokenContainer)

    // Creates a TokenContainer with the provided access token and refresh token, decodes them and returns the container
    func decode(accessToken: String, refreshToken: String) async throws -> TokenContainer

    /// Activate the account with a platform signature
    /// - Parameter signature: The platform signature
    /// - Returns: A container of tokens
    func activate(withPlatformSignature signature: String) async throws -> TokenContainer

    /// Exchange token v1 for tokens v2
    /// - Parameter accessTokenV1: The legacy auth token
    /// - Returns: A TokenContainer with access and refresh tokens
    func exchange(accessTokenV1: String) async throws -> TokenContainer

    // MARK: Logout

    /// Logout by invalidating the current access token
    func logout() async throws

    /// Remove the tokens container stored locally
    func removeLocalAccount()
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
        let codeVerifier = OAuthCodesGenerator.codeVerifier
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
        tokenStorage.tokenContainer != nil
    }

    public var currentTokenContainer: TokenContainer? {
        get  {
            tokenStorage.tokenContainer
        }
        set {
            tokenStorage.tokenContainer = newValue
        }
    }

    public func getTokens(policy: AuthTokensCachePolicy) async throws -> TokenContainer {
        let localTokenContainer = tokenStorage.tokenContainer

        if policy != .local,
           let localTokenContainer,
            localTokenContainer.decodedRefreshToken.isExpired() {
            // The refresh token is expired, the token is un-refreshable
            throw OAuthClientError.refreshTokenExpired
        }

        switch policy {

        case .local:
            guard let localTokenContainer else {
                Logger.OAuthClient.log("Tokens not found")
                throw OAuthClientError.missingTokens
            }
            Logger.OAuthClient.log("Local tokens found, expiry: \(localTokenContainer.decodedAccessToken.exp.value, privacy: .public)")
            return localTokenContainer

        case .localValid:
            guard let localTokenContainer else {
                Logger.OAuthClient.log("Tokens not found")
                throw OAuthClientError.missingTokens
            }
            let tokenExpiryDate = localTokenContainer.decodedAccessToken.exp.value
            Logger.OAuthClient.log("Local tokens found, expiry: \(tokenExpiryDate, privacy: .public)")

            // If the token expires in less than `Constants.tokenExpiryBufferInterval` minutes we treat it as already expired
            let expiresSoon = tokenExpiryDate.timeIntervalSinceNow < Constants.tokenExpiryBufferInterval
            if localTokenContainer.decodedAccessToken.isExpired() || expiresSoon {
                Logger.OAuthClient.log("Refreshing local expired token")
                return try await getTokens(policy: .localForceRefresh)
            } else {
                return localTokenContainer
            }

        case .localForceRefresh:
            guard let refreshToken = localTokenContainer?.refreshToken else {
                Logger.OAuthClient.log("Refresh token not found")
                throw OAuthClientError.missingRefreshToken
            }
            do {
                let refreshTokenResponse = try await authService.refreshAccessToken(clientID: Constants.clientID, refreshToken: refreshToken)
                let refreshedTokens = try await decode(accessToken: refreshTokenResponse.accessToken, refreshToken: refreshTokenResponse.refreshToken)
                Logger.OAuthClient.log("Tokens refreshed, expiry: \(refreshedTokens.decodedAccessToken.exp.value.description, privacy: .public)")
                tokenStorage.tokenContainer = refreshedTokens
                return refreshedTokens
            } catch OAuthServiceError.authAPIError(let code) where code == OAuthRequest.BodyErrorCode.invalidTokenRequest {
                Logger.OAuthClient.error("Failed to refresh token: invalidTokenRequest")
                throw OAuthClientError.invalidTokenRequest
            } catch OAuthServiceError.authAPIError(let code) {
                Logger.OAuthClient.error("Failed to refresh token: \(code.rawValue, privacy: .public), \(code.description, privacy: .public)")
                throw OAuthServiceError.authAPIError(code: code)
            }

        case .createIfNeeded:
            do {
                return try await getTokens(policy: .localValid)
            } catch {
                Logger.OAuthClient.log("Local token not found, creating a new account")
                do {
                    let tokens = try await createAccount()
                    tokenStorage.tokenContainer = tokens
                    return tokens
                } catch {
                    Logger.OAuthClient.fault("Failed to create account: \(error, privacy: .public)")
                    throw error
                }
            }
        }
    }

    /// Tries to retrieve the v1 auth token stored locally, if present performs a migration to v2 and removes the old token
    public func migrateV1Token() async throws -> TokenContainer? {
        guard !isUserAuthenticated else {
            Logger.OAuthClient.log("Migration not needed, user is already authenticated")
            return nil
        }

        guard let legacyTokenStorage else {
            Logger.OAuthClient.fault("Auth migration attempted without a LegacyTokenStorage")
            return nil
        }

        guard let legacyToken = legacyTokenStorage.token,
              !legacyToken.isEmpty else {
            Logger.OAuthClient.log("No V1 token available, migration not needed")
            return nil
        }

        Logger.OAuthClient.log("Migrating legacy token...")
        do {
            let tokenContainer = try await exchange(accessTokenV1: legacyToken)
            Logger.OAuthClient.log("Tokens migrated successfully")

            // NOTE: We don't remove the old token to allow roll back to Auth V1

            return tokenContainer
        } catch {
            Logger.OAuthClient.error("Failed to migrate legacy token: \(error, privacy: .public)")
            throw error
        }
    }

    public func adopt(tokenContainer: TokenContainer) {
        Logger.OAuthClient.log("Adopting TokenContainer")
        tokenStorage.tokenContainer = tokenContainer
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
        let tokens = try await getTokens(authCode: authCode, codeVerifier: codeVerifier)
        tokenStorage.tokenContainer = tokens
        Logger.OAuthClient.log("Activation completed")
        return tokens
    }

    // MARK: Exchange V1 to V2 token

    public func exchange(accessTokenV1: String) async throws -> TokenContainer {
        Logger.OAuthClient.log("Exchanging access token V1 to V2")
        let (codeVerifier, codeChallenge) = try await getVerificationCodes()
        let authSessionID = try await authService.authorize(codeChallenge: codeChallenge)
        let authCode = try await authService.exchangeToken(accessTokenV1: accessTokenV1, authSessionID: authSessionID)
        let tokenContainer = try await getTokens(authCode: authCode, codeVerifier: codeVerifier)
        tokenStorage.tokenContainer = tokenContainer
        return tokenContainer
    }

    // MARK: Logout

    public func logout() async throws {
        let existingToken = tokenStorage.tokenContainer?.accessToken
        removeLocalAccount()

        // Also removing V1
        Logger.OAuthClient.log("Removing V1 token")
        legacyTokenStorage?.token = nil

        if let existingToken {
            Logger.OAuthClient.log("Logging out")
            try await authService.logout(accessToken: existingToken)
        }
    }

    public func removeLocalAccount() {
        Logger.OAuthClient.log("Removing local account")
        tokenStorage.tokenContainer = nil
    }
}
