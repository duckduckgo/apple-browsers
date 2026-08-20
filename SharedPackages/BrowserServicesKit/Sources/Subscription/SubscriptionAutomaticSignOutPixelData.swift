//
//  SubscriptionAutomaticSignOutPixelData.swift
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
import FoundationExtensions
import Networking

/// Wire representation of `AuthTokensCachePolicy`. `AuthTokensCachePolicy.description` is display
/// text ("Local valid") and is deliberately not used here, so that reworded logs can't silently
/// change a pixel's values.
public enum TokenCachePolicyParameter: String {
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

/// The buckets shared by every "how long" parameter on the sign-out pixel. Keeping the thresholds
/// in one place stops the token-age and time-remaining buckets from drifting apart. Callers label
/// the negative side themselves: an expired token and a token issued in the future are different
/// findings, so they must not collapse into one bucket.
private enum DurationBucket {
    case lessThanOneHour
    case oneHourToOneDay
    case oneToThreeDays
    case moreThanThreeDays

    init(_ interval: TimeInterval) {
        switch interval {
        case ..<TimeInterval.hours(1):
            self = .lessThanOneHour
        case ..<TimeInterval.days(1):
            self = .oneHourToOneDay
        case ...TimeInterval.days(3):
            self = .oneToThreeDays
        default:
            self = .moreThanThreeDays
        }
    }
}

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

        public init(_ tokenStatus: OAuthRequest.TokenStatus?) {
            switch tokenStatus {
            case .invalid:
                self = .invalid
            case .expired:
                self = .expired
            case .reused:
                self = .reused
            case .loggedOut:
                self = .loggedOut
            case .fraudDetected:
                self = .fraudDetected
            case nil:
                self = .unknown
            }
        }
    }

    public enum RecoveryOutcome: String {
        case notAttempted = "not_attempted"
        case failed
        case notApplicable = "not_applicable"
    }

    public enum EntitlementState: String {
        case present
        case absent
        case unknown

        public init(_ tokenContainer: TokenContainer?) {
            guard let tokenContainer else {
                self = .unknown
                return
            }
            self = tokenContainer.decodedAccessToken.subscriptionEntitlements.isEmpty ? .absent : .present
        }
    }

    public enum TokenAgeBucket: String {
        case issuedInFuture = "issued_in_future"
        case lessThanOneHour = "less_than_1_hour"
        case oneHourToOneDay = "1_hour_to_1_day"
        case oneToThreeDays = "1_to_3_days"
        case moreThanThreeDays = "more_than_3_days"
        case unknown

        public init(issuedAt: Date?, now: Date) {
            guard let issuedAt else {
                self = .unknown
                return
            }

            let age = now.timeIntervalSince(issuedAt)
            guard age >= 0 else {
                self = .issuedInFuture
                return
            }

            switch DurationBucket(age) {
            case .lessThanOneHour:
                self = .lessThanOneHour
            case .oneHourToOneDay:
                self = .oneHourToOneDay
            case .oneToThreeDays:
                self = .oneToThreeDays
            case .moreThanThreeDays:
                self = .moreThanThreeDays
            }
        }
    }

    public enum TimeRemainingBucket: String {
        case expired
        case lessThanOneHour = "less_than_1_hour"
        case oneHourToOneDay = "1_hour_to_1_day"
        case oneToThreeDays = "1_to_3_days"
        case moreThanThreeDays = "more_than_3_days"
        case unknown
        case notPresentInProcess = "not_present_in_process"

        public init(until date: Date?, now: Date) {
            guard let date else {
                self = .unknown
                return
            }

            let timeRemaining = date.timeIntervalSince(now)
            guard timeRemaining > 0 else {
                self = .expired
                return
            }

            switch DurationBucket(timeRemaining) {
            case .lessThanOneHour:
                self = .lessThanOneHour
            case .oneHourToOneDay:
                self = .oneHourToOneDay
            case .oneToThreeDays:
                self = .oneToThreeDays
            case .moreThanThreeDays:
                self = .moreThanThreeDays
            }
        }

        public init(cachedSubscription: DuckDuckGoSubscription?, now: Date) {
            guard let cachedSubscription else {
                self = .notPresentInProcess
                return
            }
            self.init(until: cachedSubscription.expiresOrRenewsAt, now: now)
        }
    }

    public enum CachedSubscriptionStatus: String {
        case autoRenewable = "auto_renewable"
        case notAutoRenewable = "not_auto_renewable"
        case gracePeriod = "grace_period"
        case inactive
        case expired
        case unknown
        case notPresentInProcess = "not_present_in_process"

        public init(_ subscription: DuckDuckGoSubscription?) {
            guard let subscription else {
                self = .notPresentInProcess
                return
            }

            switch subscription.status {
            case .autoRenewable:
                self = .autoRenewable
            case .notAutoRenewable:
                self = .notAutoRenewable
            case .gracePeriod:
                self = .gracePeriod
            case .inactive:
                self = .inactive
            case .expired:
                self = .expired
            case .unknown:
                self = .unknown
            }
        }
    }

    public enum CachedSubscriptionTrialStatus: String {
        case active
        case notActive = "not_active"
        case notPresentInProcess = "not_present_in_process"

        public init(_ subscription: DuckDuckGoSubscription?) {
            guard let subscription else {
                self = .notPresentInProcess
                return
            }
            self = subscription.hasActiveTrialOffer ? .active : .notActive
        }
    }

    public enum CachedSubscriptionPurchasePlatform: String {
        case appStore = "app_store"
        case playStore = "play_store"
        case stripe
        case unknown
        case notPresentInProcess = "not_present_in_process"

        public init(_ subscription: DuckDuckGoSubscription?) {
            guard let subscription else {
                self = .notPresentInProcess
                return
            }

            switch subscription.platform {
            case .apple:
                self = .appStore
            case .google:
                self = .playStore
            case .stripe:
                self = .stripe
            case .unknown:
                self = .unknown
            }
        }
    }

    public enum StoredRefreshTokenState: String {
        case unchanged
        case changed
        case missing
        case readError = "read_error"
        case unavailableBeforeAttempt = "unavailable_before_attempt"

        public init(before: LocalTokenSnapshot, after: LocalTokenSnapshot) {
            guard let tokenBeforeAttempt = before.tokenContainer else {
                self = .unavailableBeforeAttempt
                return
            }

            switch after {
            case .present(let tokenAfterAttempt):
                self = tokenBeforeAttempt.refreshToken == tokenAfterAttempt.refreshToken ? .unchanged : .changed
            case .missing:
                self = .missing
            case .readError:
                self = .readError
            }
        }
    }

    public enum LocalTokenState: String {
        case present
        case missing
        case readError = "read_error"

        public init(_ state: LocalSubscriptionTokenState) {
            switch state {
            case .present:
                self = .present
            case .missing:
                self = .missing
            case .readError:
                self = .readError
            }
        }
    }

    public let reason: Reason
    public let tokenStatus: TokenStatus
    public let recoveryOutcome: RecoveryOutcome
    public let tokenCachePolicy: TokenCachePolicyParameter
    public let entitlementStateBefore: EntitlementState
    public let accessTokenTimeRemainingBefore: TimeRemainingBucket
    public let refreshTokenTimeRemainingBefore: TimeRemainingBucket
    public let refreshTokenAgeBefore: TokenAgeBucket
    public let cachedSubscriptionStatusBefore: CachedSubscriptionStatus
    public let cachedSubscriptionTrialStatusBefore: CachedSubscriptionTrialStatus
    public let cachedSubscriptionPurchasePlatformBefore: CachedSubscriptionPurchasePlatform
    public let cachedSubscriptionTimeRemainingBefore: TimeRemainingBucket
    public let storedRefreshTokenStateDuringAttempt: StoredRefreshTokenState
    public let localTokenStateAfterSignOut: LocalTokenState

    public init(reason: Reason,
                tokenStatus: TokenStatus,
                recoveryOutcome: RecoveryOutcome,
                tokenCachePolicy: TokenCachePolicyParameter,
                entitlementStateBefore: EntitlementState,
                accessTokenTimeRemainingBefore: TimeRemainingBucket,
                refreshTokenTimeRemainingBefore: TimeRemainingBucket,
                refreshTokenAgeBefore: TokenAgeBucket,
                cachedSubscriptionStatusBefore: CachedSubscriptionStatus,
                cachedSubscriptionTrialStatusBefore: CachedSubscriptionTrialStatus,
                cachedSubscriptionPurchasePlatformBefore: CachedSubscriptionPurchasePlatform,
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
        self.cachedSubscriptionTrialStatusBefore = cachedSubscriptionTrialStatusBefore
        self.cachedSubscriptionPurchasePlatformBefore = cachedSubscriptionPurchasePlatformBefore
        self.cachedSubscriptionTimeRemainingBefore = cachedSubscriptionTimeRemainingBefore
        self.storedRefreshTokenStateDuringAttempt = storedRefreshTokenStateDuringAttempt
        self.localTokenStateAfterSignOut = localTokenStateAfterSignOut
    }

    /// Derives every bucketed parameter from the state captured around a failed token request.
    /// `tokenBeforeAttempt` must have been snapshotted *before* the request, so that
    /// `storedRefreshTokenStateDuringAttempt` can tell whether the stored token rotated underneath it.
    public init(reason: Reason,
                tokenStatus: TokenStatus,
                recoveryOutcome: RecoveryOutcome,
                policy: AuthTokensCachePolicy,
                tokenBeforeAttempt: LocalTokenSnapshot,
                tokenAfterAttempt: LocalTokenSnapshot,
                cachedSubscription: DuckDuckGoSubscription?,
                localTokenStateAfterSignOut: LocalSubscriptionTokenState,
                now: Date) {
        let tokenContainerBefore = tokenBeforeAttempt.tokenContainer
        self.init(
            reason: reason,
            tokenStatus: tokenStatus,
            recoveryOutcome: recoveryOutcome,
            tokenCachePolicy: .init(policy),
            entitlementStateBefore: .init(tokenContainerBefore),
            accessTokenTimeRemainingBefore: .init(until: tokenContainerBefore?.decodedAccessToken.expirationDate, now: now),
            refreshTokenTimeRemainingBefore: .init(until: tokenContainerBefore?.decodedRefreshToken.expirationDate, now: now),
            refreshTokenAgeBefore: .init(issuedAt: tokenContainerBefore?.decodedRefreshToken.issuedAtDate, now: now),
            cachedSubscriptionStatusBefore: .init(cachedSubscription),
            cachedSubscriptionTrialStatusBefore: .init(cachedSubscription),
            cachedSubscriptionPurchasePlatformBefore: .init(cachedSubscription),
            cachedSubscriptionTimeRemainingBefore: .init(cachedSubscription: cachedSubscription, now: now),
            storedRefreshTokenStateDuringAttempt: .init(before: tokenBeforeAttempt, after: tokenAfterAttempt),
            localTokenStateAfterSignOut: .init(localTokenStateAfterSignOut))
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
            "cached_subscription_trial_status_before": cachedSubscriptionTrialStatusBefore.rawValue,
            "cached_subscription_purchase_platform_before": cachedSubscriptionPurchasePlatformBefore.rawValue,
            "cached_subscription_time_remaining_bucket_before": cachedSubscriptionTimeRemainingBefore.rawValue,
            "stored_refresh_token_state_during_attempt": storedRefreshTokenStateDuringAttempt.rawValue,
            "local_token_state_after_sign_out": localTokenStateAfterSignOut.rawValue
        ]
    }
}
