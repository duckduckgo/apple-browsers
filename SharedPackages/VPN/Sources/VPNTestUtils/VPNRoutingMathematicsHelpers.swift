//
//  VPNRoutingMathematicsHelpers.swift
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

/// Mathematical validation helpers for VPN routing ranges
public final class VPNRoutingMathematicsHelpers {

    /// Finds mathematical conflicts between included and excluded routing ranges
    public static func findActualRangeConflicts(
        included: [IPAddressRange],
        excluded: [IPAddressRange]
    ) -> [(included: IPAddressRange, excluded: IPAddressRange)] {
        var conflicts: [(included: IPAddressRange, excluded: IPAddressRange)] = []

        for includedRange in included {
            for excludedRange in excluded where includedRange.overlaps(excludedRange) {
                conflicts.append((included: includedRange, excluded: excludedRange))
            }
        }

        return conflicts
    }

    /// Validates that an IP address falls within exactly one of the provided range categories
    public static func classifyIPAddress(
        _ address: IPAddress,
        publicRanges: [IPAddressRange],
        privateRanges: [IPAddressRange],
        systemRanges: [IPAddressRange]
    ) -> (category: String, range: IPAddressRange)? {

        if let systemRange = systemRanges.first(where: { range in range.contains(address) }) {
            return ("system", systemRange)
        }

        if let privateRange = privateRanges.first(where: { range in range.contains(address) }) {
            return ("private", privateRange)
        }

        if let publicRange = publicRanges.first(where: { range in range.contains(address) }) {
            return ("public", publicRange)
        }

        return nil
    }

    /// Validates comprehensive internet coverage by checking for gaps in public ranges
    public static func findPublicInternetGaps(
        publicRanges: [IPAddressRange],
        excludingSystemRanges systemRanges: [IPAddressRange],
        excludingPrivateRanges privateRanges: [IPAddressRange]
    ) -> [String] {
        let testPublicAddresses = [
            "1.1.1.1",        // Cloudflare
            "8.8.8.8",        // Google  
            "208.67.222.222", // OpenDNS
            "4.4.4.4",        // Level3
            "199.85.126.10",  // Norton
            "75.75.75.75",    // Comcast
            "156.154.70.1",   // Neustar
            "9.9.9.9",        // Quad9
            "64.6.64.6",      // Verisign
            "77.88.8.8"       // Yandex
        ]

        var gaps: [String] = []

        for addressString in testPublicAddresses {
            guard let address = IPv4Address(addressString) else { continue }

            let isSystemAddress = systemRanges.contains { range in range.contains(address) }
            let isPrivateAddress = privateRanges.contains { range in range.contains(address) }

            if isSystemAddress || isPrivateAddress {
                continue
            }

            let isCoveredByPublic = publicRanges.contains { range in range.contains(address) }

            if !isCoveredByPublic {
                gaps.append(addressString)
            }
        }

        return gaps
    }
}
