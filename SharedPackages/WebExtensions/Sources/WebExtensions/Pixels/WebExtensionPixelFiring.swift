//
//  WebExtensionPixelFiring.swift
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

import Foundation

/// Events that can be fired for web extension management.
@available(macOS 15.4, iOS 18.4, *)
public enum WebExtensionPixelEvent {
    case installed
    case installError(error: Error)
    case uninstalled
    case uninstallError(error: Error)
    case uninstalledAll
    case uninstallAllError(error: Error)
    case loaded
    case loadError(error: Error)

    /// Fired on every consistency check (denominator for the not-loaded rate).
    case stateChecked
    /// Fired when an expected, enabled embedded extension is not loaded into the controller.
    case expectedExtensionNotLoaded(type: DuckDuckGoWebExtensionType)
    /// Fired when ad blocking is expected but its scriptlets have not been fetched.
    /// `extensionLoaded` distinguishes "extension also missing" (false) from "loaded but scriptlet-less" (true).
    case adBlockingScriptletsNotFetched(extensionLoaded: Bool)

    case embeddedInstalled(type: DuckDuckGoWebExtensionType)
    case embeddedUpgraded(type: DuckDuckGoWebExtensionType, fromVersion: String?, toVersion: String?)
    case embeddedInstallError(type: DuckDuckGoWebExtensionType, error: Error)

    case scriptletFetchSuccess(type: DuckDuckGoWebExtensionType, version: String, count: Int)
    case scriptletFetchError(type: DuckDuckGoWebExtensionType, error: Error)
    case scriptletValidationError(type: DuckDuckGoWebExtensionType, error: Error)
    case scriptletInstalled(type: DuckDuckGoWebExtensionType, version: String)
    case scriptletInstallError(type: DuckDuckGoWebExtensionType, error: Error)

    /// CPM did not return dashboard state before a navigation's grace period expired.
    case cpmInitializationFailed(reason: CPMMessagingFailureReason)
    /// A later eligible navigation confirmed the preceding initialization failure.
    case cpmMessagingStuck(reason: CPMMessagingFailureReason)
    /// CPM messaging recovered without an intervening successful extension reload.
    case cpmMessagingRecoveredWithoutExtensionReload
    /// CPM messaging recovered after an embedded-extension reload.
    case cpmMessagingRecoveredAfterExtensionReload
    /// The first CPM measurement using a successful extension-reload generation also failed.
    case cpmMessagingExtensionReloadFailed
}

/// Reporting cadence shared by both platform CPM pixel adapters.
public enum CPMWebExtensionPixelFrequency: Equatable, Sendable {
    case daily
    case dailyAndCount
}

/// Canonical CPM pixel contract. Platform adapters add only platform and form-factor parameters.
public struct CPMWebExtensionPixelMetadata: Equatable, Sendable {
    public let name: String
    public let frequency: CPMWebExtensionPixelFrequency
    public let parameters: [String: String]

    @available(macOS 15.4, iOS 18.4, *)
    public init?(event: WebExtensionPixelEvent) {
        switch event {
        case .cpmInitializationFailed(let reason):
            name = "debug_web_extension_cpm_initialization_failed_after_\(reason.rawValue)"
            frequency = .daily
            parameters = [:]
        case .cpmMessagingStuck(let reason):
            name = "debug_web_extension_cpm_messaging_stuck_\(reason.rawValue)"
            frequency = .dailyAndCount
            parameters = [:]
        case .cpmMessagingRecoveredWithoutExtensionReload:
            name = "debug_web_extension_cpm_messaging_recovered_without_extension_reload"
            frequency = .dailyAndCount
            parameters = [:]
        case .cpmMessagingRecoveredAfterExtensionReload:
            name = "debug_web_extension_cpm_messaging_recovered_after_extension_reload"
            frequency = .dailyAndCount
            parameters = [:]
        case .cpmMessagingExtensionReloadFailed:
            name = "debug_web_extension_cpm_messaging_extension_reload_failed"
            frequency = .dailyAndCount
            parameters = [:]
        default:
            return nil
        }
    }
}

/// Protocol for firing web extension pixels.
/// Implement this protocol in each platform to wire up to the platform-specific pixel system.
@available(macOS 15.4, iOS 18.4, *)
public protocol WebExtensionPixelFiring {
    func fire(_ event: WebExtensionPixelEvent)
}

/// Default no-op implementation for when pixel firing is not needed.
@available(macOS 15.4, iOS 18.4, *)
public struct NoOpWebExtensionPixelFiring: WebExtensionPixelFiring {
    public init() {}
    public func fire(_ event: WebExtensionPixelEvent) {}
}
