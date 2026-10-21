//
//  NetworkProtectionIPAddressCategory.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import Darwin
import Foundation
import Network

public enum NetworkProtectionIPAddressCategory: String, Codable, CaseIterable, Hashable {
    case ipv4Public
    case ipv4Private10
    case ipv4Private172
    case ipv4Private192
    case ipv4CGNAT
    case ipv4LinkLocal
    case ipv4Loopback
    case ipv4Multicast
    case ipv4Reserved
    case ipv6Public
    case ipv6UniqueLocal
    case ipv6LinkLocal
    case ipv6Loopback
    case ipv6Multicast
    case unknown
}

public enum NetworkProtectionIPAddressClassifier {

    public static func classify(_ address: String) -> NetworkProtectionIPAddressCategory {
        let address = address.split(separator: "%").first.map(String.init) ?? address

        if let ipv4Address = IPv4Address(address) {
            return classify(ipv4Address)
        }

        if let ipv6Address = IPv6Address(address) {
            return classify(ipv6Address)
        }

        return .unknown
    }

    public static func uniqueCategories(for addresses: [String]) -> [NetworkProtectionIPAddressCategory] {
        let categories = Set(addresses.map(classify))
        return categories.sorted { $0.rawValue < $1.rawValue }
    }

    private static func classify(_ address: IPv4Address) -> NetworkProtectionIPAddressCategory {
        if address.isLoopback {
            return .ipv4Loopback
        }

        if address.isLinkLocal {
            return .ipv4LinkLocal
        }

        if address.isMulticast {
            return .ipv4Multicast
        }

        let bytes = [UInt8](address.rawValue)
        guard bytes.count == 4 else { return .unknown }

        let firstByte = bytes[0]
        let secondByte = bytes[1]

        if firstByte == 10 {
            return .ipv4Private10
        }

        if firstByte == 172 && (16...31).contains(secondByte) {
            return .ipv4Private172
        }

        if firstByte == 192 && secondByte == 168 {
            return .ipv4Private192
        }

        if firstByte == 100 && (64...127).contains(secondByte) {
            return .ipv4CGNAT
        }

        if firstByte == 0 || firstByte >= 240 {
            return .ipv4Reserved
        }

        return .ipv4Public
    }

    private static func classify(_ address: IPv6Address) -> NetworkProtectionIPAddressCategory {
        if address.isLoopback || address.isAny {
            return .ipv6Loopback
        }

        if address.isLinkLocal {
            return .ipv6LinkLocal
        }

        if address.isMulticast {
            return .ipv6Multicast
        }

        let bytes = [UInt8](address.rawValue)
        guard let firstByte = bytes.first else { return .unknown }

        if firstByte == 0xfc || firstByte == 0xfd {
            return .ipv6UniqueLocal
        }

        return .ipv6Public
    }
}

public enum NetworkProtectionAddressMetadata {

    public static func deviceAddressCategories(for path: NWPath) -> [NetworkProtectionIPAddressCategory] {
        let interfaceNames = Set(path.availableInterfaces
            .filter(isPhysicalInterface)
            .map(\.name))

        return categories(for: interfaceAddresses(named: interfaceNames))
    }

    public static func routerAddressCategories(for path: NWPath) -> [NetworkProtectionIPAddressCategory] {
        categories(for: path.gateways.compactMap(addressString))
    }

    public static func categories(for addresses: [String]) -> [NetworkProtectionIPAddressCategory] {
        let categories = NetworkProtectionIPAddressClassifier.uniqueCategories(for: addresses)
        return categories.isEmpty ? [.unknown] : categories
    }

    private static func isPhysicalInterface(_ interface: NWInterface) -> Bool {
        switch interface.type {
        case .wifi, .wiredEthernet, .cellular:
            return true
        default:
            return false
        }
    }

    private static func interfaceAddresses(named interfaceNames: Set<String>) -> [String] {
        guard !interfaceNames.isEmpty else {
            return []
        }

        var addresses: [String] = []
        var ifaddrsPointer: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddrsPointer) == 0, let firstAddress = ifaddrsPointer else {
            return []
        }

        defer {
            freeifaddrs(ifaddrsPointer)
        }

        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let interface = pointer?.pointee {
            defer {
                pointer = interface.ifa_next
            }

            let interfaceName = String(cString: interface.ifa_name)
            guard interfaceNames.contains(interfaceName), let addressPointer = interface.ifa_addr else {
                continue
            }

            let family = Int32(addressPointer.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addressPointer,
                socklen_t(addressPointer.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            guard result == 0 else {
                continue
            }

            addresses.append(String(cString: host))
        }

        return addresses
    }

    private static func addressString(from endpoint: NWEndpoint) -> String? {
        switch endpoint {
        case .hostPort(let host, _):
            return addressString(from: host)
        default:
            return nil
        }
    }

    private static func addressString(from host: NWEndpoint.Host) -> String? {
        switch host {
        case .ipv4(let address):
            return "\(address)"
        case .ipv6(let address):
            return "\(address)"
        case .name(let name, _):
            return name
        @unknown default:
            return nil
        }
    }
}
