//
//  NETunnelProviderManager+DuckDuckGoConfiguration.swift
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

#if os(iOS)
import Foundation
import NetworkExtension

extension NETunnelProviderManager {

    /// Applies the DuckDuckGo VPN configuration derived from `VPNSettings`.
    ///
    /// Must be called by every path that starts the tunnel — both in-app and from widget/shortcut
    /// intents — so that route and exclusion changes the user made in Settings reach the system
    /// VPN configuration. Skipping it leaves stale `enforceRoutes`, `includeAllNetworks`,
    /// `excludeLocalNetworks`, `excludeAPNs`, `excludeCellularServices`, and
    /// `excludeDeviceCommunication` values in the system profile.
    public func applyDuckDuckGoConfiguration(from settings: VPNSettings) {
        localizedDescription = "DuckDuckGo VPN"
        isEnabled = true

        // Mutate the loaded protocolConfiguration in place so the system's internal binding to the
        // packet-tunnel extension survives. Replacing it with a fresh NETunnelProviderProtocol() works
        // from the host app (iOS auto-resolves the provider against the app bundle on save) but fails
        // from widget/shortcut extension processes with "configuration type is wrong".
        let protocolConfiguration = (protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        protocolConfiguration.serverAddress = "127.0.0.1" // Dummy address... the NetP service will take care of grabbing a real server
        protocolConfiguration.providerConfiguration = [:]
        protocolConfiguration.disconnectOnSleep = false

        protocolConfiguration.enforceRoutes = settings.enforceRoutes
        protocolConfiguration.includeAllNetworks = settings.includeAllNetworks
        protocolConfiguration.excludeLocalNetworks = settings.excludeLocalNetworks

        if #available(iOS 16.4, *) {
            protocolConfiguration.excludeAPNs = settings.excludeAPNs
            protocolConfiguration.excludeCellularServices = settings.excludeCellularServices
        }

        if #available(iOS 17.4, *) {
            protocolConfiguration.excludeDeviceCommunication = settings.excludeDeviceCommunication
        }

        self.protocolConfiguration = protocolConfiguration
        onDemandRules = [NEOnDemandRuleConnect()]
    }
}
#endif
