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

    /// Returns advertised ports in selection priority order, without duplicates.
    ///
    /// An advertised remembered port comes first, followed by the default and remaining ports in server order.
    /// Always includes the default port; returns only that port when `ports` is nil.
    public func endpointPortCandidates(preferring rememberedPort: UInt16?) -> [UInt16] {
        guard let ports else {
            return [port]
        }

        let advertisedPorts = [port] + ports

        var candidates: [UInt16] = []

        if let rememberedPort, rememberedPort != 0, advertisedPorts.contains(rememberedPort) {
            candidates.append(rememberedPort)
        }

        if !candidates.contains(port) {
            candidates.append(port)
        }

        for candidate in ports where candidate != 0 && !candidates.contains(candidate) {
            candidates.append(candidate)
        }

        return candidates
    }

}
