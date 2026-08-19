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

import Foundation
import Networking

public struct SubscriptionAutomaticSignOutPixelData: Equatable {

    public enum Reason: String {
        case unknownAccount = "unknown_account"
        case invalidRefreshToken = "invalid_refresh_token"
    }

    public enum TokenStatus: String {
        case invalid
        case expired
        case reused
        case loggedOut = "logged_out"
        case fraudDetected = "fraud_detected"
        case unknown
        case notApplicable = "not_applicable"
    }

    public enum RecoveryOutcome: String {
        case notAttempted = "not_attempted"
        case failed
        case notApplicable = "not_applicable"
    }

    public enum TokenCachePolicy: String {
        case local
        case localValid = "local_valid"
        case localForceRefresh = "local_force_refresh"
        case createIfNeeded = "create_if_needed"

        public init(_ policy: AuthTokensCachePolicy) {
            switch policy {
            case .local:
                self = .local
            case .localValid:
                self = .localValid
            case .localForceRefresh:
                self = .localForceRefresh
            case .createIfNeeded:
                self = .createIfNeeded
            }
        }
    }

    public enum EntitlementState: String {
        case present
        case absent
        case unknown
    }

    public enum TokenAgeBucket: String {
        case issuedInFuture = "issued_in_future"
        case lessThanOneHour = "less_than_1_hour"
        case oneHourToOneDay = "1_hour_to_1_day"
        case oneToSevenDays = "1_to_7_days"
        case sevenToThirtyDays = "7_to_30_days"
        case moreThanThirtyDays = "more_than_30_days"
        case unknown
    }

    public enum TimeRemainingBucket: String {
        case expired
        case lessThanOneHour = "less_than_1_hour"
        case oneHourToOneDay = "1_hour_to_1_day"
        case oneToSevenDays = "1_to_7_days"
        case sevenToThirtyDays = "7_to_30_days"
        case moreThanThirtyDays = "more_than_30_days"
        case unknown
        case notPresentInProcess = "not_present_in_process"
    }

    public enum CachedSubscriptionStatus: String {
        case autoRenewable = "auto_renewable"
        case notAutoRenewable = "not_auto_renewable"
        case gracePeriod = "grace_period"
        case inactive
        case expired
        case unknown
        case notPresentInProcess = "not_present_in_process"
    }

    public enum StoredRefreshTokenState: String {
        case unchanged
        case changed
        case missing
        case readError = "read_error"
        case unavailableBeforeAttempt = "unavailable_before_attempt"
    }

    public enum LocalTokenState: String {
        case present
        case missing
        case readError = "read_error"
    }

    public let reason: Reason
    public let tokenStatus: TokenStatus
    public let recoveryOutcome: RecoveryOutcome
    public let tokenCachePolicy: TokenCachePolicy
    public let entitlementStateBefore: EntitlementState
    public let accessTokenTimeRemainingBefore: TimeRemainingBucket
    public let refreshTokenTimeRemainingBefore: TimeRemainingBucket
    public let refreshTokenAgeBefore: TokenAgeBucket
    public let cachedSubscriptionStatusBefore: CachedSubscriptionStatus
    public let cachedSubscriptionTimeRemainingBefore: TimeRemainingBucket
    public let storedRefreshTokenStateDuringAttempt: StoredRefreshTokenState
    public let localTokenStateAfterSignOut: LocalTokenState

    public init(reason: Reason,
                tokenStatus: TokenStatus,
                recoveryOutcome: RecoveryOutcome,
                tokenCachePolicy: TokenCachePolicy,
                entitlementStateBefore: EntitlementState,
                accessTokenTimeRemainingBefore: TimeRemainingBucket,
                refreshTokenTimeRemainingBefore: TimeRemainingBucket,
                refreshTokenAgeBefore: TokenAgeBucket,
                cachedSubscriptionStatusBefore: CachedSubscriptionStatus,
                cachedSubscriptionTimeRemainingBefore: TimeRemainingBucket,
                storedRefreshTokenStateDuringAttempt: StoredRefreshTokenState,
                localTokenStateAfterSignOut: LocalTokenState) {
        self.reason = reason
        self.tokenStatus = tokenStatus
        self.recoveryOutcome = recoveryOutcome
        self.tokenCachePolicy = tokenCachePolicy
        self.entitlementStateBefore = entitlementStateBefore
        self.accessTokenTimeRemainingBefore = accessTokenTimeRemainingBefore
        self.refreshTokenTimeRemainingBefore = refreshTokenTimeRemainingBefore
        self.refreshTokenAgeBefore = refreshTokenAgeBefore
        self.cachedSubscriptionStatusBefore = cachedSubscriptionStatusBefore
        self.cachedSubscriptionTimeRemainingBefore = cachedSubscriptionTimeRemainingBefore
        self.storedRefreshTokenStateDuringAttempt = storedRefreshTokenStateDuringAttempt
        self.localTokenStateAfterSignOut = localTokenStateAfterSignOut
    }

    public var parameters: [String: String] {
        [
            "reason": reason.rawValue,
            "token_status": tokenStatus.rawValue,
            "recovery_outcome": recoveryOutcome.rawValue,
            "policycache": tokenCachePolicy.rawValue,
            "had_subscription_entitlements_before": entitlementStateBefore.rawValue,
            "access_token_time_remaining_bucket_before": accessTokenTimeRemainingBefore.rawValue,
            "refresh_token_time_remaining_bucket_before": refreshTokenTimeRemainingBefore.rawValue,
            "refresh_token_age_bucket_before": refreshTokenAgeBefore.rawValue,
            "cached_subscription_status_before": cachedSubscriptionStatusBefore.rawValue,
            "cached_subscription_time_remaining_bucket_before": cachedSubscriptionTimeRemainingBefore.rawValue,
            "stored_refresh_token_state_during_attempt": storedRefreshTokenStateDuringAttempt.rawValue,
            "local_token_state_after_sign_out": localTokenStateAfterSignOut.rawValue
        ]
    }
}

public enum SubscriptionPixelType: Equatable {
    case invalidRefreshToken
    case subscriptionIsActive
    case osDistributionActiveSubscription
    case getTokensError(AuthTokensCachePolicy, Error)
    case automaticSignOut(SubscriptionAutomaticSignOutPixelData)
    case invalidRefreshTokenSignedOut
    case invalidRefreshTokenRecovered
    case purchaseSuccessAfterPendingTransaction
    case pendingTransactionApproved

    public static func == (lhs: SubscriptionPixelType, rhs: SubscriptionPixelType) -> Bool {
        switch (lhs, rhs) {
        case (.invalidRefreshToken, .invalidRefreshToken),
            (.subscriptionIsActive, .subscriptionIsActive),
            (.osDistributionActiveSubscription, .osDistributionActiveSubscription),
            (.invalidRefreshTokenSignedOut, .invalidRefreshTokenSignedOut),
            (.invalidRefreshTokenRecovered, .invalidRefreshTokenRecovered),
            (.getTokensError, .getTokensError),
            (.purchaseSuccessAfterPendingTransaction, .purchaseSuccessAfterPendingTransaction),
            (.pendingTransactionApproved, .pendingTransactionApproved):
            return true
        case let (.automaticSignOut(lhsData), .automaticSignOut(rhsData)):
            return lhsData == rhsData
        default:
            return false
        }
    }
}
