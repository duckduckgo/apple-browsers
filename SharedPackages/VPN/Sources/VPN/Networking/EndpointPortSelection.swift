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

/// Probes advertised ports and chooses which endpoint port to use.
struct EndpointPortSelection {

    private let prober: EndpointPortProbing

    init(prober: EndpointPortProbing = EndpointPortProber()) {
        self.prober = prober
    }

    /// Returns nil when probing is needed but the server has no usable endpoint.
    func select(for serverInfo: NetworkProtectionServerInfo,
                previousPort: UInt16?,
                preferring rememberedPort: UInt16?) async throws -> Decision? {
        try Task.checkCancellation()
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

        let decision = decide(candidates: candidates,
                              currentPort: previousPort ?? serverInfo.port,
                              serverDefaultPort: serverInfo.port,
                              responding: responding)
        Logger.networkProtection.log("Port probe: candidates \(candidates, privacy: .public), \(responding.sorted(), privacy: .public) answered, using port \(decision.port, privacy: .public)")

        return decision
    }

    struct Decision: Equatable {
        /// Selected endpoint port.
        let port: UInt16
        /// Non-default port to retain for the next selection, including when no probe answered.
        /// Nil means the next selection falls back to that server's default port.
        let automaticPort: UInt16?
        /// Port to remember for the next connection: only a port that actually answered.
        let rememberedPort: UInt16?
    }

    /// `candidates` is the ordered list from `endpointPortCandidates(preferring:)`. `currentPort` is the
    /// previous selection, or the server's default port when no previous selection is supplied.
    /// Rules: the first candidate that answered wins. If nothing answered, keep `currentPort` when it is a candidate,
    /// otherwise fall back to `serverDefaultPort` (a port carried over from another server must never be forced on
    /// one that does not advertise it).
    func decide(candidates: [UInt16], currentPort: UInt16, serverDefaultPort: UInt16, responding: Set<UInt16>) -> Decision {
        let respondingPort = candidates.first(where: { responding.contains($0) })
        let fallbackPort = candidates.contains(currentPort) ? currentPort : serverDefaultPort
        let port = respondingPort ?? fallbackPort

        return Decision(
            port: port,
            automaticPort: port == serverDefaultPort ? nil : port,
            rememberedPort: respondingPort
        )
    }

}
