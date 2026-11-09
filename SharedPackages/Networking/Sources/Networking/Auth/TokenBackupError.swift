//
//  TokenBackupError.swift
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
import DDGError

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
    /// The stored backup can't be decoded as a token container.
    case undecodable

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
        case .undecodable:
            return "The backup token can't be decoded"
        }
    }

    public static var errorDomain: String { "com.duckduckgo.networking.TokenBackupError" }

    public var errorCode: Int {
        switch self {
        case .unavailable:
            return 11500
        case .accountMismatch:
            return 11501
        case .predatesSignOut:
            return 11502
        case .expired:
            return 11503
        case .sessionChanged:
            return 11504
        case .readFailed:
            return 11505
        case .undecodable:
            return 11506
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
             (.expired, .expired), (.sessionChanged, .sessionChanged), (.undecodable, .undecodable):
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
