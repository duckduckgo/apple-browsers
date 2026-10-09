//
//  DNSBlockDetector.swift
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

import Foundation
import Network

/// How the system resolver answered for a site's host.
public enum DNSResolution: String, Sendable {
    /// At least one routable address.
    case resolved

    /// Only unroutable addresses (`0.0.0.0`, `::`, loopback), as DNS blockers answer.
    case blocked

    /// Only private or link-local addresses, as Pi-hole's LAN-IP mode, captive portals and intranets answer.
    case privateIP

    /// Only reserved, multicast, documentation, NAT64 or 6to4 addresses, which no public site uses.
    case invalid

    /// No addresses: the domain doesn't exist, the lookup failed, or it timed out.
    case unresolved
}

/// Detects DNS blockers that answer with unroutable addresses, such as `0.0.0.0`, or with private addresses.
public struct DNSBlockDetector: Sendable {

    private let timeout: TimeInterval = 1

    public init() {}

    public func resolution(for host: String) async -> DNSResolution {

        // `getaddrinfo` can't be cancelled, so it races a timer off the cooperative pool; the first answer wins.
        let answers = AsyncStream<DNSResolution> { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.yield(resolution(of: resolve(host: host)))
                continuation.finish()
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                continuation.yield(.unresolved)
                continuation.finish()
            }
        }

        for await resolution in answers {
            return resolution
        }

        return .unresolved
    }
}

private extension DNSBlockDetector {

    func resolution(of addresses: [any IPAddress]) -> DNSResolution {
        let addresses = addresses.map(unwrappingIPv4Mapped)

        if addresses.isEmpty {
            return .unresolved
        }

        if addresses.allSatisfy(isUnroutable) {
            return .blocked
        }

        if addresses.allSatisfy({ isUnroutable($0) || isPrivate($0) }) {
            return .privateIP
        }

        if addresses.allSatisfy({ isUnroutable($0) || isPrivate($0) || isInvalid($0) }) {
            return .invalid
        }

        return .resolved
    }

    func resolve(host: String) -> [any IPAddress] {
        var result: UnsafeMutablePointer<addrinfo>?

        guard getaddrinfo(host, nil, nil, &result) == 0, let first = result else {
            return []
        }

        defer {
            freeaddrinfo(first)
        }

        var addresses: [any IPAddress] = []
        var node: UnsafeMutablePointer<addrinfo>? = first

        // `getaddrinfo` returns a linked list.
        while let current = node {
            if let address = ipAddress(from: current.pointee) {
                addresses.append(address)
            }

            node = current.pointee.ai_next
        }

        return addresses
    }

    func ipAddress(from info: addrinfo) -> (any IPAddress)? {
        switch info.ai_family {
        case AF_INET:
            return info.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { socketAddress in
                let bytes = withUnsafeBytes(of: socketAddress.pointee.sin_addr) { Data($0) }
                return IPv4Address(bytes)
            }
        case AF_INET6:
            return info.ai_addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { socketAddress in
                let bytes = withUnsafeBytes(of: socketAddress.pointee.sin6_addr) { Data($0) }
                return IPv6Address(bytes)
            }
        default:
            return nil
        }
    }

    /// `::ffff:a.b.c.d` as the IPv4 it embeds, so every check sees plain IPv4.
    func unwrappingIPv4Mapped(_ address: any IPAddress) -> any IPAddress {
        guard let ipv6 = address as? IPv6Address, ipv6.isIPv4Mapped, let ipv4 = ipv6.asIPv4 else {
            return address
        }

        return ipv4
    }

    /// Unspecified, loopback and discard addresses, as DNS blockers answer.
    func isUnroutable(_ address: any IPAddress) -> Bool {
        switch address {
        case let ipv4 as IPv4Address:
            return isUnroutable(ipv4)
        case let ipv6 as IPv6Address:
            return isUnroutable(ipv6)
        default:
            return false
        }
    }

    /// `0.0.0.0/8` (unspecified) and `127.0.0.0/8` (loopback).
    func isUnroutable(_ address: IPv4Address) -> Bool {
        let firstByte = address.rawValue.first
        return firstByte == 0 || firstByte == 127
    }

    /// `::`, `::1` and `100::/64` (discard).
    func isUnroutable(_ address: IPv6Address) -> Bool {
        let isDiscard = address.rawValue.starts(with: [0x01, 0, 0, 0, 0, 0, 0, 0])
        return address == .any || address == .loopback || isDiscard
    }

    /// Private and link-local ranges, as Pi-hole's LAN-IP mode, captive portals and intranets answer.
    func isPrivate(_ address: any IPAddress) -> Bool {
        let bytes = [UInt8](address.rawValue)

        switch address {
        case is IPv4Address:
            return bytes.hasPrefix([10], bits: 8)               // 10.0.0.0/8
                || bytes.hasPrefix([172, 16], bits: 12)         // 172.16.0.0/12
                || bytes.hasPrefix([192, 168], bits: 16)        // 192.168.0.0/16
                || bytes.hasPrefix([169, 254], bits: 16)        // 169.254.0.0/16
        case is IPv6Address:
            return bytes.hasPrefix([0xFC], bits: 7)             // fc00::/7
                || bytes.hasPrefix([0xFE, 0x80], bits: 10)      // fe80::/10
        default:
            return false
        }
    }

    /// Reserved, multicast, documentation and translation ranges, which no public site resolves to.
    func isInvalid(_ address: any IPAddress) -> Bool {
        let bytes = [UInt8](address.rawValue)

        switch address {
        case is IPv4Address:
            return bytes.hasPrefix([240], bits: 4)              // 240.0.0.0/4, reserved, including 255.255.255.255
                || bytes.hasPrefix([224], bits: 4)              // 224.0.0.0/4, multicast
                || bytes.hasPrefix([192, 0, 0], bits: 24)       // 192.0.0.0/24, IETF protocol assignments
                || bytes.hasPrefix([192, 0, 2], bits: 24)       // 192.0.2.0/24, documentation
                || bytes.hasPrefix([198, 51, 100], bits: 24)    // 198.51.100.0/24, documentation
                || bytes.hasPrefix([203, 0, 113], bits: 24)     // 203.0.113.0/24, documentation
        case is IPv6Address:
            return bytes.hasPrefix([0x00, 0x64, 0xFF, 0x9B, 0, 0, 0, 0, 0, 0, 0, 0], bits: 96)  // 64:ff9b::/96, NAT64
                || bytes.hasPrefix([0x00, 0x64, 0xFF, 0x9B, 0x00, 0x01], bits: 48)          // 64:ff9b:1::/48, local NAT64
                || bytes.hasPrefix([0x20, 0x02], bits: 16)                                  // 2002::/16, 6to4
                || bytes.hasPrefix([0xFF], bits: 8)                                         // ff00::/8, multicast
                || bytes.hasPrefix([0x20, 0x01, 0x0D, 0xB8], bits: 32)                      // 2001:db8::/32, documentation
                || bytes.hasPrefix([0x3F, 0xFF, 0x00], bits: 20)                            // 3fff::/20, documentation
                || bytes.hasPrefix([0x01, 0, 0, 0, 0, 0, 0, 0x01], bits: 64)                // 100:0:0:1::/64, dummy
        default:
            return false
        }
    }
}

private extension Array where Element == UInt8 {

    /// Whether the first `bits` bits match `prefix`, as in CIDR notation.
    func hasPrefix(_ prefix: [UInt8], bits: Int) -> Bool {
        (0..<bits).allSatisfy { bit in
            let mask = UInt8(0x80) >> (bit % 8)
            return self[bit / 8] & mask == prefix[bit / 8] & mask
        }
    }
}
