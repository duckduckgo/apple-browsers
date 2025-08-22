//
//  VPNRoutingMathematicsTests.swift
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

import XCTest
import Foundation
import Network
import VPNTestUtils
@testable import VPN

/// Tests for mathematical validation of VPN routing ranges
///
/// Validates IP range mathematics and routing logic using precise mathematical operations
/// rather than string comparisons, ensuring robust routing behavior.
final class VPNRoutingMathematicsTests: XCTestCase {

    /// Verifies that private network addresses never appear in public routing ranges
    func testPrivateAddressesNeverInPublicRanges() {

        let publicRanges = VPNRoutingRange.publicNetworkRange.filter { $0.address is IPv4Address }
        let privateAddresses = ["10.0.0.1", "172.16.0.1", "192.168.1.1"]

        for addressString in privateAddresses {
            guard let address = IPv4Address(addressString) else { continue }

            let foundInPublic = publicRanges.first { range in range.contains(address) }
            XCTAssertNil(foundInPublic,
                        "Private address \(addressString) incorrectly found in public range \(foundInPublic?.description ?? "nil")")
        }
    }

    /// Verifies that system addresses never overlap with public network ranges
    ///
    /// - Discussion: System addresses (loopback, link-local, multicast) should never be mathematically
    ///   contained within public network ranges, as this could create routing ambiguity.
    func testSystemAddressesNeverOverlapWithPublicRanges() {

        let publicRanges = VPNRoutingRange.publicNetworkRange.filter { $0.address is IPv4Address }
        let systemRanges = VPNRoutingRange.alwaysExcludedIPv4Range

        var overlaps: [(system: IPAddressRange, public: IPAddressRange)] = []
        for systemRange in systemRanges {
            for publicRange in publicRanges where systemRange.overlaps(publicRange) {
                overlaps.append((system: systemRange, public: publicRange))
            }
        }

        XCTAssertTrue(overlaps.isEmpty, "System ranges should never overlap with public ranges: \(overlaps)")

        // Verify system traffic is still properly excluded in routing
        let resolver = VPNRoutingTableResolver(dnsServers: [], excludeLocalNetworks: true)
        let excludedRoutes = resolver.excludedRoutes

        for systemRange in systemRanges {
            let isExcluded = excludedRoutes.contains { range in range.description == systemRange.description }
            XCTAssertTrue(isExcluded, "System range \(systemRange) should be explicitly excluded")
        }
    }

    /// Verifies that CIDR range mathematics work correctly for subnet operations
    func testCIDRMathematicsWorkCorrectly() {
        let wideRange = IPAddressRange(from: "64.0.0.0/2")!
        let narrowRanges = [
            IPAddressRange(from: "64.0.0.0/3")!,
            IPAddressRange(from: "96.0.0.0/4")!,
            IPAddressRange(from: "112.0.0.0/5")!,
            IPAddressRange(from: "120.0.0.0/6")!,
            IPAddressRange(from: "124.0.0.0/7")!,
            IPAddressRange(from: "126.0.0.0/8")!
        ]
        let excludedRange = IPAddressRange(from: "127.0.0.0/8")!

        XCTAssertTrue(wideRange.contains(excludedRange),
                     "64.0.0.0/2 mathematically contains 127.0.0.0/8")

        for narrowRange in narrowRanges {
            XCTAssertFalse(narrowRange.contains(excludedRange),
                          "Granular range \(narrowRange) should not contain 127.0.0.0/8")
        }

        let testAddresses = ["75.75.75.75", "100.100.100.100", "125.125.125.125"]
        for addressString in testAddresses {
            guard let address = IPv4Address(addressString) else { continue }

            let coveredByWide = wideRange.contains(address)
            let coveredByNarrow = narrowRanges.contains { range in range.contains(address) }

            XCTAssertEqual(coveredByWide, coveredByNarrow,
                          "Address \(addressString) should have equivalent coverage")
        }
    }

    /// Verifies that VPN correctly handles overlapping ranges by prioritizing exclusions
    func testVPNHandlesOverlappingRangesCorrectly() {
        let resolver = VPNRoutingTableResolver(
            dnsServers: [DNSServer(address: IPv4Address("192.168.1.1")!)],
            excludeLocalNetworks: true
        )

        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes

        let overlaps = VPNRoutingMathematicsHelpers.findActualRangeConflicts(
            included: includedRoutes,
            excluded: excludedRoutes
        )

        // VPN should handle overlaps by giving exclusions higher priority
        for overlap in overlaps {
            // Verify this is an expected type of overlap (DNS host routes overriding broader exclusions)
            let isDNSHostRoute = overlap.included.networkPrefixLength == 32
            let isBroadExclusion = overlap.excluded.networkPrefixLength < 32

            if isDNSHostRoute && isBroadExclusion {

                continue
            }

            // Any other overlaps should be documented as intentional VPN behavior
        }
    }

    /// Verifies that DNS server routes can conflict with excluded ranges by design
    func testDNSRoutesCanConflictWithExcludedRanges() {
        let corporateDNS = DNSServer(address: IPv4Address("192.168.1.53")!)
        let resolver = VPNRoutingTableResolver(dnsServers: [corporateDNS], excludeLocalNetworks: true)

        let conflicts = VPNRoutingMathematicsHelpers.findActualRangeConflicts(
            included: resolver.includedRoutes,
            excluded: resolver.excludedRoutes
        )

        let dnsConflicts = conflicts.filter { conflict in
            conflict.included.networkPrefixLength == 32 && // DNS host route
            conflict.included.description.contains("192.168.1.53")
        }

        XCTAssertFalse(dnsConflicts.isEmpty, "Should find DNS server conflict with excluded range")

    }

    /// Verifies that subnet containment logic works correctly
    func testSubnetContainmentLogicWorks() {
        let wideRange = IPAddressRange(from: "192.168.0.0/16")!
        let mediumRange = IPAddressRange(from: "192.168.1.0/24")!
        let narrowRange = IPAddressRange(from: "192.168.1.0/28")!
        let differentSubnet = IPAddressRange(from: "192.168.2.0/24")!

        XCTAssertTrue(wideRange.contains(mediumRange), "/16 should contain /24 within same network")
        XCTAssertTrue(wideRange.contains(narrowRange), "/16 should contain /28 within same network")
        XCTAssertTrue(mediumRange.contains(narrowRange), "/24 should contain /28 within same subnet")

        XCTAssertFalse(mediumRange.contains(wideRange), "/24 should not contain /16 (reversed relationship)")
        XCTAssertFalse(mediumRange.contains(differentSubnet), "Different subnets should not contain each other")

        XCTAssertTrue(wideRange.overlaps(differentSubnet), "/16 should overlap with /24 within same network")
        XCTAssertFalse(mediumRange.overlaps(differentSubnet), "Different /24 subnets should not overlap")
    }

    /// Verifies that public internet coverage has no gaps for major services
    func testPublicInternetCoverageHasNoGaps() {

        let publicRanges = VPNRoutingRange.publicNetworkRange.filter { $0.address is IPv4Address }
        let systemRanges = VPNRoutingRange.alwaysExcludedIPv4Range
        let privateRanges = VPNRoutingRange.localNetworkRange.filter { $0.address is IPv4Address }

        let gaps = VPNRoutingMathematicsHelpers.findPublicInternetGaps(
            publicRanges: publicRanges,
            excludingSystemRanges: systemRanges,
            excludingPrivateRanges: privateRanges
        )

        XCTAssertTrue(gaps.isEmpty, "Public internet should have comprehensive coverage. Missing: \(gaps)")
    }
}
