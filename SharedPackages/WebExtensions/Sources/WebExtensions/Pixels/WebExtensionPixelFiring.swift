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
import PrivacyConfig

/// Identifies the reload operation that failed before a replacement extension context became active.
@available(macOS 15.4, iOS 18.4, *)
public enum WebExtensionReloadFailurePhase: String, Equatable, Sendable {
    case unload
    case load
    case lightweightLoad = "light_load"
    case fullLoad = "full_load"
    case fallbackLoad = "fallback_load"
}

/// The extension a pixel reports: its entry in the Chrome Web Store catalog, or `other` for one the
/// catalog doesn't list. Extension pixels use this bounded value instead of an extension's own
/// identifier or name.
public enum WebExtensionPixelExtension: Equatable, CaseIterable {
    case catalog(ExtensionsCatalogSubfeature)
    case other

    public static var allCases: [WebExtensionPixelExtension] {
        ExtensionsCatalogSubfeature.allCases.map(Self.catalog) + [.other]
    }

    /// The version pixels send for an extension: its manifest version when it has Chrome's format,
    /// one to four numbers separated by dots, or `other`, so no other text from the manifest is sent.
    public static func version(_ manifestVersion: String?) -> String {
        guard let manifestVersion,
              manifestVersion.range(of: #"^[0-9]{1,9}(\.[0-9]{1,9}){0,3}$"#, options: .regularExpression) != nil else {
            return "other"
        }
        return manifestVersion
    }

    /// The value pixels send, matching the `extension` parameter in the pixel definitions.
    public var parameterValue: String {
        switch self {
        case .catalog(let entry): entry.rawValue
        case .other: "other"
        }
    }
}

/// The bounded outcomes reported by Chrome Web Store update discovery. No server text is sent.
public enum WebExtensionUpdateCheckOutcome: String, CaseIterable, Sendable {
    case updateFound = "update_found"
    case googleFlagged = "google_flagged"
    case invalidRequest = "invalid_request"
    case invalidResponse = "invalid_response"
    case invalidManifest = "invalid_manifest"
    case responseTooLarge = "response_too_large"
    case networkFailure = "network_failure"
    case httpStatus = "http_status"

    @available(macOS 15.4, iOS 18.4, *)
    init?(checkOutcome: ChromeWebStoreUpdateChecker.Outcome) {
        switch checkOutcome {
        case .update: self = .updateFound
        case .skipped: self = .googleFlagged
        case .noUpdate, .failure(.cancelled): return nil
        case .failure(.invalidRequest): self = .invalidRequest
        case .failure(.invalidResponse): self = .invalidResponse
        case .failure(.invalidManifest): self = .invalidManifest
        case .failure(.responseTooLarge): self = .responseTooLarge
        case .failure(.networkFailure): self = .networkFailure
        case .failure(.httpStatus): self = .httpStatus
        }
    }
}

/// Events that can be fired for web extension management.
@available(macOS 15.4, iOS 18.4, *)
public enum WebExtensionPixelEvent {
    /// Discovery pixels report the catalog extension and, for failures, a bounded reason.
    case updateCheck(extension: WebExtensionPixelExtension, outcome: WebExtensionUpdateCheckOutcome)
    case updateDownloadFailed(extension: WebExtensionPixelExtension, outcome: WebExtensionUpdateDownloadFailure)
    case updateVerificationFailed(extension: WebExtensionPixelExtension, outcome: WebExtensionUpdateVerificationFailure)
    case updateVerified(extension: WebExtensionPixelExtension)
    /// The replacement is committed, either loaded with existing approval or installed disabled without executing it.
    case updateApplied(extension: WebExtensionPixelExtension)
    case updateInstallFailed(extension: WebExtensionPixelExtension, outcome: WebExtensionUpdateInstallFailure)
    /// A fresh install; updates aren't reported.
    case installed(extension: WebExtensionPixelExtension)
    case installError(extension: WebExtensionPixelExtension, error: Error)
    case uninstalled(extension: WebExtensionPixelExtension)
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

    /// One report for each tab that stayed silent after a page loaded.
    case cpmMessagingBreakage(CPMMessagingBreakageReport)
    /// Sent once when a second tab goes silent without any answer from the extension in between.
    case cpmMessagingBreakagePersistent

    /// An extension turned password saving off, which makes it the default password manager.
    case defaultPasswordManagerSet(extension: WebExtensionPixelExtension)
    /// Bitwarden is installed and loaded. Fired once a day.
    case bitwardenDailyActive(isDefault: Bool)
    /// How many distinct missing APIs a catalog extension used, and Chrome pages it tried to open,
    /// since launch, with its version. Fired once a day.
    case apiCompatibilityGaps(extension: ExtensionsCatalogSubfeature, version: String, missingAPICount: Int, unsupportedURLCount: Int)

    case enabled(extension: WebExtensionPixelExtension)
    case disabled(extension: WebExtensionPixelExtension)
    case remotelyDisabled(extension: WebExtensionPixelExtension)
    case retained14Days(extension: WebExtensionPixelExtension)
    case churned14Days(extension: WebExtensionPixelExtension)
    case installedCount(installed: Int, enabled: Int)
}

/// How many tabs have been silent since the extension last answered anything.
public enum CPMSilentTabs: String, Equatable, Sendable {
    /// Only this tab: the page, not the extension, is the likely cause.
    case one
    /// Another tab was already silent: the extension itself is the likely cause.
    case many
}

/// One detected breakage. Sent the moment it is detected, so nothing is lost if the app closes afterwards.
public struct CPMMessagingBreakageReport: Equatable, Sendable {
    public let tabs: CPMSilentTabs

    public init(tabs: CPMSilentTabs) {
        self.tabs = tabs
    }

    var pixelParameters: [String: String] {
        ["tabs": tabs.rawValue]
    }
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
        let nsError = NSError.webKitSafe(error)
        var parameters = [
            "extension_type": type?.shortLabel ?? "unknown",
            "reload_trigger": trigger.pixelParameterValue,
            "reload_phase": phase.rawValue,
            "d": nsError.domain,
            "e": String(nsError.code)
        ]
        if let underlying = nsError.underlyingError {
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
        case .cpmBackgroundLoadFailure: return "cpm_background_load_failed"
        }
    }
}

/// Canonical CPM pixel contract. Platform adapters preserve these names and let PixelKit apply its standard platform suffix policy.
public struct CPMWebExtensionPixelMetadata: Equatable, Sendable {
    public let name: String
    public let parameters: [String: String]

    @available(macOS 15.4, iOS 18.4, *)
    public init?(event: WebExtensionPixelEvent) {
        switch event {
        case .cpmMessagingBreakage(let report):
            name = "web_extension_cpm_breakage"
            parameters = report.pixelParameters
        case .cpmMessagingBreakagePersistent:
            name = "web_extension_cpm_breakage_persistent"
            parameters = [:]
        case .updateCheck, .updateDownloadFailed, .updateVerificationFailed, .updateVerified, .updateApplied, .updateInstallFailed,
             .installed, .installError, .uninstalled, .uninstallError, .uninstalledAll,
             .uninstallAllError, .loaded, .loadError, .reloadError, .stateChecked, .expectedExtensionNotLoaded,
             .adBlockingScriptletsNotFetched, .embeddedInstalled, .embeddedUpgraded,
             .embeddedInstallError, .scriptletFetchSuccess, .scriptletFetchError,
             .scriptletValidationError, .scriptletInstalled, .scriptletInstallError,
             .defaultPasswordManagerSet, .bitwardenDailyActive, .apiCompatibilityGaps,
             .enabled, .disabled, .remotelyDisabled, .retained14Days, .churned14Days, .installedCount:
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
