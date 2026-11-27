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
import WebKit

/// Describes how a committed main-frame navigation started.
public enum CPMNavigationKind: String, Equatable, Sendable {
    /// A navigation performed while restoring a tab from the previous session at browser startup.
    case sessionRestoration = "session_restoration"
    /// A history navigation that may restore a cached document without rerunning CPM initialization.
    case backForward = "back_forward"
    /// The browser's own page shown in place of a failed load. It reports the failed http(s) URL but never
    /// runs content scripts, so CPM cannot answer on it.
    case errorPage = "error_page"
    /// A main-frame document that is not HTML (a PDF, an image, a video, plain text). The extension's content
    /// scripts may not initialize there, so CPM cannot answer.
    case nonHTMLDocument = "non_html_document"
    /// Any other main-frame navigation.
    case other

    /// Whether a response with this MIME type is an HTML document. An unknown type counts as HTML, so a page
    /// is left out only when the response says it is something else.
    static func isHTMLDocument(mimeType: String?) -> Bool {
        guard let type = mimeType?.lowercased(), !type.isEmpty else { return true }
        return type == "text/html" || type == "application/xhtml+xml"
    }

    /// The kind once the response is known: only an ordinary navigation can turn out to be a non-HTML document.
    public func resolved(forMimeType mimeType: String?) -> CPMNavigationKind {
        guard self == .other, !Self.isHTMLDocument(mimeType: mimeType) else { return self }
        return .nonHTMLDocument
    }
}

/// A tab that the health monitor follows by an identifier. It is the identifier the tab reports navigations with,
/// so the extension events listener can tell the monitor which tab closed.
@MainActor
public protocol CPMMonitoredTab: AnyObject {
    var cpmTabIdentifier: String { get }
}

/// The last step of a main-frame init the extension reported, in the order the chain runs.
public enum CPMInitStage: String, CaseIterable, Sendable {
    /// The background received `init`.
    case backgroundReceived = "background_received"
    /// The background read its configuration.
    case configRead = "config_read"
    /// The background read the user's setting.
    case settingsChecked = "settings_checked"
    /// The background checked the site.
    case siteChecked = "site_checked"
    /// The background answered the page's `init`; the reply itself is not observed.
    case responseSent = "response_sent"

    /// Position in the chain, which is the order of the cases; a later report never lowers the last stage reached.
    var rank: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

/// What a breakage report says about how far the page's init got.
public enum CPMLastStage: Hashable, Sendable {
    /// The `cpmInitProgress` subfeature is off, so nothing was measured and the parameter is left out.
    case notMeasured
    /// Measured, and the extension reported no step for the page.
    case noMark
    /// The furthest step the extension reported for the page.
    case reached(CPMInitStage)

    /// The value of the `last_stage` pixel parameter, nil when the parameter is left out.
    public var pixelValue: String? {
        switch self {
        case .notMeasured: return nil
        case .noMark: return "none"
        case .reached(let stage): return stage.rawValue
        }
    }
}

/// Where the extension says the tab of a message is: its index in its window, that window, and the ids of all the
/// windows the extension knows, ascending.
@available(macOS 15.4, iOS 18.4, *)
public struct CPMExtensionTabPosition: Sendable, Equatable {
    public let tabIndex: Int
    public let windowId: Int
    public let windowIds: [Int]

    public init(tabIndex: Int, windowId: Int, windowIds: [Int]) {
        self.tabIndex = tabIndex
        self.windowId = windowId
        self.windowIds = windowIds
    }

    /// The window's place among all the windows the extension knows, from 0.
    var windowRank: Int? { windowIds.sorted().firstIndex(of: windowId) }
}

/// Facts supplied by tabs, the native messaging handler, and the extension manager.
@available(macOS 15.4, iOS 18.4, *)
public enum CPMMessagingHealthEvent: Sendable {
    /// A main-frame document committed, with the kind of navigation that loaded it.
    case navigationCommitted(tabIdentifier: String, url: URL, navigationKind: CPMNavigationKind, extensionIsLoaded: Bool)
    case tabClosed(tabIdentifier: String)
    case webContentProcessTerminated(tabIdentifier: String)
    /// The extension refreshed the dashboard of a page. `isAnswer` is false when it said it cannot answer the
    /// page's init (no configuration, no settings): the extension is running, but the page stays unanswered.
    case dashboardResponse(url: URL, extensionIdentifier: String? = nil, isAnswer: Bool = true,
                           position: CPMExtensionTabPosition? = nil)
    /// A progress mark for one main-frame init, sent by the extension. It never answers a page; it only tells how
    /// far the init got.
    case initProgress(url: URL, stage: CPMInitStage, extensionIdentifier: String? = nil,
                      position: CPMExtensionTabPosition? = nil)
    case extensionLifecycle(WebExtensionLifecycleEvent)
    /// The embedded extension was uninstalled, or replaced by a newer version: pages waiting for it will never be
    /// answered, and the extension is gone rather than broken.
    case embeddedExtensionRemoved
    /// The process may stop running: iOS entered the background, or macOS is going to sleep.
    case interruptionBegan
    /// The app is running again: iOS returns to the foreground, or macOS woke.
    case interruptionEnded
}

@available(macOS 15.4, iOS 18.4, *)
public protocol CPMMessagingHealthMonitoring: AnyObject, Sendable {
    @MainActor
    func handle(_ event: CPMMessagingHealthEvent)
}

/// Reports tabs whose page never heard from the extension.
///
/// A committed page that can run the extension must hear from it: the extension sends a message from the
/// tab while the page initializes. A page with no message for `silenceWindow` seconds of app time makes
/// its tab silent, reported once. A tab that navigates or closes before the window ends is not reported.
/// A message that arrives later still counts as an answer.
///
/// There is no timer: the check runs when an event arrives.
///
/// A second silent tab, with no message from the extension in between, reports the persistent pixel once.
/// A tab whose page got a refresh saying the extension cannot answer it is reported, but never counts
/// towards that second tab: the extension is running, so it is not hung.
///
/// The extension also marks how far each page's init got. A mark is not an answer; the furthest mark of a page
/// goes into the report of its silent tab.
///
/// It also reports through `onHealthyResponse` when the current embedded extension answers.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
public final class CPMMessagingHealthMonitor: CPMMessagingHealthMonitoring {

    /// Lets the manager reset the three-restart limit when the current extension answers.
    var onHealthyResponse: (() -> Void)?
    /// Old and new embedded versions can coexist during an upgrade; only the current sender is evidence.
    var isCurrentEmbeddedExtension: ((String) -> Bool)?

    /// The app tab at `index` in one window: the window that is number `windowRank` (from 0, in the order WebKit got
    /// the windows) of the `windowCount` windows the extension `extensionIdentifier` knows. The platform returns nil
    /// when it cannot tell, for example when it has another number of windows.
    public var tabIdentifierAtExtensionPosition: (@MainActor (_ extensionIdentifier: String, _ index: Int,
                                                              _ windowRank: Int, _ windowCount: Int) -> String?)?

    /// Debug-only switch that makes dashboard responses invisible to the health algorithm.
    public private(set) var isCPMMessagingBreakageSimulationEnabled = false

    /// The latest eligible page of each app tab, which a message from the extension can belong to.
    private var committedPages: [String: URL] = [:]
    /// When each tab's latest eligible page committed, until a message from the tab answers it.
    private var pendingCommits: [String: Date] = [:]
    /// Tabs reported silent since the extension last sent any message.
    private var silentTabs: Set<String> = []
    /// Waiting tabs whose page got a refresh saying the extension cannot answer it (no configuration or settings).
    /// The extension is running, so these tabs are reported but never count towards a series.
    private var cannotBeAnsweredTabs: Set<String> = []
    private var didReportPersistentBreakage = false
    private var suspensionStart: Date?
    /// The furthest init stage reported for each tab's latest page.
    private var lastStages: [String: CPMInitStage] = [:]
    /// Marks that arrived before any tab was waiting on their page.
    private var recentMarks: [RecentMark] = []

    private struct RecentMark {
        let url: URL
        let stage: CPMInitStage
        let date: Date
    }

    private let pixelFiring: WebExtensionPixelFiring
    private let isUnmeasuredPage: (URL) -> Bool
    private let silenceWindow: TimeInterval
    private let messageTolerance: TimeInterval
    private let isInitProgressEnabled: () -> Bool
    private let now: () -> Date

    /// - Parameters:
    ///   - isUnmeasuredPage: Whether the extension's message can never be matched to the page committed at this URL,
    ///     because the tab reports another URL to the extension (a Duck Player video). Such pages are not measured.
    ///   - silenceWindow: How long a committed page may stay silent before its tab is reported.
    ///   - messageTolerance: How long before its page commits a mark still counts for that page: the mark travels
    ///     through the extension, while the commit is seen by the app directly.
    ///   - isInitProgressEnabled: Whether the `cpmInitProgress` subfeature is on. While it is off the report has no
    ///     `last_stage`, which tells a page nobody measured from a page whose init reported no step.
    public init(pixelFiring: WebExtensionPixelFiring,
                isUnmeasuredPage: @escaping (URL) -> Bool,
                silenceWindow: TimeInterval = 30,
                messageTolerance: TimeInterval = 2,
                isInitProgressEnabled: @escaping () -> Bool = { true },
                now: @escaping () -> Date = CPMMessagingHealthMonitor.uptimeDate) {
        self.pixelFiring = pixelFiring
        self.isUnmeasuredPage = isUnmeasuredPage
        self.silenceWindow = silenceWindow
        self.messageTolerance = messageTolerance
        self.isInitProgressEnabled = isInitProgressEnabled
        self.now = now
    }

    /// A clock that a wall-clock change cannot move: time since boot.
    public static func uptimeDate() -> Date {
        Date(timeIntervalSinceReferenceDate: ProcessInfo.processInfo.systemUptime)
    }

    /// Enables or disables Debug-menu simulation of missing CPM dashboard responses.
    public func setBreakageSimulationEnabled(_ isEnabled: Bool) {
        guard isCPMMessagingBreakageSimulationEnabled != isEnabled else { return }
        isCPMMessagingBreakageSimulationEnabled = isEnabled
        Logger.webExtensions.debug("[CPM Health Monitor] Breakage simulation changed: enabled=\(isEnabled)")
    }

    /// Applies one tab, native-message, or extension-lifecycle event.
    public func handle(_ event: CPMMessagingHealthEvent) {
        defer {
            let state = "tabs=\(committedPages.count)"
            Logger.webExtensions.debug("[CPM Health Monitor] \(event.logDescription, privacy: .public) -> \(state, privacy: .public)")
        }

        if case .dashboardResponse(let url, let extensionIdentifier, let isAnswer, let position) = event {
            // The answer is applied before the check, so a slow answer is never counted as silence.
            receiveResponse(url: url, extensionIdentifier: extensionIdentifier, isAnswer: isAnswer, position: position)
            reportSilentTabs()
            return
        }
        reportSilentTabs()

        switch event {
        case .navigationCommitted(let tabIdentifier, let url, let navigationKind, let extensionIsLoaded):
            let eligible = isEligible(url: url, navigationKind: navigationKind)
            committedPages[tabIdentifier] = eligible ? url : nil
            pendingCommits[tabIdentifier] = nil
            cannotBeAnsweredTabs.remove(tabIdentifier)
            lastStages[tabIdentifier] = eligible ? earlyStage(for: url) : nil
            if eligible && extensionIsLoaded { pendingCommits[tabIdentifier] = now() }
        case .tabClosed(let tabIdentifier):
            // The marks of the closed page must not be taken by a page that commits next on the same URL.
            if let page = committedPages[tabIdentifier] {
                recentMarks.removeAll { $0.url.matchesCPMDashboardStatePage(page) }
            }
            committedPages.removeValue(forKey: tabIdentifier)
            pendingCommits.removeValue(forKey: tabIdentifier)
            cannotBeAnsweredTabs.remove(tabIdentifier)
            lastStages.removeValue(forKey: tabIdentifier)
        case .webContentProcessTerminated(let tabIdentifier):
            // A crashed page is not the extension's silence.
            committedPages.removeValue(forKey: tabIdentifier)
            pendingCommits.removeValue(forKey: tabIdentifier)
            cannotBeAnsweredTabs.remove(tabIdentifier)
            lastStages.removeValue(forKey: tabIdentifier)
        case .dashboardResponse:
            break
        case .initProgress(let url, let stage, let extensionIdentifier, let position):
            receiveProgress(url: url, stage: stage, extensionIdentifier: extensionIdentifier, position: position)
        case .extensionLifecycle(let lifecycleEvent):
            handle(lifecycleEvent)
        case .embeddedExtensionRemoved:
            endWaits()
        case .interruptionBegan:
            suspensionStart = suspensionStart ?? now()
        case .interruptionEnded:
            resume()
        }
    }

    /// Whether the extension can answer on the committed page: http(s), and not the browser's own error page,
    /// a history restore (WebKit may not rerun content scripts), a restored session, or a page the app says is not
    /// measured.
    private func isEligible(url: URL, navigationKind: CPMNavigationKind) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        guard !isUnmeasuredPage(url) else { return false }
        return navigationKind == .other
    }

    /// Time spent suspended does not count towards the silence window.
    private func resume() {
        guard let start = suspensionStart else { return }
        suspensionStart = nil
        let resumedAt = now()
        let suspended = resumedAt.timeIntervalSince(start)
        // A page that committed while suspended starts waiting now.
        pendingCommits = pendingCommits.mapValues { $0 < start ? $0.addingTimeInterval(suspended) : resumedAt }
    }

    private func receiveResponse(url: URL, extensionIdentifier: String?, isAnswer: Bool, position: CPMExtensionTabPosition?) {
        if let extensionIdentifier, isCurrentEmbeddedExtension?(extensionIdentifier) == false { return }
        guard !isCPMMessagingBreakageSimulationEnabled else { return }
        let tabs = tabs(for: url, at: position, extensionIdentifier: extensionIdentifier)
        if isAnswer {
            answer(tabs)
        } else {
            cannotBeAnsweredTabs.formUnion(tabs)
        }
        onHealthyResponse?()
    }

    private func answer(_ tabs: [String]) {
        for tabIdentifier in tabs {
            pendingCommits[tabIdentifier] = nil
            cannotBeAnsweredTabs.remove(tabIdentifier)
        }
        silentTabs.removeAll()
        didReportPersistentBreakage = false
    }

    /// The tabs a message is about. The tab at the message's position in its window, when it shows the message's
    /// page, is the one tab; a message about a tab that no longer waits is about no waiting tab. A message that
    /// cannot be tied to one tab belongs to every waiting tab it could be about.
    private func tabs(for url: URL, at position: CPMExtensionTabPosition?, extensionIdentifier: String?) -> [String] {
        let waiting = waitingTabs(showing: url)
        guard let tab = tab(at: position, extensionIdentifier: extensionIdentifier),
              committedPages[tab]?.matchesCPMDashboardStatePage(url) == true else { return waiting }
        return waiting.contains(tab) ? [tab] : []
    }

    /// The app tab at the position the extension reports, when the platform can tell the window and the index.
    /// Window ids grow in the order WebKit first gets the windows, so the rank of the window's id among all ids is the
    /// rank of the window among the platform's.
    private func tab(at position: CPMExtensionTabPosition?, extensionIdentifier: String?) -> String? {
        guard let position, let rank = position.windowRank, let extensionIdentifier else { return nil }
        return tabIdentifierAtExtensionPosition?(extensionIdentifier, position.tabIndex, rank, position.windowIds.count)
    }

    /// The tabs still waiting for an answer.
    var waitingTabIdentifiers: Set<String> { Set(pendingCommits.keys) }

    /// The tabs still waiting on the message's page. Two tabs on one page both get the message.
    private func waitingTabs(showing url: URL) -> [String] {
        committedPages.filter { pendingCommits[$0.key] != nil && $0.value.matchesCPMDashboardStatePage(url) }.map(\.key)
    }

    /// Records how far one page's init got. A mark is not an answer: the background can receive `init` and
    /// still never answer, which is the silence this metric reports. Two tabs on one page both get the mark.
    /// The Debug simulation drops only the answers, so the marks of a simulated silent tab are still recorded.
    private func receiveProgress(url: URL, stage: CPMInitStage, extensionIdentifier: String?, position: CPMExtensionTabPosition?) {
        if let extensionIdentifier, isCurrentEmbeddedExtension?(extensionIdentifier) == false { return }
        // Kept for a page that commits next even when a tab already waits on this page: a reload or a second tab
        // starts a new wait that this mark belongs to.
        keepForCommit(RecentMark(url: url, stage: stage, date: now()))
        tabs(for: url, at: position, extensionIdentifier: extensionIdentifier).forEach { raiseStage(of: $0, to: stage) }
    }

    private func lastStage(of tabIdentifier: String) -> CPMLastStage {
        guard isInitProgressEnabled() else { return .notMeasured }
        return lastStages[tabIdentifier].map { .reached($0) } ?? .noMark
    }

    private func raiseStage(of tabIdentifier: String, to stage: CPMInitStage) {
        guard stage.rank > (lastStages[tabIdentifier]?.rank ?? -1) else { return }
        lastStages[tabIdentifier] = stage
    }

    private func keepForCommit(_ mark: RecentMark) {
        recentMarks.removeAll { $0.date < mark.date.addingTimeInterval(-messageTolerance) }
        recentMarks.append(mark)
    }

    /// The furthest stage of the marks that arrived just before a page committed: the mark travels through the
    /// extension, so it can come first.
    private func earlyStage(for url: URL) -> CPMInitStage? {
        let earliest = now().addingTimeInterval(-messageTolerance)
        let early = recentMarks.filter { $0.date >= earliest && $0.url.matchesCPMDashboardStatePage(url) }
        return early.map(\.stage).max { $0.rank < $1.rank }
    }

    /// Reports the tabs whose page has waited for the extension longer than the window.
    private func reportSilentTabs() {
        guard suspensionStart == nil else { return }
        let deadline = now().addingTimeInterval(-silenceWindow)
        let silent = pendingCommits.filter { $0.value <= deadline }.sorted { $0.value < $1.value }
        guard !silent.isEmpty else { return }
        // Tabs found silent together are not a single-tab breakage.
        silentTabs.formUnion(silent.map { $0.key }.filter { !cannotBeAnsweredTabs.contains($0) })
        for (tabIdentifier, _) in silent {
            pendingCommits[tabIdentifier] = nil
            if cannotBeAnsweredTabs.remove(tabIdentifier) != nil {
                pixelFiring.fire(.cpmMessagingBreakage(lastStage: lastStage(of: tabIdentifier), tabs: .one))
            } else {
                reportSilentTab(tabIdentifier)
            }
        }
    }

    private func reportSilentTab(_ tabIdentifier: String) {
        let otherTabsWereSilent = !silentTabs.subtracting([tabIdentifier]).isEmpty
        let tabs: CPMSilentTabs = otherTabsWereSilent ? .many : .one
        pixelFiring.fire(.cpmMessagingBreakage(lastStage: lastStage(of: tabIdentifier), tabs: tabs))
        guard silentTabs.count >= 2, !didReportPersistentBreakage else { return }
        didReportPersistentBreakage = true
        pixelFiring.fire(.cpmMessagingBreakagePersistent)
    }

    /// Drops every wait and the silent series: the extension that would have answered is gone or being replaced.
    private func endWaits() {
        pendingCommits.removeAll()
        cannotBeAnsweredTabs.removeAll()
        silentTabs.removeAll()
        lastStages.removeAll()
        recentMarks.removeAll()
        didReportPersistentBreakage = false
    }

    /// Updates state from an extension-manager lifecycle event. A reload ends the waits and the silent series.
    func handle(_ event: WebExtensionLifecycleEvent) {
        guard event.extensionType == .embedded else { return }

        switch event {
        case .willReload, .reloaded:
            endWaits()
        case .loaded, .reloadFailed:
            break
        }
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

@available(macOS 15.4, iOS 18.4, *)
private extension CPMMessagingHealthEvent {
    /// Describes an incoming event without recording a browsing URL.
    var logDescription: String {
        switch self {
        case .navigationCommitted(let tabIdentifier, _, let navigationKind, let extensionIsLoaded):
            return "navigationCommitted tab=\(tabIdentifier) kind=\(navigationKind.rawValue) extensionLoaded=\(extensionIsLoaded)"
        case .tabClosed(let tabIdentifier):
            return "tabClosed tab=\(tabIdentifier)"
        case .webContentProcessTerminated(let tabIdentifier):
            return "webContentProcessTerminated tab=\(tabIdentifier)"
        case .dashboardResponse:
            return "dashboardResponse"
        case .initProgress(_, let stage, _, _):
            return "initProgress stage=\(stage.rawValue)"
        case .extensionLifecycle(let event):
            return "extensionLifecycle \(event.logDescription)"
        case .embeddedExtensionRemoved:
            return "embeddedExtensionRemoved"
        case .interruptionBegan:
            return "interruptionBegan"
        case .interruptionEnded:
            return "interruptionEnded"
        }
    }
}

@available(macOS 15.4, iOS 18.4, *)
private extension WebExtensionLifecycleEvent {
    /// Describes a lifecycle event and its reload trigger for debug logs.
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

public extension URL {
    /// Matches the page identity used by the CPM dashboard, whose state follows query and fragment changes.
    ///
    /// Ignores scheme, port and query, and compares the host case-sensitively.
    func matchesCPMDashboardStatePage(_ other: URL) -> Bool {
        host == other.host && normalizedCPMPath == other.normalizedCPMPath
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
