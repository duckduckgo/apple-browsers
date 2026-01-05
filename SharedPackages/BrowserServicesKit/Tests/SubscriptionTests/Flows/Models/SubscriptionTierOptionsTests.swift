//
//  SubscriptionTierOptionsTests.swift
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

import Testing
@testable import Subscription
import SubscriptionTestingUtilities
import Networking
import Foundation

@Suite("SubscriptionTierOptions Tests")
struct SubscriptionTierOptionsTests {

    @Test("Encoding tier options to JSON")
    func encoding() throws {
        let monthlySubscriptionOffer = SubscriptionOptionOffer(type: .freeTrial, id: "1", durationInDays: 7, isUserEligible: true)
        let yearlySubscriptionOffer = SubscriptionOptionOffer(type: .freeTrial, id: "2", durationInDays: 7, isUserEligible: true)

        let plusTier = SubscriptionTier(
            tier: .plus,
            features: [TierFeature(product: .paidAIChat, name: .plus),
                       TierFeature(product: .networkProtection, name: .plus)],
            options: [
                SubscriptionOptionV2(id: "1",
                                   cost: SubscriptionOptionCost(displayPrice: "5 USD", recurrence: "monthly"),
                                   offer: monthlySubscriptionOffer)
            ]
        )

        let proTier = SubscriptionTier(
            tier: .pro,
            features: [TierFeature(product: .paidAIChat, name: .pro),
                       TierFeature(product: .networkProtection, name: .plus)],
            options: [
                SubscriptionOptionV2(id: "2",
                                   cost: SubscriptionOptionCost(displayPrice: "9 USD", recurrence: "monthly"),
                                   offer: monthlySubscriptionOffer),
                SubscriptionOptionV2(id: "3",
                                   cost: SubscriptionOptionCost(displayPrice: "99 USD", recurrence: "yearly"),
                                   offer: yearlySubscriptionOffer)
            ]
        )

        let tierOptions = SubscriptionTierOptions(platform: .macos, products: [plusTier, proTier])

        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try #require(try? jsonEncoder.encode(tierOptions))
        let tierOptionsString = try #require(String(data: data, encoding: .utf8))

        #expect(tierOptionsString == """
{
  "platform" : "macos",
  "products" : [
    {
      "features" : [
        {
          "name" : "plus",
          "product" : "Duck.ai"
        },
        {
          "name" : "plus",
          "product" : "Network Protection"
        }
      ],
      "options" : [
        {
          "cost" : {
            "displayPrice" : "5 USD",
            "recurrence" : "monthly"
          },
          "id" : "1",
          "offer" : {
            "durationInDays" : 7,
            "id" : "1",
            "isUserEligible" : true,
            "type" : "freeTrial"
          }
        }
      ],
      "tier" : "plus"
    },
    {
      "features" : [
        {
          "name" : "pro",
          "product" : "Duck.ai"
        },
        {
          "name" : "plus",
          "product" : "Network Protection"
        }
      ],
      "options" : [
        {
          "cost" : {
            "displayPrice" : "9 USD",
            "recurrence" : "monthly"
          },
          "id" : "2",
          "offer" : {
            "durationInDays" : 7,
            "id" : "1",
            "isUserEligible" : true,
            "type" : "freeTrial"
          }
        },
        {
          "cost" : {
            "displayPrice" : "99 USD",
            "recurrence" : "yearly"
          },
          "id" : "3",
          "offer" : {
            "durationInDays" : 7,
            "id" : "2",
            "isUserEligible" : true,
            "type" : "freeTrial"
          }
        }
      ],
      "tier" : "pro"
    }
  ]
}
""")
    }

    @Test("Empty subscription tier options")
    func emptySubscriptionTierOptions() {
        let empty = SubscriptionTierOptions.empty

        let platform: SubscriptionPlatformName
#if os(iOS)
        platform = .ios
#else
        platform = .macos
#endif

        #expect(empty.platform == platform)
        #expect(empty.products.isEmpty)
    }

    @Test("Remove purchase options while preserving tier data")
    func withoutPurchaseOptions() {
        let plusTier = SubscriptionTier(
            tier: .plus,
            features: [TierFeature(product: .networkProtection, name: .plus)],
            options: [
                SubscriptionOptionV2(id: "1",
                                   cost: SubscriptionOptionCost(displayPrice: "5 USD", recurrence: "monthly"),
                                   offer: nil)
            ]
        )

        let proTier = SubscriptionTier(
            tier: .pro,
            features: [TierFeature(product: .identityTheftRestoration, name: .plus),
                       TierFeature(product: .dataBrokerProtection, name: .plus),
                       TierFeature(product: .networkProtection, name: .plus)],
            options: [
                SubscriptionOptionV2(id: "2",
                                   cost: SubscriptionOptionCost(displayPrice: "9 USD", recurrence: "monthly"),
                                   offer: nil),
                SubscriptionOptionV2(id: "3",
                                   cost: SubscriptionOptionCost(displayPrice: "99 USD", recurrence: "yearly"),
                                   offer: nil)
            ]
        )

        let tierOptions = SubscriptionTierOptions(platform: .macos, products: [plusTier, proTier])
        let withoutOptions = tierOptions.withoutPurchaseOptions()

        // Verify platform is preserved
        #expect(withoutOptions.platform == .macos)

        // Verify same number of tiers
        #expect(withoutOptions.products.count == 2)

        // Verify first tier (plus)
        #expect(withoutOptions.products[0].tier == .plus)
        #expect(withoutOptions.products[0].features == [TierFeature(product: .networkProtection, name: .plus)])
        #expect(withoutOptions.products[0].options.isEmpty, "Plus tier should have no purchase options")

        // Verify second tier (pro)
        #expect(withoutOptions.products[1].tier == .pro)
        #expect(withoutOptions.products[1].features == [TierFeature(product: .identityTheftRestoration, name: .plus),
                                                        TierFeature(product: .dataBrokerProtection, name: .plus),
                                                        TierFeature(product: .networkProtection, name: .plus)])
        #expect(withoutOptions.products[1].options.isEmpty, "Pro tier should have no purchase options")
    }

    @Test("Remove purchase options from empty tier options")
    func withoutPurchaseOptionsOnEmptyTiers() {
        let empty = SubscriptionTierOptions.empty
        let withoutOptions = empty.withoutPurchaseOptions()

        #expect(withoutOptions.products.isEmpty)

        let platform: SubscriptionPlatformName
#if os(iOS)
        platform = .ios
#else
        platform = .macos
#endif
        #expect(withoutOptions.platform == platform)
    }

    @Test("TierName defaults to plus when decoding unknown value")
    func tierNameDefaultsToPlusForUnknownValue() throws {
        // JSON with an unknown tier name
        let json = """
        {
            "product": "Network Protection",
            "name": "unknown_tier"
        }
        """
        let data = try #require(json.data(using: .utf8))

        let decoder = JSONDecoder()
        let tierFeature = try decoder.decode(TierFeature.self, from: data)

        #expect(tierFeature.name == .plus, "Unknown tier name should default to .plus")
    }
}
