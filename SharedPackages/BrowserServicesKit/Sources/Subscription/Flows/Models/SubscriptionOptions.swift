//
//  SubscriptionOptions.swift
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

public struct SubscriptionOptions: Encodable, Equatable {
    struct Feature: Encodable, Equatable {
        let name: SubscriptionEntitlement
    }

    let platform: SubscriptionPlatformName
    let options: [SubscriptionOption]
    /// The available features in the subscription based on the country and feature flags. Not based on user entitlements
    let features: [SubscriptionOptions.Feature]

    public init(platform: SubscriptionPlatformName, options: [SubscriptionOption], availableEntitlements: [SubscriptionEntitlement]) {
        self.platform = platform
        self.options = options
        self.features = availableEntitlements.map({ entitlement in
            Feature(name: entitlement)
        })
    }

    public static var empty: SubscriptionOptions {
        let features: [SubscriptionEntitlement] = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration, .paidAIChat]
        let platform: SubscriptionPlatformName
#if os(iOS)
        platform = .ios
#else
        platform = .macos
#endif
        return SubscriptionOptions(platform: platform, options: [], availableEntitlements: features)
    }

    public func withoutPurchaseOptions() -> Self {
        SubscriptionOptions(platform: platform, options: [], availableEntitlements: features.map({ feature in
            feature.name
        }))
    }
}

public enum SubscriptionPlatformName: String, Encodable {
    case ios
    case macos
    case stripe
}

public struct SubscriptionOption: Encodable, Equatable {
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
