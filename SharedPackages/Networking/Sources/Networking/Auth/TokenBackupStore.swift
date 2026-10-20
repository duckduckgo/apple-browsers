//
//  TokenBackupStore.swift
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
import DDGError
import FoundationExtensions

/// Why a backup token container can't be used to restore a session.
public enum TokenBackupError: DDGError {
    /// No backup storage is configured, no backup is stored, or a restore was skipped because a recent one failed.
    case unavailable
    /// The backup belongs to another account than the expected one.
    case accountMismatch
    /// The backup's refresh token was issued at or before the cut-off recorded at the last explicit sign-out.
    case predatesSignOut
    /// The backup's refresh token has expired.
    case expired
    /// The session changed while the restore was in progress: the backup was deleted or another current token was stored.
    /// Nothing was stored.
    case sessionChanged
    /// Reading the backup token container from its storage failed with `underlying`.
    case readFailed(underlying: Error)

    public var description: String {
        switch self {
        case .unavailable:
            return "No usable backup token"
        case .accountMismatch:
            return "The backup token belongs to another account"
        case .predatesSignOut:
            return "The backup token was issued before the last sign-out"
        case .expired:
            return "The backup token has expired"
        case .sessionChanged:
            return "The session changed during the backup restore"
        case .readFailed(let underlying):
            return "Failed to read the backup token: \(underlying)"
        }
    }

    public static var errorDomain: String { "com.duckduckgo.networking.TokenBackupError" }

    public var errorCode: Int {
        switch self {
        case .unavailable:
            return 11100
        case .accountMismatch:
            return 11101
        case .predatesSignOut:
            return 11102
        case .expired:
            return 11103
        case .sessionChanged:
            return 11104
        case .readFailed:
            return 11105
        }
    }

    public var underlyingError: (any Error)? {
        switch self {
        case .readFailed(let underlying):
            return underlying
        default:
            return nil
        }
    }

    /// Cases are equal when they match; `.readFailed` also compares its underlying errors' domain and code.
    public static func == (lhs: TokenBackupError, rhs: TokenBackupError) -> Bool {
        switch (lhs, rhs) {
        case (.unavailable, .unavailable), (.accountMismatch, .accountMismatch), (.predatesSignOut, .predatesSignOut),
             (.expired, .expired), (.sessionChanged, .sessionChanged):
            return true
        case let (.readFailed(lhsUnderlying), .readFailed(rhsUnderlying)):
            let lhsError = lhsUnderlying as NSError
            let rhsError = rhsUnderlying as NSError
            return lhsError.domain == rhsError.domain && lhsError.code == rhsError.code
        default:
            return false
        }
    }
}

/// Keeps the backup token container, an independent token pair forked from the current one, and decides when it must be renewed.
struct TokenBackupStore {

    private let storage: any AuthTokenStoring
    private let maxAge: TimeInterval
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - storage: Where the backup token container is read from and saved to.
    ///   - maxAge: How long after its refresh token was issued a backup is renewed.
    ///   - now: The current date, used to measure the backup's age.
    init(storage: any AuthTokenStoring,
         maxAge: TimeInterval = .days(14),
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.storage = storage
        self.maxAge = maxAge
        self.now = now
    }

    /// Whether a refresh of `primary` should also mint a new backup. Expiry and age are both measured with `now`.
    /// - Parameter primary: The token container about to be refreshed.
    /// - Returns: `true` when there is no backup, or the stored one is expired, belongs to another account than `primary`,
    ///   or was issued more than `maxAge` ago. `false` when the backup is still usable or reading it fails.
    func needsRenewal(for primary: TokenContainer) -> Bool {
        let backup: TokenContainer?
        do {
            backup = try storage.getTokenContainer()
        } catch {
            Logger.OAuthClient.error("Failed to read the backup token, skipping renewal: \(String(describing: error), privacy: .public)")
            return false
        }
        guard let backup else { return true }
        let now = now()
        if backup.decodedRefreshToken.expirationDate <= now { return true }
        if backup.decodedAccessToken.externalID != primary.decodedAccessToken.externalID { return true }
        return now.timeIntervalSince(backup.decodedRefreshToken.issuedAtDate) > maxAge
    }

    /// Returns the stored backup when it can be used to restore a session. Expiry is measured with `now`.
    /// - Parameters:
    ///   - expectedExternalID: The account the backup must belong to. When nil, a backup for any account is accepted.
    ///   - issuedAfter: A backup whose refresh token was issued at or before this date is rejected. When nil, no such check is made.
    /// - Returns: The stored backup token container.
    /// - Throws: `TokenBackupError.unavailable` when no backup is stored, `TokenBackupError.readFailed` when reading it fails,
    ///   otherwise the reason the backup was rejected. A rejected backup is deleted; one that is missing or can't be read is left as it is.
    func usableBackup(expectedExternalID: String?, issuedAfter: Date?) throws(TokenBackupError) -> TokenContainer {
        let stored: TokenContainer?
        do {
            stored = try storage.getTokenContainer()
        } catch {
            Logger.OAuthClient.error("Failed to read the backup token: \(String(describing: error), privacy: .public)")
            throw .readFailed(underlying: error)
        }
        guard let backup = stored else { throw .unavailable }

        let rejection: TokenBackupError?
        if let expectedExternalID, backup.decodedAccessToken.externalID != expectedExternalID {
            rejection = .accountMismatch
        } else if let issuedAfter, backup.decodedRefreshToken.issuedAtDate <= issuedAfter {
            rejection = .predatesSignOut
        } else if backup.decodedRefreshToken.expirationDate <= now() {
            rejection = .expired
        } else {
            rejection = nil
        }

        if let rejection {
            Logger.OAuthClient.log("Backup token rejected: \(rejection.description, privacy: .public)")
            remove()
            throw rejection
        }
        return backup
    }

    /// The stored backup token container, or nil when none is stored or reading it fails.
    func storedBackup() -> TokenContainer? {
        try? storage.getTokenContainer()
    }

    /// Deletes the stored backup when it belongs to another account than `tokenContainer`. A backup that can't be read is left as it is.
    /// - Parameter tokenContainer: The new current token container.
    func removeIfForAnotherAccount(than tokenContainer: TokenContainer) {
        guard let backup = storedBackup(),
              backup.decodedAccessToken.externalID != tokenContainer.decodedAccessToken.externalID else { return }
        Logger.OAuthClient.log("Deleting the backup token of another account")
        remove()
    }

    /// Whether `backup` is still the stored backup.
    /// - Parameter backup: A backup token container read earlier.
    /// - Returns: `true` when the stored backup has the same refresh token as `backup`; `false` when it differs, is missing or can't be read.
    func isStored(_ backup: TokenContainer) -> Bool {
        (try? storage.getTokenContainer())?.refreshToken == backup.refreshToken
    }

    /// Stores `backup`, replacing any previous one. A failure is logged and otherwise ignored.
    /// - Parameter backup: The new backup token container.
    func save(_ backup: TokenContainer) {
        do {
            try storage.saveTokenContainer(backup)
        } catch {
            Logger.OAuthClient.error("Failed to save the backup token: \(String(describing: error), privacy: .public)")
        }
    }

    /// Deletes the backup token container. A failure is logged and otherwise ignored.
    func remove() {
        do {
            try storage.saveTokenContainer(nil)
        } catch {
            Logger.OAuthClient.error("Failed to delete the backup token: \(String(describing: error), privacy: .public)")
        }
    }
}
