//
//  TunnelConfigurationMocks.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
@testable import NetworkProtection

extension TunnelConfiguration {
    static func make(named name: String = "", interface: InterfaceConfiguration = .make(), peers: [PeerConfiguration] = []) -> TunnelConfiguration {
        TunnelConfiguration(name: name, interface: interface, peers: peers)
    }
}

extension InterfaceConfiguration {
    static func make(
        privateKey: PrivateKey = .init(),
        addresses: [IPAddressRange] = [],
        includedRoutes: [IPAddressRange] = [],
        excludedRoutes: [IPAddressRange] = []
    ) -> Self {
        InterfaceConfiguration(
            privateKey: .init(),
            addresses: addresses,
            includedRoutes: includedRoutes,
            excludedRoutes: excludedRoutes
        )
    }
}

extension PeerConfiguration {
    static func make(publicKey: PublicKey = .init(hexKey: "00000000")!) -> Self {
        PeerConfiguration(publicKey: publicKey)
    }
}
