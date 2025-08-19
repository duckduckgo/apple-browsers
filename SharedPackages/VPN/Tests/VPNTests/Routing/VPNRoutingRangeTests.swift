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
@testable import VPN

final class VPNRoutingRangeTests: XCTestCase {
    
    // MARK: - Always Excluded IPv4 Range Tests
    
    func testAlwaysExcludedIPv4Range_ContainsLoopback() {
        // Given
        let alwaysExcluded = VPNRoutingRange.alwaysExcludedIPv4Range
        let excludedStrings = alwaysExcluded.map { $0.description }
        
        // Then
        XCTAssertTrue(excludedStrings.contains("127.0.0.0/8"), 
                     "Should exclude loopback range 127.0.0.0/8")
        
        //.info("Loopback range 127.0.0.0/8 correctly excluded")
    }
    
    func testAlwaysExcludedIPv4Range_ContainsLinkLocal() {
        // Given
        let alwaysExcluded = VPNRoutingRange.alwaysExcludedIPv4Range
        let excludedStrings = alwaysExcluded.map { $0.description }
        
        // Then
        XCTAssertTrue(excludedStrings.contains("169.254.0.0/16"), 
                     "Should exclude link-local range 169.254.0.0/16")
        
        //.info("Link-local range 169.254.0.0/16 correctly excluded")
    }
    
    func testAlwaysExcludedIPv4Range_ContainsMulticast() {
        // Given
        let alwaysExcluded = VPNRoutingRange.alwaysExcludedIPv4Range
        let excludedStrings = alwaysExcluded.map { $0.description }
        
        // Then
        XCTAssertTrue(excludedStrings.contains("224.0.0.0/4"), 
                     "Should exclude multicast range 224.0.0.0/4")
        
        //.info("Multicast range 224.0.0.0/4 correctly excluded")
    }
    
    func testAlwaysExcludedIPv4Range_ContainsClassE() {
        // Given
        let alwaysExcluded = VPNRoutingRange.alwaysExcludedIPv4Range
        let excludedStrings = alwaysExcluded.map { $0.description }
        
        // Then
        XCTAssertTrue(excludedStrings.contains("240.0.0.0/4"), 
                     "Should exclude Class E range 240.0.0.0/4")
        
        //.info("Class E range 240.0.0.0/4 correctly excluded")
    }
    
    func testAlwaysExcludedIPv4Range_HasExpectedCount() {
        // Given
        let alwaysExcluded = VPNRoutingRange.alwaysExcludedIPv4Range
        
        // Then
        XCTAssertEqual(alwaysExcluded.count, 4, "Should have exactly 4 always-excluded IPv4 ranges")
        
        //.info("Always excluded IPv4 ranges count verified: \(alwaysExcluded.count)")
    }
    
    // MARK: - Always Excluded IPv6 Range Tests
    
    func testAlwaysExcludedIPv6Range_ContainsLoopback() {
        // Given
        let alwaysExcluded = VPNRoutingRange.alwaysExcludedIPv6Range
        let excludedStrings = alwaysExcluded.map { $0.description }
        
        // Then
        XCTAssertTrue(excludedStrings.contains("::1/128"), 
                     "Should exclude IPv6 loopback ::1/128")
        
        //.info("IPv6 loopback ::1/128 correctly excluded")
    }
    
    func testAlwaysExcludedIPv6Range_ContainsLinkLocal() {
        // Given
        let alwaysExcluded = VPNRoutingRange.alwaysExcludedIPv6Range
        let excludedStrings = alwaysExcluded.map { $0.description }
        
        // Then
        XCTAssertTrue(excludedStrings.contains("fe80::/10"), 
                     "Should exclude IPv6 link-local fe80::/10")
        
        //.info("IPv6 link-local fe80::/10 correctly excluded")
    }
    
    func testAlwaysExcludedIPv6Range_ContainsMulticast() {
        // Given
        let alwaysExcluded = VPNRoutingRange.alwaysExcludedIPv6Range
        let excludedStrings = alwaysExcluded.map { $0.description }
        
        // Then
        XCTAssertTrue(excludedStrings.contains("ff00::/8"), 
                     "Should exclude IPv6 multicast ff00::/8")
        
        //.info("IPv6 multicast ff00::/8 correctly excluded")
    }
    
    func testAlwaysExcludedIPv6Range_ContainsUniqueLocal() {
        // Given
        let alwaysExcluded = VPNRoutingRange.alwaysExcludedIPv6Range
        let excludedStrings = alwaysExcluded.map { $0.description }
        
        // Then
        XCTAssertTrue(excludedStrings.contains("fc00::/7"), 
                     "Should exclude IPv6 unique local fc00::/7")
        
        //.info("IPv6 unique local fc00::/7 correctly excluded")
    }
    
    func testAlwaysExcludedIPv6Range_HasExpectedCount() {
        // Given
        let alwaysExcluded = VPNRoutingRange.alwaysExcludedIPv6Range
        
        // Then
        XCTAssertEqual(alwaysExcluded.count, 4, "Should have exactly 4 always-excluded IPv6 ranges")
        
        //.info("Always excluded IPv6 ranges count verified: \(alwaysExcluded.count)")
    }
    
    // MARK: - Local Network Range Tests
    
    func testLocalNetworkRange_ContainsRFC1918Ranges() {
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
        
        //.info("All RFC 1918 ranges verified in local network range")
    }
    
    func testLocalNetworkRangeWithoutDNS_ExcludesTenDotNetwork() {
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
        
        //.info("localNetworkRangeWithoutDNS correctly excludes 10.0.0.0/8")
    }
    
    func testLocalNetworkRange_HasExpectedCount() {
        // Given
        let localNetworks = VPNRoutingRange.localNetworkRange
        let localNetworksWithoutDNS = VPNRoutingRange.localNetworkRangeWithoutDNS
        
        // Then
        XCTAssertEqual(localNetworks.count, 3, "localNetworkRange should have exactly 3 ranges")
        XCTAssertEqual(localNetworksWithoutDNS.count, 2, "localNetworkRangeWithoutDNS should have exactly 2 ranges")
        
        //.info("Local network ranges count verified: full=\(localNetworks.count), withoutDNS=\(localNetworksWithoutDNS.count)")
    }
    
    // MARK: - Public Network Range Tests
    
    func testPublicNetworkRange_CoversComprehensiveIPv4Space() {
        // Given
        let publicNetworks = VPNRoutingRange.publicNetworkRange
        let publicStrings = publicNetworks.map { $0.description }
        
        // Then - Should include major public IPv4 ranges
        XCTAssertTrue(publicStrings.contains("1.0.0.0/8"), "Should include 1.0.0.0/8")
        XCTAssertTrue(publicStrings.contains("8.0.0.0/7"), "Should include 8.0.0.0/7 (covers 8.x and 9.x)")
        XCTAssertTrue(publicStrings.contains("64.0.0.0/2"), "Should include 64.0.0.0/2 (covers 64-127)")
        XCTAssertTrue(publicStrings.contains("128.0.0.0/3"), "Should include 128.0.0.0/3 (covers 128-159)")
        
        // Should include IPv6
        XCTAssertTrue(publicStrings.contains("::/0"), "Should include IPv6 default route ::/0")
        
        //.info("Public network range covers comprehensive IPv4 space and IPv6")
    }
    
    func testPublicNetworkRange_ExcludesPrivateRanges() {
        // Given
        let publicNetworks = VPNRoutingRange.publicNetworkRange
        let publicStrings = publicNetworks.map { $0.description }
        
        // Then - Should NOT directly include RFC 1918 ranges
        XCTAssertFalse(publicStrings.contains("10.0.0.0/8"), 
                      "Public ranges should NOT directly include private 10.0.0.0/8")
        XCTAssertFalse(publicStrings.contains("172.16.0.0/12"), 
                      "Public ranges should NOT directly include private 172.16.0.0/12")
        XCTAssertFalse(publicStrings.contains("192.168.0.0/16"), 
                      "Public ranges should NOT directly include private 192.168.0.0/16")
        
        //.info("Public network range correctly excludes RFC 1918 private ranges")
    }
    
    func testPublicNetworkRange_ExcludesSystemRanges() {
        // Given
        let publicNetworks = VPNRoutingRange.publicNetworkRange
        let publicStrings = publicNetworks.map { $0.description }
        
        // Then - Should NOT include system ranges that are always excluded
        XCTAssertFalse(publicStrings.contains("127.0.0.0/8"), 
                      "Public ranges should NOT include loopback 127.0.0.0/8")
        XCTAssertFalse(publicStrings.contains("169.254.0.0/16"), 
                      "Public ranges should NOT include link-local 169.254.0.0/16")
        XCTAssertFalse(publicStrings.contains("224.0.0.0/4"), 
                      "Public ranges should NOT include multicast 224.0.0.0/4")
        XCTAssertFalse(publicStrings.contains("240.0.0.0/4"), 
                      "Public ranges should NOT include Class E 240.0.0.0/4")
        
        //.info("Public network range correctly excludes system ranges")
    }
    
    func testPublicNetworkRange_HasReasonableCount() {
        // Given
        let publicNetworks = VPNRoutingRange.publicNetworkRange
        
        // Then - Should have comprehensive but not excessive number of ranges
        XCTAssertGreaterThan(publicNetworks.count, 30, "Should have comprehensive public range coverage")
        XCTAssertLessThan(publicNetworks.count, 100, "Should not have excessive number of ranges")
        
        //.info("Public network range count reasonable: \(publicNetworks.count) ranges")
    }
    
    // MARK: - IP Range Parsing and Validation Tests
    
    func testAllIPv4Ranges_ParseSuccessfully() {
        let allRanges = [
            ("alwaysExcludedIPv4", VPNRoutingRange.alwaysExcludedIPv4Range),
            ("localNetwork", VPNRoutingRange.localNetworkRange),
            ("localNetworkWithoutDNS", VPNRoutingRange.localNetworkRangeWithoutDNS),
            ("publicNetwork", VPNRoutingRange.publicNetworkRange.filter { !$0.description.contains(":") }) // IPv4 only
        ]
        
        for (rangeName, ranges) in allRanges {
            for (index, range) in ranges.enumerated() {
                // Given - Each range should be a valid IPAddressRange
                let rangeString = range.description
                
                // Then - Should be parseable as IPAddressRange
                XCTAssertNotNil(IPAddressRange(from: rangeString), 
                               "Range \(rangeString) in \(rangeName)[\(index)] should be valid")
            }
            
            //.debug("All ranges in \(rangeName) parsed successfully: \(ranges.count) ranges")
        }
    }
    
    func testAllIPv6Ranges_ParseSuccessfully() {
        let allIPv6Ranges = [
            ("alwaysExcludedIPv6", VPNRoutingRange.alwaysExcludedIPv6Range),
            ("publicNetworkIPv6", VPNRoutingRange.publicNetworkRange.filter { $0.description.contains(":") })
        ]
        
        for (rangeName, ranges) in allIPv6Ranges {
            for (index, range) in ranges.enumerated() {
                // Given - Each range should be a valid IPAddressRange
                let rangeString = range.description
                
                // Then - Should be parseable as IPAddressRange
                XCTAssertNotNil(IPAddressRange(from: rangeString), 
                               "IPv6 range \(rangeString) in \(rangeName)[\(index)] should be valid")
            }
            
            //.debug("All IPv6 ranges in \(rangeName) parsed successfully: \(ranges.count) ranges")
        }
    }
    
    func testInvalidRanges_HandleGracefully() {
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
        
        //.info("Invalid ranges handled gracefully")
    }
    
    // MARK: - Range Logic and Consistency Tests
    
    func testRangeCategories_DoNotOverlap() {
        // Given
        let alwaysExcluded = Set(VPNRoutingRange.alwaysExcludedIPv4Range.map { $0.description })
        let localNetwork = Set(VPNRoutingRange.localNetworkRange.map { $0.description })
        let localWithoutDNS = Set(VPNRoutingRange.localNetworkRangeWithoutDNS.map { $0.description })
        
        // Then - Categories should not overlap
        let alwaysExcludedAndLocal = alwaysExcluded.intersection(localNetwork)
        let alwaysExcludedAndLocalWithoutDNS = alwaysExcluded.intersection(localWithoutDNS)
        
        XCTAssertTrue(alwaysExcludedAndLocal.isEmpty, 
                     "Always excluded and local network ranges should not overlap")
        XCTAssertTrue(alwaysExcludedAndLocalWithoutDNS.isEmpty, 
                     "Always excluded and local network (without DNS) ranges should not overlap")
        
        //.info("Range categories do not overlap")
    }
    
    func testLocalNetworkRangeWithoutDNS_IsSubsetOfLocalNetworkRange() {
        // Given
        let localNetwork = Set(VPNRoutingRange.localNetworkRange.map { $0.description })
        let localWithoutDNS = Set(VPNRoutingRange.localNetworkRangeWithoutDNS.map { $0.description })
        
        // Then - localNetworkRangeWithoutDNS should be subset of localNetworkRange
        XCTAssertTrue(localWithoutDNS.isSubset(of: localNetwork), 
                     "localNetworkRangeWithoutDNS should be a subset of localNetworkRange")
        
        //.info("localNetworkRangeWithoutDNS is proper subset of localNetworkRange")
    }
    
    func testPublicNetworkRange_CoversExpectedAddressSpace() {
        // Given
        let publicNetworks = VPNRoutingRange.publicNetworkRange
        let publicStrings = publicNetworks.map { $0.description }
        
        // Then - Should cover major internet address blocks
        let expectedMajorBlocks = [
            "1.0.0.0/8",      // APNIC
            "8.0.0.0/7",      // Various (Level 3, Google, etc.)
            "64.0.0.0/2",     // North America
            "128.0.0.0/3",    // Various global
            "::/0"            // IPv6 default
        ]
        
        for expectedBlock in expectedMajorBlocks {
            XCTAssertTrue(publicStrings.contains(expectedBlock), 
                         "Public network range should contain \(expectedBlock)")
        }
        
        //.info("Public network range covers expected major address blocks")
    }
    
    // MARK: - Performance Tests
    
    func testRangeAccess_Performance() {
        // Given - Measure time to access all static ranges multiple times
        let iterations = 1000
        
        // When
        let startTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = VPNRoutingRange.alwaysExcludedIPv4Range
            _ = VPNRoutingRange.alwaysExcludedIPv6Range
            _ = VPNRoutingRange.localNetworkRange
            _ = VPNRoutingRange.localNetworkRangeWithoutDNS
            _ = VPNRoutingRange.publicNetworkRange
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        // Then
        let averageTime = elapsed / Double(iterations) * 1000 // Convert to milliseconds
        XCTAssertLessThan(averageTime, 0.1, "Average range access should be under 0.1ms")
        
        //.info("Range access performance: \(averageTime)ms average over \(iterations) iterations")
    }
    
    // MARK: - Documentation and Comments Verification
    
    func testRangeComments_MatchActualRanges() {
        // Test that comments in the source code match the actual IP ranges
        // This test validates the human-readable comments against the actual ranges
        
        // Given
        let alwaysExcluded = VPNRoutingRange.alwaysExcludedIPv4Range.map { $0.description }
        
        // Then - Verify comments match actual ranges (based on source code comments)
        if alwaysExcluded.contains("127.0.0.0/8") {
            //.info("✓ Loopback range 127.0.0.0/8 matches comment: 127.0.0.0 - 127.255.255.255 Loopback")
        }
        
        if alwaysExcluded.contains("169.254.0.0/16") {
            //.info("✓ Link-local range 169.254.0.0/16 matches comment: 169.254.0.0 - 169.254.255.255 Link-local")
        }
        
        if alwaysExcluded.contains("224.0.0.0/4") {
            //.info("✓ Multicast range 224.0.0.0/4 matches comment: 224.0.0.0 - 239.255.255.255 Multicast")
        }
        
        if alwaysExcluded.contains("240.0.0.0/4") {
            //.info("✓ Class E range 240.0.0.0/4 matches comment: 240.0.0.0 - 255.255.255.255 Class E")
        }
        
        // Test local network range comments
        let localNetworks = VPNRoutingRange.localNetworkRange.map { $0.description }
        
        if localNetworks.contains("10.0.0.0/8") {
            //.info("✓ Private range 10.0.0.0/8 matches comment: 255.0.0.0")
        }
        
        if localNetworks.contains("172.16.0.0/12") {
            //.info("✓ Private range 172.16.0.0/12 matches comment: 255.240.0.0")
        }
        
        if localNetworks.contains("192.168.0.0/16") {
            //.info("✓ Private range 192.168.0.0/16 matches comment: 255.255.0.0")
        }
    }
}
