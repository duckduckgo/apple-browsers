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

/// App-owned launch facts shared with CPM diagnostics; does not read or persist application state.
public struct CPMAppSessionDiagnostics {
    public enum VersionChange: String, Sendable {
        case updated
        case downgraded
    }

    /// Foreground state of the app, read with each diagnostics snapshot and when a background load error is recorded.
    public enum ApplicationState: String, Sendable {
        case active
        case inactive
        case background
    }

    public let appVersionChange: VersionChange?
    public let launchDate: Date
    /// Reads the app's current state; `nil` leaves it unreported.
    public let applicationState: (@MainActor () -> ApplicationState)?
    /// Reads when the device or app last resumed (macOS: the system woke; iOS: the app became active); `nil` leaves it unreported.
    public let lastResumeDate: (@MainActor () -> Date?)?

    public init(appVersionChange: VersionChange?,
                launchDate: Date,
                applicationState: (@MainActor () -> ApplicationState)? = nil,
                lastResumeDate: (@MainActor () -> Date?)? = nil) {
        self.appVersionChange = appVersionChange
        self.launchDate = launchDate
        self.applicationState = applicationState
        self.lastResumeDate = lastResumeDate
    }
}

/// Whether WebKit finished loading the CPM background, as reported by `WKWebExtensionContext.loadBackgroundContent`.
public enum CPMBackgroundReadiness: Equatable, Sendable {
    /// No background view was created for the current context.
    case noBackground
    /// WebKit has not finished loading the current background.
    case pending
    /// The current background finished loading this long after its view was created.
    case loaded(secondsAfterViewCreation: TimeInterval)
    /// WebKit reported that the current background failed to load.
    case failed
}

/// Best-effort state attached to Web Extension messaging failures. Unavailable facts are omitted.
public struct CPMMessagingDiagnostics: Equatable, Sendable {

    public var extensionContextLoaded: Bool?
    public var appVersionChange: CPMAppSessionDiagnostics.VersionChange?
    public var secondsSinceAppLaunch: TimeInterval?
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
    /// Whether the background-process termination associated with this health episode had treatment enabled.
    public var backgroundGraveyardTreatmentEnabled: Bool?
    /// App state when the most recent `BackgroundContentFailedToLoad` (error 6) was recorded for this context;
    /// `nil` when none was recorded or the app does not report its state.
    public var backgroundLoadErrorAppState: CPMAppSessionDiagnostics.ApplicationState?
    /// Seconds from the creation of the background view whose load failed to that error 6. WebKit unloads a background
    /// that has not finished loading 30 s after the wake that started it, so values near 30 s point at that timer.
    public var secondsFromBackgroundViewToLoadError: TimeInterval?
    /// Whether this context recorded a background load error: `false` reports `none`, `nil` (unknown) omits both values.
    public var hasBackgroundLoadError: Bool?
    /// App state at the snapshot; `nil` when the app does not report its state.
    public var applicationState: CPMAppSessionDiagnostics.ApplicationState?
    /// Seconds since the current background view was created; `nil` when there is no background view.
    public var secondsSinceBackgroundViewCreation: TimeInterval?
    /// Whether the current background had finished loading; `nil` when readiness is not observed.
    public var backgroundReadiness: CPMBackgroundReadiness?
    /// Tabs in `WKWebExtensionContext.openTabs`, and how many of their web views were loading.
    public var openTabCount: Int?
    public var loadingTabCount: Int?
    /// Seconds from the start of this context's load to the creation of its first background view. WebKit may clear
    /// website data for a new origin before it starts the background, so a slow start can happen before any view exists.
    public var secondsFromContextLoadToBackgroundView: TimeInterval?
    /// Power, thermal and Lockdown Mode conditions at the snapshot; `nil` when the app does not read them.
    public var deviceState: CPMDeviceState?
    /// Seconds since the device or app last resumed; `nil` when it has not resumed since launch or is not reported.
    public var secondsSinceResume: TimeInterval?
    /// Most recent background lifecycle events, oldest first (context load, view created/deallocated, process death with
    /// reason, unresponsive/responsive, load errors, and proxy state). Rendered as `token@<age bucket>`.
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
        backgroundGraveyardTreatmentEnabled: Bool? = nil,
        backgroundEvents: [BackgroundEvent] = []
    ) {
        self.backgroundWebProcessResponsive = backgroundWebProcessResponsive
        self.backgroundGraveyardTreatmentEnabled = backgroundGraveyardTreatmentEnabled
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
        public static let appVersionChange = "app_version_change"
        public static let appLaunchAge = "app_launch_age"
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
        public static let backgroundGraveyardTreatmentEnabled = "background_graveyard_enabled"
        public static let backgroundEvents = "bg_events"
        public static let backgroundLoadErrorAppState = "bg_load_error_app_state"
        public static let backgroundLoadErrorAfter = "bg_load_error_after"
        public static let applicationState = "app_state"
        public static let backgroundViewAge = "bg_view_age"
        public static let backgroundReadyAfter = "bg_ready_after"
        public static let openTabs = "open_tabs"
        public static let loadingTabs = "loading_tabs"
        public static let contextLoadToBackgroundView = "ctx_load_to_view"
        public static let lowPowerMode = "low_power_mode"
        public static let thermalState = "thermal_state"
        public static let lockdownMode = "lockdown_mode"
        public static let resumeAge = "resume_age"
    }

    /// Longest `bg_events` value; older events are dropped first.
    static let maximumBackgroundEventsLength = 255

    /// Bucketed, PII-free representation for pixel parameters. Unknown facts are omitted.
    public var pixelParameters: [String: String] {
        var parameters: [String: String] = [:]
        parameters[ParameterName.appVersionChange] = appVersionChange?.rawValue
        parameters[ParameterName.appLaunchAge] = secondsSinceAppLaunch.map(Self.ageBucket)

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
        parameters[ParameterName.backgroundGraveyardTreatmentEnabled] = backgroundGraveyardTreatmentEnabled.map(String.init)
        if !backgroundEvents.isEmpty {
            parameters[ParameterName.backgroundEvents] = Self.backgroundEventsValue(backgroundEvents)
        }
        switch hasBackgroundLoadError {
        case true?:
            parameters[ParameterName.backgroundLoadErrorAppState] = backgroundLoadErrorAppState?.rawValue
            parameters[ParameterName.backgroundLoadErrorAfter] = secondsFromBackgroundViewToLoadError.map(Self.loadErrorDelayBucket)
        case false?:
            parameters[ParameterName.backgroundLoadErrorAppState] = "none"
            parameters[ParameterName.backgroundLoadErrorAfter] = "none"
        case nil:
            break
        }
        parameters[ParameterName.applicationState] = applicationState?.rawValue
        parameters[ParameterName.backgroundViewAge] = secondsSinceBackgroundViewCreation.map(Self.backgroundViewAgeBucket)
        parameters[ParameterName.backgroundReadyAfter] = backgroundReadiness.map(Self.readinessValue)
        parameters[ParameterName.openTabs] = openTabCount.map(Self.tabCountBucket)
        parameters[ParameterName.loadingTabs] = loadingTabCount.map(Self.countBucket)
        parameters[ParameterName.contextLoadToBackgroundView] = secondsFromContextLoadToBackgroundView.map(Self.contextLoadDelayBucket)
        parameters.merge(deviceState?.pixelParameters ?? [:]) { _, device in device }
        parameters[ParameterName.resumeAge] = secondsSinceResume.map(Self.resumeAgeBucket)
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

    /// Separates loads that failed quickly from those cut off by WebKit's 30 s background unload timer.
    static func loadErrorDelayBucket(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<5: return "under_5s"
        case ..<25: return "5s_to_25s"
        case ..<35: return "25s_to_35s"
        default: return "over_35s"
        }
    }

    /// Fine enough to tell a failure during a wake (the view is a few seconds old) from one long after it.
    static func backgroundViewAgeBucket(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<4: return "under_4s"
        case ..<8: return "4s_to_8s"
        case ..<30: return "8s_to_30s"
        case ..<120: return "30s_to_2m"
        default: return "over_2m"
        }
    }

    /// Load times around the monitor's 4 s grace period and WebKit's 30 s unload timer.
    static func readinessValue(_ readiness: CPMBackgroundReadiness) -> String {
        switch readiness {
        case .noBackground: return "none"
        case .pending: return "pending"
        case .failed: return "failed"
        case .loaded(let seconds):
            switch seconds {
            case ..<1: return "under_1s"
            case ..<4: return "1s_to_4s"
            case ..<10: return "4s_to_10s"
            case ..<30: return "10s_to_30s"
            default: return "over_30s"
            }
        }
    }

    /// Around the 0.75-1.35 s that clearing a large cache before the first start was measured to add.
    static func contextLoadDelayBucket(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<0.25: return "under_250ms"
        case ..<1: return "250ms_to_1s"
        case ..<4: return "1s_to_4s"
        case ..<10: return "4s_to_10s"
        default: return "over_10s"
        }
    }

    static func resumeAgeBucket(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<30: return "under_30s"
        case ..<120: return "30s_to_2m"
        case ..<600: return "2m_to_10m"
        default: return "over_10m"
        }
    }

    static func tabCountBucket(_ count: Int) -> String {
        switch count {
        case ...0: return "0"
        case 1: return "1"
        case 2...5: return "2_to_5"
        case 6...10: return "6_to_10"
        case 11...20: return "11_to_20"
        case 21...50: return "21_to_50"
        default: return "over_50"
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

    private static func ageBucket(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<30: return "30s"
        case ..<60: return "1m"
        case ..<120: return "2m"
        case ..<300: return "5m"
        case ..<900: return "15m"
        default: return "over_15"
        }
    }

    /// `token@<age bucket>` entries, oldest first, comma-separated; drops the oldest entries until the value fits the cap.
    /// Tokens are sanitized (they may embed error domain/code pairs).
    static func backgroundEventsValue(_ events: [BackgroundEvent]) -> String {
        var entries = events.map { event -> String in
            let token = sanitizedEventToken(event.token)
            return "\(token)@\(ageBucket(event.secondsBeforeSnapshot))"
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
