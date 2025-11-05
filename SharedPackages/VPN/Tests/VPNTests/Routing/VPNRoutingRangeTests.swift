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
            IPAddressRange(from: "ff00::/8")!,
            IPAddressRange(from: "fc00::/7")!
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

    // MARK: - Public Network Range Tests

    /// Verifies that VPN routes all major public internet traffic through the tunnel for comprehensive protection
    func testPublicInternetTrafficIsFullyCovered() {

        let publicNetworks = VPNRoutingRange.publicNetworkRange

        let expectedPublicRanges = [
            IPAddressRange(from: "1.0.0.0/8")!,
            IPAddressRange(from: "8.0.0.0/7")!,
            IPAddressRange(from: "64.0.0.0/3")!,
            IPAddressRange(from: "128.0.0.0/3")!,
            IPAddressRange(from: "::/0")!
        ]

        for expectedRange in expectedPublicRanges {
            XCTAssertTrue(expectedRange.hasExactMatch(in: publicNetworks),
                         "Major public range \(expectedRange) should be covered")
        }

    }

    /// Verifies clear separation between public internet and private network traffic routing
    func testPublicAndPrivateTrafficAreSeparated() {

        let publicNetworks = VPNRoutingRange.publicNetworkRange

        let privateRanges = [
            IPAddressRange(from: "10.0.0.0/8")!,
            IPAddressRange(from: "172.16.0.0/12")!,
            IPAddressRange(from: "192.168.0.0/16")!
        ]

        for privateRange in privateRanges {
            XCTAssertFalse(privateRange.hasExactMatch(in: publicNetworks),
                          "Private range \(privateRange) should NOT be in public ranges")
        }

    }

    /// Verifies clean separation between internet-routable and system-reserved address ranges
    func testInternetTrafficDoesNotIncludeSystemRanges() {

        let publicNetworks = VPNRoutingRange.publicNetworkRange

        let systemRanges = [
            IPAddressRange(from: "127.0.0.0/8")!,      // Loopback
            IPAddressRange(from: "169.254.0.0/16")!,   // Link-local
            IPAddressRange(from: "224.0.0.0/4")!,      // Multicast
            IPAddressRange(from: "240.0.0.0/4")!       // Experimental
        ]

        for systemRange in systemRanges {
            let foundInPublic = publicNetworks.contains { publicRange in
                publicRange == systemRange || publicRange.contains(systemRange) || systemRange.contains(publicRange)
            }
            XCTAssertFalse(foundInPublic, "System range \(systemRange) should NOT be in public ranges")
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
            ("publicNetwork", VPNRoutingRange.publicNetworkRange)
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

    /// Verifies that VPN provides comprehensive global internet access by covering all major address blocks
    func testGlobalInternetAccessIsComprehensive() {

        let publicNetworks = VPNRoutingRange.publicNetworkRange

        let expectedMajorBlocks = [
            "1.0.0.0/8",      // APNIC
            "8.0.0.0/7",      // Various (Level 3, Google, etc.)
            "64.0.0.0/3",     // Part of former 64.0.0.0/2 (64-95)
            "96.0.0.0/4",     // Part of former 64.0.0.0/2 (96-111)
            "128.0.0.0/3",    // Various global
            "::/0"            // IPv6 default
        ]

        for expectedBlock in expectedMajorBlocks {
            guard let expectedRange = IPAddressRange(from: expectedBlock) else {
                XCTFail("Invalid test range: \(expectedBlock)")
                continue
            }

            let isCovered = publicNetworks.contains { publicRange in
                publicRange == expectedRange || publicRange.contains(expectedRange)
            }
            XCTAssertTrue(isCovered, "Public network range should contain \(expectedBlock)")
        }

    }

    // MARK: - Performance Tests

}
