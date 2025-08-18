//
//  MockNetworkProtectionDeviceManagement.swift
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
import VPN

public final class MockNetworkProtectionDeviceManagement: NetworkProtectionDeviceManagement {

    enum MockError: Error {
        case noStubSet
    }

    public var spyGenerateTunnelConfiguration: (
        selectionMethod: VPN.NetworkProtectionServerSelectionMethod,
        excludeLocalNetworks: Bool,
        dnsSettings: NetworkProtectionDNSSettings,
        regenerateKey: Bool
    )?

    public var stubGenerateTunnelConfiguration: (
        tunnelConfiguration: VPN.TunnelConfiguration,
        server: VPN.NetworkProtectionServer
    )?

    public var stubGenerateTunnelConfigurationError: Error?

    public init() {}

    public func generateTunnelConfiguration(
        resolvedSelectionMethod: VPN.NetworkProtectionServerSelectionMethod,
        excludeLocalNetworks: Bool,
        dnsSettings: NetworkProtectionDNSSettings,
        regenerateKey: Bool) async throws -> (tunnelConfiguration: VPN.TunnelConfiguration, server: VPN.NetworkProtectionServer) {
            spyGenerateTunnelConfiguration = (
                selectionMethod: resolvedSelectionMethod,
                excludeLocalNetworks: excludeLocalNetworks,
                dnsSettings: dnsSettings,
                regenerateKey: regenerateKey
                )
            if let stubGenerateTunnelConfiguration {
                return stubGenerateTunnelConfiguration
            } else if let stubGenerateTunnelConfigurationError {
                throw stubGenerateTunnelConfigurationError
            }
            throw MockError.noStubSet
    }

}
