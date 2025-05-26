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

public struct SubscriptionOptions: Encodable, Equatable {
    let platform: SubscriptionPlatformName
    let options: [SubscriptionOption]
    let features: [SubscriptionFeature]

    public static var empty: SubscriptionOptions {
        let features = [SubscriptionFeature(name: .networkProtection),
                        SubscriptionFeature(name: .dataBrokerProtection),
                        SubscriptionFeature(name: .identityTheftRestoration)]
        let platform: SubscriptionPlatformName
#if os(iOS)
        platform = .ios
#else
        platform = .macos
#endif
        return SubscriptionOptions(platform: platform, options: [], features: features)
    }

    public func withoutPurchaseOptions() -> Self {
        SubscriptionOptions(platform: platform, options: [], features: features)
    }
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

public struct SubscriptionFeature: Encodable, Equatable {
    let name: Entitlement.ProductName
}
