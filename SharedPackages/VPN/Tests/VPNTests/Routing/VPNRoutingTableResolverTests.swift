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

    /// Verifies that critical system traffic (loopback, multicast, link-local) never goes through the VPN tunnel regardless of configuration
    func testSystemTrafficAlwaysStaysLocal() {
        // Test both configurations include system ranges
        let configurations = [
            (excludeLocal: true, description: "with exclude local networks"),
            (excludeLocal: false, description: "without exclude local networks")
        ]

        for config in configurations {

            let dnsServers = [DNSServer(address: IPv4Address("8.8.8.8")!)]
            let resolver = VPNRoutingTableResolver(
                dnsServers: dnsServers,
                excludeLocalNetworks: config.excludeLocal
            )

            let excludedRoutes = resolver.excludedRoutes
            let excludedStrings = excludedRoutes.map { $0.description }

            XCTAssertTrue(excludedStrings.contains("127.0.0.0/8"),
                         "Should always exclude loopback \(config.description)")
            XCTAssertTrue(excludedStrings.contains("169.254.0.0/16"),
                         "Should always exclude link-local \(config.description)")
            XCTAssertTrue(excludedStrings.contains("224.0.0.0/4"),
                         "Should always exclude multicast \(config.description)")
            XCTAssertTrue(excludedStrings.contains("240.0.0.0/4"),
                         "Should always exclude Class E \(config.description)")

        }
    }

    // MARK: - Included Routes Logic Tests

    /// Verifies that all public internet traffic is always routed through the VPN tunnel regardless of local network settings
    func testPublicInternetAlwaysUsesTunnel() {
        let configurations = [
            (excludeLocal: true, description: "with exclude local networks"),
            (excludeLocal: false, description: "without exclude local networks")
        ]

        for config in configurations {

            let dnsServers = [DNSServer(address: IPv4Address("8.8.8.8")!)]
            let resolver = VPNRoutingTableResolver(
                dnsServers: dnsServers,
                excludeLocalNetworks: config.excludeLocal
            )

            let includedRoutes = resolver.includedRoutes
            let includedStrings = includedRoutes.map { $0.description }

            XCTAssertTrue(includedStrings.contains("1.0.0.0/8"),
                         "Should always include 1.0.0.0/8 \(config.description)")
            XCTAssertTrue(includedStrings.contains("8.0.0.0/7"),
                         "Should always include 8.0.0.0/7 \(config.description)")
            XCTAssertTrue(includedStrings.contains("::/0"),
                         "Should always include IPv6 default route \(config.description)")

        }
    }

    // MARK: - DNS Routes Generation Tests

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

        let hasHostRoutes = includedRoutes.contains { route in
            route.networkPrefixLength == 32 &&
            !route.hasExactMatch(in: VPNRoutingRange.publicNetworkRange)
        }

        XCTAssertFalse(hasHostRoutes, "Should not have any /32 host routes when no DNS servers provided")

    }

}
