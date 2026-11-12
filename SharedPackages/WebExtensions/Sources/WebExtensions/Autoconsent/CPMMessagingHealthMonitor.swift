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
    public static func isHTMLDocument(mimeType: String?) -> Bool {
        guard let type = mimeType?.lowercased(), !type.isEmpty else { return true }
        return type == "text/html" || type == "application/xhtml+xml"
    }

    /// The kind once the response is known: only an ordinary navigation can turn out to be a non-HTML document.
    public func resolved(forMimeType mimeType: String?) -> CPMNavigationKind {
        guard self == .other, !Self.isHTMLDocument(mimeType: mimeType) else { return self }
        return .nonHTMLDocument
    }
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
    case dashboardResponse(url: URL, extensionIdentifier: String? = nil, isAnswer: Bool = true)
    case extensionLifecycle(WebExtensionLifecycleEvent)
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
/// its tab silent, reported once; a tab that navigates or closes before the window ends is not reported. A message that arrives later still counts as an answer; there is no timer, the
/// check runs when an event arrives. A second silent tab, with no message from the extension in between,
/// reports the persistent pixel once.
///
/// It also reports through `onHealthyResponse` when the current embedded extension answers.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
public final class CPMMessagingHealthMonitor: CPMMessagingHealthMonitoring {

    /// Lets the manager reset the three-restart limit when the current extension answers.
    var onHealthyResponse: (() -> Void)?
    /// Old and new embedded versions can coexist during an upgrade; only the current sender is evidence.
    var isCurrentEmbeddedExtension: ((String) -> Bool)?

    /// Debug-only switch that makes dashboard responses invisible to the health algorithm.
    public private(set) var isCPMMessagingBreakageSimulationEnabled = false

    /// The latest eligible page of each app tab, which a message from the extension can belong to.
    private var committedPages: [String: URL] = [:]
    /// When each tab's latest eligible page committed, until a message from the tab answers it.
    private var pendingCommits: [String: Date] = [:]
    /// Tabs reported silent since the extension last sent any message.
    private var silentTabs: Set<String> = []
    private var didReportPersistentBreakage = false
    private var suspensionStart: Date?

    private let pixelFiring: WebExtensionPixelFiring
    private let silenceWindow: TimeInterval
    private let now: () -> Date

    /// - Parameters:
    ///   - silenceWindow: How long a committed page may stay silent before its tab is reported.
    public init(pixelFiring: WebExtensionPixelFiring,
                silenceWindow: TimeInterval = 30,
                now: @escaping () -> Date = CPMMessagingHealthMonitor.uptimeDate) {
        self.pixelFiring = pixelFiring
        self.silenceWindow = silenceWindow
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

        if case .dashboardResponse(let url, let extensionIdentifier, let isAnswer) = event {
            // The answer is applied before the check, so a slow answer is never counted as silence.
            receiveResponse(url: url, extensionIdentifier: extensionIdentifier, isAnswer: isAnswer)
            reportSilentTabs()
            return
        }
        reportSilentTabs()

        switch event {
        case .navigationCommitted(let tabIdentifier, let url, let navigationKind, let extensionIsLoaded):
            let eligible = isEligible(url: url, navigationKind: navigationKind)
            committedPages[tabIdentifier] = eligible ? url : nil
            pendingCommits[tabIdentifier] = nil
            if eligible && extensionIsLoaded { pendingCommits[tabIdentifier] = now() }
        case .tabClosed(let tabIdentifier):
            committedPages.removeValue(forKey: tabIdentifier)
            pendingCommits.removeValue(forKey: tabIdentifier)
        case .webContentProcessTerminated(let tabIdentifier):
            // A crashed page is not the extension's silence.
            committedPages.removeValue(forKey: tabIdentifier)
            pendingCommits.removeValue(forKey: tabIdentifier)
        case .dashboardResponse:
            break
        case .extensionLifecycle(let lifecycleEvent):
            handle(lifecycleEvent)
        case .interruptionBegan:
            suspensionStart = suspensionStart ?? now()
        case .interruptionEnded:
            resume()
        }
    }

    /// Whether the extension can answer on the committed page: http(s), and not the browser's own error page,
    /// a history restore (WebKit may not rerun content scripts) or a restored session.
    private func isEligible(url: URL, navigationKind: CPMNavigationKind) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
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

    private func receiveResponse(url: URL, extensionIdentifier: String?, isAnswer: Bool) {
        if let extensionIdentifier, isCurrentEmbeddedExtension?(extensionIdentifier) == false { return }
        guard !isCPMMessagingBreakageSimulationEnabled else { return }
        if isAnswer { answerPages(url: url) }
        onHealthyResponse?()
    }

    private func answerPages(url: URL) {
        // A message that cannot be tied to one tab answers every waiting tab it could belong to.
        for tabIdentifier in answeredTabs(url: url) {
            pendingCommits[tabIdentifier] = nil
        }
        silentTabs.removeAll()
        didReportPersistentBreakage = false
    }

    /// The tabs still waiting on the message's page. Two tabs on one page both get the message.
    private func answeredTabs(url: URL) -> [String] {
        committedPages.filter { pendingCommits[$0.key] != nil && $0.value.matchesCPMDashboardStatePage(url) }.map(\.key)
    }

    /// Reports the tabs whose page has waited for the extension longer than the window.
    private func reportSilentTabs() {
        guard suspensionStart == nil else { return }
        let deadline = now().addingTimeInterval(-silenceWindow)
        let silent = pendingCommits.filter { $0.value <= deadline }.sorted { $0.value < $1.value }
        guard !silent.isEmpty else { return }
        // Tabs found silent together are not a single-tab breakage.
        silentTabs.formUnion(silent.map { $0.key })
        for (tabIdentifier, _) in silent {
            pendingCommits[tabIdentifier] = nil
            reportSilentTab(tabIdentifier)
        }
    }

    private func reportSilentTab(_ tabIdentifier: String) {
        let otherTabsWereSilent = !silentTabs.subtracting([tabIdentifier]).isEmpty
        let report = CPMMessagingBreakageReport(tabs: otherTabsWereSilent ? .many : .one)
        pixelFiring.fire(.cpmMessagingBreakage(report))
        guard silentTabs.count >= 2, !didReportPersistentBreakage else { return }
        didReportPersistentBreakage = true
        pixelFiring.fire(.cpmMessagingBreakagePersistent)
    }

    /// Updates state from an extension-manager lifecycle event. A reload ends the waits and the silent series.
    func handle(_ event: WebExtensionLifecycleEvent) {
        guard event.extensionType == .embedded else { return }

        switch event {
        case .willReload, .reloaded:
            pendingCommits.removeAll()
            silentTabs.removeAll()
            didReportPersistentBreakage = false
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
        case .extensionLifecycle(let event):
            return "extensionLifecycle \(event.logDescription)"
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
