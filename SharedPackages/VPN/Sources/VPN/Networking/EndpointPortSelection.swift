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

/// Decides which advertised WireGuard port to use from the probe results.
enum EndpointPortSelection {

    struct Decision: Equatable {
        /// Port the tunnel configuration should use.
        let port: UInt16
        /// Value for the provider's automatic port: nil when it matches the server default (so the plain,
        /// override-free path is used), and set to `port` whenever it differs from the default — whether
        /// that's because a candidate answered or because a non-default port was kept as a fallback.
        let automaticPort: UInt16?
        /// Port to remember for the next connection: only a port that actually answered.
        let rememberedPort: UInt16?
    }

    /// `candidates` is the ordered list from `endpointPortCandidates(preferring:)`, `currentPort` the port already
    /// in the generated configuration, `serverDefaultPort` the server's `port`, `responding` the probe result.
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
