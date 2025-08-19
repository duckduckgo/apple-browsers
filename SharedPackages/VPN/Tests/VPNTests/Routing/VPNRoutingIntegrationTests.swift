//
//  VPNRoutingIntegrationTests.swift
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

final class VPNRoutingIntegrationTests: XCTestCase {
    
    // MARK: - Real-World Configuration Tests
    
    func testHomeNetworkConfiguration_WithCloudflareDNS_RoutesCorrectly() {
        // Given - Typical home network setup with Cloudflare DNS and local network exclusion
        let dnsServers = [
            DNSServer(address: IPv4Address("1.1.1.1")!), // Cloudflare primary
            DNSServer(address: IPv4Address("1.0.0.1")!)  // Cloudflare secondary
        ]
        let resolver = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: true
        )
        
        // When
        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes
        
        // Then - Verify complete routing configuration
        self.assertTypicalVPNRouting(
            includedRoutes: includedRoutes,
            excludedRoutes: excludedRoutes,
            expectedDNSServers: ["1.1.1.1/32", "1.0.0.1/32"],
            excludesLocalNetworks: true,
            testName: "HomeNetwork+Cloudflare"
        )
        
        //.info("Home network with Cloudflare DNS configuration validated")
    }
    
    func testCorporateNetworkConfiguration_WithInternalDNS_AllowsLocalAccess() {
        // Given - Corporate network with internal DNS and local network access
        let dnsServers = [
            DNSServer(address: IPv4Address("10.1.1.10")!), // Corporate DNS
            DNSServer(address: IPv4Address("8.8.8.8")!)    // Fallback public DNS
        ]
        let resolver = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: false
        )
        
        // When
        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes
        
        // Then - Verify corporate routing configuration
        self.assertCorporateVPNRouting(
            includedRoutes: includedRoutes,
            excludedRoutes: excludedRoutes,
            expectedDNSServers: ["10.1.1.10/32", "8.8.8.8/32"],
            testName: "CorporateNetwork+InternalDNS"
        )
        
        //.info("Corporate network with internal DNS configuration validated")
    }
    
    func testPublicWiFiConfiguration_WithGoogleDNS_BlocksLocalAccess() {
        // Given - Public WiFi with Google DNS and strict local network blocking
        let dnsServers = [
            DNSServer(address: IPv4Address("8.8.8.8")!),
            DNSServer(address: IPv4Address("8.8.4.4")!)
        ]
        let resolver = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: true
        )
        
        // When
        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes
        
        // Then - Verify public WiFi security configuration
        self.assertTypicalVPNRouting(
            includedRoutes: includedRoutes,
            excludedRoutes: excludedRoutes,
            expectedDNSServers: ["8.8.8.8/32", "8.8.4.4/32"],
            excludesLocalNetworks: true,
            testName: "PublicWiFi+GoogleDNS"
        )
        
        //.info("Public WiFi with Google DNS security configuration validated")
    }
    
    func testMixedDNSConfiguration_IPv4AndIPv6_HandlesCorrectly() {
        // Given - Mixed IPv4 and IPv6 DNS configuration
        let ipv4DNS = DNSServer(address: IPv4Address("1.1.1.1")!)
        let ipv6DNS = DNSServer(address: IPv6Address("2606:4700:4700::1111")!) // Cloudflare IPv6
        
        let resolver = VPNRoutingTableResolver(
            dnsServers: [ipv4DNS, ipv6DNS],
            excludeLocalNetworks: true
        )
        
        // When
        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes
        
        // Then
        let includedStrings = includedRoutes.map { $0.description }
        let excludedStrings = excludedRoutes.map { $0.description }
        
        // Should include both IPv4 and IPv6 DNS routes
        XCTAssertTrue(includedStrings.contains("1.1.1.1/32"), "Should route IPv4 DNS")
        
        let hasIPv6DNS = includedStrings.contains { route in
            route.contains("2606:4700:4700::1111")
        }
        XCTAssertTrue(hasIPv6DNS, "Should route IPv6 DNS")
        
        // Should have standard excluded ranges
        XCTAssertTrue(excludedStrings.contains("127.0.0.0/8"), "Should exclude loopback")
        // Note: IPv6 exclusions might be handled differently in the current implementation
        
        //.info("Mixed IPv4/IPv6 DNS configuration validated")
    }
    
    // MARK: - Edge Case and Boundary Tests
    
    func testExtremeDNSConfiguration_ManyServers_HandlesPerformantly() {
        // Given - Configuration with many DNS servers (stress test)
        let manyDNSServers: [DNSServer] = (1...50).compactMap { i in
            guard let ip = IPv4Address("8.8.8.\(i % 254 + 1)") else { return nil }
            return DNSServer(address: ip)
        }
        
        // When
        let startTime = CFAbsoluteTimeGetCurrent()
        let resolver = VPNRoutingTableResolver(
            dnsServers: manyDNSServers,
            excludeLocalNetworks: true
        )
        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        // Then - Should handle large DNS server lists performantly
        XCTAssertLessThan(elapsed, 0.2, "Should handle \(manyDNSServers.count) DNS servers in under 200ms")
        XCTAssertGreaterThan(includedRoutes.count, 50, "Should generate comprehensive route list")
        XCTAssertGreaterThan(excludedRoutes.count, 4, "Should maintain proper exclusions")
        
        // Verify a sampling of DNS routes were created
        let includedStrings = includedRoutes.map { $0.description }
        let dnsRouteCount = includedStrings.filter { $0.hasSuffix("/32") && $0.hasPrefix("8.8.8.") }.count
        XCTAssertGreaterThan(dnsRouteCount, 40, "Should create DNS routes for most servers")
        
        //.info("Extreme DNS configuration performance test passed: \(manyDNSServers.count) servers, \(elapsed)s elapsed")
    }
    
    func testEmptyDNSConfiguration_NoDNSServers_GeneratesValidRoutes() {
        // Given - Configuration without any DNS servers
        let resolver = VPNRoutingTableResolver(
            dnsServers: [],
            excludeLocalNetworks: true
        )
        
        // When
        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes
        
        // Then - Should still generate valid routing table
        XCTAssertFalse(includedRoutes.isEmpty, "Should have public network routes even without DNS")
        XCTAssertFalse(excludedRoutes.isEmpty, "Should have system exclusions even without DNS")
        
        let includedStrings = includedRoutes.map { $0.description }
        let excludedStrings = excludedRoutes.map { $0.description }
        
        // Should have no DNS-specific /32 routes
        let dnsRoutes = includedStrings.filter { $0.hasSuffix("/32") }
        XCTAssertTrue(dnsRoutes.isEmpty, "Should have no /32 DNS routes when no DNS servers configured")
        
        // Should still exclude system ranges
        XCTAssertTrue(excludedStrings.contains("127.0.0.0/8"), "Should still exclude loopback")
        XCTAssertTrue(excludedStrings.contains("192.168.0.0/16"), "Should exclude local networks")
        
        //.info("Empty DNS configuration handled correctly")
    }
    
    func testDuplicateDNSServers_SameIP_HandlesGracefully() {
        // Given - Configuration with duplicate DNS servers
        let duplicateDNS = [
            DNSServer(address: IPv4Address("8.8.8.8")!),
            DNSServer(address: IPv4Address("8.8.8.8")!), // Exact duplicate
            DNSServer(address: IPv4Address("1.1.1.1")!),
            DNSServer(address: IPv4Address("1.1.1.1")!)  // Exact duplicate
        ]
        
        let resolver = VPNRoutingTableResolver(
            dnsServers: duplicateDNS,
            excludeLocalNetworks: false
        )
        
        // When
        let includedRoutes = resolver.includedRoutes
        
        // Then - Should handle duplicates gracefully (may or may not deduplicate)
        let includedStrings = includedRoutes.map { $0.description }
        
        // At minimum, should have routes for the unique DNS servers
        XCTAssertTrue(includedStrings.contains("8.8.8.8/32"), "Should route to 8.8.8.8")
        XCTAssertTrue(includedStrings.contains("1.1.1.1/32"), "Should route to 1.1.1.1")
        
        //.info("Duplicate DNS servers handled gracefully")
    }
    
    // MARK: - Routing Table Completeness Tests
    
    func testRoutingTableCompleteness_CoversAllInternetSpace() {
        // Given - Standard VPN configuration
        let resolver = VPNRoutingTableResolver(
            dnsServers: [DNSServer(address: IPv4Address("8.8.8.8")!)],
            excludeLocalNetworks: true
        )
        
        // When
        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes
        
        // Then - Verify routing table completeness
        self.assertRoutingTableCompleteness(
            includedRoutes: includedRoutes,
            excludedRoutes: excludedRoutes
        )
        
        //.info("Routing table completeness verified")
    }
    
    func testRoutingTable_NoConflictsBetweenIncludedAndExcluded() {
        let configurations = [
            (excludeLocal: true, description: "excluding local networks"),
            (excludeLocal: false, description: "including local networks")
        ]
        
        for config in configurations {
            // Given
            let resolver = VPNRoutingTableResolver(
                dnsServers: [DNSServer(address: IPv4Address("8.8.8.8")!)],
                excludeLocalNetworks: config.excludeLocal
            )
            
            // When
            let includedRoutes = Set(resolver.includedRoutes.map { $0.description })
            let excludedRoutes = Set(resolver.excludedRoutes.map { $0.description })
            
            // Then - No route should be both included and excluded
            let conflicts = includedRoutes.intersection(excludedRoutes)
            XCTAssertTrue(conflicts.isEmpty, 
                         "No routes should be both included and excluded \(config.description). Conflicts: \(conflicts)")
            
            //.debug("No routing conflicts found \(config.description)")
        }
    }
    
    // MARK: - Configuration Change Tests
    
    func testConfigurationToggle_ExcludeLocalNetworks_UpdatesCorrectly() {
        let dnsServers = [DNSServer(address: IPv4Address("1.1.1.1")!)]
        
        // Given - Initial configuration excluding local networks
        let resolverExcluding = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: true
        )
        
        let resolverIncluding = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: false
        )
        
        // When
        let routesExcluding = (
            included: resolverExcluding.includedRoutes.map { $0.description },
            excluded: resolverExcluding.excludedRoutes.map { $0.description }
        )
        
        let routesIncluding = (
            included: resolverIncluding.includedRoutes.map { $0.description },
            excluded: resolverIncluding.excludedRoutes.map { $0.description }
        )
        
        // Then - Local network routing should be opposite
        XCTAssertFalse(routesExcluding.included.contains("192.168.0.0/16"), 
                      "Should NOT include local networks when excluding")
        XCTAssertTrue(routesExcluding.excluded.contains("192.168.0.0/16"), 
                     "Should exclude local networks when excluding")
        
        XCTAssertTrue(routesIncluding.included.contains("192.168.0.0/16"), 
                     "Should include local networks when including")
        XCTAssertFalse(routesIncluding.excluded.contains("192.168.0.0/16"), 
                      "Should NOT exclude local networks when including")
        
        // DNS routes should be the same in both configurations
        XCTAssertTrue(routesExcluding.included.contains("1.1.1.1/32"), 
                     "DNS route should exist when excluding local")
        XCTAssertTrue(routesIncluding.included.contains("1.1.1.1/32"), 
                     "DNS route should exist when including local")
        
        //.info("Configuration toggle for local networks verified")
    }
    
    // MARK: - Helper Methods for Assertions
    
    private func assertTypicalVPNRouting(
        includedRoutes: [IPAddressRange],
        excludedRoutes: [IPAddressRange],
        expectedDNSServers: [String],
        excludesLocalNetworks: Bool,
        testName: String
    ) {
        let includedStrings = includedRoutes.map { $0.description }
        let excludedStrings = excludedRoutes.map { $0.description }
        
        // Verify DNS server routes
        for dnsRoute in expectedDNSServers {
            XCTAssertTrue(includedStrings.contains(dnsRoute), 
                         "\(testName): Should include DNS route \(dnsRoute)")
        }
        
        // Verify public network coverage
        XCTAssertTrue(includedStrings.contains("1.0.0.0/8"), 
                     "\(testName): Should include public range 1.0.0.0/8")
        XCTAssertTrue(includedStrings.contains("8.0.0.0/7"), 
                     "\(testName): Should include public range 8.0.0.0/7")
        XCTAssertTrue(includedStrings.contains("::/0"), 
                     "\(testName): Should include IPv6 default route")
        
        // Verify system exclusions
        XCTAssertTrue(excludedStrings.contains("127.0.0.0/8"), 
                     "\(testName): Should exclude loopback")
        XCTAssertTrue(excludedStrings.contains("224.0.0.0/4"), 
                     "\(testName): Should exclude multicast")
        
        // Verify local network handling
        if excludesLocalNetworks {
            XCTAssertTrue(excludedStrings.contains("192.168.0.0/16"), 
                         "\(testName): Should exclude local networks")
            XCTAssertFalse(includedStrings.contains("192.168.0.0/16"), 
                          "\(testName): Should NOT include excluded local networks")
        } else {
            XCTAssertFalse(excludedStrings.contains("192.168.0.0/16"), 
                          "\(testName): Should NOT exclude local networks")
            XCTAssertTrue(includedStrings.contains("192.168.0.0/16"), 
                         "\(testName): Should include local networks")
        }
        
        // Verify reasonable route counts
        XCTAssertGreaterThan(includedRoutes.count, 30, "\(testName): Should have comprehensive included routes")
        XCTAssertGreaterThan(excludedRoutes.count, 3, "\(testName): Should have proper excluded routes")
    }
    
    private func assertCorporateVPNRouting(
        includedRoutes: [IPAddressRange],
        excludedRoutes: [IPAddressRange],
        expectedDNSServers: [String],
        testName: String
    ) {
        let includedStrings = includedRoutes.map { $0.description }
        let excludedStrings = excludedRoutes.map { $0.description }
        
        // Verify DNS server routes (including internal DNS)
        for dnsRoute in expectedDNSServers {
            XCTAssertTrue(includedStrings.contains(dnsRoute), 
                         "\(testName): Should include DNS route \(dnsRoute)")
        }
        
        // Verify local network inclusion for corporate access
        XCTAssertTrue(includedStrings.contains("10.0.0.0/8"), 
                     "\(testName): Should include corporate network 10.0.0.0/8")
        XCTAssertTrue(includedStrings.contains("172.16.0.0/12"), 
                     "\(testName): Should include corporate network 172.16.0.0/12")
        XCTAssertTrue(includedStrings.contains("192.168.0.0/16"), 
                     "\(testName): Should include corporate network 192.168.0.0/16")
        
        // Verify system exclusions still apply
        XCTAssertTrue(excludedStrings.contains("127.0.0.0/8"), 
                     "\(testName): Should still exclude loopback")
        XCTAssertTrue(excludedStrings.contains("169.254.0.0/16"), 
                     "\(testName): Should still exclude link-local")
        
        // Verify local networks are NOT excluded in corporate mode
        XCTAssertFalse(excludedStrings.contains("10.0.0.0/8"), 
                      "\(testName): Should NOT exclude corporate networks")
        XCTAssertFalse(excludedStrings.contains("192.168.0.0/16"), 
                      "\(testName): Should NOT exclude corporate networks")
    }
    
    private func assertRoutingTableCompleteness(
        includedRoutes: [IPAddressRange],
        excludedRoutes: [IPAddressRange]
    ) {
        let includedStrings = includedRoutes.map { $0.description }
        let excludedStrings = excludedRoutes.map { $0.description }
        
        // Should cover major internet address space
        let majorPublicRanges = [
            "1.0.0.0/8", "8.0.0.0/7", "64.0.0.0/2", "128.0.0.0/3", "193.0.0.0/8"
        ]
        
        for range in majorPublicRanges {
            XCTAssertTrue(includedStrings.contains(range), 
                         "Should include major public range \(range)")
        }
        
        // Should exclude critical system ranges
        let criticalExclusions = [
            "127.0.0.0/8", "169.254.0.0/16", "224.0.0.0/4", "240.0.0.0/4"
        ]
        
        for exclusion in criticalExclusions {
            XCTAssertTrue(excludedStrings.contains(exclusion), 
                         "Should exclude critical system range \(exclusion)")
        }
        
        // Should have IPv6 coverage
        XCTAssertTrue(includedStrings.contains("::/0"), "Should include IPv6 default route")
        
        // Route counts should be reasonable
        XCTAssertGreaterThan(includedRoutes.count, 30, "Should have comprehensive route coverage")
        XCTAssertLessThan(includedRoutes.count, 200, "Should not have excessive routes")
    }
}
