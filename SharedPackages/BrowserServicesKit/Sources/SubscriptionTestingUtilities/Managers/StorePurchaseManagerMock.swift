//
//  StorePurchaseManagerMock.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Subscription

public final class StorePurchaseManagerMock: StorePurchaseManager {

    public var purchasedProductIDs: [String] = []
    public var purchaseQueue: [String] = []
    public var areProductsAvailable: Bool = false
    public var currentStorefrontRegion: SubscriptionRegion = .usa

    public var subscriptionOptionsResult: SubscriptionOptions?
    public var freeTrialSubscriptionOptionsResult: SubscriptionOptions?
    public var syncAppleIDAccountResultError: Error?

    public var mostRecentTransactionResult: String?
    public var hasActiveSubscriptionResult: Bool = false
    public var purchaseSubscriptionResult: Result<TransactionJWS, StorePurchaseManagerError>?

    public var onUpdateAvailableProducts: (() -> Void)?

    public var updateAvailableProductsCalled: Bool = false
    public var mostRecentTransactionCalled: Bool = false
    public var purchaseSubscriptionCalled: Bool = false
    public var isEligibleForFreeTrialResult: Bool = false

    public init() { }

    public func subscriptionOptions() async -> SubscriptionOptions? {
        subscriptionOptionsResult
    }

    public func freeTrialSubscriptionOptions() async -> SubscriptionOptions? {
        freeTrialSubscriptionOptionsResult
    }

    public func syncAppleIDAccount() async throws {
        if let syncAppleIDAccountResultError {
            throw syncAppleIDAccountResultError
        }
    }

    public func updateAvailableProducts() async {
        updateAvailableProductsCalled = true
        onUpdateAvailableProducts?()
    }

    public func updatePurchasedProducts() async { }

    public func mostRecentTransaction() async -> String? {
        mostRecentTransactionCalled = true
        return mostRecentTransactionResult
    }

    public func hasActiveSubscription() async -> Bool {
        return hasActiveSubscriptionResult
    }

    public func purchaseSubscription(with identifier: String, externalID: String) async -> Result<TransactionJWS, StorePurchaseManagerError> {
        purchaseSubscriptionCalled = true
        return purchaseSubscriptionResult!
    }

    public func isUserEligibleForFreeTrial() -> Bool {
        isEligibleForFreeTrialResult
    }
}
