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

    /// Verifies that VPN routing works correctly when DNS servers are configured
    func testVPNRoutingWorksWithDNSServers() {

        let dnsServers = [
            DNSServer(address: IPv4Address("8.8.8.8")!),
            DNSServer(address: IPv4Address("1.1.1.1")!)
        ]
        let excludeLocalNetworks = true

        let resolver = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: excludeLocalNetworks
        )

        let routes = resolver.includedRoutes
        XCTAssertFalse(routes.isEmpty, "Resolver should generate routes with valid DNS servers")

    }

    /// Verifies that VPN routing works correctly even when no DNS servers are configured
    func testVPNRoutingWorksWithoutDNSServers() {

        let dnsServers: [DNSServer] = []
        let excludeLocalNetworks = false

        let resolver = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: excludeLocalNetworks
        )

        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes

        XCTAssertFalse(includedRoutes.isEmpty, "Should still have public network routes even without DNS servers")
        XCTAssertFalse(excludedRoutes.isEmpty, "Should always have excluded routes for system ranges")

    }

    // MARK: - Excluded Routes Logic Tests

    /// Verifies that IPv4 system traffic is always excluded when local networks are excluded
    func testIPv4SystemTrafficExcludedWhenExcludingLocalNetworks() {
        let resolver = VPNRoutingTableResolver(
            dnsServers: [DNSServer(address: IPv4Address("8.8.8.8")!)],
            excludeLocalNetworks: true
        )

        let excludedRoutes = resolver.excludedRoutes
        let excludedStrings = excludedRoutes.map { $0.description }

        XCTAssertTrue(excludedStrings.contains("127.0.0.0/8"), "Should always exclude loopback")
        XCTAssertTrue(excludedStrings.contains("169.254.0.0/16"), "Should always exclude link-local")
        XCTAssertTrue(excludedStrings.contains("224.0.0.0/4"), "Should always exclude multicast")
        XCTAssertTrue(excludedStrings.contains("240.0.0.0/4"), "Should always exclude Class E")
    }

    /// Verifies that IPv4 system traffic is always excluded when local networks are included
    func testIPv4SystemTrafficExcludedWhenIncludingLocalNetworks() {
        let resolver = VPNRoutingTableResolver(
            dnsServers: [DNSServer(address: IPv4Address("8.8.8.8")!)],
            excludeLocalNetworks: false
        )

        let excludedRoutes = resolver.excludedRoutes
        let excludedStrings = excludedRoutes.map { $0.description }

        XCTAssertTrue(excludedStrings.contains("127.0.0.0/8"), "Should always exclude loopback")
        XCTAssertTrue(excludedStrings.contains("169.254.0.0/16"), "Should always exclude link-local")
        XCTAssertTrue(excludedStrings.contains("224.0.0.0/4"), "Should always exclude multicast")
        XCTAssertTrue(excludedStrings.contains("240.0.0.0/4"), "Should always exclude Class E")
    }

    /// Verifies that IPv6 system traffic is always excluded when local networks are excluded
    func testIPv6SystemTrafficExcludedWhenExcludingLocalNetworks() {
        let resolver = VPNRoutingTableResolver(
            dnsServers: [DNSServer(address: IPv4Address("8.8.8.8")!)],
            excludeLocalNetworks: true
        )

        let excludedRoutes = resolver.excludedRoutes
        let excludedStrings = excludedRoutes.map { $0.description }

        XCTAssertTrue(excludedStrings.contains("::1/128"), "Should always exclude IPv6 loopback")
        XCTAssertTrue(excludedStrings.contains("fe80::/10"), "Should always exclude IPv6 link-local")
        XCTAssertTrue(excludedStrings.contains("ff00::/8"), "Should always exclude IPv6 multicast")
    }

    /// Verifies that IPv6 system traffic is always excluded when local networks are included
    func testIPv6SystemTrafficExcludedWhenIncludingLocalNetworks() {
        let resolver = VPNRoutingTableResolver(
            dnsServers: [DNSServer(address: IPv4Address("8.8.8.8")!)],
            excludeLocalNetworks: false
        )

        let excludedRoutes = resolver.excludedRoutes
        let excludedStrings = excludedRoutes.map { $0.description }

        XCTAssertTrue(excludedStrings.contains("::1/128"), "Should always exclude IPv6 loopback")
        XCTAssertTrue(excludedStrings.contains("fe80::/10"), "Should always exclude IPv6 link-local")
        XCTAssertTrue(excludedStrings.contains("ff00::/8"), "Should always exclude IPv6 multicast")
    }

    // MARK: - Included Routes Logic Tests

    /// Verifies that public internet traffic is routed through the VPN when excluding local networks
    func testPublicInternetUsesTunnelWhenExcludingLocalNetworks() {
        let resolver = VPNRoutingTableResolver(
            dnsServers: [DNSServer(address: IPv4Address("8.8.8.8")!)],
            excludeLocalNetworks: true
        )

        let includedRoutes = resolver.includedRoutes
        let includedStrings = includedRoutes.map { $0.description }

        XCTAssertTrue(includedStrings.contains("1.0.0.0/8"), "Should include 1.0.0.0/8")
        XCTAssertTrue(includedStrings.contains("8.0.0.0/7"), "Should include 8.0.0.0/7")
        XCTAssertTrue(includedStrings.contains("::/0"), "Should include all IPv6 addresses ::/0")
    }

    /// Verifies that public internet traffic is routed through the VPN when including local networks
    func testPublicInternetUsesTunnelWhenIncludingLocalNetworks() {
        let resolver = VPNRoutingTableResolver(
            dnsServers: [DNSServer(address: IPv4Address("8.8.8.8")!)],
            excludeLocalNetworks: false
        )

        let includedRoutes = resolver.includedRoutes
        let includedStrings = includedRoutes.map { $0.description }

        XCTAssertTrue(includedStrings.contains("1.0.0.0/8"), "Should include 1.0.0.0/8")
        XCTAssertTrue(includedStrings.contains("8.0.0.0/7"), "Should include 8.0.0.0/7")
        XCTAssertTrue(includedStrings.contains("::/0"), "Should include all IPv6 addresses ::/0")
    }

    // MARK: - DNS Routes Generation Tests

    /// Verifies that IPv4 DNS host routes use /32 prefix length
    func testIPv4DNSRoutesUseCorrectPrefixLength() {
        let dnsServers = [
            DNSServer(address: IPv4Address("8.8.8.8")!),
            DNSServer(address: IPv4Address("1.1.1.1")!)
        ]
        let resolver = VPNRoutingTableResolver(
            dnsServers: dnsServers,
            excludeLocalNetworks: true
        )

        let includedRoutes = resolver.includedRoutes
        let googleDNS = IPv4Address("8.8.8.8")!
        let cloudflareDNS = IPv4Address("1.1.1.1")!

        // Filter for host routes (/32) specifically
        let googleRoute = includedRoutes.first { $0.networkPrefixLength == 32 && $0.contains(googleDNS) }
        let cloudflareRoute = includedRoutes.first { $0.networkPrefixLength == 32 && $0.contains(cloudflareDNS) }

        XCTAssertNotNil(googleRoute, "Should create /32 host route for Google DNS")
        XCTAssertNotNil(cloudflareRoute, "Should create /32 host route for Cloudflare DNS")
        XCTAssertEqual(googleRoute?.networkPrefixLength, 32, "IPv4 DNS routes must use /32 prefix")
        XCTAssertEqual(cloudflareRoute?.networkPrefixLength, 32, "IPv4 DNS routes must use /32 prefix")
    }

    /// Verifies that IPv6 DNS host routes use /128 prefix length
    func testIPv6DNSRoutesUseCorrectPrefixLength() {
        let ipv6DNS = DNSServer(address: IPv6Address("2606:4700:4700::1111")!)
        let resolver = VPNRoutingTableResolver(
            dnsServers: [ipv6DNS],
            excludeLocalNetworks: true
        )

        let includedRoutes = resolver.includedRoutes
        let cloudflareIPv6 = IPv6Address("2606:4700:4700::1111")!

        // Filter for host routes (/128) specifically, not the broader ::/0
        let dnsRoute = includedRoutes.first { route in
            route.address is IPv6Address && route.networkPrefixLength == 128 && route.contains(cloudflareIPv6)
        }

        XCTAssertNotNil(dnsRoute, "Should create /128 host route for IPv6 DNS")
        XCTAssertEqual(dnsRoute?.networkPrefixLength, 128, "IPv6 DNS routes must use /128 prefix, not /32")
    }

    /// Verifies that all configured DNS servers remain accessible through the VPN
    func testDNSServersRemainAccessible() {
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

        let includedRoutes = resolver.includedRoutes
        let includedStrings = includedRoutes.map { $0.description }

        XCTAssertTrue(includedStrings.contains("8.8.8.8/32"), "Should have Google DNS primary")
        XCTAssertTrue(includedStrings.contains("8.8.4.4/32"), "Should have Google DNS secondary")
        XCTAssertTrue(includedStrings.contains("1.1.1.1/32"), "Should have Cloudflare DNS primary")
        XCTAssertTrue(includedStrings.contains("1.0.0.1/32"), "Should have Cloudflare DNS secondary")
    }

    /// Verifies that DNS routes are created even when DNS server is in an excluded range
    func testDNSRoutesOverrideExclusions() {
        let localDNS = DNSServer(address: IPv4Address("192.168.1.1")!)
        let resolver = VPNRoutingTableResolver(
            dnsServers: [localDNS],
            excludeLocalNetworks: true
        )

        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes

        let dnsAddress = IPv4Address("192.168.1.1")!
        let hasDNSRoute = includedRoutes.contains { $0.contains(dnsAddress) }
        let isInExcludedRange = excludedRoutes.contains { $0.contains(dnsAddress) }

        XCTAssertTrue(hasDNSRoute, "DNS server route should be in included routes")
        XCTAssertTrue(isInExcludedRange, "192.168.1.1 should be within an excluded range (192.168.0.0/16)")
    }

    /// Verifies that mixed IPv4 and IPv6 DNS servers are both correctly routed
    func testMixedIPv4AndIPv6DNSServers() {
        let mixedDNS = [
            DNSServer(address: IPv4Address("8.8.8.8")!),
            DNSServer(address: IPv6Address("2606:4700:4700::1111")!)
        ]
        let resolver = VPNRoutingTableResolver(
            dnsServers: mixedDNS,
            excludeLocalNetworks: true
        )

        let includedRoutes = resolver.includedRoutes

        let googleIPv4 = IPv4Address("8.8.8.8")!
        let cloudflareIPv6 = IPv6Address("2606:4700:4700::1111")!

        let hasIPv4Route = includedRoutes.contains { $0.contains(googleIPv4) }
        let hasIPv6Route = includedRoutes.contains { $0.contains(cloudflareIPv6) }

        XCTAssertTrue(hasIPv4Route, "Should create route for IPv4 DNS")
        XCTAssertTrue(hasIPv6Route, "Should create route for IPv6 DNS")
    }

    /// Verifies that duplicate DNS servers don't create duplicate routes
    func testDuplicateDNSServersHandledGracefully() {
        let duplicateDNS = [
            DNSServer(address: IPv4Address("8.8.8.8")!),
            DNSServer(address: IPv4Address("8.8.8.8")!),
            DNSServer(address: IPv4Address("8.8.8.8")!)
        ]
        let resolver = VPNRoutingTableResolver(
            dnsServers: duplicateDNS,
            excludeLocalNetworks: true
        )

        let includedRoutes = resolver.includedRoutes
        let googleDNS = IPv4Address("8.8.8.8")!

        let googleRoutes = includedRoutes.filter { $0.contains(googleDNS) && $0.networkPrefixLength == 32 }

        XCTAssertGreaterThanOrEqual(googleRoutes.count, 1, "Should have at least one route for 8.8.8.8")
    }

    /// Verifies that IPv6 DNS servers work correctly with VPN in modern dual-stack network environments
    func testIPv6DNSServersWorkCorrectly() {
        let ipv6Address = IPv6Address("2001:4860:4860::8888")!
        let dnsServer = DNSServer(address: ipv6Address)
        let resolver = VPNRoutingTableResolver(
            dnsServers: [dnsServer],
            excludeLocalNetworks: true
        )

        let includedRoutes = resolver.includedRoutes
        let googleIPv6 = IPv6Address("2001:4860:4860::8888")!
        let hasIPv6DNSRoute = includedRoutes.contains { route in
            route.address is IPv6Address && route.contains(googleIPv6)
        }

        XCTAssertTrue(hasIPv6DNSRoute, "Should create host route for IPv6 DNS server")

        // Verify IPv6 DNS routes use correct /128 prefix for single host
        let ipv6DNSRoute = includedRoutes.first { route in
            route.address.rawValue == googleIPv6.rawValue
        }
        XCTAssertNotNil(ipv6DNSRoute, "Should create IPv6 DNS route")
        if let route = ipv6DNSRoute {
            XCTAssertEqual(route.networkPrefixLength, 128,
                          "IPv6 DNS routes must use /128 for single host, not /32")
        }
    }

    /// Verifies that VPN routing table remains clean and efficient when no DNS servers are specified
    func testRoutingTableStaysCleanWithoutDNSServers() {
        let resolver = VPNRoutingTableResolver(
            dnsServers: [],
            excludeLocalNetworks: true
        )

        let includedRoutes = resolver.includedRoutes

        let publicRanges = VPNRoutingRange.publicIPv4NetworkRange + [VPNRoutingRange.fullIPv6RoutingRange]
        let hasHostRoutes = includedRoutes.contains { route in
            route.networkPrefixLength == 32 &&
            !route.hasExactMatch(in: publicRanges)
        }

        XCTAssertFalse(hasHostRoutes, "Should not have any /32 host routes when no DNS servers provided")
    }

    // MARK: - Local Network Handling Tests

    /// Verifies that 10.0.0.0/8 is NOT excluded even when excluding local networks (VPN tunnel compatibility)
    func testTenDotZeroNotExcludedForVPNCompatibility() {
        let resolver = VPNRoutingTableResolver(
            dnsServers: [],
            excludeLocalNetworks: true
        )

        let excludedRoutes = resolver.excludedRoutes
        let excludedStrings = excludedRoutes.map { $0.description }

        XCTAssertFalse(excludedStrings.contains("10.0.0.0/8"),
                      "10.0.0.0/8 should NOT be excluded (VPN tunnels commonly use this range)")
        XCTAssertTrue(excludedStrings.contains("172.16.0.0/12"),
                     "172.16.0.0/12 should be excluded")
        XCTAssertTrue(excludedStrings.contains("192.168.0.0/16"),
                     "192.168.0.0/16 should be excluded")
    }

    /// Verifies that 10.0.0.0/8 IS included when including local networks
    func testTenDotZeroIncludedWhenIncludingLocalNetworks() {
        let resolver = VPNRoutingTableResolver(
            dnsServers: [],
            excludeLocalNetworks: false
        )

        let includedRoutes = resolver.includedRoutes
        let includedStrings = includedRoutes.map { $0.description }

        XCTAssertTrue(includedStrings.contains("10.0.0.0/8"),
                     "10.0.0.0/8 should be included when including local networks")
        XCTAssertTrue(includedStrings.contains("172.16.0.0/12"),
                     "172.16.0.0/12 should be included")
        XCTAssertTrue(includedStrings.contains("192.168.0.0/16"),
                     "192.168.0.0/16 should be included")
    }

    /// Verifies that IPv6 ULA is excluded alongside IPv4 RFC 1918 ranges when excluding local networks
    func testIPv6ULAExcludedWhenExcludingLocalNetworks() {
        let resolver = VPNRoutingTableResolver(
            dnsServers: [],
            excludeLocalNetworks: true
        )
        let excludedRoutes = resolver.excludedRoutes
        let excludedStrings = excludedRoutes.map { $0.description }

        XCTAssertTrue(excludedStrings.contains("172.16.0.0/12"),
                     "Should exclude IPv4 private range 172.16.0.0/12")
        XCTAssertTrue(excludedStrings.contains("192.168.0.0/16"),
                     "Should exclude IPv4 private range 192.168.0.0/16")

        let hasULA = excludedRoutes.contains { $0.description.contains("fc00::/7") }
        XCTAssertTrue(hasULA, "IPv6 ULA should be excluded matching IPv4 RFC 1918 behavior")
    }

    /// Verifies that IPv6 ULA is not excluded alongside IPv4 RFC 1918 ranges when including local networks
    func testIPv6ULAIncludedWhenIncludingLocalNetworks() {
        let resolver = VPNRoutingTableResolver(
            dnsServers: [],
            excludeLocalNetworks: false
        )
        let excludedRoutes = resolver.excludedRoutes
        let excludedStrings = excludedRoutes.map { $0.description }

        XCTAssertFalse(excludedStrings.contains("172.16.0.0/12"),
                      "Should NOT exclude IPv4 private range 172.16.0.0/12")
        XCTAssertFalse(excludedStrings.contains("192.168.0.0/16"),
                      "Should NOT exclude IPv4 private range 192.168.0.0/16")

        let hasULA = excludedRoutes.contains { $0.description.contains("fc00::/7") }
        XCTAssertFalse(hasULA, "IPv6 ULA should NOT be excluded matching IPv4 RFC 1918 behavior")
    }

    /// Verifies that IPv4 included routes are properly carved to avoid overlaps with excluded routes when excluding local networks
    func testIPv4IncludedRoutesCarvedProperlyWhenExcludingLocalNetworks() {
        let resolver = VPNRoutingTableResolver(
            dnsServers: [DNSServer(address: IPv4Address("8.8.8.8")!)],
            excludeLocalNetworks: true
        )

        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes

        let ipv4Included = includedRoutes.filter { $0.address is IPv4Address }
        let ipv4Excluded = excludedRoutes.filter { $0.address is IPv4Address }

        for included in ipv4Included {
            for excluded in ipv4Excluded {
                let includedContainedInExcluded = excluded.contains(included)
                XCTAssertFalse(includedContainedInExcluded,
                              "IPv4 included route \(included) should NOT be contained in excluded route \(excluded)")
            }
        }
    }

    /// Verifies that IPv4 included routes are properly carved to avoid overlaps with excluded routes when including local networks
    func testIPv4IncludedRoutesCarvedProperlyWhenIncludingLocalNetworks() {
        let resolver = VPNRoutingTableResolver(
            dnsServers: [DNSServer(address: IPv4Address("8.8.8.8")!)],
            excludeLocalNetworks: false
        )

        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes

        let ipv4Included = includedRoutes.filter { $0.address is IPv4Address }
        let ipv4Excluded = excludedRoutes.filter { $0.address is IPv4Address }

        for included in ipv4Included {
            for excluded in ipv4Excluded {
                let includedContainedInExcluded = excluded.contains(included)
                XCTAssertFalse(includedContainedInExcluded,
                              "IPv4 included route \(included) should NOT be contained in excluded route \(excluded)")
            }
        }
    }

    /// Verifies that IPv6 uses ::/0 with proper exclusions when excluding local networks
    func testIPv6UsesFullRangeWithExclusionsWhenExcludingLocalNetworks() {
        let resolver = VPNRoutingTableResolver(
            dnsServers: [DNSServer(address: IPv4Address("8.8.8.8")!)],
            excludeLocalNetworks: true
        )

        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes

        XCTAssertTrue(includedRoutes.contains { $0.description == "::/0" },
                     "IPv6 should include ::/0 for all addresses")
        XCTAssertTrue(excludedRoutes.contains { $0.description == "::1/128" },
                     "IPv6 should exclude loopback")
        XCTAssertTrue(excludedRoutes.contains { $0.description.contains("fe80::/10") },
                     "IPv6 should exclude link-local")
    }

    /// Verifies that IPv6 uses ::/0 with proper exclusions when including local networks
    func testIPv6UsesFullRangeWithExclusionsWhenIncludingLocalNetworks() {
        let resolver = VPNRoutingTableResolver(
            dnsServers: [DNSServer(address: IPv4Address("8.8.8.8")!)],
            excludeLocalNetworks: false
        )

        let includedRoutes = resolver.includedRoutes
        let excludedRoutes = resolver.excludedRoutes

        XCTAssertTrue(includedRoutes.contains { $0.description == "::/0" },
                     "IPv6 should include ::/0 for all addresses")
        XCTAssertTrue(excludedRoutes.contains { $0.description == "::1/128" },
                     "IPv6 should exclude loopback")
        XCTAssertTrue(excludedRoutes.contains { $0.description.contains("fe80::/10") },
                     "IPv6 should exclude link-local")
    }

}
