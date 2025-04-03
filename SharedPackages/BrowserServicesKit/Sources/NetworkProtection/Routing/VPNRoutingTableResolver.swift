//
//  VPNRoutingTableResolver.swift
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
import Network
import os.log

/// Owns the responsibility of defining the routing table for the VPN.
///
/// This class is a bit limited in scope right now and only combines ``VPNSettings``
/// routing rules with the DNS settings, which can only be known with certainty at connection-time.
/// This class could be extended in the future to also factor in provider configurations, since
/// those are not taken into account in ``VPNSettings``.
///
struct VPNRoutingTableResolver {

    private let dnsServers: [DNSServer]
    private let excludeLocalNetworks: Bool

    init(dnsServers: [DNSServer],
         excludeLocalNetworks: Bool) {

        self.dnsServers = dnsServers
        self.excludeLocalNetworks = excludeLocalNetworks
    }

    var excludedRoutes: [IPAddressRange] {
        var routes = VPNRoutingRange.alwaysExcludedIPv4Range

        if excludeLocalNetworks {
            routes += VPNRoutingRange.localNetworkRangeWithoutDNS
        }

        return routes
    }

    var includedRoutes: [IPAddressRange] {
        var routes = VPNRoutingRange.publicNetworkRange + dnsRoutes()

        if !excludeLocalNetworks {
            routes += VPNRoutingRange.localNetworkRange
        }

        return routes
    }

    // MARK: - Included Routes

    private func dnsRoutes() -> [IPAddressRange] {
        dnsServers.map { server in
            return IPAddressRange(address: server.address, networkPrefixLength: 32)
        }
    }
}
