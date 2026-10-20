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
import DDGError
import os.log
import Common
import FoundationExtensions

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

public enum AuthTokensCachePolicy: CustomStringConvertible, Equatable {
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
    /// - Parameter trigger: What initiated this token request, surfaced on the refresh wide event.
    func getTokens(policy: AuthTokensCachePolicy, trigger: TokenRefreshTrigger) async throws -> TokenContainer

    /// Use the TokenContainer provided. A backup token container of another account is deleted.
    func adopt(tokenContainer: TokenContainer) throws

    // Creates a TokenContainer with the provided access token and refresh token, decodes them and returns the container
    func decode(accessToken: String, refreshToken: String, refreshID: String?) async throws -> TokenContainer

    /// Activate the account with a platform signature. A backup token container of another account is deleted.
    /// - Parameter signature: The platform signature
    /// - Returns: A container of tokens
    func activate(withPlatformSignature signature: String) async throws -> TokenContainer

    // MARK: Logout

    /// Removes the backup token container, if any, then the current one, and asks the server to invalidate the current access token.
    func logout() async throws

    /// Removes the current token container. A backup token container, if any, is kept.
    func removeLocalAccount() throws

    // MARK: Backup

    /// Restores the current token container from the backup: spends the backup's refresh token to mint a new current pair and a new backup,
    /// and stores both. Concurrent calls share one restore.
    /// - Parameters:
    ///   - expectedExternalID: The account the backup must belong to. When nil, a backup for any account is accepted.
    ///   - issuedAfter: A backup whose refresh token was issued at or before this date is rejected. When nil, no such check is made.
    /// - Returns: The new current token container, already stored.
    /// - Throws: `TokenBackupError` when there is no usable backup, `.readFailed` when it can't be read; `TokenBackupError.sessionChanged`,
    ///   storing nothing, when while the restore was in progress this client signed out, deleted the backup, adopted or activated a token
    ///   container, or another current token container was stored, or the current one can't be read; the storage error when reading the
    ///   current token container before the restore fails (nothing is refreshed then); otherwise the error of the first refresh call or of
    ///   storing the new current pair.
    ///   A current token container deleted by another process doesn't stop the restore.
    ///   After `OAuthClientError.invalidTokenRequest` or `.unknownAccount` the backup is deleted; after any other refresh error it is kept.
    func restoreFromBackup(expectedExternalID: String?, issuedAfter: Date?) async throws -> TokenContainer

    /// Deletes the backup token container, if any. The current one is kept. A failure is logged and otherwise ignored.
    func removeBackup()

    /// The stored backup token container, or nil when there is no backup storage, no backup is stored, or reading it fails.
    func backupTokenContainer() -> TokenContainer?
}

public extension OAuthClient {
    /// Convenience overload defaulting the refresh trigger to `.client` (most refreshes are
    /// client-initiated); callers with a more specific origin pass `trigger` explicitly.
    func getTokens(policy: AuthTokensCachePolicy) async throws -> TokenContainer {
        try await getTokens(policy: policy, trigger: .client)
    }
}

/// What initiated a token refresh. Recorded on the AuthV2 refresh wide event as `refresh_trigger`
/// so the refresh SLO can be segmented by origin. Raw values match the schema enum.
public enum TokenRefreshTrigger: String, Codable {
    /// A refresh driven by a backend interaction, such as an API 401/retry path. The token may also be locally expired.
    case backend
    /// A client-initiated refresh: proactive, lazy expiry refresh, or an explicit force refresh.
    case client
    /// The refresh probe performed before `.createIfNeeded` falls back to creating a new account.
    case createIfNeeded = "create_if_needed"
    /// The forced refresh performed as part of adopting an externally-provided token container.
    case tokenAdoption = "token_adoption"
}

public enum OAuthClientRefreshEvent {
    case tokenRefreshStarted(refreshID: String, trigger: TokenRefreshTrigger)
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
    private var backupRestoreOngoingTask: Task<TokenContainer, Error>?
    private let sessionGeneration = SessionGeneration()
    private let refreshEventMapping: EventMapping<OAuthClientRefreshEvent>?
    private let tokenRefresher: any TokenRefreshing
    private let backupStore: TokenBackupStore?

    /// Creates a client that refreshes and decodes tokens through a `DefaultTokenRefresher` backed by `authService`.
    /// - Parameters:
    ///   - tokensStorage: Where the current token container is read from and saved to.
    ///   - authService: The auth API client.
    ///   - refreshEventMapping: Receives the token refresh step events.
    ///   - backupStorage: Where the backup token container, an independent pair forked from the current one, is kept.
    ///     When non-nil, a refresh also mints a new backup when there is none, or the stored one is expired, belongs to another account
    ///     or was issued more than 14 days ago; `logout()` deletes it and `removeLocalAccount()` keeps it. When nil, no backup is created.
    public init(tokensStorage: any AuthTokenStoring,
                authService: OAuthService,
                refreshEventMapping: EventMapping<OAuthClientRefreshEvent>?,
                backupStorage: (any AuthTokenStoring)? = nil) {
        self.init(tokensStorage: tokensStorage,
                  authService: authService,
                  refreshEventMapping: refreshEventMapping,
                  tokenRefresher: DefaultTokenRefresher(authService: authService,
                                                        clientID: Constants.clientID,
                                                        refreshEventMapping: refreshEventMapping),
                  backupStorage: backupStorage)
    }

    /// Creates a client that refreshes and decodes tokens through `tokenRefresher`.
    /// - Parameters:
    ///   - tokensStorage: Where the current token container is read from and saved to.
    ///   - authService: The auth API client, used for every request other than refreshing and decoding.
    ///   - refreshEventMapping: Receives the refresh events the client reports itself: started, saving, succeeded and failed.
    ///   - tokenRefresher: Performs refreshes and decoding, and reports their steps.
    ///   - backupStorage: Where the backup token container, an independent pair forked from the current one, is kept.
    ///     When non-nil, a refresh also mints a new backup when there is none, or the stored one is expired, belongs to another account
    ///     or was issued more than 14 days ago; `logout()` deletes it and `removeLocalAccount()` keeps it. When nil, no backup is created.
    init(tokensStorage: any AuthTokenStoring,
         authService: OAuthService,
         refreshEventMapping: EventMapping<OAuthClientRefreshEvent>?,
         tokenRefresher: any TokenRefreshing,
         backupStorage: (any AuthTokenStoring)? = nil) {
        self.tokenStorage = tokensStorage
        self.authService = authService
        self.refreshEventMapping = refreshEventMapping
        self.tokenRefresher = tokenRefresher
        self.backupStore = backupStorage.map { TokenBackupStore(storage: $0) }
    }

    // MARK: - Internal

    @discardableResult
    func getTokens(authCode: String, codeVerifier: String) async throws -> TokenContainer {
        Logger.OAuthClient.log("Exchanging the authorization code for tokens")
        let getTokensResponse = try await authService.getAccessToken(clientID: Constants.clientID,
                                                             codeVerifier: codeVerifier,
                                                             code: authCode,
                                                             redirectURI: Constants.redirectURI)
        return try await decode(accessToken: getTokensResponse.accessToken, refreshToken: getTokensResponse.refreshToken)
    }

    func getVerificationCodes() async throws -> (codeVerifier: String, codeChallenge: String) {
        Logger.OAuthClient.log("Generating verification codes")
        let codeVerifier = try OAuthCodesGenerator.generateCodeVerifier()
        guard let codeChallenge = OAuthCodesGenerator.codeChallenge(codeVerifier: codeVerifier) else {
            Logger.OAuthClient.error("Failed to generate the code challenge")
            throw OAuthClientError.internalError("Failed to generate code challenge")
        }
        return (codeVerifier, codeChallenge)
    }

    public func decode(accessToken: String, refreshToken: String, refreshID: String? = nil) async throws -> TokenContainer {
        try await tokenRefresher.decode(accessToken: accessToken, refreshToken: refreshToken, refreshID: refreshID)
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
        sessionGeneration.increment()
        try tokenStorage.saveTokenContainer(tokenContainer)
    }

    public func getTokens(policy: AuthTokensCachePolicy, trigger: TokenRefreshTrigger) async throws -> TokenContainer {
        switch policy {
        case .local:
            let localTokenContainer = try tokenStorage.getTokenContainer()
            guard let localTokenContainer else {
                Logger.OAuthClient.log("Current token not found")
                throw OAuthClientError.missingTokenContainer
            }
            Logger.OAuthClient.log("Current token found, access token expiry: \(localTokenContainer.decodedAccessToken.exp.value, privacy: .public)")
            return localTokenContainer

        case .localValid:
            let localTokenContainer = try tokenStorage.getTokenContainer()
            guard let localTokenContainer else {
                Logger.OAuthClient.log("Current token not found")
                throw OAuthClientError.missingTokenContainer
            }
            let tokenExpiryDate = localTokenContainer.decodedAccessToken.exp.value
            Logger.OAuthClient.log("Current token found, access token expiry: \(tokenExpiryDate, privacy: .public)")

            // If the token expires in less than `Constants.tokenExpiryBufferInterval` minutes we treat it as already expired
            let expirationInterval = tokenExpiryDate.timeIntervalSinceNow
            let expiresSoon = expirationInterval < Constants.tokenExpiryBufferInterval
            if localTokenContainer.decodedAccessToken.isExpired() || expiresSoon {
                Logger.OAuthClient.log("Access token expired or about to expire, refreshing it")
                return try await getTokens(policy: .localForceRefresh, trigger: trigger)
            } else {
                return localTokenContainer
            }

        case .localForceRefresh:
            if let task = refreshOngoingTask {
                Logger.OAuthClient.log("Awaiting result from existing token refresh operation")
                return try await task.value
            }

            let refreshID = UUID().uuidString
            refreshEventMapping?.fire(.tokenRefreshStarted(refreshID: refreshID, trigger: trigger))

            let localTokenContainer: TokenContainer?
            do {
                localTokenContainer = try tokenStorage.getTokenContainer()
            } catch {
                Logger.OAuthClient.error("Failed to read the current token before refreshing it: \(String(describing: error), privacy: .public)")
                refreshEventMapping?.fire(.tokenRefreshFailed(refreshID: refreshID, error: error))
                throw error
            }

            guard let localTokenContainer else {
                Logger.OAuthClient.log("Current token not found")
                let error = OAuthClientError.missingTokenContainer
                refreshEventMapping?.fire(.tokenRefreshFailed(refreshID: refreshID, error: error))
                throw error
            }

            let task = Task {
                defer {
                    self.refreshOngoingTask = nil
                }

                Logger.OAuthClient.log("Starting token refresh, trigger: \(trigger.rawValue, privacy: .public)")

                do {
                    let (refreshedTokens, newBackup) = try await refreshPossiblyForking(localTokenContainer, refreshID: refreshID)

                    refreshEventMapping?.fire(.tokenRefreshSavingTokens(refreshID: refreshID))
                    try saveRefreshedTokens(refreshedTokens, backup: newBackup)

                    refreshEventMapping?.fire(.tokenRefreshSucceeded(refreshID: refreshID))

                    return refreshedTokens
                } catch {
                    refreshEventMapping?.fire(.tokenRefreshFailed(refreshID: refreshID, error: error))
                    throw error
                }
            }

            refreshOngoingTask = task
            return try await task.value

        case .createIfNeeded:
            // A keychain read failure must surface as an error, not as a missing token that triggers account creation.
            // Trigger the read here to ensure that the keychain is accessible before proceeding with the creation.
            _ = try tokenStorage.getTokenContainer()

            do {
                return try await getTokens(policy: .localValid, trigger: .createIfNeeded)
            } catch {
                Logger.OAuthClient.log("No valid current token, creating a new account: \(String(describing: error), privacy: .public)")
                do {
                    let tokenContainer = try await createAccount()
                    sessionGeneration.increment()
                    try tokenStorage.saveTokenContainer(tokenContainer)
                    backupStore?.removeIfForAnotherAccount(than: tokenContainer)
                    return tokenContainer
                } catch {
                    Logger.OAuthClient.error("Failed to create account: \(String(describing: error), privacy: .public)")
                    throw error
                }
            }
        }
    }

    public func adopt(tokenContainer: TokenContainer) throws {
        Logger.OAuthClient.log("Adopting token container")
        sessionGeneration.increment()
        try tokenStorage.saveTokenContainer(tokenContainer)
        backupStore?.removeIfForAnotherAccount(than: tokenContainer)
    }

    // MARK: Backup

    /// Stores the refreshed token container, then the new backup when there is one.
    /// - Parameters:
    ///   - refreshedTokens: The new current token container.
    ///   - backup: The new backup token container, or nil when the refresh didn't mint one.
    /// - Throws: The storage error when saving `refreshedTokens` fails; the backup is then not saved. A failure to save the backup is only logged.
    private func saveRefreshedTokens(_ refreshedTokens: TokenContainer, backup: TokenContainer?) throws {
        do {
            try tokenStorage.saveTokenContainer(refreshedTokens)
        } catch {
            Logger.OAuthClient.error("Failed to save the refreshed tokens: \(String(describing: error), privacy: .public)")
            throw error
        }
        if let backup {
            backupStore?.save(backup)
        }
    }

    /// Spends the refresh token of `source` once, or twice when the backup needs renewal.
    /// - Parameters:
    ///   - source: The token container to refresh.
    ///   - refreshID: The identifier of the refresh, under which the first refresh call reports its steps.
    /// - Returns: The new primary and, when two pairs were minted, the new backup. If the second call of a renewal fails,
    ///   the pair from the first call is returned as the primary and no backup.
    /// - Throws: The error of the first refresh call, as `TokenRefreshing.refresh` throws it, or
    ///   `OAuthClientError.internalError` when `fork` returns a number of pairs other than two.
    private func refreshPossiblyForking(_ source: TokenContainer, refreshID: String) async throws -> (primary: TokenContainer, backup: TokenContainer?) {
        guard let backupStore, backupStore.needsRenewal(for: source) else {
            return (try await tokenRefresher.refresh(source, refreshID: refreshID), nil)
        }
        Logger.OAuthClient.log("Refreshing the current token and renewing the backup token")
        do {
            let minted = try await tokenRefresher.fork(source, count: 2, refreshID: refreshID)
            guard minted.count == 2, let backup = minted.first, let primary = minted.last else {
                throw OAuthClientError.internalError("Fork returned \(minted.count) token pairs instead of 2")
            }
            return (primary, backup)
        } catch TokenForkError.incomplete(let minted, let underlying) {
            guard let primary = minted.last else { throw underlying }
            Logger.OAuthClient.error("Backup token fork incomplete, keeping the minted pair as primary: \(String(describing: underlying), privacy: .public)")
            return (primary, nil)
        }
    }

    public func restoreFromBackup(expectedExternalID: String?, issuedAfter: Date?) async throws -> TokenContainer {
        if let task = backupRestoreOngoingTask {
            Logger.OAuthClient.log("Awaiting result from existing backup restore operation")
            return try await task.value
        }
        let task = Task {
            defer {
                self.backupRestoreOngoingTask = nil
            }
            return try await performRestoreFromBackup(expectedExternalID: expectedExternalID, issuedAfter: issuedAfter)
        }
        backupRestoreOngoingTask = task
        return try await task.value
    }

    /// Validates the backup, forks it into a new current pair and a new backup, and stores both, current pair first.
    /// - Parameters:
    ///   - expectedExternalID: The account the backup must belong to, or nil for any account.
    ///   - issuedAfter: The date the backup's refresh token must be issued after, or nil.
    /// - Returns: The new current token container. If the second fork call fails, the pair from the first call is stored as the
    ///   current one and the spent backup is deleted.
    /// - Throws: As `restoreFromBackup(expectedExternalID:issuedAfter:)`.
    private func performRestoreFromBackup(expectedExternalID: String?, issuedAfter: Date?) async throws -> TokenContainer {
        guard let backupStore else { throw TokenBackupError.unavailable }
        let backup = try backupStore.usableBackup(expectedExternalID: expectedExternalID, issuedAfter: issuedAfter)
        let generationBeforeRestore = sessionGeneration.current
        let currentBeforeRestore = try tokenStorage.getTokenContainer()
        Logger.OAuthClient.log("Restoring tokens from the backup")

        do {
            let minted = try await tokenRefresher.fork(backup, count: 2, refreshID: nil)
            guard minted.count == 2, let newBackup = minted.first, let primary = minted.last else {
                throw OAuthClientError.internalError("Fork returned \(minted.count) token pairs instead of 2")
            }
            try ensureSessionUnchanged(backup: backup,
                                       generationBeforeRestore: generationBeforeRestore,
                                       currentBeforeRestore: currentBeforeRestore,
                                       backupStore: backupStore)
            try tokenStorage.saveTokenContainer(primary)
            backupStore.save(newBackup)
            return primary
        } catch TokenForkError.incomplete(let minted, let underlying) {
            if let primary = minted.last {
                Logger.OAuthClient.error("Backup restore fork incomplete, keeping the minted pair as current: \(String(describing: underlying), privacy: .public)")
                try ensureSessionUnchanged(backup: backup,
                                           generationBeforeRestore: generationBeforeRestore,
                                           currentBeforeRestore: currentBeforeRestore,
                                           backupStore: backupStore)
                try tokenStorage.saveTokenContainer(primary)
                backupStore.remove()
                return primary
            }
            switch underlying {
            case OAuthClientError.invalidTokenRequest, OAuthClientError.unknownAccount:
                Logger.OAuthClient.error("Backup token rejected by the server, deleting it: \(String(describing: underlying), privacy: .public)")
                backupStore.remove()
            default:
                break
            }
            throw underlying
        }
    }

    /// Checks that the session is still the one a backup restore started from. When it isn't, the restore is discarded, and `backup`,
    /// whose refresh token the fork already spent, is deleted if it is still the stored backup.
    /// - Parameters:
    ///   - backup: The backup the restore forked.
    ///   - generationBeforeRestore: The session generation when the restore started.
    ///   - currentBeforeRestore: The current token container when the restore started, or nil if none was stored.
    ///   - backupStore: The store holding the backup.
    /// - Throws: `TokenBackupError.sessionChanged` when the session generation changed, the backup is no longer stored, the current token
    ///   container can't be read, or a current token container other than `currentBeforeRestore` is stored. A current token container that was
    ///   deleted without changing the session generation, by another process, passes.
    private func ensureSessionUnchanged(backup: TokenContainer,
                                        generationBeforeRestore: Int,
                                        currentBeforeRestore: TokenContainer?,
                                        backupStore: TokenBackupStore) throws {
        do {
            try checkSessionUnchanged(backup: backup,
                                      generationBeforeRestore: generationBeforeRestore,
                                      currentBeforeRestore: currentBeforeRestore,
                                      backupStore: backupStore)
        } catch {
            if backupStore.isStored(backup) {
                Logger.OAuthClient.log("Deleting the backup token spent by the discarded restore")
                backupStore.remove()
            }
            throw error
        }
    }

    /// Throws `TokenBackupError.sessionChanged` in the cases listed on `ensureSessionUnchanged`.
    private func checkSessionUnchanged(backup: TokenContainer,
                                       generationBeforeRestore: Int,
                                       currentBeforeRestore: TokenContainer?,
                                       backupStore: TokenBackupStore) throws {
        guard sessionGeneration.current == generationBeforeRestore, backupStore.isStored(backup) else {
            Logger.OAuthClient.log("The session was ended or replaced during the backup restore, discarding the restored tokens")
            throw TokenBackupError.sessionChanged
        }
        let current: TokenContainer?
        do {
            current = try tokenStorage.getTokenContainer()
        } catch {
            Logger.OAuthClient.error("Failed to read the current token after the backup restore, discarding the restored tokens: \(String(describing: error), privacy: .public)")
            throw TokenBackupError.sessionChanged
        }
        if let current, current.refreshToken != currentBeforeRestore?.refreshToken {
            Logger.OAuthClient.log("Another current token was stored during the backup restore, discarding the restored tokens")
            throw TokenBackupError.sessionChanged
        }
    }

    public func backupTokenContainer() -> TokenContainer? {
        backupStore?.storedBackup()
    }

    public func removeBackup() {
        Logger.OAuthClient.log("Deleting the backup token")
        sessionGeneration.increment()
        backupStore?.remove()
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
        sessionGeneration.increment()
        try tokenStorage.saveTokenContainer(tokenContainer)
        backupStore?.removeIfForAnotherAccount(than: tokenContainer)
        Logger.OAuthClient.log("Activation completed")
        return tokenContainer
    }

    // MARK: Logout

    /// Removes the backup token container, if any, then the current one, and asks the server to invalidate the current access token.
    /// The server request is not awaited and its result is ignored.
    public func logout() async throws {
        Logger.OAuthClient.log("Logging out")
        sessionGeneration.increment()
        let existingToken = try tokenStorage.getTokenContainer()?.accessToken
        backupStore?.remove()
        try removeLocalAccount()

        if let existingToken {
            Task { // Not waiting for an answer
                Logger.OAuthClient.log("Invalidating the V2 token")
                do {
                    try await authService.logout(accessToken: existingToken)
                } catch {
                    Logger.OAuthClient.error("Failed to invalidate the V2 token: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    /// Removes the current token container. A backup token container, if any, is kept.
    public func removeLocalAccount() throws {
        Logger.OAuthClient.log("Removing the current token")
        try tokenStorage.saveTokenContainer(nil)
    }
}

/// A counter of the changes that end or replace a session: sign-out, backup deletion, adoption, activation and account creation.
/// It can be read and incremented from any thread.
private final class SessionGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    /// The current generation.
    var current: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    /// Moves to the next generation.
    func increment() {
        lock.lock()
        defer { lock.unlock() }
        value += 1
    }
}
