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
    /// Any other main-frame navigation.
    case other
}

/// Facts supplied by tabs, the native messaging handler, and the extension manager.
@available(macOS 15.4, iOS 18.4, *)
public enum CPMMessagingHealthEvent: Sendable {
    /// A main-frame document committed, with the kind of navigation that loaded it.
    case navigationCommitted(tabIdentifier: String, url: URL, navigationKind: CPMNavigationKind, extensionIsLoaded: Bool)
    case tabClosed(tabIdentifier: String)
    case webContentProcessTerminated(tabIdentifier: String)
    case dashboardResponse(extensionTabIdentifier: Int?, url: URL, extensionIdentifier: String? = nil)
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

/// Follows which extension tab belongs to which app tab, and reports through `onHealthyResponse` when the
/// current embedded extension answers.
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
    /// The extension's tab identifier of each app tab, learned from the first message that matches one page.
    private var extensionTabMappings: [Int: String] = [:]

    public init() {}

    /// Enables or disables Debug-menu simulation of missing CPM dashboard responses.
    public func setBreakageSimulationEnabled(_ isEnabled: Bool) {
        guard isCPMMessagingBreakageSimulationEnabled != isEnabled else { return }
        isCPMMessagingBreakageSimulationEnabled = isEnabled
        Logger.webExtensions.debug("[CPM Health Monitor] Breakage simulation changed: enabled=\(isEnabled)")
    }

    /// The app tab learned for an extension tab, if any.
    func tabIdentifier(forExtensionTab extensionTabIdentifier: Int) -> String? {
        extensionTabMappings[extensionTabIdentifier]
    }

    /// Applies one tab, native-message, or extension-lifecycle event.
    public func handle(_ event: CPMMessagingHealthEvent) {
        defer {
            let state = "tabs=\(committedPages.count) mappings=\(extensionTabMappings.count)"
            Logger.webExtensions.debug("[CPM Health Monitor] \(event.logDescription, privacy: .public) -> \(state, privacy: .public)")
        }

        switch event {
        case .navigationCommitted(let tabIdentifier, let url, let navigationKind, _):
            committedPages[tabIdentifier] = isEligible(url: url, navigationKind: navigationKind) ? url : nil
        case .tabClosed(let tabIdentifier):
            committedPages.removeValue(forKey: tabIdentifier)
            extensionTabMappings = extensionTabMappings.filter { $0.value != tabIdentifier }
        case .webContentProcessTerminated(let tabIdentifier):
            committedPages.removeValue(forKey: tabIdentifier)
        case .dashboardResponse(let extensionTabIdentifier, let url, let extensionIdentifier):
            if let extensionIdentifier, isCurrentEmbeddedExtension?(extensionIdentifier) == false { return }
            guard !isCPMMessagingBreakageSimulationEnabled else { return }
            learnTab(forExtensionTab: extensionTabIdentifier, url: url)
            onHealthyResponse?()
        case .extensionLifecycle(let lifecycleEvent):
            handle(lifecycleEvent)
        case .interruptionBegan, .interruptionEnded:
            // Suspension does not change which tab a message belongs to.
            break
        }
    }

    /// Whether the extension can answer on the committed page: http(s), and not the browser's own error page,
    /// a history restore (WebKit may not rerun content scripts) or a restored session.
    private func isEligible(url: URL, navigationKind: CPMNavigationKind) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return navigationKind == .other
    }

    /// Learns the app tab of an extension tab when the message's page matches exactly one tab's page.
    private func learnTab(forExtensionTab extensionTabIdentifier: Int?, url: URL) {
        guard let extensionTabIdentifier, extensionTabMappings[extensionTabIdentifier] == nil else { return }
        let candidates = committedPages.filter { $0.value.matchesCPMDashboardStatePage(url) }
        guard candidates.count == 1, let tabIdentifier = candidates.keys.first else { return }
        extensionTabMappings[extensionTabIdentifier] = tabIdentifier
    }

    /// Updates state from an extension-manager lifecycle event. A reload creates new extension tabs, so the
    /// learned identifiers no longer apply; the open pages stay, so the tabs can be learned again.
    func handle(_ event: WebExtensionLifecycleEvent) {
        guard event.extensionType == .embedded else { return }

        switch event {
        case .willReload, .reloaded:
            extensionTabMappings.removeAll()
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
        case .dashboardResponse(let extensionTabIdentifier, _, _):
            return "dashboardResponse extensionTab=\(extensionTabIdentifier.map(String.init) ?? "none")"
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
