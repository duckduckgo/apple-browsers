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
        if addresses.isEmpty {
            return .unresolved
        }

        if addresses.allSatisfy(isUnroutable) {
            return .blocked
        }

        if addresses.allSatisfy({ isUnroutable($0) || isPrivate($0) }) {
            return .privateIP
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

    /// `::`, `::1`, `100::/64` (discard), and unroutable IPv4-mapped addresses, such as `::ffff:0.0.0.0`.
    func isUnroutable(_ address: IPv6Address) -> Bool {
        if address.isIPv4Mapped, let ipv4 = address.asIPv4 {
            return isUnroutable(ipv4)
        }

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
