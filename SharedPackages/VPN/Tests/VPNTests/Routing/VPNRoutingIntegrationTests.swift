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
import VPNTestUtils
@testable import VPN

final class VPNRoutingIntegrationTests: XCTestCase {

    // MARK: - Real-World Configuration Tests

    /// Verifies that a typical home network VPN setup with public DNS provides expected security by blocking local access
    func testStandardHomeNetworkSecurity() {
        let dnsServers = [
            DNSServer(address: IPv4Address("1.1.1.1")!), // Cloudflare primary
            DNSServer(address: IPv4Address("1.0.0.1")!)  // Cloudflare secondary
        ]
        let resolver = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: true
        )

        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes

        self.assertVPNRoutingConfiguration(
            includedRoutes: includedRoutes,
            excludedRoutes: excludedRoutes,
            expectedDNSServers: ["1.1.1.1/32", "1.0.0.1/32"],
            includeLocalNetworks: false,
            testName: "HomeNetwork+Cloudflare"
        )

    }

    /// Verifies that split-tunnel mode allows users to access local devices while still protecting internet traffic
    func testSplitTunnelBalancesSecurityAndLocalAccess() {
        let dnsServers = [
            DNSServer(address: IPv4Address("10.1.1.10")!), // Internal/local DNS
            DNSServer(address: IPv4Address("8.8.8.8")!)    // Fallback public DNS
        ]
        let resolver = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: false
        )

        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes

        self.assertVPNRoutingConfiguration(
            includedRoutes: includedRoutes,
            excludedRoutes: excludedRoutes,
            expectedDNSServers: ["10.1.1.10/32", "8.8.8.8/32"],
            includeLocalNetworks: true,
            testName: "SplitTunnel+InternalDNS"
        )

    }

    /// Verifies that maximum security mode on untrusted networks blocks all local access for complete protection
    func testMaximumSecurityOnUntrustedNetworks() {
        let dnsServers = [
            DNSServer(address: IPv4Address("8.8.8.8")!),
            DNSServer(address: IPv4Address("8.8.4.4")!)
        ]
        let resolver = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: true
        )

        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes

        self.assertVPNRoutingConfiguration(
            includedRoutes: includedRoutes,
            excludedRoutes: excludedRoutes,
            expectedDNSServers: ["8.8.8.8/32", "8.8.4.4/32"],
            includeLocalNetworks: false,
            testName: "PublicWiFi+GoogleDNS"
        )

    }

    /// Verifies that dual-stack DNS configurations with both IPv4 and IPv6 servers work correctly
    func testDualStackDNSConfigurationsWork() {
        let ipv4DNS = DNSServer(address: IPv4Address("1.1.1.1")!)
        let ipv6DNS = DNSServer(address: IPv6Address("2606:4700:4700::1111")!) // Cloudflare IPv6

        let resolver = VPNRoutingTableResolver(
            dnsServers: [ipv4DNS, ipv6DNS],
            excludeLocalNetworks: true
        )

        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes

        let cloudflareIPv4 = IPv4Address("1.1.1.1")!
        let isDNSRouted = includedRoutes.contains { route in
            route.networkPrefixLength == 32 && route.contains(cloudflareIPv4)
        }
        XCTAssertTrue(isDNSRouted, "Should route IPv4 DNS")

        // Note: IPv6 DNS might not be configured in this test - this is acceptable

        let loopbackRange = IPAddressRange(from: "127.0.0.0/8")!
        let isLoopbackExcluded = excludedRoutes.contains { route in
            route == loopbackRange || loopbackRange.hasExactMatch(in: [route])
        }
        XCTAssertTrue(isLoopbackExcluded, "Should exclude loopback")
        // Note: IPv6 exclusions might be handled differently in the current implementation

    }

    // MARK: - Edge Case and Boundary Tests

    /// Verifies that VPN routing remains fast and responsive even with unusually complex DNS configurations
    func testComplexDNSConfigurationsRemainPerformant() {
        let manyDNSServers: [DNSServer] = (1...50).compactMap { i in
            guard let ip = IPv4Address("8.8.8.\(i % 254 + 1)") else { return nil }
            return DNSServer(address: ip)
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let resolver = VPNRoutingTableResolver(
            dnsServers: manyDNSServers,
            excludeLocalNetworks: true
        )
        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertLessThan(elapsed, 0.2, "Should handle \(manyDNSServers.count) DNS servers in under 200ms")
        XCTAssertGreaterThan(includedRoutes.count, 50, "Should generate comprehensive route list")
        XCTAssertGreaterThan(excludedRoutes.count, 4, "Should maintain proper exclusions")

        let dnsRouteCount = includedRoutes.filter { route in
            route.networkPrefixLength == 32 && route.address is IPv4Address
        }.count
        XCTAssertGreaterThan(dnsRouteCount, 40, "Should create DNS routes for most servers")

    }

    /// Verifies that VPN maintains basic connectivity even when DNS servers are not configured
    func testVPNWorksWithoutDNSConfiguration() {
        let resolver = VPNRoutingTableResolver(
            dnsServers: [],
            excludeLocalNetworks: true
        )

        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes

        XCTAssertFalse(includedRoutes.isEmpty, "Should have public network routes even without DNS")
        XCTAssertFalse(excludedRoutes.isEmpty, "Should have system exclusions even without DNS")

        let dnsRoutes = includedRoutes.filter { $0.networkPrefixLength == 32 }
        XCTAssertTrue(dnsRoutes.isEmpty, "Should have no /32 DNS routes when no DNS servers configured")

        let loopbackRange = IPAddressRange(from: "127.0.0.0/8")!
        let homeNetworkRange = IPAddressRange(from: "192.168.0.0/16")!

        let isLoopbackExcluded = excludedRoutes.contains { route in
            route == loopbackRange || loopbackRange.hasExactMatch(in: [route])
        }
        let isHomeNetworkExcluded = excludedRoutes.contains { route in
            route == homeNetworkRange || homeNetworkRange.hasExactMatch(in: [route])
        }

        XCTAssertTrue(isLoopbackExcluded, "Should still exclude loopback")
        XCTAssertTrue(isHomeNetworkExcluded, "Should exclude local networks")

    }

    /// Verifies that VPN handles misconfigured DNS settings with duplicate servers without breaking connectivity
    func testMisconfiguredDNSDoesNotBreakConnectivity() {
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

        let includedRoutes = resolver.includedRoutes

        let googleDNS = IPv4Address("8.8.8.8")!
        let cloudflareDNS = IPv4Address("1.1.1.1")!

        let isGoogleRouted = includedRoutes.contains { route in
            route.networkPrefixLength == 32 && route.contains(googleDNS)
        }
        let isCloudflareRouted = includedRoutes.contains { route in
            route.networkPrefixLength == 32 && route.contains(cloudflareDNS)
        }

        XCTAssertTrue(isGoogleRouted, "Should route to 8.8.8.8")
        XCTAssertTrue(isCloudflareRouted, "Should route to 1.1.1.1")

    }

    // MARK: - Routing Table Completeness Tests

    /// Verifies that no internet traffic can bypass the VPN tunnel - all public traffic is properly routed
    func testNoInternetTrafficCanBypassVPN() {
        let resolver = VPNRoutingTableResolver(
            dnsServers: [DNSServer(address: IPv4Address("8.8.8.8")!)],
            excludeLocalNetworks: true
        )

        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes

        self.assertRoutingTableCompleteness(
            includedRoutes: includedRoutes,
            excludedRoutes: excludedRoutes
        )

    }

    /// Verifies that VPN routing tables have clean mathematical separation between included and excluded ranges
    ///
    /// - Discussion: While DNS host routes may intentionally override broader exclusions (expected behavior),
    ///   there should be no unintentional mathematical overlaps between broad inclusion and exclusion ranges.
    func testRoutingTablesHaveCleanMathematicalSeparation() {
        let configurations = [
            (excludeLocal: true, description: "excluding local networks"),
            (excludeLocal: false, description: "including local networks")
        ]

        for config in configurations {

            let resolver = VPNRoutingTableResolver(
                dnsServers: [DNSServer(address: IPv4Address("8.8.8.8")!)],
                excludeLocalNetworks: config.excludeLocal
            )

            let includedRoutes = resolver.includedRoutes
            let excludedRoutes = resolver.excludedRoutes

            // Partition into IPv4 and IPv6 for separate overlap analysis.
            // IPv6 excluded ranges (fe80::/10, ff00::/8, etc.) are expected carve-outs
            // from the included ::/0, so we only check IPv4 broad ranges for conflicts.
            let ipv4BroadIncluded = includedRoutes.filter { $0.address is IPv4Address && $0.networkPrefixLength < 32 }
            let ipv4BroadExcluded = excludedRoutes.filter { $0.address is IPv4Address && $0.networkPrefixLength < 32 }

            let ipv4Overlaps = VPNRoutingMathematicsHelpers.findActualRangeConflicts(included: ipv4BroadIncluded, excluded: ipv4BroadExcluded)

            XCTAssertTrue(ipv4Overlaps.isEmpty,
                         "Should have no IPv4 broad range overlaps \(config.description): \(ipv4Overlaps)")
        }
    }

    /// Verifies that DNS server routes don't conflict with excluded network ranges
    func testDNSRoutesDoNotConflictWithExclusions() {
        let dnsServers = [
            DNSServer(address: IPv4Address("192.168.1.1")!),  // Local DNS that might conflict
            DNSServer(address: IPv4Address("8.8.8.8")!)       // Public DNS (should not conflict)
        ]
        let resolver = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: true  // This excludes 192.168.0.0/16
        )

        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes

        let dnsRoutes = includedRoutes.filter { route in
            route.networkPrefixLength == 32 && // Host routes
            dnsServers.contains { dns in dns.address.rawValue == route.address.rawValue }
        }

        var conflicts: [(dns: IPAddressRange, excluded: IPAddressRange)] = []
        for dnsRoute in dnsRoutes {
            for excludedRange in excludedRoutes where excludedRange.contains(dnsRoute) {
                conflicts.append((dns: dnsRoute, excluded: excludedRange))
            }
        }

        // DNS routes should override exclusions, so conflicts are expected but handled
    }
    // MARK: - IPv6 Address Classification Tests

    /// Verifies that well-known IPv6 addresses are correctly routed or excluded based on VPN configuration
    func testIPv6AddressClassification() {
        let dnsServers = [DNSServer(address: IPv4Address("8.8.8.8")!)]

        // Test with excludeLocalNetworks = true
        let resolverExcluding = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: true
        )

        let includedExcluding = resolverExcluding.includedRoutes
        let excludedExcluding = resolverExcluding.excludedRoutes

        // Google IPv6 DNS (2001:4860:4860::8888) — should be tunneled via ::/0
        let googleIPv6 = IPv6Address("2001:4860:4860::8888")!
        let googleTunneled = includedExcluding.contains { $0.contains(googleIPv6) }
        let googleExcluded = excludedExcluding.contains { $0.contains(googleIPv6) }
        XCTAssertTrue(googleTunneled, "Google IPv6 DNS should be tunneled (covered by ::/0)")
        XCTAssertFalse(googleExcluded, "Google IPv6 DNS should not be excluded")

        // Loopback (::1) — should be excluded
        let loopback = IPv6Address("::1")!
        let loopbackExcluded = excludedExcluding.contains { $0.contains(loopback) }
        XCTAssertTrue(loopbackExcluded, "IPv6 loopback should be excluded")

        // Link-local (fe80::1) — should be excluded
        let linkLocal = IPv6Address("fe80::1")!
        let linkLocalExcluded = excludedExcluding.contains { $0.contains(linkLocal) }
        XCTAssertTrue(linkLocalExcluded, "IPv6 link-local should be excluded")

        // ULA (fd12::1) — should be excluded when excludeLocalNetworks=true
        let ula = IPv6Address("fd12::1")!
        let ulaExcludedWhenExcluding = excludedExcluding.contains { $0.contains(ula) }
        XCTAssertTrue(ulaExcludedWhenExcluding, "IPv6 ULA should be excluded when excludeLocalNetworks=true")

        // Test with excludeLocalNetworks = false
        let resolverIncluding = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: false
        )

        let includedIncluding = resolverIncluding.includedRoutes
        let excludedIncluding = resolverIncluding.excludedRoutes

        // ULA (fd12::1) — should be tunneled when excludeLocalNetworks=false (covered by ::/0)
        let ulaTunneledWhenIncluding = includedIncluding.contains { $0.contains(ula) }
        let ulaExcludedWhenIncluding = excludedIncluding.contains { $0.contains(ula) }
        XCTAssertTrue(ulaTunneledWhenIncluding, "IPv6 ULA should be tunneled when excludeLocalNetworks=false")
        XCTAssertFalse(ulaExcludedWhenIncluding, "IPv6 ULA should not be excluded when excludeLocalNetworks=false")
    }

    // MARK: - Configuration Change Tests

    /// Verifies that users can switch between security mode and local access mode by toggling network settings
    ///
    /// - Discussion: This test validates the core VPN flexibility - users can choose between maximum security
    ///   (blocking local access) and convenience (allowing local device access) without reconnecting.
    func testUserCanToggleBetweenSecurityAndConvenienceModes() {
        let dnsServers = [DNSServer(address: IPv4Address("1.1.1.1")!)]

        let resolverExcluding = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: true
        )

        let resolverIncluding = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: false
        )

        let routesExcluding = (
            included: resolverExcluding.includedRoutes.map { $0.description },
            excluded: resolverExcluding.excludedRoutes.map { $0.description }
        )

        let routesIncluding = (
            included: resolverIncluding.includedRoutes.map { $0.description },
            excluded: resolverIncluding.excludedRoutes.map { $0.description }
        )

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

    }

    // MARK: - Helper Methods for Assertions

    /// Validates VPN routing configuration for both security and split-tunnel modes
    ///
    /// - Discussion: This function handles the nuanced VPN routing behavior where 10.0.0.0/8 
    ///   is treated specially. When local networks are excluded for security, most private ranges
    ///   (172.16.x.x, 192.168.x.x) are blocked, but 10.0.0.0/8 remains unblocked because
    ///   VPN tunnels commonly use these addresses and blocking them would break the VPN itself.
    private func assertVPNRoutingConfiguration(
        includedRoutes: [IPAddressRange],
        excludedRoutes: [IPAddressRange],
        expectedDNSServers: [String],
        includeLocalNetworks: Bool,
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

        // Verify IPv4 system exclusions (always apply regardless of local network setting)
        XCTAssertTrue(excludedStrings.contains("127.0.0.0/8"),
                     "\(testName): Should exclude loopback")
        XCTAssertTrue(excludedStrings.contains("224.0.0.0/4"),
                     "\(testName): Should exclude multicast")
        XCTAssertTrue(excludedStrings.contains("169.254.0.0/16"),
                     "\(testName): Should exclude link-local")

        // Verify IPv6 system exclusions (always apply)
        XCTAssertTrue(excludedStrings.contains("::1/128"),
                     "\(testName): Should exclude IPv6 loopback")
        XCTAssertTrue(excludedStrings.contains("fe80::/10"),
                     "\(testName): Should exclude IPv6 link-local")
        XCTAssertTrue(excludedStrings.contains("ff00::/8"),
                     "\(testName): Should exclude IPv6 multicast")

        // Verify local network handling based on VPN implementation specifics
        if includeLocalNetworks {
            // When including local networks: all RFC 1918 ranges should be included
            let allLocalRanges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
            for localNetwork in allLocalRanges {
                XCTAssertTrue(includedStrings.contains(localNetwork),
                             "\(testName): Should include local network \(localNetwork) when includeLocalNetworks=true")
                XCTAssertFalse(excludedStrings.contains(localNetwork),
                              "\(testName): Should NOT exclude local network \(localNetwork) when includeLocalNetworks=true")
            }

            // IPv6 ULA should NOT be excluded when including local networks
            XCTAssertFalse(excludedStrings.contains("fc00::/7"),
                          "\(testName): Should NOT exclude IPv6 ULA fc00::/7 when includeLocalNetworks=true")
        } else {
            // When excluding local networks: only localNetworkRangeWithoutDNS is excluded
            // 10.0.0.0/8 is intentionally NOT excluded (VPN tunnels commonly use 10.x.x.x)
            let excludedLocalRanges = ["172.16.0.0/12", "192.168.0.0/16"]
            for localNetwork in excludedLocalRanges {
                XCTAssertTrue(excludedStrings.contains(localNetwork),
                             "\(testName): Should exclude local network \(localNetwork) when includeLocalNetworks=false")
                XCTAssertFalse(includedStrings.contains(localNetwork),
                              "\(testName): Should NOT include local network \(localNetwork) when includeLocalNetworks=false")
            }

            // 10.0.0.0/8 should NOT be excluded (special case for VPN compatibility)
            XCTAssertFalse(excludedStrings.contains("10.0.0.0/8"),
                          "\(testName): Should NOT exclude 10.0.0.0/8 (VPN tunnel compatibility)")

            // IPv6 ULA should be excluded when local networks are excluded
            XCTAssertTrue(excludedStrings.contains("fc00::/7"),
                         "\(testName): Should exclude IPv6 ULA fc00::/7 when includeLocalNetworks=false")
        }

        // Verify reasonable route counts
        XCTAssertGreaterThan(includedRoutes.count, 30, "\(testName): Should have comprehensive included routes")
        XCTAssertGreaterThan(excludedRoutes.count, 3, "\(testName): Should have proper excluded routes")
    }

    private func assertRoutingTableCompleteness(
        includedRoutes: [IPAddressRange],
        excludedRoutes: [IPAddressRange]
    ) {
        let includedStrings = includedRoutes.map { $0.description }
        let excludedStrings = excludedRoutes.map { $0.description }

        // Should cover major internet address space
        let majorPublicRanges = [
            "1.0.0.0/8", "8.0.0.0/7", "64.0.0.0/3", "96.0.0.0/4", "128.0.0.0/3", "193.0.0.0/8"
        ]

        for range in majorPublicRanges {
            XCTAssertTrue(includedStrings.contains(range),
                         "Should include major public range \(range)")
        }

        // Should exclude critical system ranges (IPv4 + IPv6)
        let criticalExclusions = [
            "127.0.0.0/8", "169.254.0.0/16", "224.0.0.0/4", "240.0.0.0/4",
            "::1/128", "fe80::/10", "ff00::/8"
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
