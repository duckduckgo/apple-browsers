//
//  PopupHandlingTabExtension.swift
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

import AppKit
import BrowserServicesKit
import Combine
import Common
import ContentBlocking
import FeatureFlags
import Navigation
import OSLog
import TrackerRadarKit
import WebKit

final class PopupHandlingTabExtension {

    private let tabsPreferences: TabsPreferences
    private let burnerMode: BurnerMode
    private let permissionModel: PermissionModel
    private let createChildTab: (WKWebViewConfiguration, WKNavigationAction, NewWindowPolicy) -> Tab?
    private let presentTab: (Tab, NewWindowPolicy) -> Void
    private let newWindowPolicyDecisionMakers: () -> [NewWindowPolicyDecisionMaker]?
    private let featureFlagger: FeatureFlagger
    private let popupBlockingConfig: PopupBlockingConfiguration
    private let dateProvider: () -> Date

    private var cancellables = Set<AnyCancellable>()

    /// The last user interaction date based on mouseDown/keyDown events
    @MainActor private var lastUserInteractionDate: Date?

    /// Whether pop-ups were allowed by the user for the current page (until next navigation)
    @MainActor private(set) var popupsTemporarilyAllowedForCurrentPage = false
    /// Whether any pop-up was opened by the page for the current page (until next navigation)
    /// Used to persist the pop-up button state in the navigation bar
    @MainActor private(set) var popupWasOpenedForCurrentPage = false {
        didSet {
            popupOpenedSubject.send()
        }
    }
    /// Notifies when a pop-up was opened
    private let popupOpenedSubject = PassthroughSubject<Void, Never>()

    init(tabsPreferences: TabsPreferences,
         burnerMode: BurnerMode,
         permissionModel: PermissionModel,
         createChildTab: @escaping (WKWebViewConfiguration, WKNavigationAction, NewWindowPolicy) -> Tab?,
         presentTab: @escaping (Tab, NewWindowPolicy) -> Void,
         newWindowPolicyDecisionMakers: @escaping () -> [NewWindowPolicyDecisionMaker]?,
         featureFlagger: FeatureFlagger,
         popupBlockingConfig: PopupBlockingConfiguration,
         dateProvider: @escaping () -> Date = Date.init,
         interactionEventsPublisher: some Publisher<WebViewInteractionEvent, Never>) {
        self.tabsPreferences = tabsPreferences
        self.burnerMode = burnerMode
        self.permissionModel = permissionModel
        self.createChildTab = createChildTab
        self.presentTab = presentTab
        self.newWindowPolicyDecisionMakers = newWindowPolicyDecisionMakers
        self.featureFlagger = featureFlagger
        self.popupBlockingConfig = popupBlockingConfig
        self.dateProvider = dateProvider

        interactionEventsPublisher
            .filter { event in
                guard featureFlagger.isFeatureOn(.popupBlocking),
                      featureFlagger.isFeatureOn(.extendedUserInitiatedPopupTimeout) else { return false }

                switch event {
                case .mouseDown, .keyDown: return true
                case .scrollWheel: return false
                }
            }
            .sink { [weak self] _ in
                guard let self else { return }
                MainActor.assumeMainThread {
                    self.lastUserInteractionDate = self.dateProvider()
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    func createWebView(from webView: WKWebView,
                       with configuration: WKWebViewConfiguration,
                       for navigationAction: WKNavigationAction,
                       windowFeatures: WKWindowFeatures) -> WKWebView? {

        var isCalledSynchronously = true
        var synchronousResultWebView: WKWebView?
        handleCreateWebViewRequest(from: webView,
                                   with: configuration,
                                   for: navigationAction,
                                   windowFeatures: windowFeatures) { [weak self] childWebView in
            guard self != nil else { return }
            if isCalledSynchronously {
                synchronousResultWebView = childWebView
            } else {
                // automatic loading won‘t start for asynchronous callback as we‘ve already returned nil at this point
                childWebView?.load(navigationAction.request)
            }
        }
        isCalledSynchronously = false
        return synchronousResultWebView
    }

    @MainActor
    private func handleCreateWebViewRequest(from webView: WKWebView,
                                            with configuration: WKWebViewConfiguration,
                                            for navigationAction: WKNavigationAction,
                                            windowFeatures: WKWindowFeatures,
                                            completionHandler: @escaping (WKWebView?) -> Void) {

        let completionHandler = { [weak self, completionHandler] (webView: WKWebView?) in
            guard let self, let webView else {
                return completionHandler(nil)
            }
            completionHandler(webView)
        }

        switch newWindowPolicy(for: navigationAction) {
        case .allow(var targetKind):
            // replace `.tab` with `.window` when user prefers windows over tabs
            if case .tab(_, let isBurner, contextMenuInitiated: false) = targetKind,
               !tabsPreferences.preferNewTabsToWindows {
                targetKind = .window(active: true, burner: isBurner)
            }
            // proceed to web view creation
            completionHandler(createChildWebView(from: webView,
                                                 with: configuration,
                                                 for: navigationAction,
                                                 of: targetKind.preferringSelectedTabs(tabsPreferences.switchToNewTabWhenOpened)))
            return
        case .cancel:
            completionHandler(nil)
            return
        case .none:
            break
        }

        // select new tab by default; ⌘-click modifies the selection state
        let linkOpenBehavior = LinkOpenBehavior(event: NSApp.currentEvent,
                                                switchToNewTabWhenOpenedPreference: tabsPreferences.switchToNewTabWhenOpened,
                                                canOpenLinkInCurrentTab: false,
                                                shouldSelectNewTab: true)

        // determine pop-up kind from provided windowFeatures and current key modifiers
        let targetKind = NewWindowPolicy(windowFeatures,
                                         linkOpenBehavior: linkOpenBehavior,
                                         isBurner: burnerMode.isBurner,
                                         preferTabsToWindows: tabsPreferences.preferNewTabsToWindows)

        let url = navigationAction.request.url
        guard let sourceSecurityOrigin = navigationAction.safeSourceFrame.map({ SecurityOrigin($0.securityOrigin) }) else {
            // disable pop-ups from unknown sources
            completionHandler(nil)
            return
        }

        // action doesn't require pop-up permission as it's user-initiated
        if shouldAllowPopupBypassingPermissionRequest(for: navigationAction, windowFeatures: windowFeatures) {
            // reset last user interaction date to block future pop-ups within the throttle window
            self.lastUserInteractionDate = nil
            completionHandler(createChildWebView(from: webView, with: configuration, for: navigationAction, of: targetKind))
            return
        }

        Logger.general.debug("Requesting pop-up permission for \(String(describing: navigationAction))")

        // Pop-up permission is needed: firing an async PermissionAuthorizationQuery
        var isCalledSynchronously = true
        permissionModel.request([.popups], forDomain: sourceSecurityOrigin.host, url: url).receive { [weak self] result in
            guard let self, case .success(true) = result else {
                Logger.general.info("Pop-up permission denied")
                completionHandler(nil)
                return
            }

            if !isCalledSynchronously,
               // disable opening empty or about: URLs as they would be non-functional when returned asynchronously after user‘s permission
               featureFlagger.isFeatureOn(.popupBlocking), featureFlagger.isFeatureOn(.suppressEmptyPopUpsOnApproval),
               url?.isEmpty ?? true || url?.navigationalScheme == .about {
                Logger.general.info("Suppressing pop-up: empty or about: URL")
                self.popupsTemporarilyAllowedForCurrentPage = true

                completionHandler(nil)
                return
            }

            // Permission granted: create and present new tab for regular pop-ups
            Logger.general.debug("Creating regular pop-up tab after permission granted")
            let webView = self.createChildWebView(from: webView, with: configuration, for: navigationAction, of: targetKind)
            completionHandler(webView)
        }
        isCalledSynchronously = false
    }

    @MainActor
    private func newWindowPolicy(for navigationAction: WKNavigationAction) -> NavigationDecision? {
        // Are we handling custom Context Menu navigation action or link click with a hotkey?
        for handler in newWindowPolicyDecisionMakers() ?? [] {
            if let decision = handler.decideNewWindowPolicy(for: navigationAction) {
                return decision
            }
        }
        // allow pop-ups opened from an empty window console
        if let sourceURL = navigationAction.safeSourceFrame?.safeRequest?.url {
            if sourceURL.isEmpty || sourceURL.scheme == URL.NavigationalScheme.about.rawValue {
                return .allow(.tab(selected: true, burner: burnerMode.isBurner))
            }
        }

        return nil
    }

    /// create a new Tab returning its WebView to a createWebViewWithConfiguration callback
    @MainActor
    private func createChildWebView(from webView: WKWebView,
                                    with configuration: WKWebViewConfiguration,
                                    for navigationAction: WKNavigationAction,
                                    of kind: NewWindowPolicy) -> WKWebView? {
        // disable opening 'javascript:' links in new tab
        guard navigationAction.request.url?.navigationalScheme != .javascript else { return nil }

        guard let childTab = createChildTab(configuration, navigationAction, kind) else { return nil }

        presentTab(childTab, kind)

        // Set flag to indicate that a pop-up was opened for the current page
        popupWasOpenedForCurrentPage = true

        // WebKit automatically loads the request in the returned web view.
        return childTab.webView
    }

    @MainActor internal func shouldAllowPopupBypassingPermissionRequest(for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> Bool {
        // Check if the pop-up is user-initiated (clicked link, etc.)
        if isNavigationActionUserInitiated(navigationAction) {
            return true
        }

        let url = navigationAction.request.url ?? .empty
        // Check if pop-ups are already allowed for the current page:
        // Either for empty/about: URLs specifically with "Allow pop-ups" option selected,
        // OR for all URLs when allowPopupsForCurrentPage feature flag is enabled
        if featureFlagger.isFeatureOn(.popupBlocking),
           featureFlagger.isFeatureOn(.suppressEmptyPopUpsOnApproval),
           popupsTemporarilyAllowedForCurrentPage,
           url.isEmpty || url.navigationalScheme == .about || featureFlagger.isFeatureOn(.allowPopupsForCurrentPage) {
            return true
        }

        return false
    }

    @MainActor
    func isNavigationActionUserInitiated(_ navigationAction: WKNavigationAction) -> Bool {
        let threshold = popupBlockingConfig.userInitiatedPopupThreshold
        // Check if enhanced popup blocking is enabled and configured properly
        guard featureFlagger.isFeatureOn(.popupBlocking),
              featureFlagger.isFeatureOn(.extendedUserInitiatedPopupTimeout),
              threshold > 0 else {
            // Fall back to WebKit's basic user-initiated check (1s. user interaction timeout) if feature is disabled or misconfigured
            assert(threshold > 0, "userInitiatedPopupThreshold must be positive")
            return navigationAction.isUserInitiated == true
        }

        // Check if user interaction happened within the threshold
        guard let lastUserInteractionDate,
              dateProvider().timeIntervalSince(lastUserInteractionDate) < threshold else {
            return false
        }

        return true
    }

}

// MARK: - NavigationResponder

extension PopupHandlingTabExtension: NavigationResponder {

    @MainActor
    func willStart(_ navigation: Navigation) {
        // Clear pop-up allowance on any navigation
        popupsTemporarilyAllowedForCurrentPage = false
        popupWasOpenedForCurrentPage = false
    }

}
// MARK: Tab Extension protocol
protocol PopupHandlingTabExtensionProtocol: AnyObject, NavigationResponder {
    @MainActor
    func createWebView(from webView: WKWebView,
                       with configuration: WKWebViewConfiguration,
                       for navigationAction: WKNavigationAction,
                       windowFeatures: WKWindowFeatures) -> WKWebView?

    /// Whether pop-ups were allowed by the user for the current page (until next navigation)
    @MainActor var popupsTemporarilyAllowedForCurrentPage: Bool { get }
    /// Whether any pop-up was opened by the page for the current page (until next navigation)
    @MainActor var popupWasOpenedForCurrentPage: Bool { get }
    @MainActor var popupOpenedPublisher: AnyPublisher<Void, Never> { get }
    /// Set temporary pop-up allowance (called when user selects "Allow pop-ups for this visit")
    @MainActor func setPopupAllowanceForCurrentPage()
    /// Clear temporary pop-up allowance (called when user selects "Notify" or "Always allow" pop-up permission)
    @MainActor func clearPopupAllowanceForCurrentPage()
}

extension PopupHandlingTabExtension: TabExtension, PopupHandlingTabExtensionProtocol {
    func getPublicProtocol() -> PopupHandlingTabExtensionProtocol { self }

    var popupOpenedPublisher: AnyPublisher<Void, Never> {
        popupOpenedSubject.eraseToAnyPublisher()
    }

    /// Set temporary pop-up allowance (called when user selects "Allow pop-ups for this visit")
    @MainActor func setPopupAllowanceForCurrentPage() {
        popupsTemporarilyAllowedForCurrentPage = true
    }

    /// Clear temporary pop-up allowance (called when user selects "Notify")
    @MainActor func clearPopupAllowanceForCurrentPage() {
        popupsTemporarilyAllowedForCurrentPage = false
    }

}

extension TabExtensions {
    var popupHandling: PopupHandlingTabExtensionProtocol? {
        resolve(PopupHandlingTabExtension.self)
    }
}
