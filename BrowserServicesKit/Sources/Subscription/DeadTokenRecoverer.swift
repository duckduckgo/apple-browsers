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

@available(macOS 12.0, *)
public struct DeadTokenRecoverer {

    private static var recoveryAttemptCount: Int = 0

    public static func attemptRecoveryFromPastPurchase(endpointService: any SubscriptionEndpointServiceV2, restoreFlow: any AppStoreRestoreFlowV2) async throws {
        if recoveryAttemptCount != 0 {
            recoveryAttemptCount -= 1
            throw SubscriptionManagerError.tokenUnRefreshable
        }
        recoveryAttemptCount += 1

        let subscription = try await endpointService.getSubscription(accessToken: "", cachePolicy: .returnCacheDataDontLoad)
        guard subscription.platform == .apple else {
            throw SubscriptionManagerError.tokenUnRefreshable
        }

        switch await restoreFlow.restoreAccountFromPastPurchase() {
        case .success:
            break
        case .failure:
            throw SubscriptionManagerError.tokenUnRefreshable
        }
    }
}
