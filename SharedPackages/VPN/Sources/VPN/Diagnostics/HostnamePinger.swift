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

public struct HostnamePinger: Sendable {

    private let host: String
    private let timeout: TimeInterval

    public init(host: String, timeout: TimeInterval) {
        self.host = host
        self.timeout = timeout
    }

    /// Pings the configured host once and buckets the round-trip time; `.unknown` when resolution or the ping fails.
    public func currentPingQuality() async -> NetworkProtectionLatencyMonitor.ConnectionQuality {
        guard let ip = await Self.resolveIPv4(host: host),
              case .success(let result) = await Pinger(ip: ip, timeout: timeout).ping() else {
            return .unknown
        }

        return .init(average: result.time * 1000)
    }

    /// Runs the blocking lookup off the cooperative pool.
    private static func resolveIPv4(host: String) async -> IPv4Address? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: resolveIPv4Sync(host: host))
            }
        }
    }

    private static func resolveIPv4Sync(host: String) -> IPv4Address? {
        let endpoint = Endpoint(host: .name(host, nil), port: .https)
        guard case .success(let resolved) = DefaultDNSResolver().resolveSync(endpoints: [endpoint]).first ?? nil,
              case .ipv4(let address) = resolved.host else {
            return nil
        }

        return address
    }
}
