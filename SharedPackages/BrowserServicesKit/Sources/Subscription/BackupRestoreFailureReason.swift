//
//  BackupRestoreFailureReason.swift
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
import Networking

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
