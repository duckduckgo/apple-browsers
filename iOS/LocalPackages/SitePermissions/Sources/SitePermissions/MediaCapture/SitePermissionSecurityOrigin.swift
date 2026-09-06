//
//  SitePermissionSecurityOrigin.swift
//  DuckDuckGo
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

import WebKit

public struct SitePermissionSecurityOrigin: Equatable, Sendable {
    private let protocolName: String
    public let host: String
    private let port: Int

    @MainActor
    public init(_ origin: WKSecurityOrigin) {
        protocolName = origin.protocol.lowercased()
        host = Self.normalizedHost(origin.host)
        port = Self.effectivePort(for: protocolName, explicitPort: origin.port)
    }

    public init?(_ url: URL) {
        guard let protocolName = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }
        self.protocolName = protocolName
        self.host = Self.normalizedHost(host)
        port = Self.effectivePort(for: protocolName, explicitPort: url.port ?? 0)
    }

    public var isPotentiallyTrustworthy: Bool {
        guard !host.isEmpty else { return false }
        if protocolName == "https" {
            return true
        }
        guard protocolName == "http" else { return false }

        let ipv4Octets = host.split(separator: ".", omittingEmptySubsequences: false)
        let isIPv4Loopback = ipv4Octets.count == 4
            && ipv4Octets.allSatisfy { UInt8($0) != nil }
            && UInt8(ipv4Octets[0]) == 127
        return host == "localhost"
            || host.hasSuffix(".localhost")
            || host == "::1"
            || isIPv4Loopback
    }

    private static func normalizedHost(_ host: String) -> String {
        host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }

    private static func effectivePort(for protocolName: String, explicitPort: Int) -> Int {
        guard explicitPort == 0 else { return explicitPort }
        switch protocolName {
        case "https":
            return 443
        case "http":
            return 80
        default:
            return 0
        }
    }
}
