//
//  ControlWidgetVPNIntents.swift
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

import AppIntents
import NetworkExtension
import VPN
import WidgetKit
import Core
import OSLog
import VPNWidgetSupport
import PixelKit

// MARK: - Toggle

@available(iOS 17.0, *)
struct ControlWidgetToggleVPNIntent: SetValueIntent {

    private enum EnableAttemptFailure: CustomNSError, LocalizedError {
        case cancelled

        var errorDescription: String? {
            switch self {
            case .cancelled:
                return UserText.vpnNeedsToBeEnabledFromApp
            }
        }
    }

    static let title: LocalizedStringResource = "Toggle DuckDuckGo VPN from the Control Center Widget"
    static let description: LocalizedStringResource = "Toggles the DuckDuckGo VPN from the Control Center widget"
    static let isDiscoverable = false

    @Parameter(title: "Enabled")
    var value: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = WidgetsPixelKitSetup.didSetUp
        if value {
            try await startVPN()
        } else {
            try await stopVPN()
        }

        return .result()
    }

    private func startVPN() async throws {
        do {
            PixelKit.fire(Pixel.Event.vpnControlCenterConnectAttempt, frequency: .dailyAndCount)

            let controller = VPNWidgetTunnelController()
            try await controller.start(settings: VPNSettings(defaults: .networkProtectionGroupDefaults))

            await VPNSnoozeLiveActivityManager().endSnoozeActivity()
            VPNReloadStatusWidgets()

            PixelKit.fire(Pixel.Event.vpnControlCenterConnectSuccess, frequency: .dailyAndCount)
        } catch {
            switch error {
            case VPNWidgetTunnelController.StartFailure.vpnNotConfigured,
                // On update the VPN configuration becomes disabled, until started manually from
                // the app.
                NEVPNError.configurationDisabled:

                PixelKit.fire(Pixel.Event.vpnControlCenterConnectCancelled, frequency: .dailyAndCount)
                throw EnableAttemptFailure.cancelled
            default:
                PixelKit.fire(Pixel.Event.vpnControlCenterConnectFailure.withError(error), frequency: .dailyAndCount)
                throw error
            }
        }
    }

    private func stopVPN() async throws {
        do {
            PixelKit.fire(Pixel.Event.vpnControlCenterDisconnectAttempt, frequency: .dailyAndCount)

            let controller = VPNWidgetTunnelController()
            try await controller.stop()

            await VPNSnoozeLiveActivityManager().endSnoozeActivity()
            VPNReloadStatusWidgets()

            PixelKit.fire(Pixel.Event.vpnControlCenterDisconnectSuccess, frequency: .dailyAndCount)
        } catch {
            switch error {
            case VPNWidgetTunnelController.StopFailure.vpnNotConfigured:
                PixelKit.fire(Pixel.Event.vpnControlCenterDisconnectCancelled, frequency: .dailyAndCount)
                throw error
            default:
                PixelKit.fire(Pixel.Event.vpnControlCenterDisconnectFailure.withError(error), frequency: .dailyAndCount)
                throw error
            }
        }
    }
}
