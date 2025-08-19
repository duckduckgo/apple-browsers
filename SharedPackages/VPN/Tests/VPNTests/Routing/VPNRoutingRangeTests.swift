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
        // Given - System ranges that should always be excluded
        let ipv4Excluded = VPNRoutingRange.alwaysExcludedIPv4Range
        let ipv6Excluded = VPNRoutingRange.alwaysExcludedIPv6Range
        
        // Define expected system ranges
        let expectedIPv4Ranges = [
            IPAddressRange(from: "127.0.0.0/8")!,      // Loopback
            IPAddressRange(from: "169.254.0.0/16")!,   // Link-local
            IPAddressRange(from: "224.0.0.0/4")!,      // Multicast
            IPAddressRange(from: "240.0.0.0/4")!       // Experimental
        ]
        
        let expectedIPv6Ranges = [
            IPAddressRange(from: "::1/128")!,          // IPv6 loopback
            IPAddressRange(from: "fe80::/10")!,        // IPv6 link-local
            IPAddressRange(from: "ff00::/8")!,         // IPv6 multicast
            IPAddressRange(from: "fc00::/7")!          // IPv6 private
        ]
        
        // Then - Verify critical system ranges are excluded using exact matching
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
        // Given
        let localNetworks = VPNRoutingRange.localNetworkRange
        let localStrings = localNetworks.map { $0.description }
        
        // Then - Verify all RFC 1918 private network ranges
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
        // Given
        let localNetworksWithoutDNS = VPNRoutingRange.localNetworkRangeWithoutDNS
        let localStrings = localNetworksWithoutDNS.map { $0.description }
        
        // Then - Should not include 10.0.0.0/8 (commonly used for VPN tunnel)
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
        // Given
        let publicNetworks = VPNRoutingRange.publicNetworkRange
        
        // Expected major public ranges that should be covered
        let expectedPublicRanges = [
            IPAddressRange(from: "1.0.0.0/8")!,       // Major public block
            IPAddressRange(from: "8.0.0.0/7")!,       // Covers 8.x and 9.x
            IPAddressRange(from: "64.0.0.0/3")!,      // Part of fixed 64.0.0.0/2 split
            IPAddressRange(from: "128.0.0.0/3")!,     // Major upper block
            IPAddressRange(from: "::/0")!             // IPv6 default route
        ]
        
        // Then - Verify major public ranges are covered using exact matching
        for expectedRange in expectedPublicRanges {
            XCTAssertTrue(expectedRange.hasExactMatch(in: publicNetworks), 
                         "Major public range \(expectedRange) should be covered")
        }
        
    }
    
    /// Verifies clear separation between public internet and private network traffic routing
    func testPublicAndPrivateTrafficAreSeparated() {
        // Given
        let publicNetworks = VPNRoutingRange.publicNetworkRange
        
        // Define private ranges that should NOT be in public ranges
        let privateRanges = [
            IPAddressRange(from: "10.0.0.0/8")!,
            IPAddressRange(from: "172.16.0.0/12")!,
            IPAddressRange(from: "192.168.0.0/16")!
        ]
        
        // Then - Verify private ranges are NOT in public ranges using exact matching
        for privateRange in privateRanges {
            XCTAssertFalse(privateRange.hasExactMatch(in: publicNetworks), 
                          "Private range \(privateRange) should NOT be in public ranges")
        }
        
    }
    
    /// Verifies clean separation between internet-routable and system-reserved address ranges
    func testInternetTrafficDoesNotIncludeSystemRanges() {
        // Given
        let publicNetworks = VPNRoutingRange.publicNetworkRange
        
        // Define system ranges that should NOT be in public ranges
        let systemRanges = [
            IPAddressRange(from: "127.0.0.0/8")!,      // Loopback
            IPAddressRange(from: "169.254.0.0/16")!,   // Link-local
            IPAddressRange(from: "224.0.0.0/4")!,      // Multicast
            IPAddressRange(from: "240.0.0.0/4")!       // Experimental
        ]
        
        // Then - Verify system ranges are NOT included in public internet using mathematical operations
        for systemRange in systemRanges {
            let foundInPublic = publicNetworks.contains { publicRange in
                publicRange == systemRange || publicRange.contains(systemRange) || systemRange.contains(publicRange)
            }
            XCTAssertFalse(foundInPublic, "System range \(systemRange) should NOT be in public ranges")
        }
        
    }
    

    
    // MARK: - IP Range Parsing and Validation Tests
    
    /// Verifies that all static IPv4 range definitions are valid and don't contain typos that could break routing
    func testIPv4RangeDefinitionsAreValid() {
        let allRanges = [
            ("alwaysExcludedIPv4", VPNRoutingRange.alwaysExcludedIPv4Range),
            ("localNetwork", VPNRoutingRange.localNetworkRange),
            ("localNetworkWithoutDNS", VPNRoutingRange.localNetworkRangeWithoutDNS),
            ("publicNetwork", VPNRoutingRange.publicNetworkRange.filter { $0.address is IPv4Address }) // IPv4 only
        ]
        
        for (rangeName, ranges) in allRanges {
            for (index, range) in ranges.enumerated() {
                // Given - Each range should be a valid IPAddressRange
                let rangeString = range.description
                
                // Then - Should be parseable as IPAddressRange
                XCTAssertNotNil(IPAddressRange(from: rangeString), 
                               "Range \(rangeString) in \(rangeName)[\(index)] should be valid")
            }
            

        }
    }
    
    /// Verifies that all static IPv6 range definitions are valid and don't contain typos that could break routing
    func testIPv6RangeDefinitionsAreValid() {
        let allIPv6Ranges = [
            ("alwaysExcludedIPv6", VPNRoutingRange.alwaysExcludedIPv6Range),
            ("publicNetworkIPv6", VPNRoutingRange.publicNetworkRange.filter { $0.address is IPv6Address })
        ]
        
        for (rangeName, ranges) in allIPv6Ranges {
            for (index, range) in ranges.enumerated() {
                // Given - Each range should be a valid IPAddressRange
                let rangeString = range.description
                
                // Then - Should be parseable as IPAddressRange
                XCTAssertNotNil(IPAddressRange(from: rangeString), 
                               "IPv6 range \(rangeString) in \(rangeName)[\(index)] should be valid")
            }
            

        }
    }
    
    /// Verifies that malformed IP address configurations are handled gracefully without crashing VPN
    func testMalformedConfigurationsAreHandledGracefully() {
        // Given - Some invalid range strings
        let invalidRanges = [
            "256.256.256.256/8",   // Invalid IPv4 address
            "not.an.ip/24",        // Not an IP address
            "",                    // Empty string
            "192.168.1.1/-1"       // Negative prefix
        ]
        
        for invalidRange in invalidRanges {
            // When - Try to parse invalid range
            let result = IPAddressRange(from: invalidRange)
            
            // Then - Should return nil for invalid ranges
            XCTAssertNil(result, "Invalid range '\(invalidRange)' should return nil")
        }
        

    }
    
    // MARK: - Range Logic and Consistency Tests
    
    /// Verifies that no IP ranges overlap between different routing categories which would cause routing conflicts
    func testRoutingLogicIsConsistent() {
        // Given
        let alwaysExcluded = VPNRoutingRange.alwaysExcludedIPv4Range
        let localNetwork = VPNRoutingRange.localNetworkRange
        let localWithoutDNS = VPNRoutingRange.localNetworkRangeWithoutDNS
        
        // Then - Check for actual range overlaps, not just exact string matches
        let alwaysExcludedAndLocal = findOverlappingRanges(alwaysExcluded, localNetwork)
        let alwaysExcludedAndLocalWithoutDNS = findOverlappingRanges(alwaysExcluded, localWithoutDNS)
        
        XCTAssertTrue(alwaysExcludedAndLocal.isEmpty, 
                     "Found overlapping ranges between always excluded and local: \(alwaysExcludedAndLocal)")
        XCTAssertTrue(alwaysExcludedAndLocalWithoutDNS.isEmpty, 
                     "Found overlapping ranges between always excluded and local (without DNS): \(alwaysExcludedAndLocalWithoutDNS)")
    }
    
    /// Verifies that DNS-compatible local ranges are properly contained within full local ranges
    func testDNSCompatibleRangesAreProperSubset() {
        // Given
        let localNetwork = VPNRoutingRange.localNetworkRange
        let localWithoutDNS = VPNRoutingRange.localNetworkRangeWithoutDNS
        
        // Then - Every range in localWithoutDNS should be contained in or equal to a range in localNetwork
        for rangeWithoutDNS in localWithoutDNS {
            let isContained = localNetwork.contains { localRange in
                localRange.contains(rangeWithoutDNS) || localRange == rangeWithoutDNS
            }
            XCTAssertTrue(isContained, 
                         "Range \(rangeWithoutDNS) should be contained within localNetworkRange")
        }
    }
    
    /// Verifies that public and private IP ranges have no overlaps that could cause routing ambiguity
    func testPublicAndPrivateRangesDoNotOverlap() {
        // Given
        let publicRanges = VPNRoutingRange.publicNetworkRange.filter { range in
            // Only check IPv4 public ranges vs IPv4 private ranges
            range.address is IPv4Address
        }
        let privateRanges = VPNRoutingRange.localNetworkRange
        
        // Then - No public range should overlap with private ranges
        let overlaps = findOverlappingRanges(publicRanges, privateRanges)
        XCTAssertTrue(overlaps.isEmpty, 
                     "Found overlaps between public and private ranges: \(overlaps)")
    }
    

    
    // MARK: - Helper Methods
    
    private func findOverlappingRanges(_ ranges1: [IPAddressRange], _ ranges2: [IPAddressRange]) -> [(IPAddressRange, IPAddressRange)] {
        var overlaps: [(IPAddressRange, IPAddressRange)] = []
        
        for range1 in ranges1 {
            for range2 in ranges2 {
                if range1.overlaps(range2) {
                    overlaps.append((range1, range2))
                }
            }
        }
        
        return overlaps
    }

    
    /// Verifies that VPN provides comprehensive global internet access by covering all major address blocks
    func testGlobalInternetAccessIsComprehensive() {
        // Given
        let publicNetworks = VPNRoutingRange.publicNetworkRange
        // Expected major internet address blocks that should be covered
        let expectedMajorBlocks = [
            "1.0.0.0/8",      // APNIC
            "8.0.0.0/7",      // Various (Level 3, Google, etc.)
            "64.0.0.0/3",     // Part of former 64.0.0.0/2 (64-95)
            "96.0.0.0/4",     // Part of former 64.0.0.0/2 (96-111)
            "128.0.0.0/3",    // Various global
            "::/0"            // IPv6 default
        ]
        
        // Then - Verify all expected blocks are covered using mathematical operations
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
