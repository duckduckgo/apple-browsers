//
//  PendingTransactionHandling.swift
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

/// Handler for tracking pending transactions (e.g., Ask to Buy, payment issues) and firing pixels
/// when a subscription is activated after being in a pending state.
///
public protocol PendingTransactionHandling {
    /// Sets the flag to indicate that a purchase is pending.
    func markPurchasePending()

    /// Fires the pixel and clears the flag if the purchase was pending.
    func handleSubscriptionActivated()

    /// Fires a pixel if the pending flag is set when a pending transaction is approved.
    /// Does NOT clear the flag (subscription activation handles that).
    func handlePendingTransactionApproved()
}

/// Default implementation that stores the pending flag in UserDefaults,
/// fires a pixel on activation if the flag was set, and clears the flag.
public final class DefaultPendingTransactionHandler: PendingTransactionHandling {

    private let userDefaults: UserDefaults
    private let pixelHandler: SubscriptionPixelHandling

    public init(userDefaults: UserDefaults = .standard,
                pixelHandler: SubscriptionPixelHandling) {
        self.userDefaults = userDefaults
        self.pixelHandler = pixelHandler
    }

    public func markPurchasePending() {
        userDefaults.hasPurchasePendingTransaction = true
    }

    public func handleSubscriptionActivated() {
        if userDefaults.hasPurchasePendingTransaction {
            pixelHandler.handle(pixel: .purchaseSuccessAfterPendingTransaction)
            userDefaults.hasPurchasePendingTransaction = false
        }
    }

    public func handlePendingTransactionApproved() {
        if userDefaults.hasPurchasePendingTransaction {
            pixelHandler.handle(pixel: .pendingTransactionApproved)
        }
    }
}
