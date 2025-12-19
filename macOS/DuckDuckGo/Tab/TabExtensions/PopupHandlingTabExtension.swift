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
    private let createChildTab: (WKWebViewConfiguration?, SecurityOrigin?, NewWindowPolicy) -> Tab?
    private let presentTab: (Tab, NewWindowPolicy) -> Void
    private let newWindowPolicyDecisionMakers: () -> [NewWindowPolicyDecisionMaking]?
    private let featureFlagger: FeatureFlagger
    private let popupBlockingConfig: PopupBlockingConfiguration
    private let tld: TLD
    private let machAbsTimeProvider: () -> TimeInterval

    // Navigation hotkey handler properties
    private let isTabPinned: () -> Bool
    private let isBurner: Bool
    private let isInPopUpWindow: () -> Bool
    private var onNewWindow: ((WKNavigationAction) -> NewWindowPolicyDecision?)?

    private var cancellables = Set<AnyCancellable>()

    /// The last user interaction event from the publisher (contains timestamp)
    @MainActor private var lastUserInteractionEvent: NSEvent? {
        didSet {
            Logger.navigation.debug("PopupHandlingTabExtension.lastUserInteractionEvent.didSet: \(self.lastUserInteractionEvent ??? "<nil>")")
        }
    }

    /// Whether pop-ups were allowed by the user for the current page (until next navigation)
    @MainActor private(set) var popupsTemporarilyAllowedForCurrentPage = false {
        didSet {
            let newValue = popupsTemporarilyAllowedForCurrentPage
            if oldValue != newValue {
                Logger.navigation.debug("PopupHandlingTabExtension.popupsTemporarilyAllowedForCurrentPage → \(newValue)")
            }
        }
    }
    /// Whether any page-initiated (non-user-initiated) pop-up was opened by the page for the current page (until next navigation)
    /// Used to persist the pop-up button state in the navigation bar
    @MainActor private(set) var pageInitiatedPopupOpened = false {
        didSet {
            pageInitiatedPopupSubject.send()
        }
    }
    /// Notifies when a page-initiated (non-user-initiated) pop-up was opened
    private let pageInitiatedPopupSubject = PassthroughSubject<Void, Never>()

    init(tabsPreferences: TabsPreferences,
         burnerMode: BurnerMode,
         permissionModel: PermissionModel,
         createChildTab: @escaping (WKWebViewConfiguration?, SecurityOrigin?, NewWindowPolicy) -> Tab?,
         presentTab: @escaping (Tab, NewWindowPolicy) -> Void,
         newWindowPolicyDecisionMakers: @escaping () -> [NewWindowPolicyDecisionMaking]?,
         featureFlagger: FeatureFlagger,
         popupBlockingConfig: PopupBlockingConfiguration,
         tld: TLD,
         machAbsTimeProvider: @escaping () -> TimeInterval = CACurrentMediaTime,
         interactionEventsPublisher: some Publisher<WebViewInteractionEvent, Never>,
         isTabPinned: @escaping () -> Bool,
         isBurner: Bool,
         isInPopUpWindow: @escaping () -> Bool) {
        self.tabsPreferences = tabsPreferences
        self.burnerMode = burnerMode
        self.permissionModel = permissionModel
        self.createChildTab = createChildTab
        self.presentTab = presentTab
        self.newWindowPolicyDecisionMakers = newWindowPolicyDecisionMakers
        self.featureFlagger = featureFlagger
        self.popupBlockingConfig = popupBlockingConfig
        self.tld = tld
        self.machAbsTimeProvider = machAbsTimeProvider
        self.isTabPinned = isTabPinned
        self.isBurner = isBurner
        self.isInPopUpWindow = isInPopUpWindow

        interactionEventsPublisher
            .filter { event in
                switch event {
                case .mouseDown, .keyDown, .middleMouseDown:
                    guard featureFlagger.isFeatureOn(.popupBlocking),
                          featureFlagger.isFeatureOn(.extendedUserInitiatedPopupTimeout) else {
                        return false
                    }
                    Logger.navigation.debug("PopupHandlingTabExtension.interactionEventsPublisher.filter: event: \(String(describing: event))")
                    return true
                case .scrollWheel: return false
                }
            }
            .sink { [weak self] event in
                guard let self else { return }
                MainActor.assumeMainThread {
                    switch event {
                    case .mouseDown(let nsEvent), .keyDown(let nsEvent), .middleMouseDown(let nsEvent):
                        self.lastUserInteractionEvent = nsEvent
                    case .scrollWheel:
                        break // Already filtered out above
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// Handles WKUIDelegate createWebViewWithConfiguration:forNavigationAction:windowFeatures: callback
    @MainActor
    func createWebView(from webView: WKWebView, with configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {

        let url = navigationAction.request.url
        switch newWindowPolicy(for: navigationAction) {
        case .allow(var targetKind):
            // Replace `.tab` with `.window` when user prefers windows over tabs
            if case .tab(_, let isBurner, contextMenuInitiated: false) = targetKind,
               !tabsPreferences.preferNewTabsToWindows {
                targetKind = .window(active: true, burner: isBurner)
            }
            // apply selecting the tab if `switchToNewTabWhenOpened` is `true`.
            targetKind = targetKind.preferringSelectedTabs(tabsPreferences.switchToNewTabWhenOpened)
            Logger.navigation.debug("handleCreateWebViewRequest: newWindowPolicy: \(targetKind) for \(url?.absoluteString ??? "<nil>")")
            return createChildWebView(from: webView, with: configuration, for: navigationAction, of: targetKind, isUserInitiated: true)

        case .cancel:
            Logger.navigation.debug("handleCreateWebViewRequest: canceling request for `\(url?.absoluteString ??? "<nil>")` per newWindowPolicy")
            return nil

        case .none: break
        }

        // Use current keyboard modifiers state from NSApp.currentEvent to determine the link open behavior.
        // Select new tab by default; ⌘-click modifies the selection state.
        let linkOpenBehavior = LinkOpenBehavior(event: NSApp.currentEvent,
                                                switchToNewTabWhenOpenedPreference: tabsPreferences.switchToNewTabWhenOpened,
                                                canOpenLinkInCurrentTab: false,
                                                shouldSelectNewTab: true)
        // Determine pop-up kind from provided windowFeatures and current keyboard modifiers state.
        let targetKind = NewWindowPolicy(windowFeatures,
                                         linkOpenBehavior: linkOpenBehavior,
                                         isBurner: burnerMode.isBurner,
                                         preferTabsToWindows: tabsPreferences.preferNewTabsToWindows)

        // Disable pop-ups from unknown sources
        guard let sourceSecurityOrigin = navigationAction.safeSourceFrame.map({ SecurityOrigin($0.securityOrigin) }) else {
            Logger.navigation.debug("handleCreateWebViewRequest: disabling pop-ups from unknown source for `\(url?.absoluteString ??? "<nil>")`")
            return nil
        }

        // Action doesn't require pop-up permission
        if let bypassReason = shouldAllowPopupBypassingPermissionRequest(for: navigationAction, windowFeatures: windowFeatures) {
            Logger.navigation.debug("handleCreateWebViewRequest: allowing pop-up bypassing permission request for `\(url?.absoluteString ??? "<nil>")`: \(bypassReason)")
            // Reset last user interaction event to block future pop-ups within the throttle window (only for user-initiated popups)
            if bypassReason.isUserInitiated {
                lastUserInteractionEvent = nil
            }
            return createChildWebView(from: webView, with: configuration, for: navigationAction, of: targetKind, isUserInitiated: bypassReason.isUserInitiated)
        }

        Logger.navigation.debug("handleCreateWebViewRequest: requesting pop-up permission for `\(url?.absoluteString ??? "<nil>")`")

        // Pop-up permission is needed: firing an async PermissionAuthorizationQuery.
        // ---
        // When the permission is granted synchronously, the resulting WebView is returned immediately.
        // When the callback is called asynchronously, the resulting Tab is created, presented and loaded manually.
        var resultWebView: WKWebView?
        var isCalledSynchronously = true
        defer { isCalledSynchronously = false } // whether the callback was called synchronously or asynchronously
        permissionModel.request([.popups], forDomain: sourceSecurityOrigin.host, url: url)
            .receive { [weak self] result in
                self?.handlePermissionRequestResult(result,
                                                    from: webView,
                                                    with: configuration,
                                                    for: navigationAction,
                                                    targetKind: targetKind,
                                                    isCalledSynchronously: isCalledSynchronously) { resultWebView = $0 }
            }

        return resultWebView
    }

    /// Handles the result of the pop-up permission request
    @MainActor
    func handlePermissionRequestResult(_ permissionRequestResult: Result<Bool, Never>,
                                       from webView: WKWebView,
                                       with configuration: WKWebViewConfiguration,
                                       for navigationAction: WKNavigationAction,
                                       targetKind: NewWindowPolicy,
                                       isCalledSynchronously: Bool,
                                       completionHandler: @escaping (WKWebView?) -> Void) {
        // guarantee the completionHandler is called at all paths
        let result: WKWebView?
        defer {
            // automatic loading won‘t start for asynchronous callback as we‘ve already returned nil as the `createWebView` result at this point
            if !isCalledSynchronously {
                result?.load(navigationAction.request)
            }
            completionHandler(result)
        }

        let url = navigationAction.request.url
        guard case .success(true) = permissionRequestResult else {
            // pop-up permission denied
            Logger.navigation.info("handleCreateWebViewRequest: pop-up permission denied for `\(url?.absoluteString ??? "<nil>")`")
            result = nil
            return
        }
        // Pop-up permission granted.

        // Disable opening empty or `about:` URLs as the opened pop-ups would be non-functional
        // when opened asynchronously after the user has granted the permission.
        if !isCalledSynchronously,
           featureFlagger.isFeatureOn(.popupBlocking), featureFlagger.isFeatureOn(.suppressEmptyPopUpsOnApproval),
           url?.isEmpty ?? true || url?.navigationalScheme == .about {
            Logger.navigation.info("handleCreateWebViewRequest: suppressing pop-up for `\(url?.absoluteString ??? "<nil>")`")
            self.popupsTemporarilyAllowedForCurrentPage = true

            result = nil
            return
        }

        // Permission granted: create and present new tab for the pop-up
        Logger.navigation.debug("handleCreateWebViewRequest: permission granted for `\(url?.absoluteString ??? "<nil>")`")
        result = self.createChildWebView(from: webView, with: configuration, for: navigationAction, of: targetKind, isUserInitiated: false)
        // `defer` calls the completionHandler 
    }

    /// Determines the new window policy for a navigation action based on LinkOpenBehavior and NewWindowPolicy
    /// handled below in decidePolicy(for:) or NewWindowPolicyDecisionMaking-s (ContextMenuManager, DuckPlayerTabExtension, etc.)
    @MainActor
    private func newWindowPolicy(for navigationAction: WKNavigationAction) -> NewWindowPolicyDecision? {
        for handler in [self] + (newWindowPolicyDecisionMakers() ?? []) {
            if let decision = handler.decideNewWindowPolicy(for: navigationAction) {
                return decision
            }
        }
        return nil
    }

    /// Creates a new Tab returning its WebView to a createWebViewWithConfiguration callback
    @MainActor
    private func createChildWebView(from webView: WKWebView,
                                    with configuration: WKWebViewConfiguration,
                                    for navigationAction: WKNavigationAction,
                                    of kind: NewWindowPolicy,
                                    isUserInitiated: Bool) -> WKWebView? {
        // disable opening 'javascript:' links in new tab
        guard navigationAction.request.url?.navigationalScheme != .javascript else { return nil }
        // disable opening internal pages in pop-up windows
        guard TabContent.contentFromURL(navigationAction.request.url, source: .link).isExternalUrl || !kind.isPopup else { return nil }

        let securityOrigin = navigationAction.safeSourceFrame.map { SecurityOrigin($0.securityOrigin) }
        guard let childTab = createChildTab(configuration, securityOrigin, kind) else { return nil }

        presentTab(childTab, kind)

        // Set flag to indicate that a page-initiated (non-user-initiated) pop-up was opened for the current page
        if !isUserInitiated {
            pageInitiatedPopupOpened = true
        }

        // WebKit automatically loads the request in the returned web view.
        return childTab.webView
    }

    /// Determines if a popup should be allowed bypassing the permission request:
    /// - If the navigation action is user-initiated (clicked link, etc.), allow the popup
    /// - If the pop-ups temporarily allowed for the current page with the "Only allow pop-ups for this visit" option selected:
    ///   - Either for empty/about: URLs specifically with `suppressEmptyPopUpsOnApproval` feature flag enabled
    ///   - OR for all URLs when `allowPopupsForCurrentPage` feature flag is enabled
    /// - If the initiating domain is allowlisted in the popupBlockingConfig
    /// - Otherwise, do not allow the popup
    /// ---
    /// - Returns: A `PopupPermissionBypassReason` describing the reason for bypassing permission, or `nil` if the popup should not be allowed
    @MainActor internal func shouldAllowPopupBypassingPermissionRequest(for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> PopupPermissionBypassReason? {
        // Check if the pop-up is user-initiated (clicked link, etc.)
        if let reason = isNavigationActionUserInitiated(navigationAction) {
            return .userInitiated(reason)
        }

        // Check if the source domain is in the allowlist
        if let sourceFrame = navigationAction.safeSourceFrame {
            let allowlist = popupBlockingConfig.allowlist
            let sourceHost = sourceFrame.securityOrigin.host
            if isDomainInAllowlist(sourceHost, allowlist: allowlist) {
                Logger.general.debug("Pop-up allowed: source domain \(sourceHost) is in allowlist")
                return .allowlistedDomain(sourceHost)
            }
        }

        let url = navigationAction.request.url ?? .empty
        // Check if pop-ups temporarily allowed for the current page with the "Only allow pop-ups for this visit" option selected:
        // Either for empty/about: URLs specifically with `suppressEmptyPopUpsOnApproval` feature flag enabled,
        // OR for all URLs when `allowPopupsForCurrentPage` feature flag is enabled
        if featureFlagger.isFeatureOn(.popupBlocking),
           popupsTemporarilyAllowedForCurrentPage
            && (
                (featureFlagger.isFeatureOn(.suppressEmptyPopUpsOnApproval) && (url.isEmpty || url.navigationalScheme == .about))
                || featureFlagger.isFeatureOn(.allowPopupsForCurrentPage)
            ) {
            return .popupsTemporarilyAllowedForCurrentPage
        }

        return nil
    }

    /// Determines if a navigation action is user-initiated (clicked link, etc.)
    /// based on the last user interaction event timestamp and the userInitiatedPopupThreshold
    /// ---
    /// - Returns: A `UserInitiatedReason` describing why the action is user-initiated, or `nil` if the navigation action is not user-initiated
    @MainActor
    func isNavigationActionUserInitiated(_ navigationAction: WKNavigationAction) -> UserInitiatedReason? {
        var threshold = popupBlockingConfig.userInitiatedPopupThreshold

#if DEBUG || REVIEW
        // Allow debug override for faster UI testing (e.g., from environment variable in UI tests)
        if let envValue = ProcessInfo.processInfo.environment["POPUP_TIMEOUT_OVERRIDE"],
           let overrideValue = TimeInterval(envValue) {
            threshold = overrideValue
        }
#endif

        // Check if enhanced popup blocking is enabled and configured properly
        guard featureFlagger.isFeatureOn(.popupBlocking),
              featureFlagger.isFeatureOn(.extendedUserInitiatedPopupTimeout),
              threshold > 0 else {
            assert(threshold > 0, "userInitiatedPopupThreshold in macos-config must be positive")
            // Fall back to WebKit's basic user-initiated check (1s. user interaction timeout) if feature is disabled or misconfigured
            return (navigationAction.isUserInitiated ?? false) ? .webKitUserInitiated : nil
        }

        // Check if user interaction happened within the threshold using the last user interaction event timestamp
        guard let lastUserInteractionEvent else { return nil }

        let currentTime = machAbsTimeProvider()
        let timeSinceInteraction = currentTime - lastUserInteractionEvent.timestamp
        if (0...threshold).contains(timeSinceInteraction) {
            return .extendedTimeout(eventTimestamp: lastUserInteractionEvent.timestamp, currentTime: currentTime)
        }
        return nil
    }

    /// Checks if a domain matches any entry in the allowlist
    /// If "x.example.com" is in the allowlist, it will match "x.example.com" and any subdomain like "sub.x.example.com"
    private func isDomainInAllowlist(_ domain: String, allowlist: Set<String>) -> Bool {
        // Normalize: drop www prefix and lowercase for case-insensitive comparison
        let normalizedDomain = domain.lowercased().droppingWwwPrefix()

        // Get eTLD+1 for the domain to know when to stop stripping components
        guard let domainETLDplus1 = tld.eTLDplus1(normalizedDomain) else {
            return false
        }

        // Check the normalized domain and all parent domains up to eTLD+1
        var currentDomain = normalizedDomain
        repeat {
            // Check if current domain is in allowlist
            if allowlist.contains(currentDomain) {
                return true
            }

            // Strip the first component to get parent domain
            if currentDomain.count > domainETLDplus1.count,
               let dotIndex = currentDomain.firstIndex(of: ".") {
                currentDomain = String(currentDomain[currentDomain.index(after: dotIndex)...])
            } else {
                break
            }
        } while true

        return false
    }

}

// MARK: - NewWindowPolicyDecisionMaking
extension PopupHandlingTabExtension: NewWindowPolicyDecisionMaking {

    func decideNewWindowPolicy(for navigationAction: WKNavigationAction) -> NewWindowPolicyDecision? {
        if let decision = onNewWindow?(navigationAction) {
            onNewWindow = nil
            return decision
        }
        return nil
    }

}

// MARK: - NavigationResponder
extension PopupHandlingTabExtension: NavigationResponder {

    @MainActor
    func willStart(_ navigation: Navigation) {
        // Clear pop-up allowance on any navigation
        popupsTemporarilyAllowedForCurrentPage = false
        pageInitiatedPopupOpened = false
        onNewWindow = nil
    }

    /// Redirect Navigation Actions to the new window/tab for user actions with key modifiers (⌘-click, middle mouse button press…)
    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? {
        // Prevent pop-ups opening internal pages (bookmarks, history, settings, etc.)
        if isInPopUpWindow(),
           !TabContent.contentFromURL(navigationAction.url, source: .link).isExternalUrl {
            return .cancel
        }

        // Must be targeting an existing frame (not a new window/tab)
        guard let targetFrame = navigationAction.targetFrame else { return .next }

        // Check if the navigation action is a link activation (clicked link, etc.)
        let isLinkActivated = !navigationAction.isTargetingNewWindow
        && (navigationAction.navigationType.isLinkActivated || (navigationAction.navigationType == .other && navigationAction.isUserInitiated))
        // Must be a link activation (clicked link, etc.)
        guard isLinkActivated else { return .next }

        // Links clicked in a pinned tab navigating to another domain should open in a new tab
        let canOpenLinkInCurrentTab: Bool = {
            let isNavigatingToAnotherDomain = navigationAction.url.host != targetFrame.url.host && !targetFrame.url.isEmpty
            let isNavigatingAwayFromPinnedTab = isLinkActivated && self.isTabPinned() && isNavigatingToAnotherDomain && navigationAction.isForMainFrame
            return !isNavigatingAwayFromPinnedTab
        }()

        // Last interaction event that triggered the link activation (regular click, ⌘-click, middle-click, key press, etc.)
        let userInteractionEvent = if featureFlagger.isFeatureOn(.popupBlocking), featureFlagger.isFeatureOn(.extendedUserInitiatedPopupTimeout) {
            lastUserInteractionEvent
        } else {
            NSApp.currentEvent
        }
        Logger.navigation.debug("PopupHandlingTabExtension.decidePolicyFor: \(String(describing: navigationAction)) userInteractionEvent: \(userInteractionEvent ??? "<nil>") currentEvent: \(NSApp.currentEvent ??? "<nil>")")

        let linkOpenBehavior = LinkOpenBehavior(button: navigationAction.navigationType.isMiddleButtonClick ? .middle : .left,
                                                modifierFlags: userInteractionEvent?.modifierFlags ?? [],
                                                switchToNewTabWhenOpenedPreference: tabsPreferences.switchToNewTabWhenOpened,
                                                canOpenLinkInCurrentTab: canOpenLinkInCurrentTab)
        // Handle behavior for navigation
        switch linkOpenBehavior {
        case .currentTab:
            return .next

        case .newTab, .newWindow:
            let url = navigationAction.url
            // Save the link open behavior for the upcoming createWebViewWithConfiguration callback that will follow the loadInNewWindow call
            self.onNewWindow = { [isBurner] newWindowNavigationAction -> NewWindowPolicyDecision? in
                // Only allow the new window/tab if the URL matches the original navigation action URL.
                // Fallback to default createWebViewWithConfiguration handling otherwise.
                guard newWindowNavigationAction.request.url?.matches(url) ?? false else {
                    Logger.navigation.debug("PopupHandlingTabExtension.onNewWindow: ignoring `\(newWindowNavigationAction.request.url?.absoluteString ??? "<nil>")`")
                    return nil
                }
                Logger.navigation.debug("PopupHandlingTabExtension.onNewWindow: allowing \(linkOpenBehavior) for `\(url.absoluteString)`")

                return linkOpenBehavior.newWindowPolicy(isBurner: isBurner).map(NewWindowPolicyDecision.allow)
            }
            Logger.navigation.debug("PopupHandlingTabExtension.decidePolicy: \(linkOpenBehavior) for \(url) initiated by \(userInteractionEvent ??? "<nil>")")

            // Consume the user interaction event when actually opening a new window/tab (⌘-click or middle mouse button press…)
            lastUserInteractionEvent = nil
            targetFrame.webView?.loadInNewWindow(url)
            return .cancel
        }
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
    /// Whether any page-initiated (non-user-initiated) pop-up was opened by the page for the current page (until next navigation)
    @MainActor var pageInitiatedPopupOpened: Bool { get }
    @MainActor var pageInitiatedPopupPublisher: AnyPublisher<Void, Never> { get }
    /// Set temporary pop-up allowance (called when user selects "Only allow pop-ups for this visit")
    @MainActor func setPopupAllowanceForCurrentPage()
    /// Clear temporary pop-up allowance (called when user selects "Notify" or "Always allow" pop-up permission)
    @MainActor func clearPopupAllowanceForCurrentPage()
}

extension PopupHandlingTabExtension: TabExtension, PopupHandlingTabExtensionProtocol {
    func getPublicProtocol() -> PopupHandlingTabExtensionProtocol { self }

    var pageInitiatedPopupPublisher: AnyPublisher<Void, Never> {
        pageInitiatedPopupSubject.eraseToAnyPublisher()
    }

    /// Set temporary pop-up allowance (called when user selects "Only allow pop-ups for this visit")
    @MainActor func setPopupAllowanceForCurrentPage() {
        Logger.navigation.debug("PopupHandlingTabExtension.setPopupAllowanceForCurrentPage")
        popupsTemporarilyAllowedForCurrentPage = true
    }

    /// Clear temporary pop-up allowance (called when user selects "Notify")
    @MainActor func clearPopupAllowanceForCurrentPage() {
        Logger.navigation.debug("PopupHandlingTabExtension.clearPopupAllowanceForCurrentPage")
        popupsTemporarilyAllowedForCurrentPage = false
    }

}

extension TabExtensions {
    var popupHandling: PopupHandlingTabExtensionProtocol? {
        resolve(PopupHandlingTabExtension.self)
    }
}

// MARK: - UserInitiatedReason
enum UserInitiatedReason: Equatable {
    case webKitUserInitiated
    case extendedTimeout(eventTimestamp: TimeInterval, currentTime: TimeInterval)
}
extension UserInitiatedReason: CustomStringConvertible {
    var description: String {
        switch self {
        case .webKitUserInitiated:
            return "webKitUserInitiated"
        case .extendedTimeout(eventTimestamp: let eventTimestamp, currentTime: let currentTime):
            return "extendedTimeout(event: \(eventTimestamp), current: \(currentTime), elapsed: \(currentTime - eventTimestamp))"
        }
    }
}

// MARK: - PopupPermissionBypassReason
enum PopupPermissionBypassReason: Equatable {
    case userInitiated(UserInitiatedReason)
    case popupsTemporarilyAllowedForCurrentPage
    case allowlistedDomain(String)

    var isUserInitiated: Bool {
        switch self {
        case .userInitiated, .allowlistedDomain:
            // Don‘t show the pop-up button for user-initiated popups, popups temporarily allowed for the current page, or allowlisted domains
            return true
        case .popupsTemporarilyAllowedForCurrentPage:
            return false
        }
    }
}
extension PopupPermissionBypassReason: CustomStringConvertible {
    var description: String {
        switch self {
        case .userInitiated(let reason):
            return "userInitiated(\(reason))"
        case .popupsTemporarilyAllowedForCurrentPage:
            return "popupsTemporarilyAllowedForCurrentPage"
        case .allowlistedDomain(let domain):
            return "allowlistedDomain(\(domain))"
        }
    }
}
