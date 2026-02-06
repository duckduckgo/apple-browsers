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
import Common

public enum OAuthClientError: DDGError {
    case internalError(String)
    case missingTokenContainer
    case unauthenticated
    case invalidTokenRequest(OAuthRequest.TokenStatus?)
    case unknownAccount

    public var description: String {
        switch self {
        case .internalError(let errorDescription):
            return "Internal error: \(errorDescription)"
        case .missingTokenContainer:
            return "No tokens available"
        case .unauthenticated:
            return "The account is not authenticated, please re-authenticate"
        case .invalidTokenRequest(let tokenStatus):
            return "Invalid token request: \(tokenStatus?.description ?? "Unknown")"
        case .unknownAccount:
            return "Unknown account"
        }
    }

    public static var errorDomain: String { "com.duckduckgo.networking.OAuthClientError" }

    public var errorCode: Int {
        switch self {
        case .internalError:
            return 11000
        case .missingTokenContainer:
            return 11001
        case .unauthenticated:
            return 11002
        case .invalidTokenRequest:
            return 11003
        case .unknownAccount:
            return 11005
        }
    }

    public var underlyingError: (any Error)? {
        switch self {
        case .invalidTokenRequest(let tokenStatus):
            return tokenStatus
        default:
            return nil
        }
    }
}

/// Provides the locally stored tokens container
public protocol AuthTokenStoring {
    func getTokenContainer() throws -> TokenContainer?
    func saveTokenContainer(_ tokenContainer: TokenContainer?) throws
}

public enum AuthTokensCachePolicy: CustomStringConvertible {
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

    /// Use the TokenContainer provided
    func adopt(tokenContainer: TokenContainer) throws

    // Creates a TokenContainer with the provided access token and refresh token, decodes them and returns the container
    func decode(accessToken: String, refreshToken: String, refreshID: String?) async throws -> TokenContainer

    /// Activate the account with a platform signature
    /// - Parameter signature: The platform signature
    /// - Returns: A container of tokens
    func activate(withPlatformSignature signature: String) async throws -> TokenContainer

    // MARK: Logout

    /// Logout by invalidating the current access token
    func logout() async throws

    /// Remove the tokens container stored locally
    func removeLocalAccount() throws
}

public enum OAuthClientRefreshEvent {
    case tokenRefreshStarted(refreshID: String)
    case tokenRefreshRefreshingAccessToken(refreshID: String)
    case tokenRefreshRefreshedAccessToken(refreshID: String)
    case tokenRefreshFetchingJWKS(refreshID: String)
    case tokenRefreshFetchedJWKS(refreshID: String)
    case tokenRefreshVerifyingAccessToken(refreshID: String)
    case tokenRefreshVerifyingRefreshToken(refreshID: String)
    case tokenRefreshSavingTokens(refreshID: String)
    case tokenRefreshSucceeded(refreshID: String)
    case tokenRefreshFailed(refreshID: String, error: Error)
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
    private var migrationOngoingTask: Task<Void, Error>?
    private var refreshOngoingTask: Task<TokenContainer, Error>?
    private let refreshEventMapping: EventMapping<OAuthClientRefreshEvent>?

    public init(tokensStorage: any AuthTokenStoring,
                authService: OAuthService,
                refreshEventMapping: EventMapping<OAuthClientRefreshEvent>?) {
        self.tokenStorage = tokensStorage
        self.authService = authService
        self.refreshEventMapping = refreshEventMapping
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

    public func decode(accessToken: String, refreshToken: String, refreshID: String? = nil) async throws -> TokenContainer {
        Logger.OAuthClient.log("Decoding tokens")

#if DEBUG
        if let testingDecodedTokenContainer {
            return testingDecodedTokenContainer
        }
#endif

        if let refreshID { refreshEventMapping?.fire(.tokenRefreshFetchingJWKS(refreshID: refreshID)) }
        let jwtSigners = try await authService.getJWTSigners()
        if let refreshID { refreshEventMapping?.fire(.tokenRefreshFetchedJWKS(refreshID: refreshID)) }

        if let refreshID { refreshEventMapping?.fire(.tokenRefreshVerifyingAccessToken(refreshID: refreshID)) }
        let decodedAccessToken = try jwtSigners.verify(accessToken, as: JWTAccessToken.self)

        if let refreshID { refreshEventMapping?.fire(.tokenRefreshVerifyingRefreshToken(refreshID: refreshID)) }
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
            if let task = refreshOngoingTask {
                Logger.OAuthClient.log("Awaiting result from existing token refresh operation")
                return try await task.value
            }

            let refreshID = UUID().uuidString
            refreshEventMapping?.fire(.tokenRefreshStarted(refreshID: refreshID))

            guard let localTokenContainer else {
                Logger.OAuthClient.log("Tokens not found")
                let error = OAuthClientError.missingTokenContainer
                refreshEventMapping?.fire(.tokenRefreshFailed(refreshID: refreshID, error: error))
                throw error
            }

            let task = Task {
                defer {
                    self.refreshOngoingTask = nil
                }

                Logger.OAuthClient.log("Starting token refresh")

                do {
                    refreshEventMapping?.fire(.tokenRefreshRefreshingAccessToken(refreshID: refreshID))
                    let refreshTokenResponse = try await authService.refreshAccessToken(clientID: Constants.clientID, refreshToken: localTokenContainer.refreshToken)
                    refreshEventMapping?.fire(.tokenRefreshRefreshedAccessToken(refreshID: refreshID))

                    let refreshedTokens = try await decode(accessToken: refreshTokenResponse.accessToken,
                                                           refreshToken: refreshTokenResponse.refreshToken,
                                                           refreshID: refreshID)
                    Logger.OAuthClient.log("Tokens refreshed, expiry: \(refreshedTokens.decodedAccessToken.exp.value.description, privacy: .public)")

                    refreshEventMapping?.fire(.tokenRefreshSavingTokens(refreshID: refreshID))
                    try tokenStorage.saveTokenContainer(refreshedTokens)

                    refreshEventMapping?.fire(.tokenRefreshSucceeded(refreshID: refreshID))

                    return refreshedTokens
                } catch OAuthServiceError.authAPIError(let apiError) where apiError.bodyError.errorCode == .invalidTokenRequest {
                    let error = OAuthClientError.invalidTokenRequest(apiError.bodyError.tokenStatus)
                    Logger.OAuthClient.error("Failed to refresh token: \(apiError.description, privacy: .public)")
                    refreshEventMapping?.fire(.tokenRefreshFailed(refreshID: refreshID, error: error))
                    throw error
                } catch OAuthServiceError.authAPIError(let apiError) where apiError.bodyError.errorCode == .unknownAccount {
                    Logger.OAuthClient.error("Failed to refresh token: \(apiError.description, privacy: .public)")
                    let error = OAuthClientError.unknownAccount
                    refreshEventMapping?.fire(.tokenRefreshFailed(refreshID: refreshID, error: error))
                    throw error
                } catch {
                    Logger.OAuthClient.error("Failed to refresh token: \(String(describing: error), privacy: .public)")
                    refreshEventMapping?.fire(.tokenRefreshFailed(refreshID: refreshID, error: error))
                    throw error
                }
            }

            refreshOngoingTask = task
            return try await task.value

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
                    Logger.OAuthClient.fault("Failed to create account: \(String(describing: error), privacy: .public)")
                    throw error
                }
            }
        }
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

    // MARK: Logout

    public func logout() async throws {
        let existingToken = try tokenStorage.getTokenContainer()?.accessToken
        try removeLocalAccount()

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
