//
//  BackupRestoreFailure.swift
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

/// Whether a failed `OAuthClient.restoreFromBackup` call may succeed when retried.
public enum BackupRestoreFailure: Equatable {
    /// Known to be temporary: no connection or a timeout, a server error, a timed-out or rate-limited request,
    /// or a backup that couldn't be read.
    case temporary
    /// Retrying can't succeed: the backup is missing or was rejected, the session changed,
    /// or the server rejected the refresh or the account.
    case permanent
    /// Any other failure.
    case unknown

    /// Classifies `error`.
    /// - Parameter error: The error `restoreFromBackup` threw.
    public init(_ error: Error) {
        switch error {
        case TokenBackupError.readFailed, is URLError, APIRequestV2Error.urlSession:
            self = .temporary
        case OAuthServiceError.invalidResponseCode(let status):
            self = status.isServerError || status == .requestTimeout || status == .tooManyRequests ? .temporary : .unknown
        case is TokenBackupError, OAuthClientError.invalidTokenRequest, OAuthClientError.unknownAccount:
            self = .permanent
        default:
            self = .unknown
        }
    }
}
