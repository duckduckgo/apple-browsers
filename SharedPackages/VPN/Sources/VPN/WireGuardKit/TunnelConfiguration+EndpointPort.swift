//
//  TunnelConfiguration+EndpointPort.swift
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

extension TunnelConfiguration {

    /// A copy of this configuration with every peer endpoint moved to `port`. Peers without an endpoint are left as they are.
    func replacingEndpointPort(with port: UInt16) -> TunnelConfiguration {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return self }

        let peers = self.peers.map { peer -> PeerConfiguration in
            var peer = peer
            if let endpoint = peer.endpoint {
                peer.endpoint = Endpoint(host: endpoint.host, port: nwPort)
            }
            return peer
        }

        return TunnelConfiguration(name: name, interface: interface, peers: peers)
    }

}
