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
        var committedURL: URL?
        var didReceiveResponse = false
        var navigationKind: CPMNavigationKind = .other
        var measurement: CPMMessagingMeasurement?
        var timeoutTask: Task<Void, Never>?
        var crashPending = false
    }

    private struct BufferedResponse {
        let url: URL
        let receivedAt: Date
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
    private var bufferedResponses: [Int: BufferedResponse] = [:]

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
        let eventDescription = event.logDescription
        let previousState = logStateDescription
        Logger.webExtensions.debug("[CPM Health Monitor] Event received: \(eventDescription, privacy: .public)")
        defer { logState(after: eventDescription, previousState: previousState) }

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
        state.navigationKind = navigationKind
        state.committedURL = nil
        state.didReceiveResponse = false
        state.measurement = nil
        state.timeoutTask = nil
        tabs[tabIdentifier] = state
    }

    /// Records the committed document and retries responses buffered before native commit arrived.
    /// - Parameters identify the stable app tab and its committed URL.
    private func commitNavigation(in tabIdentifier: String, url: URL) {
        var state = tabs[tabIdentifier] ?? TabNavigationState()
        state.committedURL = url
        state.didReceiveResponse = false
        tabs[tabIdentifier] = state
        associateBufferedResponses()
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
        var state = tabs[tabIdentifier] ?? TabNavigationState()
        guard state.committedURL?.matchesCPMDiagnosticsDocument(url) ?? true else { return }
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
        let measurement = beginMeasurement(tabIdentifier: tabIdentifier, navigationKind: effectiveNavigationKind)
        state.measurement = measurement
        tabs[tabIdentifier] = state

        if state.didReceiveResponse {
            reportSuccess(measurement)
            tabs[tabIdentifier]?.measurement = nil
            return
        }

        scheduleTimeout(
            tabIdentifier: tabIdentifier,
            generation: state.generation,
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
        let eventDescription = "timeoutElapsed tab=\(tabIdentifier) generation=\(generation) measurement=\(measurement.identifier) outcome=\(outcome)"
        let previousState = logStateDescription
        Logger.webExtensions.debug("[CPM Health Monitor] Event received: \(eventDescription, privacy: .public)")
        defer { logState(after: eventDescription, previousState: previousState) }

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
    /// A known numeric extension-tab mapping wins. Otherwise a uniquely matching committed URL
    /// establishes the mapping; ambiguous responses are buffered until a later commit resolves
    /// them without guessing between tabs that share a URL.
    private func receiveDashboardResponse(extensionTabIdentifier: Int?, url: URL) {
        if let extensionTabIdentifier,
           let tabIdentifier = extensionTabMappings[extensionTabIdentifier],
           responseMatchesCurrentNavigation(url, in: tabIdentifier) {
            markResponseReceived(in: tabIdentifier)
            return
        }

        let candidates = availableCandidateTabs(for: url)

        if candidates.count == 1, let tabIdentifier = candidates.first {
            if let extensionTabIdentifier {
                extensionTabMappings[extensionTabIdentifier] = tabIdentifier
                bufferedResponses[extensionTabIdentifier] = nil
            }
            markResponseReceived(in: tabIdentifier)
        } else if let extensionTabIdentifier {
            bufferedResponses[extensionTabIdentifier] = BufferedResponse(url: url, receivedAt: now())
            associateBufferedResponses()
            closeEpisodeForUnattributedSuccess()
        } else {
            closeEpisodeForUnattributedSuccess()
        }
    }

    /// Returns whether a response URL belongs to the tab's current committed document.
    private func responseMatchesCurrentNavigation(_ url: URL, in tabIdentifier: String) -> Bool {
        tabs[tabIdentifier]?.committedURL?.matchesCPMDiagnosticsDocument(url) == true
    }

    /// Returns unanswered app tabs whose current committed document matches an extension response.
    private func availableCandidateTabs(for url: URL) -> [String] {
        tabs.compactMap { tabIdentifier, state -> String? in
            guard !state.didReceiveResponse,
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
        state.didReceiveResponse = true
        state.timeoutTask?.cancel()
        state.timeoutTask = nil
        tabs[tabIdentifier] = state

        if let measurement = state.measurement {
            reportSuccess(measurement)
            tabs[tabIdentifier]?.measurement = nil
        }
    }

    /// Resolves responses that could not initially be attributed to one app tab.
    ///
    /// Unique matches are consumed first. When several restored tabs share a URL, an equal number
    /// of distinct extension-tab responses proves that every candidate answered even though the
    /// individual extension-to-app tab pairing is unknowable; those responses are paired as a batch.
    private func associateBufferedResponses() {
        while let uniqueMatch = bufferedResponses.first(where: { availableCandidateTabs(for: $0.value.url).count == 1 }),
              let tabIdentifier = availableCandidateTabs(for: uniqueMatch.value.url).first {
            let extensionTabIdentifier = uniqueMatch.key
            extensionTabMappings[extensionTabIdentifier] = tabIdentifier
            bufferedResponses[extensionTabIdentifier] = nil
            markResponseReceived(in: tabIdentifier)
        }

        let groupedResponses = Dictionary(grouping: bufferedResponses.keys) { extensionTabIdentifier in
            bufferedResponses[extensionTabIdentifier].map { availableCandidateTabs(for: $0.url).sorted() } ?? []
        }
        for (candidateTabs, extensionTabIdentifiers) in groupedResponses where !candidateTabs.isEmpty {
            guard let response = extensionTabIdentifiers.first.flatMap({ bufferedResponses[$0] }),
                  availableCandidateTabs(for: response.url).sorted() == candidateTabs,
                  extensionTabIdentifiers.count == candidateTabs.count else {
                continue
            }
            for (extensionTabIdentifier, tabIdentifier) in zip(extensionTabIdentifiers.sorted(), candidateTabs) {
                extensionTabMappings[extensionTabIdentifier] = tabIdentifier
                bufferedResponses[extensionTabIdentifier] = nil
                markResponseReceived(in: tabIdentifier)
            }
        }
    }

    /// Treats an unmapped response as process health only when no reload boundary is active.
    private func closeEpisodeForUnattributedSuccess() {
        // A response without a native-tab mapping proves the current process is responsive only
        // when no reload boundary must be crossed. After a reload, require a mapped measurement
        // from the new generation so a delayed response from the old process cannot claim recovery.
        guard let episode, episode.reloadGeneration == nil else { return }
        if episode.isStuck {
            pixelFiring.fire(.cpmMessagingRecoveredWithoutExtensionReload)
        }
        self.episode = nil
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
        if !preserveCrashMarker {
            state.crashPending = false
        }
        tabs[tabIdentifier] = state
    }

    /// Removes all navigation work and extension-tab mappings owned by a closed tab, then retries
    /// buffered response attribution because removing the tab may leave a unique matching candidate.
    /// - Parameter tabIdentifier: Stable app identifier for the closed tab.
    private func removeTab(_ tabIdentifier: String) {
        if let state = tabs.removeValue(forKey: tabIdentifier) {
            state.timeoutTask?.cancel()
            cancelMeasurement(state.measurement)
        }
        extensionTabMappings = extensionTabMappings.filter { $0.value != tabIdentifier }
        associateBufferedResponses()
    }

    /// Starts a navigation-scoped measurement and captures the current extension reload generation.
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

        // Snapshot every measurement already in flight. None of them can independently confirm this
        // failure. Restoration failures seed an episode, but only a later non-restoration navigation
        // can confirm it because delayed startup affects the whole restored-tab batch.
        guard var episode else {
            let newEpisode = Episode(
                failureReason: failureReason,
                startedAt: now(),
                confirmationMustBeginAfter: latestMeasurementIdentifier,
                failedTabIdentifiers: [measurement.tabIdentifier],
                reloadGeneration: isPostExtensionReload ? measurement.extensionReloadGeneration : nil
            )
            self.episode = newEpisode
            if isPostExtensionReload {
                pixelFiring.fire(.cpmMessagingExtensionReloadFailed)
            }
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
            pixelFiring.fire(.cpmMessagingExtensionReloadFailed)
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
    /// Both attributed and buffered responses are context-scoped evidence. Clearing them at each
    /// reload boundary prevents an old response from satisfying a new-generation measurement.
    private func invalidateNavigationEvidenceForReload() {
        bufferedResponses.removeAll()
        for tabIdentifier in Array(tabs.keys) {
            guard var state = tabs[tabIdentifier] else { continue }
            state.timeoutTask?.cancel()
            cancelMeasurement(state.measurement)
            state.timeoutTask = nil
            state.measurement = nil
            state.didReceiveResponse = false
            tabs[tabIdentifier] = state
        }
    }

    /// Expires correlation state that can no longer safely participate in a health decision.
    ///
    /// Measurements and buffered responses have bounded attribution windows. Removing their tokens
    /// from tab state also cancels deadlines that could otherwise report after the evidence expired.
    private func discardExpiredState() {
        let currentDate = now()
        if let episode, currentDate.timeIntervalSince(episode.startedAt) >= episodeLifetime {
            self.episode = nil
        }
        let expiredMeasurements = measurements.values.filter { currentDate.timeIntervalSince($0.startedAt) >= episodeLifetime }
        for record in expiredMeasurements {
            cancel(record.measurement)
        }
        bufferedResponses = bufferedResponses.filter { currentDate.timeIntervalSince($0.value.receivedAt) < extensionLoadWait }
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

    /// Logs the resulting state after an event, explicitly identifying inputs that made no change.
    private func logState(after eventDescription: String, previousState: String) {
        let currentState = logStateDescription
        if currentState == previousState {
            Logger.webExtensions.debug("[CPM Health Monitor] State unchanged after \(eventDescription, privacy: .public)")
        } else {
            Logger.webExtensions.debug("[CPM Health Monitor] State changed after \(eventDescription, privacy: .public): \(currentState, privacy: .public)")
        }
    }

    /// Produces a deterministic, URL-free snapshot of all state used by the health algorithm.
    private var logStateDescription: String {
        let tabDescriptions = tabs.keys.sorted().compactMap { tabIdentifier -> String? in
            guard let state = tabs[tabIdentifier] else { return nil }
            let measurementIdentifier = state.measurement.map { String($0.identifier) } ?? "none"
            return "\(tabIdentifier){generation=\(state.generation),kind=\(state.navigationKind.rawValue),committed=\(state.committedURL != nil)," +
                "response=\(state.didReceiveResponse),measurement=\(measurementIdentifier)," +
                "timeout=\(state.timeoutTask != nil),crashPending=\(state.crashPending)}"
        }
        let measurementDescriptions = measurements.keys.sorted().compactMap { identifier -> String? in
            guard let record = measurements[identifier] else { return nil }
            return "\(identifier){tab=\(record.measurement.tabIdentifier),kind=\(record.measurement.navigationKind.rawValue)," +
                "reloadGeneration=\(record.measurement.extensionReloadGeneration),state=\(record.state)}"
        }
        let mappingDescriptions = extensionTabMappings.keys.sorted().compactMap { extensionTabIdentifier -> String? in
            guard let tabIdentifier = extensionTabMappings[extensionTabIdentifier] else { return nil }
            return "\(extensionTabIdentifier)->\(tabIdentifier)"
        }
        let episodeDescription: String
        if let episode {
            episodeDescription = "reason=\(episode.failureReason.rawValue),stuck=\(episode.isStuck)," +
                "confirmAfter=\(episode.confirmationMustBeginAfter),failedTabs=\(episode.failedTabIdentifiers.sorted())," +
                "reloadGeneration=\(episode.reloadGeneration.logDescription)"
        } else {
            episodeDescription = "none"
        }

        let tabsDescription = tabDescriptions.joined(separator: ";")
        let measurementsDescription = measurementDescriptions.joined(separator: ";")
        let mappingsDescription = mappingDescriptions.joined(separator: ";")
        let bufferedExtensionTabsDescription = String(describing: bufferedResponses.keys.sorted())
        let pendingReloadGenerationDescription = pendingExtensionReloadMeasurementGeneration.logDescription
        let postReloadMeasurementDescription = postReloadMeasurementIdentifier.logDescription

        return "tabs=[\(tabsDescription)] measurements=[\(measurementsDescription)] mappings=[\(mappingsDescription)] " +
            "bufferedExtensionTabs=\(bufferedExtensionTabsDescription) episode={\(episodeDescription)} " +
            "reloadGeneration=\(extensionReloadGeneration) pendingReloadGeneration=\(pendingReloadGenerationDescription) " +
            "postReloadMeasurement=\(postReloadMeasurementDescription) simulation=\(isCPMMessagingBreakageSimulationEnabled)"
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
    /// Matches the looser page identity used by the CPM dashboard, whose state follows query and
    /// fragment changes. This preserves the dashboard's pre-diagnostics matching behavior.
    func matchesCPMDashboardStatePage(_ other: URL) -> Bool {
        host == other.host && normalizedCPMPath == other.normalizedCPMPath
    }

    /// Matches the document identity supplied by autoconsent while ignoring only the fragment,
    /// which is not sent to the server and may change without a new document load.
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
