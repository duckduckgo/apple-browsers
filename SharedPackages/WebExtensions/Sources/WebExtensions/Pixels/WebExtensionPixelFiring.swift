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

/// Identifies the reload operation that failed before a replacement extension context became active.
@available(macOS 15.4, iOS 18.4, *)
public enum WebExtensionReloadFailurePhase: String, Equatable, Sendable {
    case unload
    case load
    case lightweightLoad = "light_load"
    case fullLoad = "full_load"
    case fallbackLoad = "fallback_load"
}

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
    /// The extension manager failed to unload or load a context while reloading an extension.
    case reloadError(type: DuckDuckGoWebExtensionType?,
                     trigger: WebExtensionReloadTrigger,
                     phase: WebExtensionReloadFailurePhase,
                     error: Error)

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
    case cpmInitializationFailed(reason: CPMMessagingFailureReason, diagnostics: CPMMessagingDiagnostics? = nil)
    /// A later eligible navigation confirmed the preceding initialization failure.
    case cpmMessagingStuck(reason: CPMMessagingFailureReason, diagnostics: CPMMessagingDiagnostics? = nil)
    /// CPM messaging recovered without an intervening successful extension reload.
    case cpmMessagingRecoveredWithoutExtensionReload(from: CPMMessagingRecoverySource)
    /// CPM messaging recovered after an embedded-extension reload.
    case cpmMessagingRecoveredAfterExtensionReload(from: CPMMessagingRecoverySource)
    /// The first CPM measurement using a successful extension-reload generation also failed.
    case cpmMessagingExtensionReloadFailed
}

/// Failure state of the episode immediately before recovery.
public enum CPMMessagingRecoverySource: String, Sendable {
    case initializationFailed = "initialization_failed"
    case messagingStuck = "messaging_stuck"
}

/// Reporting cadence shared by both platform CPM pixel adapters.
public enum CPMWebExtensionPixelFrequency: Equatable, Sendable {
    case daily
    case dailyAndCount
}

/// PII-free metadata shared by the iOS and macOS reload-error pixel adapters.
@available(macOS 15.4, iOS 18.4, *)
public struct WebExtensionReloadErrorPixelMetadata: Equatable, Sendable {
    public static let name = "debug_web_extension_reload_failed"

    public let parameters: [String: String]

    public init(type: DuckDuckGoWebExtensionType?,
                trigger: WebExtensionReloadTrigger,
                phase: WebExtensionReloadFailurePhase,
                error: Error) {
        let nsError = error as NSError
        var parameters = [
            "extension_type": type?.shortLabel ?? "unknown",
            "reload_trigger": trigger.pixelParameterValue,
            "reload_phase": phase.rawValue,
            "d": nsError.domain,
            "e": String(nsError.code)
        ]
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parameters["ud"] = underlying.domain
            parameters["ue"] = String(underlying.code)
        }
        self.parameters = parameters
    }
}

@available(macOS 15.4, iOS 18.4, *)
private extension WebExtensionReloadTrigger {
    var pixelParameterValue: String {
        switch self {
        case .dataClearing: return "data_clearing"
        case .scriptletUpdate: return "scriptlet_update"
        case .explicit: return "explicit"
        }
    }
}

/// Canonical CPM pixel contract. Platform adapters preserve these names and let PixelKit apply its standard platform suffix policy.
public struct CPMWebExtensionPixelMetadata: Equatable, Sendable {
    public let name: String
    public let frequency: CPMWebExtensionPixelFrequency
    public let parameters: [String: String]

    @available(macOS 15.4, iOS 18.4, *)
    public init?(event: WebExtensionPixelEvent) {
        switch event {
        case .cpmInitializationFailed(let reason, let diagnostics):
            name = "debug_web_extension_cpm_initialization_failed_after_\(reason.rawValue)"
            frequency = .daily
            parameters = diagnostics?.pixelParameters ?? [:]
        case .cpmMessagingStuck(let reason, let diagnostics):
            name = "debug_web_extension_cpm_messaging_stuck_\(reason.rawValue)"
            frequency = .dailyAndCount
            parameters = diagnostics?.pixelParameters ?? [:]
        case .cpmMessagingRecoveredWithoutExtensionReload(let source):
            name = "debug_web_extension_cpm_messaging_recovered_without_extension_reload"
            frequency = .dailyAndCount
            parameters = ["recovery_from": source.rawValue]
        case .cpmMessagingRecoveredAfterExtensionReload(let source):
            name = "debug_web_extension_cpm_messaging_recovered_after_extension_reload"
            frequency = .dailyAndCount
            parameters = ["recovery_from": source.rawValue]
        case .cpmMessagingExtensionReloadFailed:
            name = "debug_web_extension_cpm_messaging_extension_reload_failed"
            frequency = .dailyAndCount
            parameters = [:]
        case .installed, .installError, .uninstalled, .uninstallError, .uninstalledAll,
             .uninstallAllError, .loaded, .loadError, .reloadError, .stateChecked, .expectedExtensionNotLoaded,
             .adBlockingScriptletsNotFetched, .embeddedInstalled, .embeddedUpgraded,
             .embeddedInstallError, .scriptletFetchSuccess, .scriptletFetchError,
             .scriptletValidationError, .scriptletInstalled, .scriptletInstallError:
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
