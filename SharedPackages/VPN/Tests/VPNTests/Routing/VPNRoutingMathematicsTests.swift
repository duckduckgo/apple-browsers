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

        let publicRanges = VPNRoutingRange.publicIPv4NetworkRange
        let privateAddresses = ["10.0.0.1", "172.16.0.1", "192.168.1.1"]

        for addressString in privateAddresses {
            guard let address = IPv4Address(addressString) else { continue }

            let foundInPublic = publicRanges.first { range in range.contains(address) }
            XCTAssertNil(foundInPublic,
                        "Private address \(addressString) incorrectly found in public range \(foundInPublic?.description ?? "nil")")
        }
    }

    /// Verifies that system addresses never overlap with public network ranges
    func testSystemAddressesNeverOverlapWithPublicRanges() {
        let publicRanges = VPNRoutingRange.publicIPv4NetworkRange
        let systemRanges = VPNRoutingRange.alwaysExcludedIPv4Range

        var overlaps: [(system: IPAddressRange, public: IPAddressRange)] = []
        for systemRange in systemRanges {
            for publicRange in publicRanges where systemRange.overlaps(publicRange) {
                overlaps.append((system: systemRange, public: publicRange))
            }
        }

        XCTAssertTrue(overlaps.isEmpty, "System ranges should never overlap with public ranges: \(overlaps)")
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

        let publicRanges = VPNRoutingRange.publicIPv4NetworkRange
        let systemRanges = VPNRoutingRange.alwaysExcludedIPv4Range
        let privateRanges = VPNRoutingRange.localNetworkRange.filter { $0.address is IPv4Address }

        let gaps = VPNRoutingMathematicsHelpers.findPublicInternetGaps(
            publicRanges: publicRanges,
            excludingSystemRanges: systemRanges,
            excludingPrivateRanges: privateRanges
        )

        XCTAssertTrue(gaps.isEmpty, "Public internet should have comprehensive coverage. Missing: \(gaps)")
    }

    /// Verifies IPv6 always-excluded ranges are correctly defined
    func testIPv6AlwaysExcludedRangesAreCorrect() {
        let systemIPv6 = VPNRoutingRange.alwaysExcludedIPv6Range

        XCTAssertEqual(systemIPv6.count, 3, "Should have exactly 3 always-excluded IPv6 ranges")

        let systemDescriptions = Set(systemIPv6.map { $0.description })
        XCTAssertTrue(systemDescriptions.contains("::1/128"), "Should always exclude loopback")
        XCTAssertTrue(systemDescriptions.contains("fe80::/10"), "Should always exclude link-local")
        XCTAssertTrue(systemDescriptions.contains("ff00::/8"), "Should always exclude multicast")
    }

    /// Verifies IPv6 conditional exclusions (ULA) are correctly defined
    func testIPv6ConditionalExclusionsAreCorrect() {
        let localIPv6 = VPNRoutingRange.localIPv6NetworkRange

        XCTAssertEqual(localIPv6.count, 1, "Should have exactly 1 conditional IPv6 range (ULA)")
        XCTAssertTrue(localIPv6[0].description.contains("fc00::/7"), "Should conditionally exclude ULA")
    }

    /// Verifies no overlap between IPv6 always-excluded and conditionally-excluded ranges
    func testIPv6AlwaysExcludedAndConditionalRangesDoNotOverlap() {
        let systemIPv6 = VPNRoutingRange.alwaysExcludedIPv6Range
        let localIPv6 = VPNRoutingRange.localIPv6NetworkRange

        for alwaysExcluded in systemIPv6 {
            for local in localIPv6 {
                XCTAssertFalse(alwaysExcluded.overlaps(local),
                              "Always-excluded \(alwaysExcluded) should not overlap with conditional \(local)")
            }
        }
    }

    /// Verifies that fullIPv6RoutingRange covers all IPv6 addresses including well-known public addresses
    func testFullIPv6RoutingRangeCoversPublicAddresses() {
        let fullIPv6 = VPNRoutingRange.fullIPv6RoutingRange

        XCTAssertEqual(fullIPv6.networkPrefixLength, 0, "Full IPv6 routing range should be /0 (all addresses)")
        XCTAssertTrue(fullIPv6.address is IPv6Address, "Full IPv6 routing range should be IPv6")

        let testPublicIPv6Addresses = [
            "2606:4700:4700::1111",  // Cloudflare
            "2001:4860:4860::8888",  // Google
            "2620:fe::fe",           // Quad9
        ]

        for addressString in testPublicIPv6Addresses {
            guard let address = IPv6Address(addressString) else {
                XCTFail("Invalid test address: \(addressString)")
                continue
            }

            XCTAssertTrue(fullIPv6.contains(address), "Public IPv6 address \(addressString) should be covered by ::/0")
        }
    }

    /// Verifies that IPv6 ULA addresses are correctly categorized as local (conditional exclusion)
    func testIPv6ULAAddressesCategorizedAsLocal() {
        let localIPv6 = VPNRoutingRange.localIPv6NetworkRange
        let systemIPv6 = VPNRoutingRange.alwaysExcludedIPv6Range

        let ulaAddresses = [
            IPv6Address("fc00::1")!,
            IPv6Address("fd00::1")!,
            IPv6Address("fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff")!
        ]

        for ulaAddress in ulaAddresses {
            XCTAssertFalse(systemIPv6.contains { $0.contains(ulaAddress) },
                          "ULA \(ulaAddress) should NOT be in always-excluded system ranges")
            XCTAssertTrue(localIPv6.contains { $0.contains(ulaAddress) },
                         "ULA \(ulaAddress) should be in local ranges for conditional exclusion")
        }
    }

    /// Verifies that IPv6 link-local addresses are correctly categorized as system (always excluded)
    func testIPv6LinkLocalAddressesCategorizedAsSystem() {
        let localIPv6 = VPNRoutingRange.localIPv6NetworkRange
        let systemIPv6 = VPNRoutingRange.alwaysExcludedIPv6Range

        let linkLocalAddresses = [
            IPv6Address("fe80::1")!,
            IPv6Address("fe80::dead:beef")!,
            IPv6Address("febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff")!
        ]

        for linkLocalAddress in linkLocalAddresses {
            XCTAssertFalse(localIPv6.contains { $0.contains(linkLocalAddress) },
                          "Link-local \(linkLocalAddress) should NOT be in local ranges")
            XCTAssertTrue(systemIPv6.contains { $0.contains(linkLocalAddress) },
                         "Link-local \(linkLocalAddress) should be in always-excluded system ranges")
        }
    }

    /// Verifies that IPv6 multicast addresses are correctly categorized as system (always excluded)
    func testIPv6MulticastAddressesCategorizedAsSystem() {
        let localIPv6 = VPNRoutingRange.localIPv6NetworkRange
        let systemIPv6 = VPNRoutingRange.alwaysExcludedIPv6Range

        let multicastAddresses = [
            IPv6Address("ff02::1")!,       // All nodes
            IPv6Address("ff02::2")!,       // All routers
            IPv6Address("ff05::1:3")!,     // All DHCP servers
        ]

        for multicastAddress in multicastAddresses {
            XCTAssertFalse(localIPv6.contains { $0.contains(multicastAddress) },
                          "Multicast \(multicastAddress) should NOT be in local ranges")
            XCTAssertTrue(systemIPv6.contains { $0.contains(multicastAddress) },
                         "Multicast \(multicastAddress) should be in always-excluded system ranges")
        }
    }

    /// Verifies no overlaps within each IPv6 range category (local, system)
    func testIPv6RangesHaveNoInternalOverlaps() {
        let localIPv6 = VPNRoutingRange.localIPv6NetworkRange
        let systemIPv6 = VPNRoutingRange.alwaysExcludedIPv6Range

        func checkNoOverlapsWithin(_ ranges: [IPAddressRange], category: String) {
            for i in 0..<ranges.count {
                for j in (i+1)..<ranges.count {
                    XCTAssertFalse(ranges[i].overlaps(ranges[j]),
                                  "\(category) range \(ranges[i]) should not overlap with \(ranges[j])")
                }
            }
        }

        // Overlaps BETWEEN categories are OK (excluded routes take precedence per Apple's NEIPv6Settings docs)
        // but overlaps WITHIN a category indicate redundant/wasteful definitions
        // Note: fullIPv6RoutingRange is a single range, so no need to check for overlaps within it
        checkNoOverlapsWithin(localIPv6, category: "Local IPv6")
        checkNoOverlapsWithin(systemIPv6, category: "System IPv6")
    }

    /// Verifies full IPv6 routing range covers the entire address space and exclusions are defined
    func testIPv6FullRoutingRangeCoversEntireAddressSpace() {
        let fullIPv6 = VPNRoutingRange.fullIPv6RoutingRange
        let localIPv6 = VPNRoutingRange.localIPv6NetworkRange
        let systemIPv6 = VPNRoutingRange.alwaysExcludedIPv6Range

        func addressCount(prefixLength: Int) -> Decimal {
            let exponent = 128 - prefixLength
            return pow(Decimal(2), exponent)
        }

        func extractPrefixLength(_ range: IPAddressRange) -> Int? {
            let parts = range.description.split(separator: "/")
            guard parts.count == 2, let length = Int(parts[1]) else { return nil }
            return length
        }

        // Calculate total addresses in full IPv6 routing range
        let totalPublic: Decimal
        if let prefixLength = extractPrefixLength(fullIPv6) {
            totalPublic = addressCount(prefixLength: prefixLength)
        } else {
            XCTFail("Could not extract prefix length from fullIPv6RoutingRange")
            return
        }

        var totalLocal = Decimal(0)
        for range in localIPv6 {
            if let prefixLength = extractPrefixLength(range) {
                totalLocal += addressCount(prefixLength: prefixLength)
            }
        }

        var totalSystem = Decimal(0)
        for range in systemIPv6 {
            if let prefixLength = extractPrefixLength(range) {
                totalSystem += addressCount(prefixLength: prefixLength)
            }
        }

        let totalIPv6Space = pow(Decimal(2), 128)

        // Full IPv6 routing range (::/0) should cover the entire address space
        XCTAssertEqual(totalPublic, totalIPv6Space, "Full IPv6 routing range (::/0) should cover entire 2^128 address space")

        // Exclusions must be defined (non-zero) or VPN will route system/local traffic incorrectly
        XCTAssertGreaterThan(totalLocal, Decimal(0), "Local IPv6 ranges must be defined for conditional exclusion")
        XCTAssertGreaterThan(totalSystem, Decimal(0), "System IPv6 ranges must be defined for always-exclusion")
    }
}
