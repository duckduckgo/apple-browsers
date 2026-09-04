//
//  NetworkProtectionServerInfo+EndpointPortCandidates.swift
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

extension NetworkProtectionServerInfo {

    /// The ports to try for the WireGuard endpoint, in order of preference.
    ///
    /// - The remembered port comes first, but only if this server advertises it.
    /// - The server's primary `port` follows.
    /// - Then any remaining advertised `ports`, in the order the server listed them.
    ///
    /// Duplicates are removed. The result is never empty: it always contains at least `port`.
    public func endpointPortCandidates(preferring rememberedPort: UInt16?) -> [UInt16] {
        let advertisedPorts = [port] + (ports ?? [])

        var candidates: [UInt16] = []

        if let rememberedPort, rememberedPort != 0, advertisedPorts.contains(rememberedPort) {
            candidates.append(rememberedPort)
        }

        if !candidates.contains(port) {
            candidates.append(port)
        }

        for candidate in ports ?? [] where candidate != 0 && !candidates.contains(candidate) {
            candidates.append(candidate)
        }

        return candidates
    }

}
