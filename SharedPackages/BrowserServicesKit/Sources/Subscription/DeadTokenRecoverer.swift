//
//  DeadTokenRecoverer.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import os.log

public actor DeadTokenRecoverer {

    private static var recoveryAttemptCount: Int = 0

    @available(macOS 12.0, *)
    public static func attemptRecoveryFromPastPurchase(subscriptionManager: any SubscriptionManagerV2,
                                                       restoreFlow: any AppStoreRestoreFlowV2) async throws {
        if recoveryAttemptCount != 0 {
            Logger.subscription.debug("Recovery attempt already in progress, skipping...")
            try reportFailure()
        }
        recoveryAttemptCount += 1

        switch subscriptionManager.currentEnvironment.purchasePlatform {
        case .appStore:
            do {
                try await restoreFlow.restoreSubscriptionAfterExpiredRefreshToken()
            } catch {
                do { try reportFailure(error: error) } catch { throw error}
            }
        case .stripe:
            Logger.subscription.debug("Subscription purchased via Stripe can't be restored automatically, notifying the user...")
            NotificationCenter.default.post(name: .expiredRefreshTokenDetected, object: self, userInfo: nil)
            throw SubscriptionManagerError.tokenRefreshFailed(error: nil)
        }
    }

    public static func reportDeadRefreshToken() async throws {
        if recoveryAttemptCount != 0 {
            Logger.subscription.debug("Recovery attempt already in progress, skipping...")
            try reportFailure()
        }
        recoveryAttemptCount += 1

        Logger.subscription.debug("Subscription purchased via Stripe can't be restored automatically, removing the subscription and notifying the user...")
        NotificationCenter.default.post(name: .expiredRefreshTokenDetected, object: self, userInfo: nil)
        try reportFailure()
    }

    private static func reportFailure(error: Error? = nil) throws {
        recoveryAttemptCount = 0
        throw SubscriptionManagerError.tokenRefreshFailed(error: error)
    }
}
