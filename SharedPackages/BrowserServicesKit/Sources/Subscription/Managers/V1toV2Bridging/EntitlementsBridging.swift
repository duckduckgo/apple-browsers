//
//  File.swift
//  BrowserServicesKit
//
//  Created by Federico Cappelli on 02/07/2025.
//

import Foundation
import Networking

public struct EntitlementsBridging {

    public static func v1EntitlementsFrom(v2Entitlements: [SubscriptionEntitlement]) -> [Entitlement] {
        v2Entitlements.map { v2Entitlement in
            switch v2Entitlement {
            case .networkProtection:
                return Entitlement(product: .networkProtection)
            case .dataBrokerProtection:
                return Entitlement(product: .dataBrokerProtection)
            case .identityTheftRestoration:
                return Entitlement(product: .identityTheftRestoration)
            case .identityTheftRestorationGlobal:
                return Entitlement(product: .identityTheftRestorationGlobal)
            case .paidAIChat:
                return Entitlement(product: .paidAIChat)
            case .unknown:
                return Entitlement(product: .unknown)
            }
        }
    }

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
