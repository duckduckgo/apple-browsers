//
//  BackupTokenRecovery.swift
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
import Networking
import FoundationExtensions

/// Why a backup restore that was tried didn't restore the session, as reported on pixels.
public enum BackupRestoreFailureReason: String, CaseIterable {
    /// The backup belongs to another account than the dead current token.
    case accountMismatch = "account_mismatch"
    /// The backup was issued at or before the last sign-out.
    case predatesSignOut = "predates_sign_out"
    /// The backup's refresh token has expired.
    case expired
    /// The auth server rejected the backup's refresh token or account.
    case serverRejected = "server_rejected"
    /// A failure `BackupRestoreFailure` classifies as `.temporary`.
    case temporary
    /// The user signed out, signed in or switched account while the restore ran.
    case sessionChanged = "session_changed"
    /// Any other failure.
    case unknown

    /// Classifies `error`.
    /// - Parameter error: The error `OAuthClient.restoreFromBackup` threw.
    public init(_ error: Error) {
        switch error {
        case TokenBackupError.accountMismatch:
            self = .accountMismatch
        case TokenBackupError.predatesSignOut:
            self = .predatesSignOut
        case TokenBackupError.expired:
            self = .expired
        case TokenBackupError.sessionChanged:
            self = .sessionChanged
        case OAuthClientError.invalidTokenRequest, OAuthClientError.unknownAccount:
            self = .serverRejected
        default:
            self = BackupRestoreFailure(error) == .temporary ? .temporary : .unknown
        }
    }
}

/// Recovers the current token container from the backup token container.
public final class BackupTokenRecovery: TokenRecoveryStrategy {

    public let method: TokenRecoveryMethod = .backup

    private let oAuthClient: any OAuthClient
    private let retryInterval: TimeInterval
    private let now: () -> Date
    private let pixelHandler: any SubscriptionPixelHandling
    private let lock = NSLock()
    private var missingTokenRetryAfter: Date?

    /// - Parameters:
    ///   - oAuthClient: The client that holds the backup and stores the restored token container.
    ///   - pixelHandler: Receives `.backupRestored` for each successful restore and `.backupRestoreFailed` for each restore that was
    ///     tried and failed or was discarded.
    ///   - retryInterval: After a restore for a missing token fails for a reason that isn't `BackupRestoreFailure.permanent`, how long further missing-token restores are skipped.
    ///   - now: The current date, used to measure `retryInterval`.
    public init(oAuthClient: any OAuthClient,
                pixelHandler: any SubscriptionPixelHandling,
                retryInterval: TimeInterval = .minutes(5),
                now: @escaping () -> Date = { Date() }) {
        self.oAuthClient = oAuthClient
        self.pixelHandler = pixelHandler
        self.retryInterval = retryInterval
        self.now = now
    }

    /// Restores from the backup. The backup must belong to the dead current token's account, when there is one.
    /// `OAuthClient` also rejects a backup issued before the last sign-out.
    /// For `.missingToken`, a restore within `retryInterval` of a failure that isn't `BackupRestoreFailure.permanent` is skipped;
    /// `.accountCreation` restores are never skipped.
    /// - Returns: `.notApplicable` when no backup is stored or the restore is skipped, `.sessionChanged` when the session changed
    ///   during the restore, `.failed` with the error `restoreFromBackup` threw otherwise.
    public func recover(_ context: TokenRecoveryContext) async -> TokenRecoveryResult {
        let isMissingToken = context.trigger == .missingToken
        if isMissingToken, let retryAfter = currentRetryAfter(), now() < retryAfter {
            Logger.subscriptionTokensManagement.log("Skipping the backup restore until \(retryAfter, privacy: .public) after a transient failure")
            return .notApplicable
        }

        do {
            _ = try await oAuthClient.restoreFromBackup(expectedExternalID: context.deadPrimary?.decodedAccessToken.externalID)
        } catch TokenBackupError.unavailable {
            return .notApplicable
        } catch TokenBackupError.sessionChanged {
            pixelHandler.handle(pixel: .backupRestoreFailed(context.trigger, .sessionChanged, TokenBackupError.sessionChanged))
            return .sessionChanged
        } catch {
            pixelHandler.handle(pixel: .backupRestoreFailed(context.trigger, BackupRestoreFailureReason(error), error))
            if isMissingToken, BackupRestoreFailure(error) != .permanent {
                let retryAfter = now().addingTimeInterval(retryInterval)
                Logger.subscriptionTokensManagement.log("Backup restore failed for a transient reason, skipping missing-token restores until \(retryAfter, privacy: .public)")
                setRetryAfter(retryAfter)
            }
            return .failed(error)
        }

        setRetryAfter(nil)
        pixelHandler.handle(pixel: .backupRestored(context.trigger))
        return .recovered
    }

    private func currentRetryAfter() -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return missingTokenRetryAfter
    }

    private func setRetryAfter(_ date: Date?) {
        lock.lock()
        defer { lock.unlock() }
        missingTokenRetryAfter = date
    }
}
