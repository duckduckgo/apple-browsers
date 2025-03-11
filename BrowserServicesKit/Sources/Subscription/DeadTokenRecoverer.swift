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

public struct DeadTokenRecoverer {

    private static var recoveryAttemptCount: Int = 0

    @available(macOS 12.0, *)
    public static func attemptRecoveryFromPastPurchase(subscriptionManager: any SubscriptionManagerV2,
                                                       restoreFlow: any AppStoreRestoreFlowV2) async throws {
        if recoveryAttemptCount != 0 {
            recoveryAttemptCount -= 1
            try reportFailure()
        }
        recoveryAttemptCount += 1

        guard subscriptionManager.isUserAuthenticated else {
            return
        }

        let subscription = try await subscriptionManager.getSubscription(cachePolicy: .returnCacheDataDontLoad)

        switch subscription.platform {
        case .apple:
            switch await restoreFlow.restoreAccountFromPastPurchase() {
            case .success:
                break
            case .failure:
                try reportFailure()
            }
        case .stripe:
            Logger.subscription.debug("Subscription purchased via Stripe can't be restored automatically, notifying the user...")
            NotificationCenter.default.post(name: .expiredRefreshTokenDetected, object: self, userInfo: nil)
        default:
            try reportFailure()
        }
    }

    private static func reportFailure() throws {
        recoveryAttemptCount = 0
        throw SubscriptionManagerError.tokenUnRefreshable
    }

    public static func attemptRecoveryFromPastPurchase(subscriptionManager: any SubscriptionManagerV2) async throws {
        Logger.subscription.debug("Subscription purchased via Stripe can't be restored automatically, removing the subscription and notifying the user...")
        await subscriptionManager.signOut(notifyUI: true)
        NotificationCenter.default.post(name: .expiredRefreshTokenDetected, object: self, userInfo: nil)
        try reportFailure()
    }
}
