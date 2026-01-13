//
//  SubscriptionMockFactory.swift
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
import Networking
@testable import Subscription

/// Provides all mocks needed for testing subscription initialised with positive outcomes and basic configurations. All mocks can be partially reconfigured with failures or incorrect data
public struct SubscriptionMockFactory {

    public static let appleSubscription = DuckDuckGoSubscription(productId: UUID().uuidString,
                                                  name: "Subscription test #1",
                                                  billingPeriod: .monthly,
                                                  startedAt: Date(),
                                                  expiresOrRenewsAt: Date().addingTimeInterval(TimeInterval.days(+30)),
                                                  platform: .apple,
                                                  status: .autoRenewable,
                                                  activeOffers: [],
                                                  tier: nil,
                                                  availableChanges: nil)
    public static let expiredSubscription = DuckDuckGoSubscription(productId: UUID().uuidString,
                                                         name: "Subscription test #2",
                                                         billingPeriod: .monthly,
                                                         startedAt: Date().addingTimeInterval(TimeInterval.days(-31)),
                                                         expiresOrRenewsAt: Date().addingTimeInterval(TimeInterval.days(-1)),
                                                         platform: .apple,
                                                         status: .expired,
                                                         activeOffers: [],
                                                         tier: nil,
                                                         availableChanges: nil)

    public static let expiredStripeSubscription = DuckDuckGoSubscription(productId: UUID().uuidString,
                                                         name: "Subscription test #2",
                                                         billingPeriod: .monthly,
                                                         startedAt: Date().addingTimeInterval(TimeInterval.days(-31)),
                                                         expiresOrRenewsAt: Date().addingTimeInterval(TimeInterval.days(-1)),
                                                         platform: .stripe,
                                                         status: .expired,
                                                         activeOffers: [],
                                                         tier: nil,
                                                         availableChanges: nil)

    public static let productsItems: [GetProductsItem] = [GetProductsItem(productId: appleSubscription.productId,
                                                                          productLabel: appleSubscription.name,
                                                                          billingPeriod: appleSubscription.billingPeriod.rawValue,
                                                                          price: "0.99",
                                                                          currency: "USD")]

    public static let tierProductsResponse = GetTierProductsResponse(products: [
        TierProduct(
            productName: "Plus Subscription",
            tier: .plus,
            regions: ["us", "row"],
            entitlements: [
                TierFeature(product: .networkProtection, name: .plus),
                TierFeature(product: .dataBrokerProtection, name: .plus),
                TierFeature(product: .identityTheftRestoration, name: .plus),
                TierFeature(product: .paidAIChat, name: .plus)
            ],
            billingCycles: [
                BillingCycle(productId: "monthly-plus", period: "Monthly", price: "9.99", currency: "USD"),
                BillingCycle(productId: "yearly-plus", period: "Yearly", price: "99.99", currency: "USD")
            ]
        )
    ])

    public static func subscription(
        status: DuckDuckGoSubscription.Status,
        platform: DuckDuckGoSubscription.Platform = .apple,
        activeOffers: [DuckDuckGoSubscription.Offer] = [],
        tier: TierName? = nil,
        availableChanges: DuckDuckGoSubscription.AvailableChanges? = nil
    ) -> DuckDuckGoSubscription {
        DuckDuckGoSubscription(
            productId: UUID().uuidString,
            name: "Test Subscription",
            billingPeriod: .monthly,
            startedAt: Date(),
            expiresOrRenewsAt: Date().addingTimeInterval(TimeInterval.days(+30)),
            platform: platform,
            status: status,
            activeOffers: activeOffers,
            tier: tier,
            availableChanges: availableChanges
        )
    }
}
