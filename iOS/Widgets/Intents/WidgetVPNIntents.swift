//
//  WidgetVPNIntents.swift
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
import Persistence
import VPN
import WidgetKit
import Core
import VPNWidgetSupport
import PixelKit

/// Configures `PixelKit.shared` for the Widgets extension process, once. Guarded to the extension
/// only: these intents also compile into the main app, which already has its own `PixelKit.shared`.
enum WidgetsPixelKitSetup {
    static let didSetUp: Void = {
        guard Bundle.main.bundlePath.hasSuffix(".appex") else { return }
        PixelKitExtensionSetup.setUp(session: "ios-widgets", defaults: UserDefaults.networkProtectionGroupDefaults)
    }()
}

// MARK: - Enable & Disable

/// App intent to disable the VPN
///
/// This is used in our Widget only.
/// This is very similar to ``DisableVPNAppIntent``, but this can run in both widget and app,
/// does not support continuation in the app and does not provide any result dialog.
///
@available(iOS 17.0, *)
struct WidgetDisableVPNIntent: AppIntent {

    static let title: LocalizedStringResource = "Disable DuckDuckGo VPN"
    static let description: LocalizedStringResource = "Disables the DuckDuckGo VPN"
    static let openAppWhenRun: Bool = false
    static let isDiscoverable: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = WidgetsPixelKitSetup.didSetUp
        do {
            PixelKit.fire(Pixel.Event.networkProtectionWidgetDisconnectAttempt, frequency: .dailyAndCount)

            let controller = VPNWidgetTunnelController()
            try await controller.stop()

            await VPNSnoozeLiveActivityManager().endSnoozeActivity()
            VPNReloadStatusWidgets()

            PixelKit.fire(Pixel.Event.networkProtectionWidgetDisconnectSuccess, frequency: .dailyAndCount)
            return .result()
        } catch VPNWidgetTunnelController.StopFailure.vpnNotConfigured,
                NEVPNError.configurationDisabled {

            PixelKit.fire(Pixel.Event.networkProtectionWidgetDisconnectCancelled, frequency: .dailyAndCount)
            return .result()
        } catch {
            PixelKit.fire(Pixel.Event.networkProtectionWidgetDisconnectFailure.withError(error), frequency: .dailyAndCount)
            throw error
        }
    }
}

/// App intent to disable the VPN
///
/// This is used in our Widget only.
/// This is very similar to ``DisableVPNAppIntent``, but this can run in both widget and app,
/// does not support continuation in the app and does not provide any result dialog.
///
@available(iOS 17.0, *)
struct WidgetEnableVPNIntent: AppIntent {

    private enum EnableAttemptFailure: CustomNSError, LocalizedError {
        case cancelled

        var errorDescription: String? {
            switch self {
            case .cancelled:
                return UserText.vpnNeedsToBeEnabledFromApp
            }
        }
    }

    static let title: LocalizedStringResource = "Enable DuckDuckGo VPN"
    static let description: LocalizedStringResource = "Enables the DuckDuckGo VPN"
    static let openAppWhenRun: Bool = false
    static let isDiscoverable: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = WidgetsPixelKitSetup.didSetUp
        do {
            PixelKit.fire(Pixel.Event.networkProtectionWidgetConnectAttempt, frequency: .dailyAndCount)

            let controller = VPNWidgetTunnelController()
            try await controller.start(settings: VPNSettings(defaults: .networkProtectionGroupDefaults))

            await VPNSnoozeLiveActivityManager().endSnoozeActivity()
            VPNReloadStatusWidgets()

            PixelKit.fire(Pixel.Event.networkProtectionWidgetConnectSuccess, frequency: .dailyAndCount)
            return .result()
        } catch {
            switch error {
            case VPNWidgetTunnelController.StartFailure.vpnNotConfigured,
                NEVPNError.configurationDisabled:

                PixelKit.fire(Pixel.Event.networkProtectionWidgetConnectCancelled, frequency: .dailyAndCount)
                throw EnableAttemptFailure.cancelled
            default:
                PixelKit.fire(Pixel.Event.networkProtectionWidgetConnectFailure.withError(error), frequency: .dailyAndCount)
                throw error
            }
        }
    }
}

// MARK: - Snooze

@available(iOS 17.0, *)
struct CancelSnoozeVPNIntent: AppIntent {

    static let title: LocalizedStringResource = "Resume VPN"
    static let description: LocalizedStringResource = "Resumes the DuckDuckGo VPN"
    static let openAppWhenRun: Bool = false
    static let isDiscoverable: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = WidgetsPixelKitSetup.didSetUp
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            guard let manager = managers.first, let session = manager.connection as? NETunnelProviderSession else {
                return .result()
            }

            try? await session.sendProviderMessage(.cancelSnooze)
            VPNReloadStatusWidgets()
            await VPNSnoozeLiveActivityManager().endSnoozeActivity()

            return .result()
        } catch {
            return .result()
        }
    }
}

@available(iOS 17.0, *)
struct CancelSnoozeLiveActivityAppIntent: LiveActivityIntent {

    static var title: LocalizedStringResource = "Cancel Snooze"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = WidgetsPixelKitSetup.didSetUp
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        guard let manager = managers.first, let session = manager.connection as? NETunnelProviderSession else {
            return .result()
        }

        try? await session.sendProviderMessage(.cancelSnooze)
        await VPNSnoozeLiveActivityManager().endSnoozeActivity()
        VPNReloadStatusWidgets()

        return .result()
    }
}
