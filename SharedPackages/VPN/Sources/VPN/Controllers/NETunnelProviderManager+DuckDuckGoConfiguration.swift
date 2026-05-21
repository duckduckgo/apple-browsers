//
//  NETunnelProviderManager+DuckDuckGoConfiguration.swift
//  DuckDuckGo
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

        // Preserve the existing providerBundleIdentifier so this works when called from
        // the widget/shortcut extension processes — iOS only auto-resolves the provider
        // against the calling app's bundle, and extensions don't host packet tunnels.
        let existingProviderBundleIdentifier = (protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier

        protocolConfiguration = {
            let protocolConfiguration = NETunnelProviderProtocol()
            protocolConfiguration.serverAddress = "127.0.0.1" // Dummy address... the NetP service will take care of grabbing a real server
            protocolConfiguration.providerConfiguration = [:]
            protocolConfiguration.disconnectOnSleep = false
            protocolConfiguration.providerBundleIdentifier = existingProviderBundleIdentifier

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

            return protocolConfiguration
        }()

        onDemandRules = [NEOnDemandRuleConnect()]
    }
}
#endif
