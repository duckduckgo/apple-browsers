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
/// catalog doesn't list. Pixels take this instead of a string, so an extension's own identifier or
/// name can't reach a pixel.
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

/// Events that can be fired for web extension management.
@available(macOS 15.4, iOS 18.4, *)
public enum WebExtensionPixelEvent {
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

    /// One terminal report for a failure episode, on a valid dashboard response or the observation deadline.
    /// Intermediate initialization failures, stuck confirmation and reload checks stay local.
    case cpmMessagingEpisode(CPMMessagingEpisodeReport)
    case cpmRecovery(CPMRecoveryFix, outcome: CPMRecoveryOutcome)
    /// Stages and one terminal observation for a retained-background error-6 restart.
    case cpmBackgroundLoadRestart(CPMBackgroundLoadRestartOutcome)
    /// Missing first-document dashboard response after a successful first background startup.
    case cpmStartupResponseMissing

    /// A stale background was restarted after an observed Network process replacement.
    /// This records applying the mitigation, not confirmed messaging recovery.
    case cpmNetworkProcessRecoveryApplied

    /// An extension turned password saving off, which makes it the default password manager.
    case defaultPasswordManagerSet(extension: WebExtensionPixelExtension)
    /// Bitwarden is installed and loaded. Fired once a day.
    case bitwardenDailyActive(isDefault: Bool)
    /// How many distinct missing APIs a catalog extension used, and Chrome pages it tried to open,
    /// since launch, with its version. Fired once a day.
    case apiCompatibilityGaps(extension: ExtensionsCatalogSubfeature, version: String, missingAPICount: Int, unsupportedURLCount: Int)
}

/// A bounded summary of existing health-monitor evidence, not proof of document initialization or all-tab recovery.
public struct CPMMessagingEpisodeReport: Equatable, Sendable {
    public enum Outcome: String, Sendable {
        /// A response completed the same measurement that previously timed out.
        case failedMeasurementResponse = "failed_measurement_response"
        /// A later measurement on a previously failing tab received a response; the document may differ.
        case failedTabResponse = "failed_tab_response"
        /// Another tab answered; this does not prove recovery of the failing tabs.
        case otherTabResponse = "other_tab_response"
        /// A response matched multiple current documents and could not be attributed to one tab.
        case unattributedResponse = "unattributed_response"
        /// No qualifying response was observed in the bounded window; this does not prove permanent failure.
        case noResponseBeforeDeadline = "no_response_before_deadline"
    }

    public enum ReloadState: String, Sendable {
        case none
        case pending
        /// The manager could not replace the extension context.
        case failed
        /// A replacement context loaded; messaging recovery is reported separately by the outcome.
        case loaded
        /// The first eligible measurement after a successful reload also timed out.
        case responseTimedOut = "response_timed_out"
    }

    public let reason: CPMMessagingFailureReason
    public let wasStuck: Bool
    public let outcome: Outcome
    public let reloadState: ReloadState
    public let secondsToResponse: TimeInterval?
    public let diagnostics: CPMMessagingDiagnostics?
    /// Distinct tabs that timed out during the episode; tab identifiers stay local.
    public let failedTabCount: Int
    /// Timeouts beyond the first in a tab that had already timed out.
    public let repeatedFailureCount: Int
    /// The first failed measurement waited across an app suspension.
    public let wasInterrupted: Bool

    public init(reason: CPMMessagingFailureReason, wasStuck: Bool, outcome: Outcome,
                reloadState: ReloadState, secondsToResponse: TimeInterval?, diagnostics: CPMMessagingDiagnostics?,
                failedTabCount: Int, repeatedFailureCount: Int, wasInterrupted: Bool) {
        self.reason = reason
        self.wasStuck = wasStuck
        self.outcome = outcome
        self.reloadState = reloadState
        self.secondsToResponse = secondsToResponse
        self.diagnostics = diagnostics
        self.failedTabCount = failedTabCount
        self.repeatedFailureCount = repeatedFailureCount
        self.wasInterrupted = wasInterrupted
    }

    /// `count` as itself up to `cap - 1`, then `"<cap>+"`, so exact tab and failure counts are never sent.
    private static func bucket(_ count: Int, cap: Int) -> String {
        count >= cap ? "\(cap)+" : "\(max(0, count))"
    }

    var pixelParameters: [String: String] {
        typealias Name = CPMMessagingDiagnostics.ParameterName
        // Explicit allowlist of first-failure facts and the existing bounded lifecycle timeline.
        // Later transitions never add a second snapshot or append another timeline to the report.
        var parameters: [String: String] = [:]
        parameters[Name.extensionContextLoaded] = diagnostics?.extensionContextLoaded.map(String.init)
        parameters[Name.backgroundViewAlive] = diagnostics?.backgroundWebViewAlive.map(String.init)
        parameters[Name.backgroundWebProcessAlive] = diagnostics?.backgroundWebProcessAlive.map(String.init)
        parameters[Name.backgroundWebProcessResponsive] = diagnostics?.backgroundWebProcessResponsive.map(String.init)
        parameters[Name.tabKnownToWebKit] = diagnostics?.tabKnownToWebKit.map(String.init)
        parameters[Name.nativeMessageHandlerRegistered] = diagnostics?.nativeMessageHandlerRegistered.map(String.init)
        parameters[Name.tabControllerMatchesContext] = diagnostics?.tabControllerMatchesContext.map(String.init)
        parameters[Name.tabHasExtensionUserScripts] = diagnostics?.tabHasExtensionUserScripts.map(String.init)
        if let events = diagnostics?.backgroundEvents, !events.isEmpty {
            parameters[Name.backgroundEvents] = CPMMessagingDiagnostics.backgroundEventsValue(events)
        }
        // Load facts use the same first-failure snapshot; error fields exist only for its attributed error 6.
        parameters.merge(diagnostics?.backgroundLoadParameters ?? [:]) { _, value in value }
        parameters["reason"] = reason.rawValue
        parameters["was_stuck"] = String(wasStuck)
        parameters["tabs_affected"] = Self.bucket(failedTabCount, cap: 3)
        parameters["repeat_failures"] = Self.bucket(repeatedFailureCount, cap: 2)
        parameters["interrupted"] = String(wasInterrupted)
        parameters["outcome"] = outcome.rawValue
        parameters["reload_state"] = reloadState.rawValue
        if outcome != .noResponseBeforeDeadline, let secondsToResponse {
            switch secondsToResponse {
            case ..<30: parameters["response_after"] = "under_30s"
            case ..<60: parameters["response_after"] = "30s_to_1m"
            default: parameters["response_after"] = "1m_to_deadline"
            }
        }
        return parameters
    }
}

/// One logical report per completed episode: `_daily` estimates affected installations per day,
/// and `_count` counts episodes. PixelKit sends both requests on the first report of the day,
/// then only `_count`; both legs contain the same terminal summary, not intermediate transitions.
public enum CPMWebExtensionPixelFrequency: Equatable, Sendable {
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
        case .cpmMessagingHang: return "cpm_messaging_hung"
        case .cpmBackgroundLoadFailure: return "cpm_background_load_failed"
        }
    }
}

/// Background readiness alone is not proof that a page received its dashboard response.
public enum CPMBackgroundLoadRestartOutcome: String, CaseIterable, Sendable {
    case restartStarted = "restart_started"
    case backgroundReady = "background_ready"
    case responseReceived = "response_received"
    /// A measured navigation timed out and no qualifying response arrived within five active minutes.
    /// This is an observation deadline, not proof of permanent breakage.
    case noResponseBeforeDeadline = "no_response_before_deadline"
    /// No post-restart navigation timeout or attributable response was observed by the deadline.
    case unobserved
    /// Another context reload or embedded upgrade ended attribution to this restart.
    case superseded
    case reloadFailed = "reload_failed"
    case reloadTimedOut = "reload_timed_out"
}

/// Canonical CPM pixel contract. Platform adapters preserve these names and let PixelKit apply its standard platform suffix policy.
public struct CPMWebExtensionPixelMetadata: Equatable, Sendable {
    public let name: String
    public let frequency: CPMWebExtensionPixelFrequency
    public let parameters: [String: String]

    @available(macOS 15.4, iOS 18.4, *)
    public init?(event: WebExtensionPixelEvent) {
        switch event {
        case .cpmStartupResponseMissing:
            name = "web_extension_cpm_startup_response_missing"
            frequency = .dailyAndCount
            parameters = [:]
        case .cpmBackgroundLoadRestart(let outcome):
            name = "web_extension_cpm_background_load_restart"
            frequency = .dailyAndCount
            parameters = ["outcome": outcome.rawValue]
        case .cpmRecovery(let fix, let outcome):
            name = "web_extension_cpm_\(fix.rawValue)"
            frequency = .dailyAndCount
            parameters = ["outcome": outcome.rawValue]
        case .cpmMessagingEpisode(let report):
            name = "web_extension_cpm_episode"
            frequency = .dailyAndCount
            parameters = report.pixelParameters
        case .cpmNetworkProcessRecoveryApplied:
            name = "web_extension_cpm_network_process_recovery_applied"
            frequency = .dailyAndCount
            parameters = [:]
        case .installed, .installError, .uninstalled, .uninstallError, .uninstalledAll,
             .uninstallAllError, .loaded, .loadError, .reloadError, .stateChecked, .expectedExtensionNotLoaded,
             .adBlockingScriptletsNotFetched, .embeddedInstalled, .embeddedUpgraded,
             .embeddedInstallError, .scriptletFetchSuccess, .scriptletFetchError,
             .scriptletValidationError, .scriptletInstalled, .scriptletInstallError,
             .defaultPasswordManagerSet, .bitwardenDailyActive, .apiCompatibilityGaps:
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
