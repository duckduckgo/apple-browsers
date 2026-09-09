//
//  EndpointPortSelection.swift
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
import os.log

/// Probes advertised ports and prepares a configuration using the selected endpoint port.
struct EndpointPortSelection {

    struct Selection {
        let configuration: TunnelConfiguration
        let decision: Decision
    }

    private let prober: EndpointPortProbing

    init(prober: EndpointPortProbing = EndpointPortProber()) {
        self.prober = prober
    }

    /// Returns nil when the configuration or server has no usable endpoint.
    func select(for serverInfo: NetworkProtectionServerInfo,
                in configuration: TunnelConfiguration,
                previousPort: UInt16?,
                preferring rememberedPort: UInt16?) async throws -> Selection? {
        try Task.checkCancellation()
        guard let configurationPort = configuration.peers.first?.endpoint?.port.rawValue else {
            return nil
        }

        let candidates = serverInfo.endpointPortCandidates(preferring: rememberedPort)
        let responding: Set<UInt16>
        if candidates.count > 1 {
            // Avoid depending on name resolution through a possibly dead tunnel.
            guard let host = serverInfo.ips.first?.host ?? serverInfo.endpoint?.host else {
                return nil
            }
            responding = try await prober.respondingPorts(host: host, ports: candidates)
        } else {
            responding = []
        }
        try Task.checkCancellation()

        let decision = Self.decide(candidates: candidates,
                                   currentPort: previousPort ?? configurationPort,
                                   serverDefaultPort: serverInfo.port,
                                   responding: responding)
        Logger.networkProtection.log("🔵 Port probe: candidates \(candidates, privacy: .public), \(responding.sorted(), privacy: .public) answered, using port \(decision.port, privacy: .public)")

        return Selection(configuration: decision.port == configurationPort ? configuration : configuration.replacingEndpointPort(with: decision.port),
                         decision: decision)
    }

    struct Decision: Equatable {
        /// Port the tunnel configuration should use.
        let port: UInt16
        /// Non-default port to retain for the next selection, including when no probe answered.
        /// Nil means the next selection falls back to that server's default port.
        let automaticPort: UInt16?
        /// Port to remember for the next connection: only a port that actually answered.
        let rememberedPort: UInt16?
    }

    /// `candidates` is the ordered list from `endpointPortCandidates(preferring:)`. `currentPort` is the
    /// previous selection, or the generated configuration's port when no previous selection is supplied.
    /// Rules: the first candidate that answered wins. If nothing answered, keep `currentPort` when it is a candidate,
    /// otherwise fall back to `serverDefaultPort` (a port carried over from another server must never be forced on
    /// one that does not advertise it).
    static func decide(candidates: [UInt16], currentPort: UInt16, serverDefaultPort: UInt16, responding: Set<UInt16>) -> Decision {
        if let chosenPort = candidates.first(where: { responding.contains($0) }) {
            return Decision(
                port: chosenPort,
                automaticPort: chosenPort == serverDefaultPort ? nil : chosenPort,
                rememberedPort: chosenPort
            )
        }

        let fallbackPort = candidates.contains(currentPort) ? currentPort : serverDefaultPort
        return Decision(
            port: fallbackPort,
            automaticPort: fallbackPort == serverDefaultPort ? nil : fallbackPort,
            rememberedPort: nil
        )
    }

}
