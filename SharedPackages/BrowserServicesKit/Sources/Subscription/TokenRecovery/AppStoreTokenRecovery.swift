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
public struct AppStoreTokenRecovery: TokenRecoveryStrategy {

    private let recoverer: DeadTokenRecoverer
    private let purchasePlatform: SubscriptionEnvironment.PurchasePlatform
    private let restoreFlow: any AppStoreRestoreFlow

    /// - Parameters:
    ///   - recoverer: Runs the restore, sharing it between concurrent callers.
    ///   - purchasePlatform: The platform the subscription was bought on. Only `.appStore` can be restored.
    ///   - restoreFlow: The App Store restore flow.
    public init(recoverer: DeadTokenRecoverer, purchasePlatform: SubscriptionEnvironment.PurchasePlatform, restoreFlow: any AppStoreRestoreFlow) {
        self.recoverer = recoverer
        self.purchasePlatform = purchasePlatform
        self.restoreFlow = restoreFlow
    }

    /// Restores from the last App Store purchase. Throws `SubscriptionManagerError.tokenRecoveryNotAttempted` for other purchase platforms.
    public func recover(_ context: TokenRecoveryContext) async throws {
        try await recoverer.attemptRecoveryFromPastPurchase(purchasePlatform: purchasePlatform, restoreFlow: restoreFlow)
    }
}
