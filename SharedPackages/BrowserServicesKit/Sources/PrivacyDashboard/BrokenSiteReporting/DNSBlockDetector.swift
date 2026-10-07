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

    /// No addresses: the domain doesn't exist, the lookup failed, or it timed out.
    case unresolved
}

/// Detects DNS blockers that answer with unroutable addresses, such as `0.0.0.0`.
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

    func isUnroutable(_ address: any IPAddress) -> Bool {
        let isUnspecified = address.rawValue.allSatisfy { $0 == 0 }
        return isUnspecified || address.isLoopback
    }
}
