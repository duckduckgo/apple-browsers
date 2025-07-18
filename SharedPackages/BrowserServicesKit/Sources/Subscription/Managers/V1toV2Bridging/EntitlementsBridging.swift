//
//  EntitlementsBridging.swift
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

public struct EntitlementsBridging {

    public static func v2EntitlementsFrom(v1Entitlements: [Entitlement]) -> [SubscriptionEntitlement] {
        v1Entitlements.map { v1Entitlement in
            switch v1Entitlement.product {
            case .networkProtection:
                return .networkProtection
            case .dataBrokerProtection:
                return .dataBrokerProtection
            case .identityTheftRestoration:
                return .identityTheftRestoration
            case .identityTheftRestorationGlobal:
                return .identityTheftRestorationGlobal
            case .paidAIChat:
                return .paidAIChat
            case .unknown:
                return .unknown
            }
        }
    }
}

extension Entitlement.ProductName {

    public var subscriptionEntitlement: SubscriptionEntitlement {
        switch self {
        case .networkProtection:
            return .networkProtection
        case .dataBrokerProtection:
            return .dataBrokerProtection
        case .identityTheftRestoration:
            return .identityTheftRestoration
        case .identityTheftRestorationGlobal:
            return .identityTheftRestorationGlobal
        case .paidAIChat:
            return .paidAIChat
        case .unknown:
            return .unknown
        }
    }
}

extension SubscriptionEntitlement {

    public var product: Entitlement.ProductName {
        switch self {
        case .networkProtection:
            return .networkProtection
        case .dataBrokerProtection:
            return .dataBrokerProtection
        case .identityTheftRestoration:
            return .identityTheftRestoration
        case .identityTheftRestorationGlobal:
            return .identityTheftRestorationGlobal
        case .paidAIChat:
            return .paidAIChat
        case .unknown:
            return .unknown
        }
    }
}
