//
//  VPNAppEventsHandler.swift
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

import AppKitExtensions

import Foundation
import NetworkExtension
import Common
import VPN
import os.log

final class VPNAppEventsHandler {

    private let tunnelController: NetworkProtectionTunnelController
    private let settings: VPNSettings
    private let notifications: VPNNotificationsObserver
    @MainActor private var isRecoveringOnDemandFailure = false

    init(tunnelController: NetworkProtectionTunnelController, settings: VPNSettings, notifications: VPNNotificationsObserver) {
        self.tunnelController = tunnelController
        self.settings = settings
        self.notifications = notifications
    }

    func appDidFinishLaunching() {
        let currentVersion = AppVersion.shared.versionAndBuildNumber
        let versionStore = NetworkProtectionLastVersionRunStore(userDefaults: .netP)
        defer {
            versionStore.lastAgentVersionRun = currentVersion
        }

        let restartTunnel = {
            Logger.networking.info("App updated from \(versionStore.lastAgentVersionRun ?? "null", privacy: .public) to \(currentVersion, privacy: .public): updating login items")

            self.restartTunnel()
        }

        // Since DEBUG and REVIEW builds may not change version No. we want them to always reset.
        let buildType = StandardApplicationBuildType()
        if versionStore.lastAgentVersionRun != currentVersion || buildType.isDebugBuild || buildType.isReviewBuild {
            restartTunnel()
        }
    }

    @MainActor
    func handleTunnelAtLaunch(launchedAtLogin: Bool) async {
        let manager = launchedAtLogin ? await tunnelController.manager : nil
        tunnelController.onTunnelDisconnect = { [weak self] manager, status in
            _ = await self?.recoverOnDemandFailure(for: manager, observedStatus: status)
        }

        guard launchedAtLogin else { return }
        if let manager, await recoverOnDemandFailure(for: manager, observedStatus: manager.connection.status) { return }
        if await !tunnelController.isConnected && settings.connectOnLogin {
            await tunnelController.start()
        }
    }

    // MARK: - Private code

    @MainActor
    private func recoverOnDemandFailure(for manager: NETunnelProviderManager, observedStatus: NEVPNStatus) async -> Bool {
        if isRecoveringOnDemandFailure { return true }
        guard manager.isOnDemandEnabled else { return false }
        let code = await tunnelController.startupFailureCode(for: manager, observedStatus: observedStatus)
        // Both disconnect transitions can report the same failure while the lookup is in flight.
        if isRecoveringOnDemandFailure || !manager.isOnDemandEnabled { return true }
        guard code == .startingTunnelWithoutAuthToken || code == .reconnectBlocked else { return false }

        isRecoveringOnDemandFailure = true
        defer { isRecoveringOnDemandFailure = false }
        do {
            guard try await tunnelController.stopAfterOnDemandFailure(manager) else { return true }
        } catch {
            Logger.networkProtection.error("Failed to disable VPN On Demand after a startup failure: \(error.localizedDescription, privacy: .public)")
            return true
        }

        if code == .startingTunnelWithoutAuthToken {
            notifications.showEntitlementNotification()
        } else {
            notifications.showConnectionFailureNotification()
        }
        return true
    }

    private func restartTunnel() {
        Task {
            // Restart NetP SysEx on app update
            if await tunnelController.isConnected {
                await tunnelController.restart()
            }
        }
    }
}
