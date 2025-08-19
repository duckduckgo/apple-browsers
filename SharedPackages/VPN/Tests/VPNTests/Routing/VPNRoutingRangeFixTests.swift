//
//  VPNRoutingRangeFixTests.swift
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

final class VPNRoutingRangeFixTests: XCTestCase {
    
    /// Verifies that CIDR range splitting mathematics work correctly for avoiding unwanted inclusions
    func testCIDRRangeSplittingMathematics() {
        // Given - Current problematic range
        let currentProblematic = IPAddressRange(from: "64.0.0.0/2")!
        let loopback = IPAddressRange(from: "127.0.0.0/8")!
        
        // Verify the current problem exists
        XCTAssertTrue(currentProblematic.contains(loopback), 
                     "Current 64.0.0.0/2 range contains loopback (this is the issue)")
        
        // When - Apply the proposed fix (replace 64.0.0.0/2 with 6 more specific ranges)
        let proposedReplacement = [
            "64.0.0.0/3",   // 64.0.0.0 - 95.255.255.255  
            "96.0.0.0/4",   // 96.0.0.0 - 111.255.255.255
            "112.0.0.0/5",  // 112.0.0.0 - 119.255.255.255
            "120.0.0.0/6",  // 120.0.0.0 - 123.255.255.255
            "124.0.0.0/7",  // 124.0.0.0 - 125.255.255.255
            "126.0.0.0/8"   // 126.0.0.0 - 126.255.255.255
        ]
        
        // Then - Verify the fix resolves the overlap
        for rangeString in proposedReplacement {
            let range = IPAddressRange(from: rangeString)!
            XCTAssertFalse(range.overlaps(loopback), 
                          "Proposed range \(rangeString) should not overlap with loopback")
        }
        
        // Verify we maintain equivalent coverage (minus loopback)
        let testAddresses = [
            "64.0.0.1",     // Start of coverage
            "95.255.255.255", // End of first range
            "96.0.0.1",     // Start of second range
            "126.255.255.255", // End of last range
            "127.0.0.1"     // Should be excluded
        ]
        
        for addressString in testAddresses {
            guard let address = IPv4Address(addressString) else { continue }
            
            let currentlyCovered = currentProblematic.contains(address)
            let wouldBeCoveredByFix = proposedReplacement.contains { rangeString in
                IPAddressRange(from: rangeString)!.contains(address)
            }
            let isLoopback = loopback.contains(address)
            
            if isLoopback {
                XCTAssertTrue(currentlyCovered, "Currently \(addressString) is problematically covered")
                XCTAssertFalse(wouldBeCoveredByFix, "After fix \(addressString) should NOT be covered")
            } else {
                XCTAssertEqual(currentlyCovered, wouldBeCoveredByFix, 
                              "Coverage for \(addressString) should be preserved by the fix")
            }
        }
        
        print("✅ CIDR splitting can eliminate unwanted inclusions while maintaining coverage")
        print("Example: Covering 64-126 without 127 requires 6 granular ranges")
    }
    
    /// Verifies that all VPN routing range categories have no mathematical overlaps
    func testAllRangeCategoriesHaveNoMathematicalOverlaps() {
        // Given - All range categories from VPNRoutingRange  
        let alwaysExcluded = VPNRoutingRange.alwaysExcludedIPv4Range
        let localNetwork = VPNRoutingRange.localNetworkRange
        let publicNetwork = VPNRoutingRange.publicNetworkRange.filter { $0.address is IPv4Address }
        
        // When - Check all possible category overlaps
        let excludedVsLocal = findAllOverlaps(alwaysExcluded, localNetwork)
        let excludedVsPublic = findAllOverlaps(alwaysExcluded, publicNetwork)
        let localVsPublic = findAllOverlaps(localNetwork, publicNetwork)
        let publicInternal = findInternalOverlaps(publicNetwork)
        
        // Then - Document all findings
        XCTAssertTrue(excludedVsLocal.isEmpty, "Should be no excluded/local overlaps: \(excludedVsLocal)")
        XCTAssertTrue(localVsPublic.isEmpty, "Should be no local/public overlaps: \(localVsPublic)")
        XCTAssertTrue(publicInternal.isEmpty, "Should be no internal public overlaps: \(publicInternal)")
        
        // After the fix, there should be no overlaps
        XCTAssertEqual(excludedVsPublic.count, 0, "Should find NO excluded/public overlaps after fix")
        
        print("✅ Confirmed: No overlaps exist after loopback fix")
        print("🎯 ANALYSIS COMPLETE: All range overlaps resolved")
    }
    
    private func findAllOverlaps(_ ranges1: [IPAddressRange], _ ranges2: [IPAddressRange]) -> [(IPAddressRange, IPAddressRange)] {
        var overlaps: [(IPAddressRange, IPAddressRange)] = []
        for r1 in ranges1 {
            for r2 in ranges2 {
                if r1.overlaps(r2) {
                    overlaps.append((r1, r2))
                }
            }
        }
        return overlaps
    }
    
    private func findInternalOverlaps(_ ranges: [IPAddressRange]) -> [(IPAddressRange, IPAddressRange)] {
        var overlaps: [(IPAddressRange, IPAddressRange)] = []
        for i in 0..<ranges.count {
            for j in (i+1)..<ranges.count {
                if ranges[i].overlaps(ranges[j]) {
                    overlaps.append((ranges[i], ranges[j]))
                }
            }
        }
        return overlaps
    }
    
    /// Verifies that public internet coverage remains comprehensive after range optimizations
    func testPublicInternetCoverageIsComprehensive() {
        // Given
        let publicRanges = VPNRoutingRange.publicNetworkRange.filter { $0.address is IPv4Address }
        
        // When - Test coverage of major public internet services
        let majorPublicAddresses = [
            "1.1.1.1",        // Cloudflare DNS
            "8.8.8.8",        // Google DNS
            "208.67.222.222", // OpenDNS
            "4.4.4.4",        // Level3 DNS
            "199.85.126.10",  // Norton DNS
            "75.75.75.75",    // Comcast DNS
            "156.154.70.1"    // Neustar DNS
        ]
        
        // Then - Verify all major services are covered
        for addressString in majorPublicAddresses {
            guard let address = IPv4Address(addressString) else { continue }
            
            let isCovered = publicRanges.contains { range in range.contains(address) }
            XCTAssertTrue(isCovered, 
                         "Major public service \(addressString) should be covered by public ranges")
        }
    }
}
