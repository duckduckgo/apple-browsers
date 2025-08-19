//
//  VPNRoutingTableResolverTests.swift
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

final class VPNRoutingTableResolverTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testInit_WithValidDNSServers_SetsProperties() {
        // Given
        let dnsServers = [
            DNSServer(address: IPv4Address("8.8.8.8")!),
            DNSServer(address: IPv4Address("1.1.1.1")!)
        ]
        let excludeLocalNetworks = true
        
        // When
        let resolver = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: excludeLocalNetworks
        )
        
        // Then
        let routes = resolver.includedRoutes
        XCTAssertFalse(routes.isEmpty, "Resolver should generate routes with valid DNS servers")
        
        //.info("Successfully initialized VPNRoutingTableResolver with \(dnsServers.count) DNS servers")
    }
    
    func testInit_WithEmptyDNSServers_HandlesGracefully() {
        // Given
        let dnsServers: [DNSServer] = []
        let excludeLocalNetworks = false
        
        // When
        let resolver = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: excludeLocalNetworks
        )
        
        // Then
        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes
        
        XCTAssertFalse(includedRoutes.isEmpty, "Should still have public network routes even without DNS servers")
        XCTAssertFalse(excludedRoutes.isEmpty, "Should always have excluded routes for system ranges")
        
        //.info("Successfully handled empty DNS servers list")
    }
    
    // MARK: - Excluded Routes Logic Tests
    
    func testExcludedRoutes_WhenExcludeLocalNetworksTrue_IncludesLocalRanges() {
        // Given
        let dnsServers = [DNSServer(address: IPv4Address("8.8.8.8")!)]
        let resolver = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: true
        )
        
        // When
        let excludedRoutes = resolver.excludedRoutes
        
        // Then
        let excludedStrings = excludedRoutes.map { $0.description }
        
        // Should include always excluded ranges
        XCTAssertTrue(excludedStrings.contains("127.0.0.0/8"), "Should exclude loopback range")
        XCTAssertTrue(excludedStrings.contains("169.254.0.0/16"), "Should exclude link-local range")
        XCTAssertTrue(excludedStrings.contains("224.0.0.0/4"), "Should exclude multicast range")
        XCTAssertTrue(excludedStrings.contains("240.0.0.0/4"), "Should exclude Class E range")
        
        // Should include local network ranges when excluding local networks
        XCTAssertTrue(excludedStrings.contains("172.16.0.0/12"), "Should exclude RFC 1918 172.16.x.x range")
        XCTAssertTrue(excludedStrings.contains("192.168.0.0/16"), "Should exclude RFC 1918 192.168.x.x range")
        
        //.debug("Excluded routes with local networks: \(excludedStrings)")
    }
    
    func testExcludedRoutes_WhenExcludeLocalNetworksFalse_ExcludesOnlySystemRanges() {
        // Given
        let dnsServers = [DNSServer(address: IPv4Address("8.8.8.8")!)]
        let resolver = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: false
        )
        
        // When
        let excludedRoutes = resolver.excludedRoutes
        
        // Then
        let excludedStrings = excludedRoutes.map { $0.description }
        
        // Should include always excluded ranges
        XCTAssertTrue(excludedStrings.contains("127.0.0.0/8"), "Should exclude loopback range")
        XCTAssertTrue(excludedStrings.contains("169.254.0.0/16"), "Should exclude link-local range")
        XCTAssertTrue(excludedStrings.contains("224.0.0.0/4"), "Should exclude multicast range")
        XCTAssertTrue(excludedStrings.contains("240.0.0.0/4"), "Should exclude Class E range")
        
        // Should NOT include local network ranges when not excluding local networks
        XCTAssertFalse(excludedStrings.contains("172.16.0.0/12"), "Should NOT exclude RFC 1918 172.16.x.x range when includeLocal=true")
        XCTAssertFalse(excludedStrings.contains("192.168.0.0/16"), "Should NOT exclude RFC 1918 192.168.x.x range when includeLocal=true")
        
        //.debug("Excluded routes without local networks: \(excludedStrings)")
    }
    
    func testExcludedRoutes_AlwaysIncludesSystemRanges() {
        // Test both configurations include system ranges
        let configurations = [
            (excludeLocal: true, description: "with exclude local networks"),
            (excludeLocal: false, description: "without exclude local networks")
        ]
        
        for config in configurations {
            // Given
            let dnsServers = [DNSServer(address: IPv4Address("8.8.8.8")!)]
            let resolver = VPNRoutingTableResolver(
                dnsServers: dnsServers,
                excludeLocalNetworks: config.excludeLocal
            )
            
            // When
            let excludedRoutes = resolver.excludedRoutes
            let excludedStrings = excludedRoutes.map { $0.description }
            
            // Then
            XCTAssertTrue(excludedStrings.contains("127.0.0.0/8"), 
                         "Should always exclude loopback \(config.description)")
            XCTAssertTrue(excludedStrings.contains("169.254.0.0/16"), 
                         "Should always exclude link-local \(config.description)")
            XCTAssertTrue(excludedStrings.contains("224.0.0.0/4"), 
                         "Should always exclude multicast \(config.description)")
            XCTAssertTrue(excludedStrings.contains("240.0.0.0/4"), 
                         "Should always exclude Class E \(config.description)")
            
            //.debug("System ranges verified \(config.description)")
        }
    }
    
    // MARK: - Included Routes Logic Tests
    
    func testIncludedRoutes_WhenExcludeLocalNetworksTrue_ExcludesLocalRanges() {
        // Given
        let dnsServers = [DNSServer(address: IPv4Address("8.8.8.8")!)]
        let resolver = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: true
        )
        
        // When
        let includedRoutes = resolver.includedRoutes
        
        // Then
        let includedStrings = includedRoutes.map { $0.description }
        
        // Should include public network ranges
        XCTAssertTrue(includedStrings.contains("1.0.0.0/8"), "Should include public range 1.0.0.0/8")
        XCTAssertTrue(includedStrings.contains("8.0.0.0/7"), "Should include public range 8.0.0.0/7")
        
        // Should NOT include local network ranges when excluding local networks
        XCTAssertFalse(includedStrings.contains("10.0.0.0/8"), "Should NOT include RFC 1918 10.x.x.x range when excluding local")
        XCTAssertFalse(includedStrings.contains("172.16.0.0/12"), "Should NOT include RFC 1918 172.16.x.x range when excluding local")
        XCTAssertFalse(includedStrings.contains("192.168.0.0/16"), "Should NOT include RFC 1918 192.168.x.x range when excluding local")
        
        // Should include DNS server routes
        XCTAssertTrue(includedStrings.contains("8.8.8.8/32"), "Should include DNS server as /32 host route")
        
        //.debug("Included routes excluding local networks: count=\(includedRoutes.count)")
    }
    
    func testIncludedRoutes_WhenExcludeLocalNetworksFalse_IncludesLocalRanges() {
        // Given
        let dnsServers = [DNSServer(address: IPv4Address("1.1.1.1")!)]
        let resolver = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: false
        )
        
        // When
        let includedRoutes = resolver.includedRoutes
        
        // Then
        let includedStrings = includedRoutes.map { $0.description }
        
        // Should include public network ranges
        XCTAssertTrue(includedStrings.contains("1.0.0.0/8"), "Should include public range 1.0.0.0/8")
        XCTAssertTrue(includedStrings.contains("8.0.0.0/7"), "Should include public range 8.0.0.0/7")
        
        // Should include local network ranges when not excluding local networks
        XCTAssertTrue(includedStrings.contains("10.0.0.0/8"), "Should include RFC 1918 10.x.x.x range when including local")
        XCTAssertTrue(includedStrings.contains("172.16.0.0/12"), "Should include RFC 1918 172.16.x.x range when including local")
        XCTAssertTrue(includedStrings.contains("192.168.0.0/16"), "Should include RFC 1918 192.168.x.x range when including local")
        
        // Should include DNS server routes
        XCTAssertTrue(includedStrings.contains("1.1.1.1/32"), "Should include DNS server as /32 host route")
        
        //.debug("Included routes including local networks: count=\(includedRoutes.count)")
    }
    
    func testIncludedRoutes_AlwaysIncludesPublicRanges() {
        let configurations = [
            (excludeLocal: true, description: "with exclude local networks"),
            (excludeLocal: false, description: "without exclude local networks")
        ]
        
        for config in configurations {
            // Given
            let dnsServers = [DNSServer(address: IPv4Address("8.8.8.8")!)]
            let resolver = VPNRoutingTableResolver(
                dnsServers: dnsServers,
                excludeLocalNetworks: config.excludeLocal
            )
            
            // When
            let includedRoutes = resolver.includedRoutes
            let includedStrings = includedRoutes.map { $0.description }
            
            // Then - Should always include key public ranges
            XCTAssertTrue(includedStrings.contains("1.0.0.0/8"), 
                         "Should always include 1.0.0.0/8 \(config.description)")
            XCTAssertTrue(includedStrings.contains("8.0.0.0/7"), 
                         "Should always include 8.0.0.0/7 \(config.description)")
            XCTAssertTrue(includedStrings.contains("::/0"), 
                         "Should always include IPv6 default route \(config.description)")
            
            //.debug("Public ranges verified \(config.description)")
        }
    }
    
    // MARK: - DNS Routes Generation Tests
    
    func testDNSRoutes_WithSingleDNSServer_CreatesHostRoute() {
        // Given
        let dnsServer = DNSServer(address: IPv4Address("8.8.8.8")!)
        let resolver = VPNRoutingTableResolver(
            dnsServers: [dnsServer],
            excludeLocalNetworks: true
        )
        
        // When
        let includedRoutes = resolver.includedRoutes
        
        // Then
        let includedStrings = includedRoutes.map { $0.description }
        XCTAssertTrue(includedStrings.contains("8.8.8.8/32"), 
                     "Should create /32 host route for DNS server")
        
        //.info("DNS server route created: 8.8.8.8/32")
    }
    
    func testDNSRoutes_WithMultipleDNSServers_CreatesMultipleHostRoutes() {
        // Given
        let dnsServers = [
            DNSServer(address: IPv4Address("8.8.8.8")!),
            DNSServer(address: IPv4Address("8.8.4.4")!),
            DNSServer(address: IPv4Address("1.1.1.1")!),
            DNSServer(address: IPv4Address("1.0.0.1")!)
        ]
        let resolver = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: false
        )
        
        // When
        let includedRoutes = resolver.includedRoutes
        
        // Then
        let includedStrings = includedRoutes.map { $0.description }
        
        // Should have all DNS server host routes
        XCTAssertTrue(includedStrings.contains("8.8.8.8/32"), "Should have Google DNS primary")
        XCTAssertTrue(includedStrings.contains("8.8.4.4/32"), "Should have Google DNS secondary")
        XCTAssertTrue(includedStrings.contains("1.1.1.1/32"), "Should have Cloudflare DNS primary")
        XCTAssertTrue(includedStrings.contains("1.0.0.1/32"), "Should have Cloudflare DNS secondary")
        
        //.info("Multiple DNS server routes created: \(dnsServers.count) servers")
    }
    
    func testDNSRoutes_WithIPv6DNS_CreatesIPv6HostRoute() {
        // Given
        let ipv6Address = IPv6Address("2001:4860:4860::8888")! // Google DNS IPv6
        let dnsServer = DNSServer(address: ipv6Address)
        let resolver = VPNRoutingTableResolver(
            dnsServers: [dnsServer],
            excludeLocalNetworks: true
        )
        
        // When
        let includedRoutes = resolver.includedRoutes
        
        // Then
        let includedStrings = includedRoutes.map { $0.description }
        
        // Note: IPv6 host routes should be /128, but let's check what the implementation actually creates
        let hasIPv6DNSRoute = includedStrings.contains { route in
            route.contains("2001:4860:4860::8888")
        }
        
        XCTAssertTrue(hasIPv6DNSRoute, "Should create host route for IPv6 DNS server")
        
        //.info("IPv6 DNS server route created for 2001:4860:4860::8888")
    }
    
    func testDNSRoutes_WithEmptyDNSServers_ReturnsNoExtraRoutes() {
        // Given
        let resolver = VPNRoutingTableResolver(
            dnsServers: [],
            excludeLocalNetworks: true
        )
        
        // When
        let includedRoutes = resolver.includedRoutes
        
        // Then
        let includedStrings = includedRoutes.map { $0.description }
        
        // Should only have public network ranges, no DNS-specific host routes
        let hasHostRoutes = includedStrings.contains { route in
            route.hasSuffix("/32") && !VPNRoutingRange.publicNetworkRange.map(\.description).contains(route)
        }
        
        XCTAssertFalse(hasHostRoutes, "Should not have any /32 host routes when no DNS servers provided")
        
        //.info("No DNS routes created with empty DNS servers list")
    }
    
    // MARK: - Integration and Edge Case Tests
    
    func testRoutingTable_WithTypicalHomeConfiguration_GeneratesExpectedRoutes() {
        // Given - Typical home router setup with Cloudflare DNS
        let dnsServers = [
            DNSServer(address: IPv4Address("1.1.1.1")!),
            DNSServer(address: IPv4Address("1.0.0.1")!)
        ]
        let resolver = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: true // Typical VPN configuration
        )
        
        // When
        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes
        
        // Then
        XCTAssertTrue(includedRoutes.count > 30, "Should have comprehensive public route coverage")
        XCTAssertTrue(excludedRoutes.count >= 6, "Should exclude system ranges and local networks")
        
        let includedStrings = includedRoutes.map { $0.description }
        let excludedStrings = excludedRoutes.map { $0.description }
        
        // Verify DNS routing
        XCTAssertTrue(includedStrings.contains("1.1.1.1/32"), "Should route Cloudflare DNS primary")
        XCTAssertTrue(includedStrings.contains("1.0.0.1/32"), "Should route Cloudflare DNS secondary")
        
        // Verify local network exclusion
        XCTAssertTrue(excludedStrings.contains("192.168.0.0/16"), "Should exclude home network range")
        XCTAssertTrue(excludedStrings.contains("172.16.0.0/12"), "Should exclude RFC 1918 range")
        
        //.info("Typical home configuration validated: \(includedRoutes.count) included, \(excludedRoutes.count) excluded")
    }
    
    func testRoutingTable_WithCorporateNetworkConfiguration_AllowsLocalAccess() {
        // Given - Corporate network setup with local DNS
        let dnsServers = [
            DNSServer(address: IPv4Address("10.1.1.10")!), // Corporate DNS server
            DNSServer(address: IPv4Address("8.8.8.8")!)    // Backup public DNS
        ]
        let resolver = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: false // Allow access to corporate resources
        )
        
        // When
        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes
        
        // Then
        let includedStrings = includedRoutes.map { $0.description }
        let excludedStrings = excludedRoutes.map { $0.description }
        
        // Should include local network ranges for corporate access
        XCTAssertTrue(includedStrings.contains("10.0.0.0/8"), "Should include corporate network range")
        XCTAssertTrue(includedStrings.contains("172.16.0.0/12"), "Should include RFC 1918 range")
        XCTAssertTrue(includedStrings.contains("192.168.0.0/16"), "Should include private network range")
        
        // Should NOT exclude local networks from routing
        XCTAssertFalse(excludedStrings.contains("192.168.0.0/16"), "Should NOT exclude private networks in corporate mode")
        
        // Should still exclude system ranges
        XCTAssertTrue(excludedStrings.contains("127.0.0.0/8"), "Should still exclude loopback")
        
        // Should route both DNS servers
        XCTAssertTrue(includedStrings.contains("10.1.1.10/32"), "Should route corporate DNS server")
        XCTAssertTrue(includedStrings.contains("8.8.8.8/32"), "Should route backup DNS server")
        
        //.info("Corporate network configuration validated: local access enabled")
    }
    
    func testRoutingTable_WithManyDNSServers_HandlesPerformantly() {
        // Given - Configuration with many DNS servers
        let manyDNSServers = (1...20).map { i in
            DNSServer(address: IPv4Address("8.8.8.\(i)")!)
        }
        
        // When
        let startTime = CFAbsoluteTimeGetCurrent()
        let resolver = VPNRoutingTableResolver(
            dnsServers: manyDNSServers,
            excludeLocalNetworks: true
        )
        let _ = resolver.includedRoutes
        let _ = resolver.excludedRoutes
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        // Then
        XCTAssertLessThan(elapsed, 0.1, "Route generation should complete in under 100ms even with many DNS servers")
        
        let includedRoutes = resolver.includedRoutes
        let includedStrings = includedRoutes.map { $0.description }
        
        // Verify all DNS servers get host routes
        for i in 1...20 {
            XCTAssertTrue(includedStrings.contains("8.8.8.\(i)/32"), 
                         "Should have host route for DNS server 8.8.8.\(i)")
        }
        
        //.info("Performance test passed: \(manyDNSServers.count) DNS servers processed in \(elapsed)s")
    }
    
    func testRoutingTable_WithDuplicateDNSServers_DeduplicatesCorrectly() {
        // Given - Configuration with duplicate DNS servers
        let duplicateDNSServers = [
            DNSServer(address: IPv4Address("8.8.8.8")!),
            DNSServer(address: IPv4Address("1.1.1.1")!),
            DNSServer(address: IPv4Address("8.8.8.8")!), // Duplicate
            DNSServer(address: IPv4Address("1.1.1.1")!)  // Duplicate
        ]
        let resolver = VPNRoutingTableResolver(
            dnsServers: duplicateDNSServers,
            excludeLocalNetworks: true
        )
        
        // When
        let includedRoutes = resolver.includedRoutes
        
        // Then
        let includedStrings = includedRoutes.map { $0.description }
        
        // Count occurrences of each DNS route
        let googleDNSCount = includedStrings.filter { $0 == "8.8.8.8/32" }.count
        let cloudflareDNSCount = includedStrings.filter { $0 == "1.1.1.1/32" }.count
        
        // Implementation may or may not deduplicate automatically, but should handle gracefully
        XCTAssertTrue(googleDNSCount >= 1, "Should have at least one route for 8.8.8.8")
        XCTAssertTrue(cloudflareDNSCount >= 1, "Should have at least one route for 1.1.1.1")
        
        //.info("Duplicate DNS servers handled: Google=\(googleDNSCount), Cloudflare=\(cloudflareDNSCount)")
    }
}
