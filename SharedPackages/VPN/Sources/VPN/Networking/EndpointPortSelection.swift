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

    /// Chooses an endpoint port based on availability and candidate priority.
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

    /// A selected port and the values to retain for future selections.
    struct Decision: Equatable {
        /// Selected endpoint port.
        let port: UInt16
        /// Selected non-default port to retain if later probes receive no replies.
        /// Nil when the selected port is the server default.
        let automaticPort: UInt16?
        /// Responding port to prefer next time, or nil if no candidate answered.
        let rememberedPort: UInt16?
    }

    /// Chooses the first responding port in candidate priority order.
    /// If none respond, keeps `currentPort` when it is a candidate; otherwise uses `serverDefaultPort`.
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
