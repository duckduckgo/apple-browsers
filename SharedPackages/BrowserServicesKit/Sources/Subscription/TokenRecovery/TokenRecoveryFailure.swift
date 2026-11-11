//
//  TokenRecoveryFailure.swift
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

/// Whether the failure of a token recovery strategy is certain to repeat.
public enum TokenRecoveryFailure: Equatable {
    /// Retrying can't succeed: the backup or the refresh was rejected, the account is unknown, or there is no App Store purchase to restore.
    case permanent
    /// Not certain to repeat: a network, server or keychain failure, or any failure that can't be classified.
    case temporary

    /// Classifies `error`.
    /// - Parameter error: The error a recovery strategy failed with.
    public init(_ error: Error) {
        switch error {
        case AppStoreRestoreFlowError.missingAccountOrTransactions, AppStoreRestoreFlowError.subscriptionExpired:
            self = .permanent
        default:
            self = BackupRestoreFailure(error) == .permanent ? .permanent : .temporary
        }
    }
}
