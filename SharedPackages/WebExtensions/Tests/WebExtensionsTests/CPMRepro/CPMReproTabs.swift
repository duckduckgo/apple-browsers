//
//  CPMReproTabs.swift
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
import WebKit
@testable import WebExtensions

/// A browser tab backed by a real `WKWebView` attached to the extension controller.
///
/// Navigation callbacks are translated into health-monitor events the same way the app's tab
/// extensions do, so the production monitor measures these tabs exactly like real ones.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMReproTab: NSObject, WKWebExtensionTab, WKNavigationDelegate {

    let identifier: String
    let webView: WKWebView
    weak var window: CPMReproWindow?
    private let monitor: CPMMessagingHealthMonitoring
    private let isExtensionLoaded: () -> Bool
    private let log: CPMReproLog
    private let navigationGate = WebExtensionNavigationGate()
    private let navigationWaiterProvider: @MainActor () -> WebExtensionInitialLoadWaiter?
    var onNavigationFinished: ((URL) -> Void)?

    init(identifier: String,
         controller: WKWebExtensionController,
         monitor: CPMMessagingHealthMonitoring,
         log: CPMReproLog,
         navigationWaiterProvider: @escaping @MainActor () -> WebExtensionInitialLoadWaiter?,
         isExtensionLoaded: @escaping () -> Bool) {
        let configuration = WKWebViewConfiguration()
        configuration.webExtensionController = controller
        self.identifier = identifier
        self.webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        self.monitor = monitor
        self.log = log
        self.isExtensionLoaded = isExtensionLoaded
        self.navigationWaiterProvider = navigationWaiterProvider
        super.init()
        webView.navigationDelegate = self
    }

    func load(_ url: URL) {
        let html = "<!doctype html><html><head><title>\(identifier)</title></head><body><p>\(url.absoluteString)</p></body></html>"
        webView.loadSimulatedRequest(URLRequest(url: url), responseHTML: html)
    }

    // MARK: WKWebExtensionTab

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { window }

    func webView(for context: WKWebExtensionContext) -> WKWebView? { webView }

    func title(for context: WKWebExtensionContext) -> String? { identifier }

    func url(for context: WKWebExtensionContext) -> URL? { webView.url }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !webView.isLoading }

    func isSelected(for context: WKWebExtensionContext) -> Bool { window?.tabs.last === self }

    func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool { true }

    // MARK: WKNavigationDelegate

    /// Holds main-frame navigations behind the app's web extension gate, as the app's tabs do.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        let waiter = navigationWaiterProvider()
        if isMainFrame, waiter != nil {
            log.add("tab \(identifier) navigation waits for the web extension gate")
        }
        await navigationGate.waitIfNeeded(isMainFrame: isMainFrame, url: navigationAction.request.url, initialLoadWaiter: waiter)
        return (.allow, preferences)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        monitor.handle(.navigationStarted(tabIdentifier: identifier, navigationKind: .other))
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        monitor.handle(.navigationCommitted(tabIdentifier: identifier, url: url))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        log.add("tab \(identifier) finished \(url.absoluteString)")
        monitor.handle(.navigationFinished(tabIdentifier: identifier, url: url, extensionIsLoaded: isExtensionLoaded()))
        onNavigationFinished?(url)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        log.add("tab \(identifier) failed \(error.localizedDescription)")
        monitor.handle(.navigationFailed(tabIdentifier: identifier))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log.add("tab \(identifier) failed provisional \(error.localizedDescription)")
        monitor.handle(.navigationFailed(tabIdentifier: identifier))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.add("tab \(identifier) web content process terminated")
        monitor.handle(.webContentProcessTerminated(tabIdentifier: identifier))
    }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMReproWindow: NSObject, WKWebExtensionWindow {

    var tabs: [CPMReproTab] = []

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { tabs }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { tabs.last }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState { .normal }

    func isPrivate(for context: WKWebExtensionContext) -> Bool { false }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMReproWindowProvider: WebExtensionWindowTabProviding {

    let window: CPMReproWindow

    init(window: CPMReproWindow) {
        self.window = window
    }

    func openWindows(for context: WKWebExtensionContext) -> [any WKWebExtensionWindow] { [window] }

    func focusedWindow(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { window }

    func openNewWindow(using configuration: WKWebExtension.WindowConfiguration,
                       for context: WKWebExtensionContext) async throws -> (any WKWebExtensionWindow)? { nil }

    func openNewTab(using configuration: WKWebExtension.TabConfiguration,
                    for context: WKWebExtensionContext) async throws -> (any WKWebExtensionTab)? { nil }

    func presentPopup(_ action: WKWebExtension.Action, for context: WKWebExtensionContext) async throws {}
}
