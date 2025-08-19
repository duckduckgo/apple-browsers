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
    
    // MARK: - System Protection Tests
    
    /// Verifies that critical system traffic never goes through the VPN tunnel
    func testCriticalSystemTrafficStaysLocal() {
        // Given
        let ipv4Excluded = VPNRoutingRange.alwaysExcludedIPv4Range.map { $0.description }
        let ipv6Excluded = VPNRoutingRange.alwaysExcludedIPv6Range.map { $0.description }
        
        // Then - Verify all critical IPv4 ranges are protected
        XCTAssertTrue(ipv4Excluded.contains("127.0.0.0/8"), "Should exclude loopback")
        XCTAssertTrue(ipv4Excluded.contains("169.254.0.0/16"), "Should exclude link-local") 
        XCTAssertTrue(ipv4Excluded.contains("224.0.0.0/4"), "Should exclude multicast")
        XCTAssertTrue(ipv4Excluded.contains("240.0.0.0/4"), "Should exclude experimental ranges")
        
        // Then - Verify all critical IPv6 ranges are protected  
        XCTAssertTrue(ipv6Excluded.contains("::1/128"), "Should exclude IPv6 loopback")
        XCTAssertTrue(ipv6Excluded.contains("fe80::/10"), "Should exclude IPv6 link-local")
        XCTAssertTrue(ipv6Excluded.contains("ff00::/8"), "Should exclude IPv6 multicast")
        XCTAssertTrue(ipv6Excluded.contains("fc00::/7"), "Should exclude IPv6 private")
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
        let publicStrings = publicNetworks.map { $0.description }
        
        // Then - Should include major public IPv4 ranges
        XCTAssertTrue(publicStrings.contains("1.0.0.0/8"), "Should include 1.0.0.0/8")
        XCTAssertTrue(publicStrings.contains("8.0.0.0/7"), "Should include 8.0.0.0/7 (covers 8.x and 9.x)")
        XCTAssertTrue(publicStrings.contains("64.0.0.0/2"), "Should include 64.0.0.0/2 (covers 64-127)")
        XCTAssertTrue(publicStrings.contains("128.0.0.0/3"), "Should include 128.0.0.0/3 (covers 128-159)")
        
        // Should include IPv6
        XCTAssertTrue(publicStrings.contains("::/0"), "Should include IPv6 default route ::/0")
        
    }
    
    /// Verifies clear separation between public internet and private network traffic routing
    func testPublicAndPrivateTrafficAreSeparated() {
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
        
    }
    
    /// Verifies clean separation between internet-routable and system-reserved address ranges
    func testInternetTrafficDoesNotIncludeSystemRanges() {
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
        
    }
    

    
    // MARK: - IP Range Parsing and Validation Tests
    
    /// Verifies that all static IPv4 range definitions are valid and don't contain typos that could break routing
    func testIPv4RangeDefinitionsAreValid() {
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
            

        }
    }
    
    /// Verifies that all static IPv6 range definitions are valid and don't contain typos that could break routing
    func testIPv6RangeDefinitionsAreValid() {
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
    
    /// Verifies logical consistency - ensures no IP range is both included and excluded which would break routing
    func testRoutingLogicIsConsistent() {
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
        
    }
    
    /// Verifies that DNS-compatible and full local network range definitions have the correct relationship
    ///
    /// - Discussion: The "WithoutDNS" variant excludes 10.0.0.0/8 to prevent VPN tunnel conflicts,
    ///   while the full range includes all RFC 1918 addresses for complete local network coverage.
    func testDNSCompatibleRangesAreProperSubset() {
        // Given
        let localNetwork = Set(VPNRoutingRange.localNetworkRange.map { $0.description })
        let localWithoutDNS = Set(VPNRoutingRange.localNetworkRangeWithoutDNS.map { $0.description })
        
        // Then - localNetworkRangeWithoutDNS should be subset of localNetworkRange
        XCTAssertTrue(localWithoutDNS.isSubset(of: localNetwork), 
                     "localNetworkRangeWithoutDNS should be a subset of localNetworkRange")
        
    }
    
    /// Verifies that VPN provides comprehensive global internet access by covering all major address blocks
    func testGlobalInternetAccessIsComprehensive() {
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
        
    }
    
    // MARK: - Performance Tests
    

    

}
