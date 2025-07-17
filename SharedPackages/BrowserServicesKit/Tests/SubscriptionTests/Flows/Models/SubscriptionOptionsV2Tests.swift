//
//  SubscriptionOptionsV2Tests.swift
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

import XCTest
@testable import Subscription
import SubscriptionTestingUtilities
import Networking

final class SubscriptionOptionsV2Tests: XCTestCase {

    func testEncoding() throws {
        let monthlySubscriptionOffer = SubscriptionOptionOffer(type: .freeTrial, id: "1", durationInDays: 7, isUserEligible: true)
        let yearlySubscriptionOffer = SubscriptionOptionOffer(type: .freeTrial, id: "2", durationInDays: 7, isUserEligible: true)
        let subscriptionOptions = SubscriptionOptionsV2(platform: .macos,
                                                      options: [
                                                        SubscriptionOptionV2(id: "1",
                                                                           cost: SubscriptionOptionCost(displayPrice: "9 USD", recurrence: "monthly"), offer: monthlySubscriptionOffer),
                                                        SubscriptionOptionV2(id: "2",
                                                                           cost: SubscriptionOptionCost(displayPrice: "99 USD", recurrence: "yearly"), offer: yearlySubscriptionOffer)
                                                      ],
                                                      availableEntitlements: [
                                                        .networkProtection,
                                                        .dataBrokerProtection,
                                                        .identityTheftRestoration
                                                      ])

        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try? jsonEncoder.encode(subscriptionOptions)
        let subscriptionOptionsString = String(data: data!, encoding: .utf8)!

        XCTAssertEqual(subscriptionOptionsString, """
{
  "features" : [
    {
      "name" : "Network Protection"
    },
    {
      "name" : "Data Broker Protection"
    },
    {
      "name" : "Identity Theft Restoration"
    }
  ],
  "options" : [
    {
      "cost" : {
        "displayPrice" : "9 USD",
        "recurrence" : "monthly"
      },
      "id" : "1",
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
      "id" : "2",
      "offer" : {
        "durationInDays" : 7,
        "id" : "2",
        "isUserEligible" : true,
        "type" : "freeTrial"
      }
    }
  ],
  "platform" : "macos"
}
""")
    }

    func testSubscriptionOptionCostEncoding() throws {
        let subscriptionOptionCost = SubscriptionOptionCost(displayPrice: "9 USD", recurrence: "monthly")

        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.sortedKeys]
        let data = try? jsonEncoder.encode(subscriptionOptionCost)
        let subscriptionOptionCostString = String(data: data!, encoding: .utf8)!

        XCTAssertEqual(subscriptionOptionCostString, "{\"displayPrice\":\"9 USD\",\"recurrence\":\"monthly\"}")
    }

    func testSubscriptionFeatureEncoding() throws {
        let subscriptionFeature: SubscriptionEntitlement = .identityTheftRestoration

        let data = try? JSONEncoder().encode(subscriptionFeature)
        let subscriptionFeatureString = String(data: data!, encoding: .utf8)!

        XCTAssertEqual(subscriptionFeatureString, "\"Identity Theft Restoration\"")
    }

    func testEmptySubscriptionOptions() throws {
        let empty = SubscriptionOptionsV2.empty

        let platform: SubscriptionPlatformName
#if os(iOS)
        platform = .ios
#else
        platform = .macos
#endif

        XCTAssertEqual(empty.platform, platform)
        XCTAssertTrue(empty.options.isEmpty)
        XCTAssertEqual(empty.features.count, 4)
    }
}
