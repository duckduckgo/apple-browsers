//
//  VPNRoutingRangeTests.swift
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
import XCTest
import Network
import VPNTestUtils
@testable import VPN

final class VPNRoutingRangeTests: XCTestCase {

    // MARK: - System Protection Tests

    /// Verifies that critical system traffic never goes through the VPN tunnel
    func testCriticalSystemTrafficStaysLocal() {

        let ipv4Excluded = VPNRoutingRange.alwaysExcludedIPv4Range
        let ipv6Excluded = VPNRoutingRange.alwaysExcludedIPv6Range

        let expectedIPv4Ranges = [
            IPAddressRange(from: "127.0.0.0/8")!,      // Loopback
            IPAddressRange(from: "169.254.0.0/16")!,   // Link-local
            IPAddressRange(from: "224.0.0.0/4")!,      // Multicast
            IPAddressRange(from: "240.0.0.0/4")!       // Experimental
        ]

        let expectedIPv6Ranges = [
            IPAddressRange(from: "::1/128")!,
            IPAddressRange(from: "fe80::/10")!,
            IPAddressRange(from: "ff00::/8")!
        ]

        for expectedRange in expectedIPv4Ranges {
            XCTAssertTrue(expectedRange.hasExactMatch(in: ipv4Excluded),
                         "IPv4 system range \(expectedRange) should be excluded")
        }

        for expectedRange in expectedIPv6Ranges {
            XCTAssertTrue(expectedRange.hasExactMatch(in: ipv6Excluded),
                         "IPv6 system range \(expectedRange) should be excluded")
        }
    }

    // MARK: - Local Network Range Tests

    /// Verifies that VPN correctly identifies all standard private network ranges (10.x, 172.16-31.x, 192.168.x)
    func testPrivateNetworkRangesAreComplete() {

        let localNetworks = VPNRoutingRange.localNetworkRange
        let localStrings = localNetworks.map { $0.description }

        XCTAssertTrue(localStrings.contains("10.0.0.0/8"),
                     "Should include RFC 1918 range 10.0.0.0/8")
        XCTAssertTrue(localStrings.contains("172.16.0.0/12"),
                     "Should include RFC 1918 range 172.16.0.0/12")
        XCTAssertTrue(localStrings.contains("192.168.0.0/16"),
                     "Should include RFC 1918 range 192.168.0.0/16")

    }

    /// Verifies that VPN tunnels can use 10.x.x.x addresses without routing conflicts
    ///
    /// - Note: VPN tunnels commonly use 10.x.x.x addresses, so this range is excluded from
    ///   local network blocking to prevent the VPN from blocking itself.
    func testVPNTunnelAddressCompatibility() {

        let localNetworksWithoutDNS = VPNRoutingRange.localNetworkRangeWithoutDNS
        let localStrings = localNetworksWithoutDNS.map { $0.description }

        XCTAssertFalse(localStrings.contains("10.0.0.0/8"),
                      "localNetworkRangeWithoutDNS should NOT include 10.0.0.0/8")

        // But should include other RFC 1918 ranges
        XCTAssertTrue(localStrings.contains("172.16.0.0/12"),
                     "Should still include 172.16.0.0/12 in localNetworkRangeWithoutDNS")
        XCTAssertTrue(localStrings.contains("192.168.0.0/16"),
                     "Should still include 192.168.0.0/16 in localNetworkRangeWithoutDNS")

    }

    /// Verifies that IPv6 ULA is handled like IPv4 RFC 1918 private networks
    func testIPv6ULAHandledLikeRFC1918() {
        // Verify fc00::/7 is NOT in alwaysExcludedIPv6Range
        let alwaysExcluded = VPNRoutingRange.alwaysExcludedIPv6Range
        let hasULA = alwaysExcluded.contains { $0.description.hasPrefix("fc00::/") }
        XCTAssertFalse(hasULA, "ULA should not be in always excluded ranges")

        // Verify fc00::/7 IS in localIPv6NetworkRange
        let localIPv6 = VPNRoutingRange.localIPv6NetworkRange
        XCTAssertEqual(localIPv6.count, 1, "Should have exactly one IPv6 local range")
        XCTAssertTrue(localIPv6[0].description.contains("fc00::/7"), "Should include ULA range")

        // Verify the approach: ::/0 is the full IPv6 routing range (contains ULA), but localIPv6NetworkRange
        // will be conditionally excluded, relying on Apple's documented behavior that
        // excluded routes take precedence over included routes
        let fullIPv6 = VPNRoutingRange.fullIPv6RoutingRange
        XCTAssertEqual(fullIPv6.networkPrefixLength, 0, "Full IPv6 routing range should be ::/0 for all IPv6 addresses")
    }

    /// Verifies that fullIPv6RoutingRange is exactly ::/0 (all IPv6 addresses)
    func testFullIPv6RoutingRangeIsAllAddresses() {
        let fullIPv6 = VPNRoutingRange.fullIPv6RoutingRange

        XCTAssertEqual(fullIPv6.description, "::/0", "Full IPv6 routing range should be exactly ::/0")
        XCTAssertEqual(fullIPv6.networkPrefixLength, 0, "Prefix length should be 0")
        XCTAssertTrue(fullIPv6.address is IPv6Address, "Address should be IPv6")
    }

    /// Verifies that 10.0.0.0/8 is in localNetworkRange but not in localNetworkRangeWithoutDNS
    func testTenDotZeroOnlyInFullLocalNetworkRange() {
        let fullLocal = VPNRoutingRange.localNetworkRange
        let localWithoutDNS = VPNRoutingRange.localNetworkRangeWithoutDNS

        let fullLocalStrings = fullLocal.map { $0.description }
        let withoutDNSStrings = localWithoutDNS.map { $0.description }

        XCTAssertTrue(fullLocalStrings.contains("10.0.0.0/8"),
                     "10.0.0.0/8 should be in localNetworkRange")
        XCTAssertFalse(withoutDNSStrings.contains("10.0.0.0/8"),
                      "10.0.0.0/8 should NOT be in localNetworkRangeWithoutDNS")
    }

    // MARK: - Public Network Range Tests

    /// Verifies that VPN routes all major public internet traffic through the tunnel for comprehensive protection
    func testPublicInternetTrafficIsFullyCovered() {

        let publicNetworks = VPNRoutingRange.publicIPv4NetworkRange + [VPNRoutingRange.fullIPv6RoutingRange]

        let expectedIPv4Ranges = [
            IPAddressRange(from: "1.0.0.0/8")!,
            IPAddressRange(from: "8.0.0.0/7")!,
            IPAddressRange(from: "64.0.0.0/3")!,
            IPAddressRange(from: "128.0.0.0/3")!,
        ]

        let expectedIPv6Ranges = [
            IPAddressRange(from: "::/0")!,
        ]

        for expectedRange in expectedIPv4Ranges + expectedIPv6Ranges {
            XCTAssertTrue(expectedRange.hasExactMatch(in: publicNetworks),
                         "Major public range \(expectedRange) should be covered")
        }

    }

    // MARK: - IP Range Parsing and Validation Tests

    /// Verifies that all static IP range definitions are valid and don't contain typos that could break routing
    func testIPRangeDefinitionsAreValid() {
        let allRanges = [
            ("alwaysExcludedIPv4", VPNRoutingRange.alwaysExcludedIPv4Range),
            ("alwaysExcludedIPv6", VPNRoutingRange.alwaysExcludedIPv6Range),
            ("localNetwork", VPNRoutingRange.localNetworkRange),
            ("localNetworkWithoutDNS", VPNRoutingRange.localNetworkRangeWithoutDNS),
            ("publicIPv4Network", VPNRoutingRange.publicIPv4NetworkRange),
            ("fullIPv6Routing", [VPNRoutingRange.fullIPv6RoutingRange])
        ]

        for (rangeName, ranges) in allRanges {
            for (index, range) in ranges.enumerated() {
                let rangeString = range.description

                XCTAssertNotNil(IPAddressRange(from: rangeString),
                               "Range \(rangeString) in \(rangeName)[\(index)] should be valid")
            }
        }
    }

    /// Verifies that malformed IP address configurations are handled gracefully without crashing VPN
    func testMalformedConfigurationsAreHandledGracefully() {
        let invalidRanges = [
            "256.256.256.256/8",   // Invalid IPv4 address
            "not.an.ip/24",        // Not an IP address
            "",                    // Empty string
            "192.168.1.1/-1"       // Negative prefix
        ]

        for invalidRange in invalidRanges {
            let result = IPAddressRange(from: invalidRange)

            XCTAssertNil(result, "Invalid range '\(invalidRange)' should return nil")
        }

    }

    // MARK: - Range Logic and Consistency Tests

    /// Verifies that no IP ranges overlap between different routing categories which would cause routing conflicts
    func testRoutingLogicIsConsistent() {

        let alwaysExcluded = VPNRoutingRange.alwaysExcludedIPv4Range
        let localNetwork = VPNRoutingRange.localNetworkRange
        let localWithoutDNS = VPNRoutingRange.localNetworkRangeWithoutDNS

        let alwaysExcludedAndLocal = findOverlappingRanges(alwaysExcluded, localNetwork)
        let alwaysExcludedAndLocalWithoutDNS = findOverlappingRanges(alwaysExcluded, localWithoutDNS)

        XCTAssertTrue(alwaysExcludedAndLocal.isEmpty,
                     "Found overlapping ranges between always excluded and local: \(alwaysExcludedAndLocal)")
        XCTAssertTrue(alwaysExcludedAndLocalWithoutDNS.isEmpty,
                     "Found overlapping ranges between always excluded and local (without DNS): \(alwaysExcludedAndLocalWithoutDNS)")
    }

    /// Verifies that DNS-compatible local ranges are properly contained within full local ranges
    func testDNSCompatibleRangesAreProperSubset() {

        let localNetwork = VPNRoutingRange.localNetworkRange
        let localWithoutDNS = VPNRoutingRange.localNetworkRangeWithoutDNS

        for rangeWithoutDNS in localWithoutDNS {
            let isContained = localNetwork.contains { localRange in
                localRange.contains(rangeWithoutDNS) || localRange == rangeWithoutDNS
            }
            XCTAssertTrue(isContained,
                         "Range \(rangeWithoutDNS) should be contained within localNetworkRange")
        }
    }

    // MARK: - Helper Methods

    private func findOverlappingRanges(_ ranges1: [IPAddressRange], _ ranges2: [IPAddressRange]) -> [(IPAddressRange, IPAddressRange)] {
        var overlaps: [(IPAddressRange, IPAddressRange)] = []

        for range1 in ranges1 {
            for range2 in ranges2 where range1.overlaps(range2) {
                overlaps.append((range1, range2))
            }
        }

        return overlaps
    }
}
