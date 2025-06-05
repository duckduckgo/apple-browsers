//
//  MockStorePurchaseManagerV2.swift
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
import Subscription

class MockStorePurchaseManagerV2: StorePurchaseManagerV2 {
    func subscriptionOptions() async -> SubscriptionOptionsV2? {
        return nil
    }

    func freeTrialSubscriptionOptions() async -> SubscriptionOptionsV2? {
        return nil
    }

    var purchasedProductIDs: [String] = []

    var purchaseQueue: [String] = []

    var areProductsAvailable: Bool = true

    var currentStorefrontRegion: SubscriptionRegion = .usa

    func syncAppleIDAccount() async throws {
    }

    func updateAvailableProducts() async {
    }

    func updatePurchasedProducts() async {
    }

    func mostRecentTransaction() async -> String? {
        return nil
    }

    func hasActiveSubscription() async -> Bool {
        return true
    }

    func isUserEligibleForFreeTrial() async -> Bool {
        return true
    }

    func purchaseSubscription(with identifier: String, externalID: String) async -> Result<String, StorePurchaseManagerError> {
        return .success("")
    }

}
