//
//  IPAddressRange+Mathematics.swift
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
import Network
import VPN

/// Mathematical operations for IP address ranges
extension IPAddressRange {

    /// Checks if this range completely contains another IP range
    public func contains(_ other: IPAddressRange) -> Bool {
        guard type(of: self.address) == type(of: other.address) else { return false }
        guard self.networkPrefixLength <= other.networkPrefixLength else { return false }

        let thisNetwork = self.maskedAddress()
        let subnetMask = self.subnetMask()
        let otherMaskedAddress = other.address.maskedWith(subnetMask)

        return thisNetwork.rawValue == otherMaskedAddress.rawValue
    }

    /// Checks if this range overlaps with another IP range
    public func overlaps(_ other: IPAddressRange) -> Bool {
        guard type(of: self.address) == type(of: other.address) else { return false }
        return self.contains(other) || other.contains(self)
    }

    /// Checks if a specific IP address falls within this range
    public func contains(_ ip: IPAddress) -> Bool {
        guard type(of: self.address) == type(of: ip) else { return false }

        let ipMasked = ip.maskedWith(self.subnetMask())
        let rangeNetwork = self.maskedAddress()

        return ipMasked.rawValue == rangeNetwork.rawValue
    }

    /// Checks if this range exists exactly in a collection of ranges
    public func hasExactMatch(in ranges: [IPAddressRange]) -> Bool {
        return ranges.contains { range in
            self.description == range.description
        }
    }
}

/// IP address masking operations
extension IPAddress {
    public func maskedWith(_ mask: IPAddress) -> IPAddress {
        let addressData = self.rawValue
        let maskData = mask.rawValue

        guard addressData.count == maskData.count else {
            fatalError("Address and mask must be the same length")
        }

        var maskedData = Data(addressData)
        for i in 0..<maskData.count {
            maskedData[i] &= maskData[i]
        }

        if addressData.count == 4 {
            return IPv4Address(maskedData)!
        } else if addressData.count == 16 {
            return IPv6Address(maskedData)!
        } else {
            fatalError("Unsupported IP address length")
        }
    }
}
