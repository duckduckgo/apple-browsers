//
//  SubscriptionPixelType.swift
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

import Common
import Networking

public enum SubscriptionPixelType: Equatable {
    case invalidRefreshToken
    case subscriptionIsActive
    case osDistributionActiveSubscription
    case getTokensError(AuthTokensCachePolicy, Error)
    case automaticSignOut(SubscriptionAutomaticSignOutPixelData, Error)
    case invalidRefreshTokenSignedOut
    /// The invalid current token was recovered, by the method of the strategy that recovered it.
    case invalidRefreshTokenRecovered(TokenRecoveryMethod?)
    case purchaseSuccessAfterPendingTransaction
    case pendingTransactionApproved
    /// The backup restored the token container, in a recovery with the associated trigger.
    case backupRestored(TokenRecoveryTrigger)
    /// A backup restore was tried, in a recovery with the associated trigger, and failed or was discarded.
    case backupRestoreFailed(TokenRecoveryTrigger, BackupRestoreFailureReason, Error)
    /// A new backup token container was stored after a refresh.
    case backupRenewed
    /// Renewing the backup token container failed.
    case backupRenewalFailed(Error)
    /// Reading or writing the backup token container's keychain item failed.
    case backupKeychainError(AccountKeychainAccessType, AccountKeychainAccessError)

    public static func == (lhs: SubscriptionPixelType, rhs: SubscriptionPixelType) -> Bool {
        switch (lhs, rhs) {
        case (.invalidRefreshToken, .invalidRefreshToken),
            (.subscriptionIsActive, .subscriptionIsActive),
            (.osDistributionActiveSubscription, .osDistributionActiveSubscription),
            (.invalidRefreshTokenSignedOut, .invalidRefreshTokenSignedOut),
            (.getTokensError, .getTokensError),
            (.purchaseSuccessAfterPendingTransaction, .purchaseSuccessAfterPendingTransaction),
            (.pendingTransactionApproved, .pendingTransactionApproved),
            (.backupRenewed, .backupRenewed),
            (.backupRenewalFailed, .backupRenewalFailed):
            return true
        case let (.automaticSignOut(lhsData, _), .automaticSignOut(rhsData, _)):
            return lhsData == rhsData
        case let (.invalidRefreshTokenRecovered(lhsMethod), .invalidRefreshTokenRecovered(rhsMethod)):
            return lhsMethod == rhsMethod
        case let (.backupRestored(lhsTrigger), .backupRestored(rhsTrigger)):
            return lhsTrigger == rhsTrigger
        case let (.backupRestoreFailed(lhsTrigger, lhsReason, _), .backupRestoreFailed(rhsTrigger, rhsReason, _)):
            return lhsTrigger == rhsTrigger && lhsReason == rhsReason
        case let (.backupKeychainError(lhsType, _), .backupKeychainError(rhsType, _)):
            return lhsType == rhsType
        default:
            return false
        }
    }
}

extension SubscriptionPixelHandling {

    /// An event mapping for `DefaultOAuthClient`'s backup events that hands them to this handler as `.backupRenewed` and `.backupRenewalFailed`.
    public func backupEventMapping() -> EventMapping<OAuthClientBackupEvent> {
        EventMapping { event, _, _, _ in
            switch event {
            case .backupRenewed:
                handle(pixel: .backupRenewed)
            case .backupRenewalFailed(let error):
                handle(pixel: .backupRenewalFailed(error))
            }
        }
    }
}
