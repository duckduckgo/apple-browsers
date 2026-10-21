//
//  MockPacketTunnelSettingsGenerator.swift
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

final class MockPacketTunnelSettingsGenerator: PacketTunnelSettingsGenerating {
    var networkSettingsToReturn = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
    var uapiConfigurationReturnValue: (String, [EndpointResolutionResult?]) = ("", [])
    var endpointUapiConfigurationReturnValue: (String, [EndpointResolutionResult?]) = ("", [])

    private(set) var generateNetworkSettingsCallCount = 0
    private(set) var uapiConfigurationCallCount = 0
    private(set) var endpointUapiConfigurationCallCount = 0

    func uapiConfiguration() -> (String, [EndpointResolutionResult?]) {
        uapiConfigurationCallCount += 1
        return uapiConfigurationReturnValue
    }

    func endpointUapiConfiguration() -> (String, [EndpointResolutionResult?]) {
        endpointUapiConfigurationCallCount += 1
        return endpointUapiConfigurationReturnValue
    }

    func generateNetworkSettings() -> NEPacketTunnelNetworkSettings {
        generateNetworkSettingsCallCount += 1
        return networkSettingsToReturn
    }
}
