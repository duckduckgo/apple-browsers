//
//  CPMMessagingDiagnostics.swift
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

import Foundation

/// Attribution collected around a Web Extension messaging failure that attribute it to one of the known WebKit failure modes.
///
/// Every field is optional: the snapshot is best-effort and a missing value must never block the pixel.
/// `pixelParameters` renders the struct as bucketed, PII-free pixel parameters.
public struct CPMMessagingDiagnostics: Equatable, Sendable {

    public var extensionContextLoaded: Bool?
    public var secondsSinceCriticalMemoryPressure: TimeInterval?
    public var networkProcessRestarted: Bool?
    /// `WKWebExtensionContext.errors` domain/code pairs, including the immediate underlying error when present.
    public var extensionContextErrors: [String]
    public var backgroundWebViewCreateCount: Int?
    public var backgroundWebViewAlive: Bool?
    /// Background web views WebKit no longer references but that are still alive.
    public var leakedBackgroundWebViewCount: Int?
    public var backgroundWebProcessAlive: Bool?
    /// Whether `WKWebExtensionContext.openTabs` contains the failing tab — the set WebKit resolves message senders against.
    public var tabKnownToWebKit: Bool?
    /// Whether the app's message router has an `autoconsent` handler for the context — without it every native
    /// request from the background fails, and the background answers the content script with "setting disabled".
    public var nativeMessageHandlerRegistered: Bool?
    /// Whether the failing tab's `WKWebViewConfiguration.webExtensionController` is the controller the CPM context
    /// is loaded into. A tab created while `WebExtensionManager` did not exist (feature flag off, or off→on mid-session,
    /// which replaces the manager and its controller) keeps a controller with no CPM context: nothing is ever injected
    /// into it, page reloads do not help, new tabs work.
    public var tabControllerMatchesContext: Bool?
    /// Whether the failing tab's `WKUserContentController.userScripts` still contains scripts in the extension's content
    /// world. WebKit injects them once per user content controller; anything that calls `removeAllUserScripts()` on the
    /// tab's controller afterwards (e.g. `DuckAiNativeStorageBootstrapScriptRefresher`) strips them for good.
    public var tabHasExtensionUserScripts: Bool?
    /// One background lifecycle event: a short token (`view`, `died_crash`, `error_<domain>:<code>`, `unresponsive`, …)
    /// and how long before the snapshot it happened.
    public struct BackgroundEvent: Equatable, Sendable {
        public let token: String
        public let secondsBeforeSnapshot: TimeInterval

        public init(token: String, secondsBeforeSnapshot: TimeInterval) {
            self.token = token
            self.secondsBeforeSnapshot = secondsBeforeSnapshot
        }
    }

    // Observed through `CPMBackgroundWebViewDelegateProxy` on the background web view.
    /// `WKWebView._webProcessIsResponsive` for the background view: WebKit's hang-detection verdict at snapshot time.
    public var backgroundWebProcessResponsive: Bool?
    /// Most recent background lifecycle events, oldest first (context load, view created/deallocated, process death with
    /// reason, unresponsive/responsive, load errors, and proxy state). Rendered as `token@-<seconds>`.
    public var backgroundEvents: [BackgroundEvent] = []

    public init(
        extensionContextLoaded: Bool? = nil,
        secondsSinceCriticalMemoryPressure: TimeInterval? = nil,
        networkProcessRestarted: Bool? = nil,
        extensionContextErrors: [String] = [],
        backgroundWebViewCreateCount: Int? = nil,
        backgroundWebViewAlive: Bool? = nil,
        leakedBackgroundWebViewCount: Int? = nil,
        backgroundWebProcessAlive: Bool? = nil,
        tabKnownToWebKit: Bool? = nil,
        nativeMessageHandlerRegistered: Bool? = nil,
        tabControllerMatchesContext: Bool? = nil,
        tabHasExtensionUserScripts: Bool? = nil,
        backgroundWebProcessResponsive: Bool? = nil,
        backgroundEvents: [BackgroundEvent] = []
    ) {
        self.backgroundWebProcessResponsive = backgroundWebProcessResponsive
        self.backgroundEvents = backgroundEvents
        self.extensionContextLoaded = extensionContextLoaded
        self.secondsSinceCriticalMemoryPressure = secondsSinceCriticalMemoryPressure
        self.networkProcessRestarted = networkProcessRestarted
        self.extensionContextErrors = extensionContextErrors
        self.backgroundWebViewCreateCount = backgroundWebViewCreateCount
        self.backgroundWebViewAlive = backgroundWebViewAlive
        self.leakedBackgroundWebViewCount = leakedBackgroundWebViewCount
        self.backgroundWebProcessAlive = backgroundWebProcessAlive
        self.tabKnownToWebKit = tabKnownToWebKit
        self.nativeMessageHandlerRegistered = nativeMessageHandlerRegistered
        self.tabControllerMatchesContext = tabControllerMatchesContext
        self.tabHasExtensionUserScripts = tabHasExtensionUserScripts
    }

    // MARK: - Pixel parameters

    public enum ParameterName {
        public static let extensionContextLoaded = "context_loaded"
        public static let memoryPressureCritical = "critical_memory_age"
        public static let networkProcessRestarted = "network_restarted"
        public static let extensionContextErrors = "context_errors"
        public static let backgroundViewCreateCount = "bg_view_creations"
        public static let backgroundViewAlive = "bg_view_alive"
        public static let backgroundViewLeakedCount = "bg_view_leaked_count"
        public static let backgroundWebProcessAlive = "bg_process_alive"
        public static let tabKnownToWebKit = "tab_in_context"
        public static let nativeMessageHandlerRegistered = "handler_registered"
        public static let tabControllerMatchesContext = "tab_controller_match"
        public static let tabHasExtensionUserScripts = "tab_has_ext_scripts"
        public static let backgroundWebProcessResponsive = "bg_process_responsive"
        public static let backgroundEvents = "bg_events"
    }

    /// Longest `bg_events` value; older events are dropped first.
    static let maximumBackgroundEventsLength = 255

    /// Bucketed, PII-free representation for pixel parameters. Unknown facts are omitted.
    public var pixelParameters: [String: String] {
        var parameters: [String: String] = [:]

        parameters[ParameterName.extensionContextLoaded] = extensionContextLoaded.map(String.init)
        parameters[ParameterName.memoryPressureCritical] = Self.memoryPressureBucket(secondsSinceCriticalMemoryPressure)
        parameters[ParameterName.networkProcessRestarted] = networkProcessRestarted.map(String.init)
        parameters[ParameterName.extensionContextErrors] = extensionContextErrors.isEmpty ? "none" : extensionContextErrors.joined(separator: ",")
        parameters[ParameterName.backgroundViewCreateCount] = backgroundWebViewCreateCount.map(Self.countBucket)
        parameters[ParameterName.backgroundViewAlive] = backgroundWebViewAlive.map(String.init)
        parameters[ParameterName.backgroundViewLeakedCount] = leakedBackgroundWebViewCount.map(Self.countBucket)
        parameters[ParameterName.backgroundWebProcessAlive] = backgroundWebProcessAlive.map(String.init)
        parameters[ParameterName.tabKnownToWebKit] = tabKnownToWebKit.map(String.init)
        parameters[ParameterName.nativeMessageHandlerRegistered] = nativeMessageHandlerRegistered.map(String.init)
        parameters[ParameterName.tabControllerMatchesContext] = tabControllerMatchesContext.map(String.init)
        parameters[ParameterName.tabHasExtensionUserScripts] = tabHasExtensionUserScripts.map(String.init)
        parameters[ParameterName.backgroundWebProcessResponsive] = backgroundWebProcessResponsive.map(String.init)
        if !backgroundEvents.isEmpty {
            parameters[ParameterName.backgroundEvents] = Self.backgroundEventsValue(backgroundEvents)
        }
        return parameters
    }

    // MARK: - Bucketing

    static func memoryPressureBucket(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "none" }
        switch seconds {
        case ..<60: return "1m"
        case ..<300: return "5m"
        case ..<1800: return "30m"
        default: return "over_30"
        }
    }

    static func countBucket(_ count: Int) -> String {
        switch count {
        case ...0: return "0"
        case 1: return "1"
        case 2: return "2"
        case 3...5: return "3_to_5"
        default: return "over_5"
        }
    }

    /// `token@-<seconds>` entries, oldest first, comma-separated; drops the oldest entries until the value fits the cap.
    /// Tokens are sanitized (they may embed error domain/code pairs).
    static func backgroundEventsValue(_ events: [BackgroundEvent]) -> String {
        var entries = events.map { event -> String in
            let token = sanitizedEventToken(event.token)
            let seconds = Int(max(0, event.secondsBeforeSnapshot).rounded())
            return "\(token)@-\(seconds)"
        }
        while entries.joined(separator: ",").count > maximumBackgroundEventsLength, entries.count > 1 {
            entries.removeFirst()
        }
        return entries.joined(separator: ",")
    }

    /// Keeps the timeline's fixed alphabet while preserving `:` and `-` in error descriptors.
    private static func sanitizedEventToken(_ value: String) -> String {
        let allowed = value.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == ":" || $0 == "-"
        }
        let token = String(String.UnicodeScalarView(allowed)).prefix(64)
        return token.isEmpty ? "unknown" : String(token)
    }
}
