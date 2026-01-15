//
//  SubscriptionTierOptions.swift
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
import Networking

public struct SubscriptionTierOptions: Encodable, Equatable {
    public let platform: SubscriptionPlatformName
    public let products: [SubscriptionTier]

    public init(platform: SubscriptionPlatformName, products: [SubscriptionTier]) {
        self.platform = platform
        self.products = products
    }

    public static var empty: SubscriptionTierOptions {
        let platform: SubscriptionPlatformName
#if os(iOS)
        platform = .ios
#else
        platform = .macos
#endif
        return SubscriptionTierOptions(platform: platform, products: [])
    }

    public func withoutPurchaseOptions() -> Self {
        // Return tiers with features but empty options (no purchase allowed)
        let tiersWithoutOptions = products.map { subscriptionTier in
            SubscriptionTier(tier: subscriptionTier.tier, features: subscriptionTier.features, options: [])
        }
        return SubscriptionTierOptions(platform: platform, products: tiersWithoutOptions)
    }
}

public struct SubscriptionTier: Encodable, Equatable {
    public let tier: TierName
    public let features: [TierFeature]
    public let options: [SubscriptionOption]

    public init(tier: TierName, features: [TierFeature], options: [SubscriptionOption]) {
        self.tier = tier
        self.features = features
        self.options = options
    }
}

public struct TierFeature: Codable, Equatable {
    public let product: SubscriptionEntitlement
    public let name: TierName
}

public enum TierName: String, Codable {
    case plus
    case pro

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        // Default to .plus if rawValue doesn't match any case
        self = TierName(rawValue: rawValue) ?? .plus
    }
}
