//
//  VPNWidgetTunnelController.swift
//  DuckDuckGo
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
import NetworkExtension
import VPN

@available(iOS 17.0, *)
public struct VPNWidgetTunnelController: Sendable {

    public enum StartFailure: CustomNSError {
        case vpnNotConfigured
    }

    public enum StopFailure: CustomNSError {
        case vpnNotConfigured
    }

    public init() {}

    public var status: NEVPNStatus {
        get async {
            guard let manager = try? await NETunnelProviderManager.loadAllFromPreferences().first else {
                return .invalid
            }

            return manager.connection.status
        }
    }

    public func start(settings: VPNSettings) async throws {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        guard let manager = managers.first else {
            throw StartFailure.vpnNotConfigured
        }

        // Re-apply configuration from current settings so route/exclusion changes
        // the user made in-app actually reach the system VPN profile.
        //
        // Known gap: unlike the main tunnel controller, this widget process doesn't evaluate the
        // Strict routing feature flag, so it can't scrub a stale `enforceRoutes` value here. A
        // tunnel started solely from the widget, in the window after the flag is withdrawn but
        // before the app next runs and resets the setting, could apply the relaxed value. Changing
        // the toggle happens in VPN settings (in the app), so the app runs whenever the value
        // changes, which keeps the window small. Closing it fully would require persisting flag
        // availability to shared defaults for this process to read.
        manager.applyDuckDuckGoConfiguration(from: settings)
        manager.isOnDemandEnabled = true

        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        try manager.connection.startVPNTunnel()

        try await awaitUntilStatusIsNoLongerTransitioning(manager: manager)
    }

    public func stop() async throws {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        guard let manager = managers.first else {
            throw StopFailure.vpnNotConfigured
        }

        manager.isOnDemandEnabled = false
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        manager.connection.stopVPNTunnel()

        try await awaitUntilStatusIsNoLongerTransitioning(manager: manager)
    }

    private func awaitUntilStatusIsNoLongerTransitioning(manager: NETunnelProviderManager) async throws {

        let start = Date()

        while true {
            try await Task.sleep(for: .milliseconds(500))

            if abs(start.timeIntervalSinceNow) > 30
                || (manager.connection.status != .connecting && manager.connection.status != .disconnecting) {

                break
            }
        }
    }
}
