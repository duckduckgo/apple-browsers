//
//  NetworkProtectionNetworkPathInfo.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

/// A privacy-safe, structured view of an `NWPath`.
///
/// Holds the same anonymized properties as `NWPath.anonymousDescription` (no addresses), but as discrete
/// fields so support metadata can be machine-readable instead of a single formatted string.
public struct NetworkProtectionNetworkPathInfo: Codable, Equatable, Sendable {
    public let status: String
    public let unsatisfiedReason: String?
    public let mainInterfaceType: String?
    public let utunInterfaceCount: Int
    public let ipsecInterfaceCount: Int
    public let dnsInterfaceCount: Int
    public let unidentifiedInterfaceCount: Int
    public let isConstrained: Bool
    public let isExpensive: Bool

    public init(status: String,
                unsatisfiedReason: String?,
                mainInterfaceType: String?,
                utunInterfaceCount: Int,
                ipsecInterfaceCount: Int,
                dnsInterfaceCount: Int,
                unidentifiedInterfaceCount: Int,
                isConstrained: Bool,
                isExpensive: Bool) {
        self.status = status
        self.unsatisfiedReason = unsatisfiedReason
        self.mainInterfaceType = mainInterfaceType
        self.utunInterfaceCount = utunInterfaceCount
        self.ipsecInterfaceCount = ipsecInterfaceCount
        self.dnsInterfaceCount = dnsInterfaceCount
        self.unidentifiedInterfaceCount = unidentifiedInterfaceCount
        self.isConstrained = isConstrained
        self.isExpensive = isExpensive
    }
}
