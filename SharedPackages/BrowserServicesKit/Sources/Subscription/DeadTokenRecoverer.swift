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
    private var recoveryTask: Task<Void, Error>?

    public init() {}

    @available(macOS 12.0, *)
    public func attemptRecoveryFromPastPurchase(purchasePlatform: SubscriptionEnvironment.PurchasePlatform,
                                                restoreFlow: any AppStoreRestoreFlowV2) async throws {
        guard purchasePlatform == .appStore else {
            throw SubscriptionManagerError.noTokenAvailable
        }

        // If recovery is in progress or completed, wait for it
        if let existingTask = recoveryTask {
            try await existingTask.value
            return
        }

        // Start new recovery
        recoveryTask = Task {
            try await restoreFlow.restoreSubscriptionAfterExpiredRefreshToken()
        }

        defer { recoveryTask = nil }
        try await recoveryTask!.value
    }
}
