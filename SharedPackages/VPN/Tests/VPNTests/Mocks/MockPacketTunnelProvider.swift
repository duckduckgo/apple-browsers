//
//  MockPacketTunnelProvider.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import NetworkExtension
@testable import VPN

final class MockPacketTunnelProvider: PacketTunnelProviding {
    var reasserting: Bool = false
    private(set) var setTunnelNetworkSettingsCallCount = 0
    private(set) var lastNetworkSettings: NETunnelNetworkSettings?
    var setTunnelNetworkSettingsError: Error?
    var setTunnelNetworkSettingsDelay: DispatchTimeInterval = .milliseconds(0)

    func setTunnelNetworkSettings(_ tunnelNetworkSettings: NETunnelNetworkSettings?, completionHandler: (@Sendable (Error?) -> Void)?) {
        setTunnelNetworkSettingsCallCount += 1
        lastNetworkSettings = tunnelNetworkSettings

        if let completionHandler {
            DispatchQueue.global().asyncAfter(deadline: .now() + setTunnelNetworkSettingsDelay) {
                completionHandler(self.setTunnelNetworkSettingsError)
            }
        }
    }
}
