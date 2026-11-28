//
//  SubscriptionPixelHandling.swift
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
import Common
import Networking
import os.log

/// Pixels handler
public protocol SubscriptionPixelHandling {
    func handle(pixel: SubscriptionPixelType)
    func handle(pixel: KeychainManager.Pixel)
}

extension SubscriptionPixelHandling {

    /// An event mapping for `DefaultOAuthClient`'s backup events that hands them to this handler as `.backupRenewed`,
    /// `.backupRenewalFailed` and `.backupKeychainError`.
    public func backupEventMapping() -> EventMapping<OAuthClientBackupEvent> {
        EventMapping { event, _, _, _ in
            switch event {
            case .backupRenewed:
                handle(pixel: .backupRenewed)
            case .backupRenewalFailed(let error):
                handle(pixel: .backupRenewalFailed(error))
            case .storageFailed(let action, let operation, let error):
                handle(pixel: .backupKeychainError(action, operation, error))
            }
        }
    }

    /// An error handler for the backup token's `SubscriptionTokenKeychainStorage`. It hands this handler, as `.backupKeychainError` without
    /// an action, the problems the storage finds without throwing: an item it can't decode, and an expected item that is missing.
    /// The errors it throws are reported by `DefaultOAuthClient` through `backupEventMapping()`, with the action that hit them.
    public func backupKeychainErrorHandler() -> (AccountKeychainAccessType, AccountKeychainAccessError) -> Void {
        { accessType, error in
            Logger.subscriptionKeychain.error("Backup token keychain error, \(accessType.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            switch error {
            case .failedToDecodeKeychainData, .expectedTokenNotFound:
                handle(pixel: .backupKeychainError(nil, .read, error))
            default:
                break
            }
        }
    }
}
