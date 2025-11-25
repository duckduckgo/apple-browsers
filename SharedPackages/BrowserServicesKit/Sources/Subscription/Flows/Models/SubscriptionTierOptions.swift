//
//  SubscriptionTierOptions.swift
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

public struct SubscriptionTierOptions: Encodable, Equatable {
    public let platform: SubscriptionPlatformName
    public let products: [Tier]

    public init(platform: SubscriptionPlatformName, products: [Tier]) {
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
        let tiersWithoutOptions = products.map { tier in
            Tier(tier: tier.tier, features: tier.features, options: [])
        }
        return SubscriptionTierOptions(platform: platform, products: tiersWithoutOptions)
    }

    // MARK: - Nested Types

    public struct Tier: Encodable, Equatable {
        public let tier: String
        public let features: [EntitlementPayload]
        public let options: [SubscriptionOptionV2]

        public init(tier: String, features: [EntitlementPayload], options: [SubscriptionOptionV2]) {
            self.tier = tier
            self.features = features
            self.options = options
        }
    }
}
