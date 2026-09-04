//
//  EntitlementStatus.swift
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

/// Contains the enabled status of all subscription entitlements.
/// Use this when you need to check multiple entitlements to avoid multiple token fetches.
public struct EntitlementStatus: Equatable, CustomDebugStringConvertible {
    public let networkProtection: Bool
    public let dataBrokerProtection: Bool
    public let identityTheftRestoration: Bool
    public let identityTheftRestorationGlobal: Bool
    public let paidAIChat: Bool

    public init(networkProtection: Bool,
                dataBrokerProtection: Bool,
                identityTheftRestoration: Bool,
                identityTheftRestorationGlobal: Bool,
                paidAIChat: Bool) {
        self.networkProtection = networkProtection
        self.dataBrokerProtection = dataBrokerProtection
        self.identityTheftRestoration = identityTheftRestoration
        self.identityTheftRestorationGlobal = identityTheftRestorationGlobal
        self.paidAIChat = paidAIChat
    }

    /// Creates an EntitlementStatus from a list of enabled entitlements
    public init(enabledEntitlements: [SubscriptionEntitlement]) {
        self.networkProtection = enabledEntitlements.contains(.networkProtection)
        self.dataBrokerProtection = enabledEntitlements.contains(.dataBrokerProtection)
        self.identityTheftRestoration = enabledEntitlements.contains(.identityTheftRestoration)
        self.identityTheftRestorationGlobal = enabledEntitlements.contains(.identityTheftRestorationGlobal)
        self.paidAIChat = enabledEntitlements.contains(.paidAIChat)
    }

    /// Returns an empty status with all entitlements disabled
    public static var empty: EntitlementStatus {
        EntitlementStatus(networkProtection: false,
                          dataBrokerProtection: false,
                          identityTheftRestoration: false,
                          identityTheftRestorationGlobal: false,
                          paidAIChat: false)
    }

    /// Checks if a specific entitlement is enabled
    public func isEnabled(_ entitlement: SubscriptionEntitlement) -> Bool {
        switch entitlement {
        case .networkProtection:
            return networkProtection
        case .dataBrokerProtection:
            return dataBrokerProtection
        case .identityTheftRestoration:
            return identityTheftRestoration
        case .identityTheftRestorationGlobal:
            return identityTheftRestorationGlobal
        case .paidAIChat:
            return paidAIChat
        case .unknown:
            return false
        }
    }

    public var debugDescription: String {
        let status: (Bool) -> String = { $0 ? "Enabled" : "Disabled" }
        return """
            EntitlementStatus:
            - VPN: \(status(networkProtection))
            - PIR: \(status(dataBrokerProtection))
            - ITR: \(status(identityTheftRestoration))
            - ITR-Global: \(status(identityTheftRestorationGlobal))
            - AI Chat: \(status(paidAIChat))
            """
    }
}
