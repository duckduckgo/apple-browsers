//
//  VPNShortcutIntents.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import VPNWidgetSupport
import PixelKit

// MARK: - Enable & Disable

/// App intent to disable the VPN
///
/// This is used in App Shortcuts, for things like Shortcuts.app, Spotlight and Siri.
/// This is very similar to ``WidgetDisableVPNIntent``, but this runs in-app, allows continuation in the app if needed,
/// and provides a result dialog.
///
@available(iOS 17.0, *)
struct DisableVPNIntent: AppIntent {

    private enum DisableAttemptFailure: CustomNSError {
        case cancelled
    }

    static let title: LocalizedStringResource = "Disable DuckDuckGo VPN"
    static let description: LocalizedStringResource = "Disable DuckDuckGo VPN"
    static let openAppWhenRun: Bool = false
    static let isDiscoverable: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            PixelKit.fire(Pixel.Event.vpnShortcutDisconnectAttempt, frequency: .dailyAndCount)

            let controller = VPNWidgetTunnelController()
            try await controller.stop()

            await VPNSnoozeLiveActivityManager().endSnoozeActivity()
            VPNReloadStatusWidgets()

            PixelKit.fire(Pixel.Event.vpnShortcutDisconnectSuccess, frequency: .dailyAndCount)
            return .result(dialog: IntentDialog(stringLiteral: UserText.vpnControlWidgetDisableVPNIntentSuccess))
        } catch VPNWidgetTunnelController.StopFailure.vpnNotConfigured {
            PixelKit.fire(Pixel.Event.vpnShortcutDisconnectCancelled, frequency: .dailyAndCount)
            throw VPNWidgetTunnelController.StopFailure.vpnNotConfigured
        } catch {
            PixelKit.fire(Pixel.Event.vpnShortcutDisconnectFailure.withError(error), frequency: .dailyAndCount)
            throw error
        }
    }
}

/// App intent to enable the VPN
///
/// This is used in App Shortcuts, for things like Shortcuts.app, Spotlight and Siri.
/// This is very similar to ``WidgetEnableVPNIntent``, but this runs in-app, allows continuation in the app if needed,
/// and provides a result dialog.
///
@available(iOS 17.0, *)
struct EnableVPNIntent: ForegroundContinuableIntent {
    static let title: LocalizedStringResource = "Enable DuckDuckGo VPN"
    static let description: LocalizedStringResource = "Enable DuckDuckGo VPN"
    static let openAppWhenRun: Bool = false
    static let isDiscoverable: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            PixelKit.fire(Pixel.Event.vpnShortcutConnectAttempt, frequency: .dailyAndCount)

            let controller = VPNWidgetTunnelController()
            try await controller.start(settings: VPNSettings(defaults: .networkProtectionGroupDefaults))

            await VPNSnoozeLiveActivityManager().endSnoozeActivity()
            VPNReloadStatusWidgets()

            PixelKit.fire(Pixel.Event.vpnShortcutConnectSuccess, frequency: .dailyAndCount)
            return .result(dialog: IntentDialog(stringLiteral: UserText.vpnControlWidgetEnableVPNIntentSuccess))
        } catch {
            switch error {
            case VPNWidgetTunnelController.StartFailure.vpnNotConfigured,
                // On update the VPN configuration becomes disabled, until started manually from
                // the app.
                NEVPNError.configurationDisabled:

                PixelKit.fire(Pixel.Event.vpnShortcutConnectCancelled, frequency: .dailyAndCount)

                let dialog = IntentDialog(stringLiteral: UserText.vpnNeedsToBeEnabledFromApp)
                throw needsToContinueInForegroundError(dialog) {
                    await UIApplication.shared.open(AppDeepLinkSchemes.openVPN.url)
                }
            default:
                PixelKit.fire(Pixel.Event.vpnShortcutConnectFailure.withError(error), frequency: .dailyAndCount)

                throw error
            }
        }
    }
}
