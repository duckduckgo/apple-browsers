//
//  HostnamePinger.swift
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

/// Measures ICMP latency to a host name from the calling process, independently of the VPN tunnel.
public struct HostnamePinger: Sendable {

    private let host: String
    private let timeout: TimeInterval

    /// - Parameter timeout: Bounds the DNS lookup and the ping separately.
    public init(host: String, timeout: TimeInterval) {
        self.host = host
        self.timeout = timeout
    }

    /// Pings the configured host once and buckets the round-trip time; `.unknown` when resolution or the ping fails.
    public func currentPingQuality() async -> NetworkProtectionLatencyMonitor.ConnectionQuality {
        guard let ip = await resolveIPv4() else {
            return .unknown
        }

        guard case .success(let result) = await Pinger(ip: ip, timeout: timeout).ping() else {
            return .unknown
        }

        let milliseconds = result.time * 1000
        return .init(average: milliseconds)
    }

    /// Runs the blocking lookup off the cooperative pool; `nil` if it outlasts `timeout`, whichever arrives first wins.
    private func resolveIPv4() async -> IPv4Address? {
        let results = AsyncStream<IPv4Address?> { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.yield(resolveIPv4Sync())
                continuation.finish()
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                continuation.yield(nil)
                continuation.finish()
            }
        }

        for await address in results {
            return address
        }

        return nil
    }

    private func resolveIPv4Sync() -> IPv4Address? {
        // The resolver needs a port, but only the address is used.
        let endpoint = Endpoint(host: .name(host, nil), port: .https)
        let resolution = DefaultDNSResolver().resolveSync(endpoints: [endpoint]).first ?? nil

        guard case .success(let resolved) = resolution, case .ipv4(let address) = resolved.host else {
            return nil
        }

        return address
    }
}
