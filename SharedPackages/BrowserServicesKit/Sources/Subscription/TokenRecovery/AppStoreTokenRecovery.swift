//
//  AppStoreTokenRecovery.swift
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

/// Recovers the current token container by restoring the subscription from the last App Store purchase.
public actor AppStoreTokenRecovery: TokenRecoveryStrategy {

    private let purchasePlatform: SubscriptionEnvironment.PurchasePlatform
    private let restoreFlow: any AppStoreRestoreFlow
    private var restoreTask: Task<Void, Error>?

    /// - Parameters:
    ///   - purchasePlatform: The platform the subscription was bought on. Only `.appStore` can be restored.
    ///   - restoreFlow: The App Store restore flow.
    public init(purchasePlatform: SubscriptionEnvironment.PurchasePlatform, restoreFlow: any AppStoreRestoreFlow) {
        self.purchasePlatform = purchasePlatform
        self.restoreFlow = restoreFlow
    }

    /// Restores from the last App Store purchase. A call made while a restore is running waits for that restore and gets its result.
    /// Throws `SubscriptionManagerError.tokenRecoveryNotAttempted` for other purchase platforms.
    public func recover(_ context: TokenRecoveryContext) async throws {
        guard purchasePlatform == .appStore else {
            throw SubscriptionManagerError.tokenRecoveryNotAttempted
        }

        if let restoreTask {
            try await restoreTask.value
            return
        }

        let restoreFlow = restoreFlow
        let task = Task {
            try await restoreFlow.restoreSubscriptionAfterExpiredRefreshToken()
        }
        restoreTask = task
        defer { restoreTask = nil }
        try await task.value
    }
}
