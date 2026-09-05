//
//  CPMMessagingHealthMonitor.swift
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
import OSLog

/// Bounds how long separate navigation results may be attributed to the same CPM health episode.
private let cpmMessagingEpisodeLifetime: TimeInterval = .minutes(5)
private let cpmMessagingExtensionLoadWait: TimeInterval = .seconds(30)
private let cpmMessagingResponseGracePeriod: TimeInterval = .seconds(4)

/// Describes the navigation context in which CPM initialization was measured.
public enum CPMNavigationKind: String, Equatable, Sendable {
    /// A navigation performed while restoring a tab from the previous session at browser startup.
    case sessionRestoration = "session_restoration"
    /// A history navigation that may restore a cached document without rerunning CPM initialization.
    case backForward = "back_forward"
    /// The first completed navigation after the tab's web-content process terminated.
    case tabCrash = "tab_crash"
    /// Any other completed main-frame navigation.
    case other
}

/// Cause shared by a CPM initialization failure and the stuck episode that failure may begin.
public enum CPMMessagingFailureReason: String, Sendable {
    /// Initialization timed out on a session-restored navigation.
    case sessionRestoration = "session_restoration"
    /// Initialization timed out on the first navigation after a tab crash.
    case tabCrash = "tab_crash"
    /// Initialization timed out on the first measurement after an extension reload.
    case extensionReload = "extension_reload"
    /// Initialization timed out on another navigation.
    case other
}

/// Facts supplied by tabs, the native messaging handler, and the extension manager.
///
/// The health monitor owns all timing and correlation. Platform tabs translate their navigation
/// callbacks into these events, and the monitor determines health from extension responses.
@available(macOS 15.4, iOS 18.4, *)
public enum CPMMessagingHealthEvent: Sendable {
    case navigationStarted(tabIdentifier: String, navigationKind: CPMNavigationKind)
    case navigationCommitted(tabIdentifier: String, url: URL)
    case navigationFinished(tabIdentifier: String, url: URL, extensionIsLoaded: Bool)
    case navigationFailed(tabIdentifier: String)
    case tabClosed(tabIdentifier: String)
    case webContentProcessTerminated(tabIdentifier: String)
    case dashboardResponse(extensionTabIdentifier: Int?, url: URL)
    case extensionLifecycle(WebExtensionLifecycleEvent)
}

@available(macOS 15.4, iOS 18.4, *)
public protocol CPMMessagingHealthMonitoring: AnyObject, Sendable {
    @MainActor
    func handle(_ event: CPMMessagingHealthEvent)
}

/// Internal token tying a completed navigation to its eventual response or timeout.
struct CPMMessagingMeasurement: Equatable, Sendable {
    let identifier: UInt
    let tabIdentifier: String
    let navigationKind: CPMNavigationKind
    let extensionReloadGeneration: UInt
}

/// Correlates navigation, native-message, crash, and extension-lifecycle events across all tabs.
///
/// The monitor owns navigation-scoped timers and the browser-wide stuck episode. A failure starts an
/// episode; only a later navigation can confirm it, so simultaneous startup loads cannot race each
/// other into a stuck report. Session-restoration failures can seed an episode, but other restored
/// tabs cannot confirm it; only a later regular navigation failure proves the condition persisted
/// beyond the expected startup race.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
public final class CPMMessagingHealthMonitor: CPMMessagingHealthMonitoring {

    private enum TimeoutOutcome: Sendable {
        case reportFailure
        case cancelMeasurement
    }

    private struct TabNavigationState {
        var generation: UInt = 0
        var extensionReloadGeneration: UInt = 0
        var committedURL: URL?
        var didReceiveResponse = false
        var navigationKind: CPMNavigationKind = .other
        var measurement: CPMMessagingMeasurement?
        var timeoutTask: Task<Void, Never>?
        var crashPending = false
        /// Set when a response arrived that could not be tied to this navigation's document, so
        /// neither outcome is provable for it. Survives until the next navigation starts.
        var didReceiveUnattributableResponse = false
    }

    private enum MeasurementState: Equatable {
        case pending
        case failed
    }

    private struct MeasurementRecord {
        let measurement: CPMMessagingMeasurement
        let startedAt: Date
        var state: MeasurementState
    }

    /// State retained from the first failure until a later, relevant CPM response closes the episode.
    private struct Episode {
        let failureReason: CPMMessagingFailureReason
        let startedAt: Date
        /// Measurements up to this identifier were already in flight when the first failure arrived.
        let confirmationMustBeginAfter: UInt
        var failedTabIdentifiers: Set<String>
        var isStuck = false
        /// The successful reload that a recovery must post-date to be attributed to that reload.
        var reloadGeneration: UInt?
    }

    private let pixelFiring: WebExtensionPixelFiring
    private let episodeLifetime: TimeInterval
    private let extensionLoadWait: TimeInterval
    private let responseGracePeriod: TimeInterval
    private let now: () -> Date
    private var episode: Episode?
    private var latestMeasurementIdentifier: UInt = 0
    private var measurements: [UInt: MeasurementRecord] = [:]
    private(set) var extensionReloadGeneration: UInt = 0

    /// Debug-only switch that makes dashboard responses invisible to the health algorithm.
    public private(set) var isCPMMessagingBreakageSimulationEnabled = false

    /// Navigation state is keyed by the app's stable tab identifier. The extension's numeric tab
    /// identifier is learned from the first unambiguous response and retained only for correlation.
    private var tabs: [String: TabNavigationState] = [:]
    private var extensionTabMappings: [Int: String] = [:]

    /// The first navigation begun with this generation measures whether the latest reload restored messaging.
    private var pendingExtensionReloadMeasurementGeneration: UInt?
    private var postReloadMeasurementIdentifier: UInt?

    /// Creates a monitor using production timeout and episode-lifetime values.
    /// - Parameter pixelFiring: Sink used for CPM health telemetry.
    public convenience init(pixelFiring: WebExtensionPixelFiring) {
        self.init(
            pixelFiring: pixelFiring,
            episodeLifetime: cpmMessagingEpisodeLifetime,
            extensionLoadWait: cpmMessagingExtensionLoadWait,
            responseGracePeriod: cpmMessagingResponseGracePeriod,
            now: Date.init
        )
    }

    /// Enables or disables Debug-menu simulation of missing CPM dashboard responses.
    public func setBreakageSimulationEnabled(_ isEnabled: Bool) {
        guard isCPMMessagingBreakageSimulationEnabled != isEnabled else { return }
        isCPMMessagingBreakageSimulationEnabled = isEnabled
        Logger.webExtensions.debug("[CPM Health Monitor] Breakage simulation changed: enabled=\(isEnabled)")
    }

    /// Creates a monitor with injectable timing for deterministic state-machine tests.
    /// - Parameters:
    ///   - pixelFiring: Sink used for CPM health telemetry.
    ///   - episodeLifetime: Maximum interval over which failures may form one episode.
    ///   - extensionLoadWait: Maximum wait for an extension that was not loaded at navigation finish.
    ///   - responseGracePeriod: Wait for a dashboard response after navigation or extension load.
    ///   - now: Clock used to expire measurements, responses, and episodes.
    init(
        pixelFiring: WebExtensionPixelFiring,
        episodeLifetime: TimeInterval,
        extensionLoadWait: TimeInterval = cpmMessagingExtensionLoadWait,
        responseGracePeriod: TimeInterval = cpmMessagingResponseGracePeriod,
        now: @escaping () -> Date
    ) {
        self.pixelFiring = pixelFiring
        self.episodeLifetime = episodeLifetime
        self.extensionLoadWait = extensionLoadWait
        self.responseGracePeriod = responseGracePeriod
        self.now = now
    }

    /// Applies one tab, native-message, or extension-lifecycle event to the shared health state.
    public func handle(_ event: CPMMessagingHealthEvent) {
        defer { Logger.webExtensions.debug("[CPM Health Monitor] \(event.logDescription, privacy: .public) -> \(self.logStateDescription, privacy: .public)") }

        discardExpiredState()

        switch event {
        case .navigationStarted(let tabIdentifier, let navigationKind):
            startNavigation(in: tabIdentifier, navigationKind: navigationKind)
        case .navigationCommitted(let tabIdentifier, let url):
            commitNavigation(in: tabIdentifier, url: url)
        case .navigationFinished(let tabIdentifier, let url, let extensionIsLoaded):
            finishNavigation(in: tabIdentifier, url: url, extensionIsLoaded: extensionIsLoaded)
        case .navigationFailed(let tabIdentifier):
            cancelCurrentNavigation(in: tabIdentifier, preserveCrashMarker: true)
        case .tabClosed(let tabIdentifier):
            removeTab(tabIdentifier)
        case .webContentProcessTerminated(let tabIdentifier):
            markWebContentProcessTerminated(in: tabIdentifier)
        case .dashboardResponse(let extensionTabIdentifier, let url):
            if !isCPMMessagingBreakageSimulationEnabled {
                receiveDashboardResponse(extensionTabIdentifier: extensionTabIdentifier, url: url)
            }
        case .extensionLifecycle(let lifecycleEvent):
            handle(lifecycleEvent)
        }
    }

    /// Invalidates the previous document's work and advances the tab generation.
    /// Generation changes prevent a late timeout from affecting a replacement navigation.
    private func startNavigation(in tabIdentifier: String, navigationKind: CPMNavigationKind) {
        var state = tabs[tabIdentifier] ?? TabNavigationState()
        cancelMeasurement(state.measurement)
        state.timeoutTask?.cancel()
        state.generation &+= 1
        state.extensionReloadGeneration = extensionReloadGeneration
        state.navigationKind = navigationKind
        state.committedURL = nil
        state.didReceiveResponse = false
        state.didReceiveUnattributableResponse = false
        state.measurement = nil
        state.timeoutTask = nil
        tabs[tabIdentifier] = state
    }

    /// Records the committed document and retries responses buffered before native commit arrived.
    /// - Parameters identify the stable app tab and its committed URL.
    private func commitNavigation(in tabIdentifier: String, url: URL) {
        guard url.isEligibleForCPMMessagingHealthMeasurement else {
            cancelCurrentNavigation(in: tabIdentifier, preserveCrashMarker: true)
            return
        }
        var state = tabs[tabIdentifier] ?? TabNavigationState()
        guard state.extensionReloadGeneration == extensionReloadGeneration else {
            cancelCurrentNavigation(in: tabIdentifier, preserveCrashMarker: true)
            return
        }
        state.committedURL = url
        state.didReceiveResponse = false
        tabs[tabIdentifier] = state
    }

    /// Starts CPM measurement for an eligible completed document.
    ///
    /// Crash attribution overrides the supplied navigation kind. Back/forward cache restores are
    /// excluded because WebKit does not guarantee a new content-script initialization signal.
    private func finishNavigation(
        in tabIdentifier: String,
        url: URL,
        extensionIsLoaded: Bool
    ) {
        guard url.isEligibleForCPMMessagingHealthMeasurement else {
            cancelCurrentNavigation(in: tabIdentifier, preserveCrashMarker: true)
            return
        }
        var state = tabs[tabIdentifier] ?? TabNavigationState()
        // Checked before the generation sync below, so a dropped finish cannot leave the tab
        // half-updated — it stays on its own generation until a finish this monitor accepts.
        guard state.committedURL?.matchesCPMDiagnosticsDocument(url) ?? true else {
            Logger.webExtensions.debug("[CPM Health Monitor] Dropped navigationFinished: URL differs from committed document, tab=\(tabIdentifier, privacy: .public)")
            return
        }
        if state.extensionReloadGeneration != extensionReloadGeneration {
            // A navigation spanning an extension reload is measured against the replacement
            // context once it finishes. Responses received before this point remain stale.
            state.extensionReloadGeneration = extensionReloadGeneration
            state.didReceiveResponse = false
        }
        state.committedURL = url

        let effectiveNavigationKind: CPMNavigationKind = state.crashPending ? .tabCrash : state.navigationKind
        state.crashPending = false

        // Back/forward cache restoration does not guarantee that content scripts rerun, so the
        // absence of a fresh dashboard response is not a CPM health signal. A pending crash takes
        // precedence above because the restored document then belongs to a new content process.
        guard effectiveNavigationKind != .backForward else {
            tabs[tabIdentifier] = state
            return
        }

        // A response already arrived for this navigation that could not be attributed to it, so
        // measuring it now could only produce an unprovable failure.
        guard !state.didReceiveUnattributableResponse else {
            tabs[tabIdentifier] = state
            return
        }

        // `beginMeasurement` may mutate this tab's entry, so commit the local copy first and go
        // through the dictionary afterwards.
        let generation = state.generation
        let didReceiveResponse = state.didReceiveResponse
        tabs[tabIdentifier] = state

        let measurement = beginMeasurement(tabIdentifier: tabIdentifier, navigationKind: effectiveNavigationKind)
        tabs[tabIdentifier]?.measurement = measurement

        if didReceiveResponse {
            reportSuccess(measurement)
            tabs[tabIdentifier]?.measurement = nil
            return
        }

        scheduleTimeout(
            tabIdentifier: tabIdentifier,
            generation: generation,
            measurement: measurement,
            delay: extensionIsLoaded ? responseGracePeriod : extensionLoadWait,
            outcome: extensionIsLoaded ? .reportFailure : .cancelMeasurement
        )
    }

    /// Schedules the deadline for one navigation generation and measurement token.
    ///
    /// Both identifiers are checked when the task wakes, preventing cancelled or superseded
    /// navigations from reporting against the current document.
    private func scheduleTimeout(
        tabIdentifier: String,
        generation: UInt,
        measurement: CPMMessagingMeasurement,
        delay: TimeInterval,
        outcome: TimeoutOutcome
    ) {
        tabs[tabIdentifier]?.timeoutTask?.cancel()
        tabs[tabIdentifier]?.timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.timeoutElapsed(
                tabIdentifier: tabIdentifier,
                generation: generation,
                measurement: measurement,
                outcome: outcome
            )
        }
    }

    /// Applies a deadline only when its tab generation and measurement are still current.
    /// - Parameters identify the scheduled navigation and whether expiry reports or cancels it.
    private func timeoutElapsed(
        tabIdentifier: String,
        generation: UInt,
        measurement: CPMMessagingMeasurement,
        outcome: TimeoutOutcome
    ) {
        defer { Logger.webExtensions.debug("[CPM Health Monitor] timeoutElapsed tab=\(tabIdentifier, privacy: .public) generation=\(generation, privacy: .public) measurement=\(measurement.identifier, privacy: .public) outcome=\(String(describing: outcome), privacy: .public) -> \(self.logStateDescription, privacy: .public)") }

        guard var state = tabs[tabIdentifier],
              state.generation == generation,
              state.measurement == measurement,
              !state.didReceiveResponse else {
            return
        }
        state.timeoutTask = nil
        tabs[tabIdentifier] = state

        switch outcome {
        case .reportFailure:
            reportFailure(measurement)
        case .cancelMeasurement:
            cancelMeasurement(measurement)
            tabs[tabIdentifier]?.measurement = nil
        }
    }

    /// Correlates an extension response with the app tab that owns its document.
    ///
    /// A known extension-tab mapping identifies the sender; otherwise a uniquely matching committed
    /// URL establishes one. A response that cannot be tied to exactly one tab reports nothing: the
    /// affected navigations are abandoned rather than guessed at, because neither a failure nor a
    /// recovery is provable for them.
    private func receiveDashboardResponse(extensionTabIdentifier: Int?, url: URL) {
        guard url.isEligibleForCPMMessagingHealthMeasurement else { return }

        if let extensionTabIdentifier,
           let tabIdentifier = extensionTabMappings[extensionTabIdentifier] {
            if responseMatchesCurrentNavigation(url, in: tabIdentifier) {
                markResponseReceived(in: tabIdentifier)
            } else if isTabOnCurrentExtensionGeneration(tabIdentifier) {
                // Known sender on the loaded context, but not the document being measured — usually
                // the response beat `navigationCommitted`. Neither outcome is provable.
                abandonMeasurement(in: tabIdentifier)
            }
            // A response from a pre-reload generation is stale evidence, not grounds to abandon the
            // replacement context's navigation: that one still has to prove itself.
            return
        }

        let candidates = availableCandidateTabs(for: url)

        if candidates.count == 1, let tabIdentifier = candidates.first {
            if let extensionTabIdentifier {
                extensionTabMappings[extensionTabIdentifier] = tabIdentifier
            }
            markResponseReceived(in: tabIdentifier)
            return
        }

        Logger.webExtensions.debug("[CPM Health Monitor] Unattributable dashboard response: extensionTab=\(extensionTabIdentifier.logDescription, privacy: .public) candidates=\(candidates.count, privacy: .public)")
        for tabIdentifier in candidates {
            abandonMeasurement(in: tabIdentifier)
        }

        // No tab may be reported failed or recovered on this response's account, but matching some
        // tab's committed document still proves the extension is answering — and an episode is
        // browser-wide, so that is all closing one requires. A response matching nothing proves
        // nothing: it may be stale, or response and navigation URLs may disagree, and crediting it
        // would pair a recovery with the failure its own tab is still about to report.
        guard !candidates.isEmpty else { return }
        closeEpisodeForCurrentGeneration()
    }

    /// Closes an episode on proof that the extension is answering, without attributing it to a tab.
    ///
    /// After a reload only a measurement begun against the new generation may validate it, so a
    /// response that cannot be tied to one is not allowed to claim that recovery.
    private func closeEpisodeForCurrentGeneration() {
        guard let episode, episode.reloadGeneration == nil else { return }
        if episode.isStuck {
            pixelFiring.fire(.cpmMessagingRecoveredWithoutExtensionReload)
        }
        self.episode = nil
    }

    /// Whether the tab's navigation belongs to the extension context that is currently loaded.
    private func isTabOnCurrentExtensionGeneration(_ tabIdentifier: String) -> Bool {
        tabs[tabIdentifier]?.extensionReloadGeneration == extensionReloadGeneration
    }

    /// Returns whether a response URL belongs to the tab's current committed document.
    private func responseMatchesCurrentNavigation(_ url: URL, in tabIdentifier: String) -> Bool {
        guard let state = tabs[tabIdentifier],
              state.extensionReloadGeneration == extensionReloadGeneration else {
            return false
        }
        return state.committedURL?.matchesCPMDiagnosticsDocument(url) == true
    }

    /// Returns unanswered app tabs whose current committed document matches an extension response.
    private func availableCandidateTabs(for url: URL) -> [String] {
        tabs.compactMap { tabIdentifier, state -> String? in
            guard state.extensionReloadGeneration == extensionReloadGeneration,
                  !state.didReceiveResponse,
                  state.committedURL?.matchesCPMDiagnosticsDocument(url) == true else {
                return nil
            }
            return tabIdentifier
        }
    }

    /// Cancels the tab deadline and completes its active measurement when present.
    /// A pre-finish response remains recorded so finishing the same navigation succeeds immediately.
    private func markResponseReceived(in tabIdentifier: String) {
        guard var state = tabs[tabIdentifier] else { return }
        Logger.webExtensions.debug("[CPM Health Monitor] Dashboard response attributed to tab=\(tabIdentifier, privacy: .public)")
        state.didReceiveResponse = true
        state.timeoutTask?.cancel()
        state.timeoutTask = nil
        tabs[tabIdentifier] = state

        if let measurement = state.measurement {
            reportSuccess(measurement)
            tabs[tabIdentifier]?.measurement = nil
        }
    }

    /// Drops a navigation's measurement without reporting either outcome, and stops a later
    /// `finishNavigation` starting a new one for the same navigation.
    ///
    /// Only ever prevents an *unreported* outcome. A measurement that already failed is a fact on
    /// record, and its token is what a later attributed response needs to report the recovery.
    private func abandonMeasurement(in tabIdentifier: String) {
        guard var state = tabs[tabIdentifier] else { return }
        if let measurement = state.measurement, measurements[measurement.identifier]?.state == .failed {
            return
        }
        state.didReceiveUnattributableResponse = true
        state.timeoutTask?.cancel()
        state.timeoutTask = nil
        cancelMeasurement(state.measurement)
        state.measurement = nil
        tabs[tabIdentifier] = state
    }

    /// Cancels work owned by the terminated process and attributes the tab's next finish to a crash.
    /// - Parameter tabIdentifier: Stable app identifier for the crashed tab.
    private func markWebContentProcessTerminated(in tabIdentifier: String) {
        cancelCurrentNavigation(in: tabIdentifier, preserveCrashMarker: false)
        var state = tabs[tabIdentifier] ?? TabNavigationState()
        state.crashPending = true
        tabs[tabIdentifier] = state
    }

    /// Cancels navigation-scoped work while optionally retaining attribution from an earlier crash.
    /// - Parameters identify the tab and whether an existing crash marker survives cancellation so
    ///   a provisional failure cannot erase the crash before the eventual successful navigation.
    private func cancelCurrentNavigation(in tabIdentifier: String, preserveCrashMarker: Bool) {
        guard var state = tabs[tabIdentifier] else { return }
        state.timeoutTask?.cancel()
        cancelMeasurement(state.measurement)
        state.timeoutTask = nil
        state.measurement = nil
        state.committedURL = nil
        state.didReceiveResponse = false
        state.didReceiveUnattributableResponse = false
        if !preserveCrashMarker {
            state.crashPending = false
        }
        tabs[tabIdentifier] = state
    }

    /// Removes all navigation work and extension-tab mappings owned by a closed tab.
    /// - Parameter tabIdentifier: Stable app identifier for the closed tab.
    private func removeTab(_ tabIdentifier: String) {
        if let state = tabs.removeValue(forKey: tabIdentifier) {
            state.timeoutTask?.cancel()
            cancelMeasurement(state.measurement)
        }
        extensionTabMappings = extensionTabMappings.filter { $0.value != tabIdentifier }
    }

    /// Starts a navigation-scoped measurement and captures the current extension reload generation.
    ///
    /// - Important: This expires stale state and may therefore mutate `tabs`, including the entry
    ///   for `tabIdentifier`. Callers must not hold a local `TabNavigationState` copy across it.
    func beginMeasurement(tabIdentifier: String, navigationKind: CPMNavigationKind) -> CPMMessagingMeasurement {
        discardExpiredState()
        latestMeasurementIdentifier &+= 1
        let measurement = CPMMessagingMeasurement(
            identifier: latestMeasurementIdentifier,
            tabIdentifier: tabIdentifier,
            navigationKind: navigationKind,
            extensionReloadGeneration: extensionReloadGeneration
        )
        measurements[measurement.identifier] = MeasurementRecord(measurement: measurement, startedAt: now(), state: .pending)
        // Restored tabs may all fail during extension startup, so only a regular navigation can
        // become the first post-reload health check.
        if navigationKind != .sessionRestoration,
           pendingExtensionReloadMeasurementGeneration == measurement.extensionReloadGeneration {
            postReloadMeasurementIdentifier = measurement.identifier
            pendingExtensionReloadMeasurementGeneration = nil
        }
        return measurement
    }

    /// Removes an unfinished measurement when its owning navigation is replaced or the tab closes.
    /// A canceled post-reload probe returns its reservation to the next eligible navigation.
    func cancel(_ measurement: CPMMessagingMeasurement) {
        guard measurements[measurement.identifier]?.measurement == measurement else { return }
        measurements[measurement.identifier] = nil
        if postReloadMeasurementIdentifier == measurement.identifier {
            postReloadMeasurementIdentifier = nil
            if measurement.extensionReloadGeneration == extensionReloadGeneration {
                pendingExtensionReloadMeasurementGeneration = measurement.extensionReloadGeneration
            }
        }
    }

    /// Cancels an optional measurement token without requiring callers to unwrap it.
    private func cancelMeasurement(_ measurement: CPMMessagingMeasurement?) {
        guard let measurement else { return }
        cancel(measurement)
    }

    /// Records a CPM initialization timeout and advances the current health episode.
    ///
    /// - Parameter measurement: Token returned when the completed navigation began measurement.
    /// - Returns: `true` only when this failure newly promotes the episode to stuck.
    @discardableResult
    func reportFailure(_ measurement: CPMMessagingMeasurement) -> Bool {
        discardExpiredState()
        guard var record = measurements[measurement.identifier],
              record.measurement == measurement,
              record.state == .pending else {
            return false
        }
        record.state = .failed
        measurements[measurement.identifier] = record
        // Reload attribution is reserved when the navigation begins, so simultaneous tabs cannot
        // race to become "first" merely by returning their result sooner.
        let isPostExtensionReload = postReloadMeasurementIdentifier == measurement.identifier
        let failureReason: CPMMessagingFailureReason
        if isPostExtensionReload {
            failureReason = .extensionReload
            postReloadMeasurementIdentifier = nil
        } else {
            failureReason = measurement.navigationKind.failureReason
        }
        pixelFiring.fire(.cpmInitializationFailed(reason: failureReason))
        if isPostExtensionReload {
            pixelFiring.fire(.cpmMessagingExtensionReloadFailed)
        }

        // Snapshot every measurement already in flight. None of them can independently confirm this
        // failure. Restoration failures seed an episode, but only a later non-restoration navigation
        // can confirm it because delayed startup affects the whole restored-tab batch.
        guard var episode else {
            self.episode = Episode(
                failureReason: failureReason,
                startedAt: now(),
                confirmationMustBeginAfter: latestMeasurementIdentifier,
                failedTabIdentifiers: [measurement.tabIdentifier],
                reloadGeneration: isPostExtensionReload ? measurement.extensionReloadGeneration : nil
            )
            return false
        }

        episode.failedTabIdentifiers.insert(measurement.tabIdentifier)
        var didBecomeStuck = false
        // Require a non-restoration measurement begun after the first failure. Restored tabs may
        // finish serially, so they cannot confirm one another even when they were not concurrent.
        if !episode.isStuck,
           measurement.navigationKind != .sessionRestoration,
           measurement.identifier > episode.confirmationMustBeginAfter {
            episode.isStuck = true
            didBecomeStuck = true
            pixelFiring.fire(.cpmMessagingStuck(reason: episode.failureReason))
        }

        if isPostExtensionReload {
            episode.reloadGeneration = measurement.extensionReloadGeneration
        }
        self.episode = episode
        return didBecomeStuck
    }

    /// Records a CPM dashboard response and closes any active health episode.
    ///
    /// Any valid page response proves that the shared extension can currently answer. Responses from a
    /// pre-reload generation cannot validate a newer extension process and therefore leave that episode open.
    func reportSuccess(_ measurement: CPMMessagingMeasurement) {
        discardExpiredState()
        guard let record = measurements[measurement.identifier], record.measurement == measurement else { return }
        measurements[measurement.identifier] = nil
        if postReloadMeasurementIdentifier == measurement.identifier {
            postReloadMeasurementIdentifier = nil
        }
        guard let episode else { return }

        // Once a reload occurs, only a measurement begun against that generation can validate it.
        if let reloadGeneration = episode.reloadGeneration,
           measurement.extensionReloadGeneration < reloadGeneration {
            return
        }

        let didThisMeasurementFail = record.state == .failed
        if episode.isStuck || didThisMeasurementFail || episode.failedTabIdentifiers.contains(measurement.tabIdentifier) {
            if episode.reloadGeneration != nil {
                pixelFiring.fire(.cpmMessagingRecoveredAfterExtensionReload)
            } else {
                pixelFiring.fire(.cpmMessagingRecoveredWithoutExtensionReload)
            }
        }
        self.episode = nil
    }

    /// Updates CPM correlation state from an extension-manager lifecycle event.
    func handle(_ event: WebExtensionLifecycleEvent) {
        guard event.extensionType == .embedded else { return }
        discardExpiredState()

        switch event {
        case .loaded:
            startGracePeriodsForFinishedNavigations()
        case .willReload:
            invalidateNavigationEvidenceForReload()
        case .reloaded:
            // A response delivered while the old context was being unloaded is not evidence about
            // the replacement context, even if it arrived after `willReload` was handled.
            invalidateNavigationEvidenceForReload()
            // Generations distinguish navigations completed before and after a successful reload.
            extensionReloadGeneration &+= 1
            pendingExtensionReloadMeasurementGeneration = extensionReloadGeneration
            guard var episode else { return }
            episode.reloadGeneration = extensionReloadGeneration
            self.episode = episode
        case .reloadFailed:
            break
        }
    }

    /// Converts completed navigations that were waiting for extension load into timed measurements.
    ///
    /// A loaded event starts the short response grace period instead of immediately declaring failure.
    private func startGracePeriodsForFinishedNavigations() {
        for (tabIdentifier, state) in tabs {
            guard let measurement = state.measurement,
                  !state.didReceiveResponse,
                  measurements[measurement.identifier]?.state == .pending else {
                continue
            }
            scheduleTimeout(
                tabIdentifier: tabIdentifier,
                generation: state.generation,
                measurement: measurement,
                delay: responseGracePeriod,
                outcome: .reportFailure
            )
        }
    }

    /// Invalidates measurements and responses owned by the extension context being replaced.
    ///
    /// Responses are context-scoped evidence. Clearing document state at each reload boundary
    /// prevents an old response from satisfying a new-generation measurement. Proven tab-ID
    /// mappings remain useful, while generation checks reject their stale responses.
    private func invalidateNavigationEvidenceForReload() {
        for tabIdentifier in Array(tabs.keys) {
            guard var state = tabs[tabIdentifier] else { continue }
            state.timeoutTask?.cancel()
            cancelMeasurement(state.measurement)
            state.timeoutTask = nil
            state.measurement = nil
            state.committedURL = nil
            state.didReceiveResponse = false
            state.didReceiveUnattributableResponse = false
            tabs[tabIdentifier] = state
        }
    }

    /// Expires correlation state that can no longer safely participate in a health decision.
    ///
    /// Measurements have a bounded attribution window. Removing their tokens from tab state also
    /// cancels deadlines that could otherwise report after the evidence expired.
    private func discardExpiredState() {
        let currentDate = now()
        if let episode, currentDate.timeIntervalSince(episode.startedAt) >= episodeLifetime {
            self.episode = nil
        }
        let expiredMeasurements = measurements.values.filter { currentDate.timeIntervalSince($0.startedAt) >= episodeLifetime }
        for record in expiredMeasurements {
            cancel(record.measurement)
        }
        for tabIdentifier in Array(tabs.keys) {
            guard var state = tabs[tabIdentifier],
                  let measurement = state.measurement,
                  measurements[measurement.identifier] == nil else {
                continue
            }
            state.timeoutTask?.cancel()
            state.timeoutTask = nil
            state.measurement = nil
            tabs[tabIdentifier] = state
        }
    }

    private var logStateDescription: String {
        let episodeDescription: String
        if let episode {
            episodeDescription = "reason=\(episode.failureReason.rawValue),stuck=\(episode.isStuck)," +
                "confirmAfter=\(episode.confirmationMustBeginAfter),failedTabs=\(episode.failedTabIdentifiers.sorted())," +
                "reloadGeneration=\(episode.reloadGeneration.logDescription)"
        } else {
            episodeDescription = "none"
        }

        return "episode={\(episodeDescription)} " +
            "counts={tabs=\(tabs.count),measurements=\(measurements.count)," +
            "mappings=\(extensionTabMappings.count)} " +
            "reloadGeneration=\(extensionReloadGeneration) " +
            "pendingReloadGeneration=\(pendingExtensionReloadMeasurementGeneration.logDescription) " +
            "postReloadMeasurement=\(postReloadMeasurementIdentifier.logDescription)"
    }
}

@available(macOS 15.4, iOS 18.4, *)
public final class NoOpCPMMessagingHealthMonitor: CPMMessagingHealthMonitoring, @unchecked Sendable {
    /// Creates an event sink that intentionally performs no health tracking.
    public init() {}

    /// Discards a CPM health event.
    /// - Parameter event: Event ignored by this no-op implementation.
    @MainActor
    public func handle(_ event: CPMMessagingHealthEvent) {}
}

private extension CPMNavigationKind {
    var failureReason: CPMMessagingFailureReason {
        switch self {
        case .sessionRestoration: return .sessionRestoration
        case .tabCrash: return .tabCrash
        case .backForward, .other: return .other
        }
    }
}

@available(macOS 15.4, iOS 18.4, *)
private extension CPMMessagingHealthEvent {
    /// Describes an incoming event without recording a browsing URL.
    var logDescription: String {
        switch self {
        case .navigationStarted(let tabIdentifier, let navigationKind):
            return "navigationStarted tab=\(tabIdentifier) kind=\(navigationKind.rawValue)"
        case .navigationCommitted(let tabIdentifier, _):
            return "navigationCommitted tab=\(tabIdentifier)"
        case .navigationFinished(let tabIdentifier, _, let extensionIsLoaded):
            return "navigationFinished tab=\(tabIdentifier) extensionLoaded=\(extensionIsLoaded)"
        case .navigationFailed(let tabIdentifier):
            return "navigationFailed tab=\(tabIdentifier)"
        case .tabClosed(let tabIdentifier):
            return "tabClosed tab=\(tabIdentifier)"
        case .webContentProcessTerminated(let tabIdentifier):
            return "webContentProcessTerminated tab=\(tabIdentifier)"
        case .dashboardResponse(let extensionTabIdentifier, _):
            return "dashboardResponse extensionTab=\(extensionTabIdentifier.logDescription)"
        case .extensionLifecycle(let event):
            return "extensionLifecycle \(event.logDescription)"
        }
    }
}

@available(macOS 15.4, iOS 18.4, *)
private extension WebExtensionLifecycleEvent {
    /// Describes a lifecycle event and its reload trigger for CPM diagnostics.
    var logDescription: String {
        switch self {
        case .loaded(let identifier, let type):
            return "loaded identifier=\(identifier) type=\(String(describing: type))"
        case .willReload(let identifier, let type, let trigger):
            return "willReload identifier=\(identifier) type=\(String(describing: type)) trigger=\(trigger)"
        case .reloaded(let identifier, let type, let trigger):
            return "reloaded identifier=\(identifier) type=\(String(describing: type)) trigger=\(trigger)"
        case .reloadFailed(let identifier, let type, let trigger):
            return "reloadFailed identifier=\(identifier) type=\(String(describing: type)) trigger=\(trigger)"
        }
    }
}

private extension Optional where Wrapped: BinaryInteger {
    /// Formats optional identifiers and generations consistently in diagnostic logs.
    var logDescription: String {
        map(String.init) ?? "none"
    }
}

public extension URL {
    /// Whether CPM content-script messaging is expected for this document scheme.
    fileprivate var isEligibleForCPMMessagingHealthMeasurement: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// Matches the looser page identity used by the CPM dashboard, whose state follows query and
    /// fragment changes. This preserves the dashboard's pre-diagnostics matching behavior.
    ///
    /// Weaker than `matchesCPMDiagnosticsDocument(_:)`: ignores scheme, port and query, and compares
    /// the host case-sensitively. For dashboard state only, never for health correlation.
    func matchesCPMDashboardStatePage(_ other: URL) -> Bool {
        host == other.host && normalizedCPMPath == other.normalizedCPMPath
    }

    /// Matches the document identity supplied by autoconsent while ignoring only the fragment,
    /// which is not sent to the server and may change without a new document load.
    ///
    /// Stricter than `matchesCPMDashboardStatePage(_:)`; the two are not interchangeable.
    func matchesCPMDiagnosticsDocument(_ other: URL) -> Bool {
        scheme?.lowercased() == other.scheme?.lowercased() &&
        host?.lowercased() == other.host?.lowercased() &&
        port == other.port &&
        normalizedCPMPath == other.normalizedCPMPath &&
        query == other.query
    }

    private var normalizedCPMPath: String {
        path.isEmpty ? "/" : path
    }
}

@available(macOS 15.4, iOS 18.4, *)
private extension WebExtensionLifecycleEvent {
    var extensionType: DuckDuckGoWebExtensionType? {
        switch self {
        case .loaded(_, let type),
             .willReload(_, let type, _),
             .reloaded(_, let type, _),
             .reloadFailed(_, let type, _):
            return type
        }
    }
}
