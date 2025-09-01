// SPDX-License-Identifier: MIT
// Copyright © 2018-2021 WireGuard LLC. All Rights Reserved.

import Foundation
import Network
import NetworkExtension
import Common
import os.log

/// A type alias for `Result` type that holds a tuple with source and resolved endpoint.
typealias EndpointResolutionResult = Result<(Endpoint, Endpoint), DNSResolutionError>

final class PacketTunnelSettingsGenerator {
    let tunnelConfiguration: TunnelConfiguration
    let resolvedEndpoints: [Endpoint?]

    init(tunnelConfiguration: TunnelConfiguration, resolvedEndpoints: [Endpoint?]) {
        self.tunnelConfiguration = tunnelConfiguration
        self.resolvedEndpoints = resolvedEndpoints
    }

    func endpointUapiConfiguration() -> (String, [EndpointResolutionResult?]) {
        var resolutionResults = [EndpointResolutionResult?]()
        var wgSettings = ""

        assert(tunnelConfiguration.peers.count == resolvedEndpoints.count)
        for (peer, resolvedEndpoint) in zip(self.tunnelConfiguration.peers, self.resolvedEndpoints) {
            wgSettings.append("public_key=\(peer.publicKey.hexKey)\n")

            let result = resolvedEndpoint.map(Self.reresolveEndpoint)
            if case .success((_, let resolvedEndpoint)) = result {
                if case .name = resolvedEndpoint.host { assert(false, "Endpoint is not resolved") }
                wgSettings.append("endpoint=\(resolvedEndpoint)\n")
            }
            resolutionResults.append(result)
        }

        return (wgSettings, resolutionResults)
    }

    func uapiConfiguration() -> (String, [EndpointResolutionResult?]) {
        var resolutionResults = [EndpointResolutionResult?]()
        var wgSettings = ""
        wgSettings.append("private_key=\(tunnelConfiguration.interface.privateKey.hexKey)\n")
        if let listenPort = tunnelConfiguration.interface.listenPort {
            wgSettings.append("listen_port=\(listenPort)\n")
        }
        if !tunnelConfiguration.peers.isEmpty {
            wgSettings.append("replace_peers=true\n")
        }
        assert(tunnelConfiguration.peers.count == resolvedEndpoints.count)
        for (peer, resolvedEndpoint) in zip(self.tunnelConfiguration.peers, self.resolvedEndpoints) {
            wgSettings.append("public_key=\(peer.publicKey.hexKey)\n")
            if let preSharedKey = peer.preSharedKey?.hexKey {
                wgSettings.append("preshared_key=\(preSharedKey)\n")
            }

            let result = resolvedEndpoint.map(Self.reresolveEndpoint)
            if case .success((_, let resolvedEndpoint)) = result {
                if case .name = resolvedEndpoint.host { assert(false, "Endpoint is not resolved") }
                wgSettings.append("endpoint=\(resolvedEndpoint)\n")
            }
            resolutionResults.append(result)

            let persistentKeepAlive = peer.persistentKeepAlive ?? 0
            wgSettings.append("persistent_keepalive_interval=\(persistentKeepAlive)\n")
            if !peer.allowedIPs.isEmpty {
                wgSettings.append("replace_allowed_ips=true\n")
                peer.allowedIPs.forEach { wgSettings.append("allowed_ip=\($0.stringRepresentation)\n") }
            }
        }
        return (wgSettings, resolutionResults)
    }

    func generateNetworkSettings() -> NEPacketTunnelNetworkSettings {
        /* iOS requires a tunnel endpoint, whereas in WireGuard it's valid for
         * a tunnel to have no endpoint, or for there to be many endpoints, in
         * which case, displaying a single one in settings doesn't really
         * make sense. So, we fill it in with this placeholder, which is not
         * a valid IP address that will actually route over the Internet.
         */
        let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        if !tunnelConfiguration.interface.dnsSearch.isEmpty || !tunnelConfiguration.interface.dns.isEmpty {
            let dnsServerStrings = tunnelConfiguration.interface.dns.map { $0.stringRepresentation }
            let dnsSettings = NEDNSSettings(servers: dnsServerStrings)
            dnsSettings.searchDomains = tunnelConfiguration.interface.dnsSearch
            if !tunnelConfiguration.interface.dns.isEmpty {
                dnsSettings.matchDomains = [""] // All DNS queries must first go through the tunnel's DNS
            }
            networkSettings.dnsSettings = dnsSettings
        } else {
            networkSettings.dnsSettings = NEDNSSettings(servers: ["10.11.12.1"])
        }

        let mtu = tunnelConfiguration.interface.mtu ?? 0

        /* 0 means automatic MTU. In theory, we should just do
         * `networkSettings.tunnelOverheadBytes = 80` but in
         * practice there are too many broken networks out there.
         * Instead set it to 1280. Boohoo. Maybe someday we'll
         * add a nob, maybe, or iOS will do probing for us.
         */
        if mtu == 0 {
            #if os(iOS)
            networkSettings.mtu = NSNumber(value: 1280)
            #elseif os(macOS)
            networkSettings.tunnelOverheadBytes = 80
            #else
            #error("Unimplemented")
            #endif
        } else {
            networkSettings.mtu = NSNumber(value: mtu)
        }

        let addresses = Self.routes(from: tunnelConfiguration.interface.addresses)
        let includedRoutes = Self.routes(from: tunnelConfiguration.interface.includedRoutes)
        let excludedRoutes = Self.routes(from: tunnelConfiguration.interface.excludedRoutes)

        let ipv4Settings = NEIPv4Settings(addresses: addresses.ipv4.map { $0.destinationAddress },
                                          subnetMasks: addresses.ipv4.map { $0.destinationSubnetMask })
        ipv4Settings.includedRoutes = includedRoutes.ipv4
        ipv4Settings.excludedRoutes = excludedRoutes.ipv4
        networkSettings.ipv4Settings = ipv4Settings

        let includedRoutesDescIPv4 = includedRoutes.ipv4.reduce("") { result, route in
            "\(result), \(route.destinationAddress)/\(route.destinationSubnetMask)"
        }

        let excludedRoutesDescIPv4 = excludedRoutes.ipv4.reduce("") { result, route in
            "\(result), \(route.destinationAddress)/\(route.destinationSubnetMask)"
        }

        Logger.networkProtection.log("[GEN] Routing table information - Included Routes (IPv4): \(includedRoutesDescIPv4, privacy: .public)")
        Logger.networkProtection.log("[GEN] Routing table information - Excluded Routes (IPv4): \(excludedRoutesDescIPv4, privacy: .public)")

        let ipv6Settings = NEIPv6Settings(addresses: addresses.ipv6.map { $0.destinationAddress },
                                          networkPrefixLengths: addresses.ipv6.map { $0.destinationNetworkPrefixLength })
        ipv6Settings.includedRoutes = includedRoutes.ipv6
        ipv6Settings.excludedRoutes = excludedRoutes.ipv6
        networkSettings.ipv6Settings = ipv6Settings

        let includedRoutesDescIPv6 = includedRoutes.ipv6.reduce("") { result, route in
            "\(result), \(route.destinationAddress)/\(route.destinationNetworkPrefixLength)"
        }

        let excludedRoutesDescIPv6 = excludedRoutes.ipv6.reduce("") { result, route in
            "\(result), \(route.destinationAddress)/\(route.destinationNetworkPrefixLength)"
        }

        Logger.networkProtection.log("[GEN] Routing table information - Included Routes (IPv6): \(includedRoutesDescIPv6, privacy: .public)")
        Logger.networkProtection.log("[GEN] Routing table information - Excluded Routes (IPv6): \(excludedRoutesDescIPv6, privacy: .public)")

        return networkSettings
    }

    private static func routes(from addresses: [IPAddressRange]) -> (ipv4: [NEIPv4Route], ipv6: [NEIPv6Route]) {
        var ipv4Routes = [NEIPv4Route]()
        var ipv6Routes = [NEIPv6Route]()
        for addressRange in addresses {
            if addressRange.address is IPv4Address {
                ipv4Routes.append(NEIPv4Route(destinationAddress: "\(addressRange.address)", subnetMask: "\(addressRange.subnetMask())"))
            } else if addressRange.address is IPv6Address {
                /* Big fat ugly hack for broken iOS networking stack: the smallest prefix that will have
                 * any effect on iOS is a /120, so we clamp everything above to /120. This is potentially
                 * very bad, if various network parameters were actually relying on that subnet being
                 * intentionally small.
                 */
                ipv6Routes.append(NEIPv6Route(destinationAddress: "\(addressRange.address)",
                                              networkPrefixLength: NSNumber(value: min(120, addressRange.networkPrefixLength))))
            }
        }
        return (ipv4Routes, ipv6Routes)
    }

    private class func reresolveEndpoint(endpoint: Endpoint) -> EndpointResolutionResult {
        return Result { (endpoint, try endpoint.withReresolvedIP()) }
            .mapError { error -> DNSResolutionError in
                // swiftlint:disable:next force_cast
                return error as! DNSResolutionError
            }
    }
}
