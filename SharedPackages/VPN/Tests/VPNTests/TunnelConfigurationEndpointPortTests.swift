//
//  TunnelConfigurationEndpointPortTests.swift
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

import XCTest
import Network
@testable import VPN

final class TunnelConfigurationEndpointPortTests: XCTestCase {

    func testReplacingEndpointPort_MovesPeerEndpointToNewPort() {
        let publicKey = PrivateKey().publicKey
        var peer = PeerConfiguration.make(publicKey: publicKey)
        peer.endpoint = Endpoint(host: .ipv4(IPv4Address("1.2.3.4")!), port: 443)

        let configuration = TunnelConfiguration.make(named: "test", peers: [peer])

        let updated = configuration.replacingEndpointPort(with: 51820)

        XCTAssertEqual(updated.name, configuration.name)
        XCTAssertEqual(updated.interface, configuration.interface)
        XCTAssertEqual(updated.peers.count, 1)
        XCTAssertEqual(updated.peers.first?.publicKey, publicKey)
        XCTAssertEqual(updated.peers.first?.endpoint?.host, .ipv4(IPv4Address("1.2.3.4")!))
        XCTAssertEqual(updated.peers.first?.endpoint?.port.rawValue, 51820)
    }

    func testReplacingEndpointPort_LeavesPeerWithoutEndpointUnchanged() {
        let publicKey = PrivateKey().publicKey
        let peer = PeerConfiguration.make(publicKey: publicKey)
        XCTAssertNil(peer.endpoint)

        let configuration = TunnelConfiguration.make(peers: [peer])

        let updated = configuration.replacingEndpointPort(with: 51820)

        XCTAssertEqual(updated.peers.count, 1)
        XCTAssertNil(updated.peers.first?.endpoint)
    }

}
