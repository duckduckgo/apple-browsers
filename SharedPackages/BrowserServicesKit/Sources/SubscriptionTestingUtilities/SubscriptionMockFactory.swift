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
@testable import Subscription

/// Provides all mocks needed for testing subscription initialised with positive outcomes and basic configurations. All mocks can be partially reconfigured with failures or incorrect data
public struct SubscriptionMockFactory {

    public static let appleSubscription = PrivacyProSubscription(productId: UUID().uuidString,
                                                  name: "Subscription test #1",
                                                  billingPeriod: .monthly,
                                                  startedAt: Date(),
                                                  expiresOrRenewsAt: Date().addingTimeInterval(TimeInterval.days(+30)),
                                                  platform: .apple,
                                                  status: .autoRenewable,
                                                  activeOffers: [])
    public static let expiredSubscription = PrivacyProSubscription(productId: UUID().uuidString,
                                                         name: "Subscription test #2",
                                                         billingPeriod: .monthly,
                                                         startedAt: Date().addingTimeInterval(TimeInterval.days(-31)),
                                                         expiresOrRenewsAt: Date().addingTimeInterval(TimeInterval.days(-1)),
                                                         platform: .apple,
                                                         status: .expired,
                                                         activeOffers: [])

    public static let expiredStripeSubscription = PrivacyProSubscription(productId: UUID().uuidString,
                                                         name: "Subscription test #2",
                                                         billingPeriod: .monthly,
                                                         startedAt: Date().addingTimeInterval(TimeInterval.days(-31)),
                                                         expiresOrRenewsAt: Date().addingTimeInterval(TimeInterval.days(-1)),
                                                         platform: .stripe,
                                                         status: .expired,
                                                         activeOffers: [])

    public static let productsItems: [GetProductsItem] = [GetProductsItem(productId: appleSubscription.productId,
                                                                          productLabel: appleSubscription.name,
                                                                          billingPeriod: appleSubscription.billingPeriod.rawValue,
                                                                          price: "0.99",
                                                                          currency: "USD")]
}
