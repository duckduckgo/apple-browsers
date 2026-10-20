//
//  TokenRefresher.swift
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
import os.log
import Common
import DDGError

/// Exchanges refresh tokens for new token pairs and decodes them. It never reads or writes token storage.
public protocol TokenRefreshing: Sendable {

    /// Verifies the two JWTs against the published signing keys and wraps them in a `TokenContainer`.
    /// - Parameters:
    ///   - accessToken: The encoded access token.
    ///   - refreshToken: The encoded refresh token.
    ///   - refreshID: The identifier of the refresh this decode belongs to. When non-nil, the decode steps are reported on the refresh event mapping.
    func decode(accessToken: String, refreshToken: String, refreshID: String?) async throws -> TokenContainer

    /// Spends the refresh token of `tokenContainer` once and returns the new, decoded token pair.
    /// - Parameters:
    ///   - tokenContainer: The container whose refresh token is spent.
    ///   - refreshID: The identifier of the refresh. When non-nil, the request and decode steps are reported on the refresh event mapping.
    /// - Throws: `OAuthClientError.invalidTokenRequest` or `OAuthClientError.unknownAccount` when the auth API rejects the refresh token, otherwise the underlying error.
    func refresh(_ tokenContainer: TokenContainer, refreshID: String?) async throws -> TokenContainer

    /// Spends the refresh token of `tokenContainer` `count` times, sequentially, and returns every new token pair.
    /// - Parameters:
    ///   - tokenContainer: The container whose refresh token is spent.
    ///   - count: How many pairs to create. A value below 1 makes no calls and returns an empty array; in debug builds it is an assertion failure.
    ///   - refreshID: The identifier of the refresh. When non-nil, only the first call reports its steps on the refresh event mapping,
    ///     so the refresh event measures a single refresh call and ignores the extra pairs.
    /// - Returns: The new pairs, oldest first. The last one is the most recently minted.
    /// - Throws: `TokenForkError.incomplete` as soon as one call fails, carrying the pairs minted before it.
    func fork(_ tokenContainer: TokenContainer, count: Int, refreshID: String?) async throws(TokenForkError) -> [TokenContainer]
}

/// Thrown by `TokenRefreshing.fork` when one of its refresh calls fails.
public enum TokenForkError: DDGError {
    /// - Parameters:
    ///   - minted: The pairs created before the failure, oldest first. Empty when the first call failed.
    ///   - underlying: The error of the failed call, as `TokenRefreshing.refresh` would throw it.
    case incomplete(minted: [TokenContainer], underlying: Error)

    public static var errorDomain: String { "com.duckduckgo.networking.TokenForkError" }

    public var errorCode: Int {
        switch self {
        case .incomplete:
            return 11300
        }
    }

    public var underlyingError: (any Error)? {
        switch self {
        case .incomplete(_, let underlying):
            return underlying
        }
    }

    public var description: String {
        switch self {
        case .incomplete(let minted, _):
            return "Fork stopped after \(minted.count) token pairs"
        }
    }

    /// Two errors are equal when they minted the same pairs and their underlying errors have the same domain and code.
    public static func == (lhs: TokenForkError, rhs: TokenForkError) -> Bool {
        switch (lhs, rhs) {
        case let (.incomplete(lhsMinted, lhsUnderlying), .incomplete(rhsMinted, rhsUnderlying)):
            let lhsError = lhsUnderlying as NSError
            let rhsError = rhsUnderlying as NSError
            return lhsMinted == rhsMinted && lhsError.domain == rhsError.domain && lhsError.code == rhsError.code
        }
    }
}

/// `TokenRefreshing` backed by an `OAuthService`.
public actor DefaultTokenRefresher: TokenRefreshing {

    private let authService: any OAuthService
    private let clientID: String
    private let refreshEventMapping: EventMapping<OAuthClientRefreshEvent>?

    /// - Parameters:
    ///   - authService: The service used for the refresh request and for fetching the signing keys.
    ///   - clientID: The OAuth client identifier sent with every refresh request.
    ///   - refreshEventMapping: Receives the refresh and decode step events.
    public init(authService: any OAuthService,
                clientID: String,
                refreshEventMapping: EventMapping<OAuthClientRefreshEvent>?) {
        self.authService = authService
        self.clientID = clientID
        self.refreshEventMapping = refreshEventMapping
    }

#if DEBUG
    private var testingDecodedTokenContainers: [TokenContainer] = []

    /// Makes `decode` return these containers instead of verifying the tokens.
    /// Each call returns the next container in order; once one is left, every later call returns it.
    /// - Parameter containers: The containers to return. An empty array restores real decoding.
    func setTestingDecodedTokenContainers(_ containers: [TokenContainer]) {
        testingDecodedTokenContainers = containers
    }
#endif

    public func decode(accessToken: String, refreshToken: String, refreshID: String? = nil) async throws -> TokenContainer {
        Logger.OAuthClient.log("Decoding tokens")

#if DEBUG
        if let first = testingDecodedTokenContainers.first {
            if testingDecodedTokenContainers.count > 1 {
                testingDecodedTokenContainers.removeFirst()
            }
            return first
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

    public func refresh(_ tokenContainer: TokenContainer, refreshID: String?) async throws -> TokenContainer {
        do {
            if let refreshID { refreshEventMapping?.fire(.tokenRefreshRefreshingAccessToken(refreshID: refreshID)) }
            let refreshTokenResponse = try await authService.refreshAccessToken(clientID: clientID, refreshToken: tokenContainer.refreshToken)
            if let refreshID { refreshEventMapping?.fire(.tokenRefreshRefreshedAccessToken(refreshID: refreshID)) }

            let refreshedTokens = try await decode(accessToken: refreshTokenResponse.accessToken,
                                                   refreshToken: refreshTokenResponse.refreshToken,
                                                   refreshID: refreshID)
            Logger.OAuthClient.log("Tokens refreshed, access token expiry: \(refreshedTokens.decodedAccessToken.exp.value.description, privacy: .public)")
            return refreshedTokens
        } catch OAuthServiceError.authAPIError(let apiError) where apiError.bodyError.errorCode == .invalidTokenRequest {
            Logger.OAuthClient.error("Failed to refresh token: \(apiError.description, privacy: .public)")
            throw OAuthClientError.invalidTokenRequest(apiError.bodyError.tokenStatus)
        } catch OAuthServiceError.authAPIError(let apiError) where apiError.bodyError.errorCode == .unknownAccount {
            Logger.OAuthClient.error("Failed to refresh token: \(apiError.description, privacy: .public)")
            throw OAuthClientError.unknownAccount
        } catch {
            Logger.OAuthClient.error("Failed to refresh token: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    public func fork(_ tokenContainer: TokenContainer, count: Int, refreshID: String?) async throws(TokenForkError) -> [TokenContainer] {
        guard count >= 1 else {
            assertionFailure("fork needs at least one pair")
            return []
        }
        var minted: [TokenContainer] = []
        for index in 0..<count {
            let isFirst = index == 0
            do {
                minted.append(try await refresh(tokenContainer, refreshID: isFirst ? refreshID : nil))
            } catch {
                throw TokenForkError.incomplete(minted: minted, underlying: error)
            }
        }
        return minted
    }
}
