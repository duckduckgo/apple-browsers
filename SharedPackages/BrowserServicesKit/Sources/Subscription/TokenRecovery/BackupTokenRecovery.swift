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

/// Recovers the current token container from the backup token container.
public final class BackupTokenRecovery: TokenRecoveryStrategy {

    private let oAuthClient: any OAuthClient
    private let retryInterval: TimeInterval
    private let now: () -> Date
    private let onRestored: ((TokenRecoveryTrigger) -> Void)?
    private let lock = NSLock()
    private var missingTokenRetryAfter: Date?

    /// - Parameters:
    ///   - oAuthClient: The client that holds the backup and stores the restored token container.
    ///   - retryInterval: After a restore for a missing token fails for a transient reason, how long further missing-token restores are skipped.
    ///   - now: The current date, used to measure `retryInterval`.
    ///   - onRestored: Called with the recovery trigger after each successful restore, or nil.
    public init(oAuthClient: any OAuthClient,
                retryInterval: TimeInterval = .minutes(5),
                now: @escaping () -> Date = { Date() },
                onRestored: ((TokenRecoveryTrigger) -> Void)? = nil) {
        self.oAuthClient = oAuthClient
        self.retryInterval = retryInterval
        self.now = now
        self.onRestored = onRestored
    }

    /// Restores from the backup. The backup must belong to the dead current token's account, when there is one,
    /// and its refresh token must have been issued after the cut-off recorded at the last explicit sign-out.
    /// For `.missingToken`, a restore within `retryInterval` of a transient failure is skipped with `TokenBackupError.unavailable`;
    /// `.accountCreation` restores are never skipped.
    public func recover(_ context: TokenRecoveryContext) async throws {
        let isMissingToken = context.trigger == .missingToken
        if isMissingToken, let retryAfter = currentRetryAfter(), now() < retryAfter {
            Logger.subscriptionTokensManagement.log("Skipping the backup restore until \(retryAfter, privacy: .public) after a transient failure")
            throw TokenBackupError.unavailable
        }

        do {
            _ = try await oAuthClient.restoreFromBackup(expectedExternalID: context.deadPrimary?.decodedAccessToken.externalID,
                                                        issuedAfter: context.signOutCutoff)
        } catch {
            if isMissingToken, Self.isTransient(error) {
                let retryAfter = now().addingTimeInterval(retryInterval)
                Logger.subscriptionTokensManagement.log("Backup restore failed for a transient reason, skipping missing-token restores until \(retryAfter, privacy: .public)")
                setRetryAfter(retryAfter)
            }
            throw error
        }

        setRetryAfter(nil)
        onRestored?(context.trigger)
    }

    /// Whether a restore failure may succeed when retried: a backup that couldn't be read, or anything but a rejected or missing backup
    /// or a refresh the server rejected.
    /// - Parameter error: The error `restoreFromBackup` threw.
    private static func isTransient(_ error: Error) -> Bool {
        switch error {
        case TokenBackupError.readFailed:
            return true
        case is TokenBackupError, OAuthClientError.invalidTokenRequest, OAuthClientError.unknownAccount:
            return false
        default:
            return true
        }
    }

    /// Whether a restore failure is known to be temporary: no connection or a timeout, a server error, a timed-out or rate-limited request,
    /// or a backup that couldn't be read. Any other failure, including an unknown one, is not.
    /// - Parameter error: The error `restoreFromBackup` threw.
    static func isTemporary(_ error: Error) -> Bool {
        switch error {
        case TokenBackupError.readFailed, is URLError, APIRequestV2Error.urlSession:
            return true
        case OAuthServiceError.invalidResponseCode(let status):
            return status.isServerError || status == .requestTimeout || status == .tooManyRequests
        default:
            return false
        }
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
