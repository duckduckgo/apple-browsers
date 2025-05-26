//
//  SubscriptionOptionsV2.swift
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

public struct SubscriptionOptionsV2: Encodable, Equatable {
    struct Feature: Encodable, Equatable {
        let name: SubscriptionEntitlement
    }

    let platform: SubscriptionPlatformName
    let options: [SubscriptionOptionV2]
    /// The available features in the subscription based on the country and feature flags. Not based on user entitlements
    let features: [SubscriptionOptionsV2.Feature]

    public init(platform: SubscriptionPlatformName, options: [SubscriptionOptionV2], availableEntitlements: [SubscriptionEntitlement]) {
        self.platform = platform
        self.options = options
        self.features = availableEntitlements.map({ entitlement in
            Feature(name: entitlement)
        })
    }

    public static var empty: SubscriptionOptionsV2 {
        let features: [SubscriptionEntitlement] = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration]
        let platform: SubscriptionPlatformName
#if os(iOS)
        platform = .ios
#else
        platform = .macos
#endif
        return SubscriptionOptionsV2(platform: platform, options: [], availableEntitlements: features)
    }

    public func withoutPurchaseOptions() -> Self {
        SubscriptionOptionsV2(platform: platform, options: [], availableEntitlements: features.map({ feature in
            feature.name
        }))
    }
}

public enum SubscriptionPlatformName: String, Encodable {
    case ios
    case macos
    case stripe
}

public struct SubscriptionOptionV2: Encodable, Equatable {
    let id: String
    let cost: SubscriptionOptionCost
    let offer: SubscriptionOptionOffer?

    init(id: String, cost: SubscriptionOptionCost, offer: SubscriptionOptionOffer? = nil) {
        self.id = id
        self.cost = cost
        self.offer = offer
    }
}

struct SubscriptionOptionCost: Encodable, Equatable {
    let displayPrice: String
    let recurrence: String
}

/// A `SubscriptionOptionOffer` represents an offer (e.g Free Trials) associated with a Subscription
public struct SubscriptionOptionOffer: Encodable, Equatable {

    public enum OfferType: String, Codable, CaseIterable {
        case freeTrial
    }

    let type: OfferType
    let id: String
    let durationInDays: Int?
    let isUserEligible: Bool
}
