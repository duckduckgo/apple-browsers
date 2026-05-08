//
//  MainViewController+UnifiedToggleInput.swift
//  DuckDuckGo
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

import AIChat
import Bookmarks
import Combine
import DesignResourcesKit
import ObjectiveC
import os
import Subscription
import Suggestions
import UIKit

// MARK: - Unified Toggle Input Setup

private let aiTabToolbarLogger = Logger(subsystem: "com.duckduckgo.mobile.ios", category: "AITabToolbar")
private var toolbarIsHiddenObservationKey: UInt8 = 0
private var navBarContainerHiddenObservationKey: UInt8 = 0
private var aiChatVoiceSessionActiveKey: UInt8 = 0

extension MainViewController {

    enum Constants {
        // Bottom is longer to accommodate concurrent keyboard descent.
        static func omnibarTransitionDuration(isBottom: Bool) -> TimeInterval {
            isBottom ? 0.35 : 0.25
        }
    }

    enum UnifiedInputChromeBackgroundState: String {
        case standardChrome
        case aiTabSearchChromeHidden
        case aiTabChatChromeHidden
    }

    func setUpUnifiedToggleInputIfNeeded() {
        guard unifiedToggleInputFeature.isAvailable else { return }

        let aiChatPreferences = AIChatPreferencesPersistor()
        let stateStore = UnifiedInputStateStore(
            preferences: aiChatPreferences,
            toggleModeStorage: toggleModeStorage
        )
        stateStore.observeTabsModel(tabManager.normalTabsModel)
        stateStore.observeTabsModel(tabManager.fireModeTabsModel)
        self.unifiedInputStateStore = stateStore

        let coordinator = UnifiedToggleInputCoordinator(
            host: .omnibar,
            isToggleEnabled: aiChatSettings.isAIChatSearchInputUserSettingsEnabled,
            isFireTab: isCurrentTabFireTab(),
            duckAiNativeStorageHandler: duckAiNativeStorageHandler,
            preferences: aiChatPreferences,
            toggleModeStorage: toggleModeStorage,
            stateStore: stateStore
        )
        coordinator.delegate = self
        coordinator.updateVoiceSearchAvailability(voiceSearchHelper.isVoiceSearchEnabled)
        coordinator.updateAIVoiceChatAvailability(voiceShortcutFeature.isAvailable)
        coordinator.updateAIChatShortcutAvailability(aiChatAddressBarExperience.shouldShowDuckAIAddressBarButton)
        coordinator.onAnimatedDismissToOmnibar = { [weak self] in
            guard let self, let coordinator = self.unifiedToggleInputCoordinator else { return }
            self.dismissUnifiedToggleInputToOmnibar(coordinator: coordinator)
        }
        self.unifiedToggleInputCoordinator = coordinator

        installUnifiedToggleInputViewController(coordinator.viewController)

        if let omniBarVC = viewCoordinator.omniBar as? DefaultOmniBarViewController {
            omniBarVC.unifiedToggleInputOmnibarActivating = self
        }

        setUpAIChatTabChatHeader()
        installUnifiedInputContentViewController()
        installFloatingSubmitViewController()

        subscribeToIntentPublisher(coordinator)
        subscribeToModeChanges(coordinator)
        subscribeToSystemEvents()
        subscribeToToggleSettings()
    }

    func updateUnifiedToggleInputKeyboardVisibility(_ keyboardVisible: Bool) {
        unifiedToggleInputCoordinator?.updateOmnibarInputVisibility(keyboardVisible)
    }

    var isCurrentTabUsingUnifiedInputAIChrome: Bool {
        unifiedToggleInputFeature.isAvailable && currentTab?.isAITab == true
    }

    /// `true` when the current tab is an AI tab and either:
    /// - the URL is a Duck AI voice-mode URL, *or*
    /// - the duck.ai page has signalled it's in an active voice session via `voiceSessionStarted`.
    ///
    /// Both signals are needed because each one alone has a gap:
    /// - The URL flips to `?mode=voice` even when the connection fails (rate limit / mic denied),
    ///   so the URL catches "page is rendering voice UI" cases the notification misses.
    /// - duck.ai uses `replaceState` mid-session to clean up the URL, so the URL alone would
    ///   mistakenly say "no longer voice" while the user is still in an active voice session.
    ///   The session flag holds true through that.
    var isCurrentTabUsingVoiceMode: Bool {
        guard let currentTab, currentTab.isAITab else { return false }
        return isCurrentTabAtVoiceModeURL || aiChatVoiceSessionActive
    }

    private var aiChatVoiceSessionActive: Bool {
        get { (objc_getAssociatedObject(self, &aiChatVoiceSessionActiveKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &aiChatVoiceSessionActiveKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// Single source of truth for the AI-tab voice-mode chrome reduction: hides the chats /
    /// new-chat pair pill in the AI header and removes the bottom flanked UTI bar so the voice
    /// WebView fills the available height. Idempotent — call from every refresh.
    func reconcileVoiceModeChromeForCurrentTab() {
        let active = isCurrentTabUsingVoiceMode
        let ts = voiceDiagTimestamp()
        aiTabToolbarLogger.error(
            "[voiceDiag \(ts, privacy: .public)] reconcile active=\(active, privacy: .public) sessionActive=\(self.aiChatVoiceSessionActive, privacy: .public) urlVoice=\(self.isCurrentTabAtVoiceModeURL, privacy: .public) webViewURL=\(String(describing: self.currentTab?.webView.url), privacy: .public) reqFlag=\(self.currentTab?.isVoiceModeRequested == true, privacy: .public) isAITab=\(self.currentTab?.isAITab == true, privacy: .public)"
        )
        aiChatTabChatHeaderView?.setVoiceModeActive(active)
        viewCoordinator.setAITabBottomChromeHidden(active)
    }

    private func voiceDiagTimestamp() -> String {
        let date = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private var isCurrentTabAtVoiceModeURL: Bool {
        guard let currentTab, currentTab.isAITab else { return false }
        // Prefer `webView.url` — it updates synchronously when WK commits a navigation, while
        // `currentTab.url` lags ~100ms behind because of the `asyncAfter` delay in
        // `TabViewController`'s KVO handler. Falling back to the lagged value is fine for the
        // brief window before `webView.url` is populated.
        let url = currentTab.webView.url ?? currentTab.url ?? currentTab.tabModel.link?.url
        return url?.isDuckAIVoiceMode == true || currentTab.isVoiceModeRequested
    }

    /// Single source of truth for the bottom toolbar's hidden state in AI-tab/non-AI-tab
    /// transitions. The hidden state is **derived** from `currentTab?.isAITab` (gated by the
    /// unified-toggle-input feature flag), never imperatively passed by the caller — the
    /// previous API took a `Bool` and that asymmetry (one path setting `true`, a sibling path
    /// forgetting to set `false`) is what produced the "stuck without toolbar after the
    /// idle-return escape hatch" class of bug.
    ///
    /// Call this from any code path that:
    ///   - Changes the active tab (tab swap, swipe, tab switcher).
    ///   - Lands the user on a non-AI surface from an AI surface, or vice versa
    ///     (NTP attach, omnibar dismiss completion, idle-return routing).
    ///   - Changes size class / orientation that may have hidden the toolbar for other
    ///     reasons (`applyLargeWidth`/`applySmallWidth`).
    ///
    /// The setter is idempotent so over-calling is free; under-calling is what creates these
    /// bugs. If a new path can flip `currentTab` and the toolbar isn't reconciling, **add a
    /// call here** rather than re-introducing an imperative `setToolbarHidden(_ bool: Bool)`
    /// — that surface is what we're deliberately removing.
    ///
    /// Direct mutations of `viewCoordinator.toolbar.isHidden` outside of unrelated subsystems
    /// (minimal chrome, blank snapshot, tab-switcher multi-select) are tripwired by
    /// `installAITabToolbarObserverIfNeeded` — they will surface as `BUG: toolbar.isHidden
    /// became false on AI tab` in the logs.
    func reconcileToolbarVisibilityForCurrentTab() {
        installAITabToolbarObserverIfNeeded()
        if isCurrentTabUsingUnifiedInputAIChrome {
            viewCoordinator.toolbar.isHidden = true
        } else {
            viewCoordinator.toolbar.isHidden = AppWidthObserver.shared.isLargeWidth
        }
    }

    func refreshUnifiedToggleInput(for tab: TabViewController) {
        guard unifiedToggleInputFeature.isAvailable,
              let coordinator = unifiedToggleInputCoordinator else {
            return
        }

        coordinator.activateForTab(tab.tabModel.uid)

        let action = refreshAction(for: tab, coordinator: coordinator)
        let tabURL = tab.url ?? tab.link?.url
        aiTabToolbarLogger.debug(
            "refreshUnifiedToggleInput action=\(String(describing: action), privacy: .public) isAITab=\(tab.isAITab, privacy: .public) hasChatID=\((tabURL?.duckAIChatID != nil), privacy: .public) coordState=\(String(describing: coordinator.displayState), privacy: .public)"
        )

        switch action {
        case .unbindInactiveNonAITab:
            refreshInactiveNonAITab(tab: tab, coordinator: coordinator)
            tab.updateWebViewBottomAnchor(for: currentBarsVisibility)
            return
        case .refreshAITab(let behavior):
            let completedRefresh = refreshAITab(tab: tab, coordinator: coordinator, behavior: behavior)
            if !completedRefresh {
                return
            }
        case .refreshNonAITab:
            refreshNonAITab(tab: tab, coordinator: coordinator)
        }

        tab.updateWebViewBottomAnchor(for: currentBarsVisibility)
    }

    func applyUnifiedInputChromeBackground(_ state: UnifiedInputChromeBackgroundState, updateWebView: Bool = true) {

        let statusBackgroundPresentation: MainViewCoordinator.StatusBackgroundPresentation
        let rootBackgroundColor: UIColor
        let navigationBarContainerColor: UIColor?
        let inputContentContainerColor: UIColor
        let webViewBackgroundColor: UIColor?

        switch state {
        case .standardChrome:
            statusBackgroundPresentation = .standard
            rootBackgroundColor = ThemeManager.shared.currentTheme.mainViewBackgroundColor
            navigationBarContainerColor = nil
            inputContentContainerColor = .clear
            webViewBackgroundColor = nil
        case .aiTabSearchChromeHidden:
            // Match the top status background so the area around the input card — and the area
            // behind the keyboard's translucency — blend with the chat surface. The web view
            // also takes the same colour so the brief moment after a frame change (before
            // WKWebView's out-of-process renderer catches up) shows the same colour rather
            // than the parent flashing through.
            statusBackgroundPresentation = .aiTabSearchChromeHidden
            rootBackgroundColor = UIColor(designSystemColor: .panel)
            navigationBarContainerColor = rootBackgroundColor
            inputContentContainerColor = .clear
            webViewBackgroundColor = rootBackgroundColor
        case .aiTabChatChromeHidden:
            statusBackgroundPresentation = .aiTabChatChromeHidden
            inputContentContainerColor = .clear
            // Only paint the chrome around the input with the contextual sheet tone while the
            // input is engaged (first responder). In the idle/collapsed state we keep the chrome
            // transparent so the chat surface beneath shows through unchanged.
            if unifiedToggleInputCoordinator?.isInputEditing == true {
                rootBackgroundColor = UIColor(singleUseColor: .duckAIContextualSheetBackground)
                navigationBarContainerColor = rootBackgroundColor
                webViewBackgroundColor = rootBackgroundColor
            } else {
                rootBackgroundColor = ThemeManager.shared.currentTheme.mainViewBackgroundColor
                navigationBarContainerColor = .clear
                webViewBackgroundColor = .clear
            }
        }

        viewCoordinator.setStatusBackgroundPresentation(statusBackgroundPresentation)
        if case .standardChrome = state {
            refreshStatusBarBackgroundAfterAIChrome()
        }

        view.backgroundColor = rootBackgroundColor
        viewCoordinator.navigationBarContainer.backgroundColor = navigationBarContainerColor
        viewCoordinator.unifiedInputContentContainer?.backgroundColor = inputContentContainerColor
        viewCoordinator.unifiedToggleInputContainer.backgroundColor = .clear
        unifiedToggleInputCoordinator?.viewController.view.backgroundColor = .clear

        guard updateWebView else { return }
        if let webView = currentTab?.webView {
            webView.backgroundColor = webViewBackgroundColor
            webView.scrollView.backgroundColor = webViewBackgroundColor
            webView.underPageBackgroundColor = webViewBackgroundColor
        }
    }

    func recomputeNavigationBarContainerHeightIfNeeded() {
        guard let coordinator = unifiedToggleInputCoordinator,
              coordinator.isInputEditing else {
            return
        }
        let height = coordinator.editingHeight()
        guard viewCoordinator.constraints.navigationBarContainerHeight.constant != height else { return }
        viewCoordinator.constraints.navigationBarContainerHeight.constant = height
        viewCoordinator.navigationBarContainer.superview?.layoutIfNeeded()
        coordinator.pushContentInsets()
    }

}

private extension MainViewController {

    enum UnifiedToggleInputRefreshAction {
        case unbindInactiveNonAITab
        case refreshAITab(AITabRefreshBehavior)
        case refreshNonAITab
    }

    enum AITabRefreshBehavior {
        case preserveCurrentPresentation(allowsEarlyReturn: Bool)
        case showCollapsed(expandAfterRefresh: Bool)
    }

    func installUnifiedToggleInputViewController(_ inputVC: UnifiedToggleInputViewController) {
        addChild(inputVC)
        inputVC.view.translatesAutoresizingMaskIntoConstraints = false
        viewCoordinator.unifiedToggleInputContainer.addSubview(inputVC.view)
        NSLayoutConstraint.activate([
            inputVC.view.topAnchor.constraint(equalTo: viewCoordinator.unifiedToggleInputContainer.topAnchor),
            inputVC.view.leadingAnchor.constraint(equalTo: viewCoordinator.unifiedToggleInputContainer.leadingAnchor),
            inputVC.view.trailingAnchor.constraint(equalTo: viewCoordinator.unifiedToggleInputContainer.trailingAnchor),
            inputVC.view.bottomAnchor.constraint(equalTo: viewCoordinator.unifiedToggleInputContainer.bottomAnchor),
        ])
        inputVC.didMove(toParent: self)
    }

    func subscribeToIntentPublisher(_ coordinator: UnifiedToggleInputCoordinator) {
        coordinator.intentPublisher
            .sink { [weak self] intent in
                self?.handleUnifiedToggleInputIntent(intent)
            }
            .store(in: &unifiedToggleInputCancellables)
    }

    func subscribeToModeChanges(_ coordinator: UnifiedToggleInputCoordinator) {
        coordinator.modeChangePublisher
            .sink { [weak self] mode in
                self?.handleModeChange(mode)
            }
            .store(in: &unifiedToggleInputCancellables)

        coordinator.attachmentsChangePublisher
            .sink { [weak self] in
                guard let self, let coordinator = unifiedToggleInputCoordinator else { return }
                if coordinator.isInputEditing {
                    adjustUI(withKeyboardFrame: latestKeyboardFrame, in: 0.2, animationCurve: .curveEaseInOut)
                }
            }
            .store(in: &unifiedToggleInputCancellables)

        // The render state on AI tab in search mode depends on whether the user has typed
        // anything (empty → keep chat web view; typed → swap in suggestions). React only on
        // the empty↔non-empty boundary so we don't recompute on every keystroke.
        coordinator.textChangePublisher
            .map { $0.isEmpty }
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, let coordinator = self.unifiedToggleInputCoordinator,
                      coordinator.isAITabExpanded, coordinator.inputMode == .search else { return }
                self.updateUnifiedInputContentVisibility(for: coordinator)
            }
            .store(in: &unifiedToggleInputCancellables)
    }

    func handleModeChange(_ mode: TextEntryMode) {
        guard let coordinator = unifiedToggleInputCoordinator else { return }

        if coordinator.isOmnibarSession {
            handleOmnibarModeChange(mode, coordinator: coordinator)
        } else if coordinator.isAITabExpanded {
            handleAITabModeChange(mode, coordinator: coordinator)
        } else if coordinator.isAITabState && mode == .aiChat {
            coordinator.showExpanded(inputMode: .aiChat)
        }
    }

    func handleOmnibarModeChange(_ mode: TextEntryMode, coordinator: UnifiedToggleInputCoordinator) {
        updateUnifiedInputContentVisibility(for: coordinator)
        syncBottomOmnibarAnchorIfNeeded(for: coordinator)
        adjustUI(withKeyboardFrame: latestKeyboardFrame, in: 0.2, animationCurve: .curveEaseInOut)
        unifiedToggleInputCoordinator?.syncContentInputMode(mode)
        updateFloatingSubmitVisibility()
    }

    func handleAITabModeChange(_ mode: TextEntryMode, coordinator: UnifiedToggleInputCoordinator) {
        UIView.performWithoutAnimation {
            updateUnifiedInputContentVisibility(for: coordinator)
            let chromeBackgroundState = aiTabChromeBackgroundState(for: coordinator.computeRenderState())
            applyUnifiedInputChromeBackground(chromeBackgroundState)
            viewCoordinator.navigationBarContainer.superview?.layoutIfNeeded()
        }
        adjustUI(withKeyboardFrame: latestKeyboardFrame, in: 0.2, animationCurve: .curveEaseInOut)

        if keyboardShowing,
           !coordinator.viewController.isInputFirstResponder,
           currentTab?.aiChatContextualSheetCoordinator.isSheetPresented != true {
            DispatchQueue.main.async { [weak coordinator] in
                guard let coordinator, coordinator.isAITabExpanded else { return }
                coordinator.activateInput()
            }
        }
    }

    func subscribeToSystemEvents() {
        NotificationCenter.default.publisher(for: .speechRecognizerDidChangeAvailability)
            .sink { [weak self] _ in
                guard let self else { return }
                self.unifiedToggleInputCoordinator?.updateVoiceSearchAvailability(self.voiceSearchHelper.isVoiceSearchEnabled)
            }
            .store(in: &unifiedToggleInputCancellables)

        NotificationCenter.default.publisher(for: .entitlementsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.unifiedToggleInputCoordinator?.fetchModels()
                if self.currentTab?.isAITab == true {
                    self.refreshAIChatTabChatHeaderSubscriptionState()
                }
            }
            .store(in: &unifiedToggleInputCancellables)

        // duck.ai's user script posts these when it actually enters / exits a voice session.
        // We use them in tandem with URL detection — the page also `replaceState`s the URL off
        // `?mode=voice` mid-session, which would otherwise falsely restore chrome.
        NotificationCenter.default.publisher(for: .aiChatVoiceSessionStarted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.aiChatVoiceSessionActive = true
                self?.reconcileVoiceModeChromeForCurrentTab()
            }
            .store(in: &unifiedToggleInputCancellables)

        NotificationCenter.default.publisher(for: .aiChatVoiceSessionEnded)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.aiChatVoiceSessionActive = false
                self?.reconcileVoiceModeChromeForCurrentTab()
            }
            .store(in: &unifiedToggleInputCancellables)
    }

    func subscribeToToggleSettings() {
        NotificationCenter.default.publisher(for: .aiChatSettingsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let coordinator = self.unifiedToggleInputCoordinator else { return }
                let enabled = self.aiChatSettings.isAIChatSearchInputUserSettingsEnabled
                coordinator.updateToggleEnabled(enabled)
                coordinator.contentViewController.isSwipeEnabled = enabled
                coordinator.updateAIChatShortcutAvailability(self.aiChatAddressBarExperience.shouldShowDuckAIAddressBarButton)
            }
            .store(in: &unifiedToggleInputCancellables)
    }

    func refreshAction(for tab: TabViewController, coordinator: UnifiedToggleInputCoordinator) -> UnifiedToggleInputRefreshAction {
        // During a fresh navigation (e.g. opening a chat in a new tab), `tabModel.link` is briefly
        // set to nil before WebView reports the new URL. `tab.isAITab` is link-derived, so it would
        // momentarily report false and route us through `refreshNonAITab` → `coordinator.hide()`,
        // tearing down the UTI we just set up. Preserve the current AI presentation through that
        // window — the next refresh, after WebView reports the URL, resolves correctly.
        if tab.link == nil && coordinator.isAITabState {
            return .refreshAITab(.preserveCurrentPresentation(allowsEarlyReturn: true))
        }

        if !tab.isAITab {
            if !coordinator.isActive && viewCoordinator.aiChatTabChatHeaderContainer.isHidden {
                return .unbindInactiveNonAITab
            }
            return .refreshNonAITab
        }

        if coordinator.isAITabState {
            return .refreshAITab(.preserveCurrentPresentation(allowsEarlyReturn: viewCoordinator.isNavigationChromeHidden))
        }

        // `tab.url` lags behind `tab.link?.url` during a freshly-opened tab; use the same
        // fallback for hasExistingChat so we don't spuriously auto-expand the UTI on top of
        // an existing-chat URL whose query string only just arrived.
        let tabURL = tab.url ?? tab.link?.url
        let hasExistingChat = tabURL?.duckAIChatID != nil
        let isVoiceMode = tabURL?.isDuckAIVoiceMode == true || tab.isVoiceModeRequested
        let isSidebarOpen = tabURL?.isDuckAISidebarOpen == true
        let shouldExpandAfterRefresh = !hasExistingChat && !coordinator.hasSubmittedPrompt && !isVoiceMode && !isSidebarOpen
        return .refreshAITab(.showCollapsed(expandAfterRefresh: shouldExpandAfterRefresh))
    }

    func refreshInactiveNonAITab(tab: TabViewController, coordinator: UnifiedToggleInputCoordinator) {
        viewCoordinator.hideAITabChrome()
        applyUnifiedInputChromeBackground(.standardChrome)
        viewCoordinator.moveAddressBarToPosition(appSettings.currentAddressBarPosition)
        refreshViewsBasedOnAddressBarPosition(appSettings.currentAddressBarPosition)
        // Reconcile toolbar against the now-non-AI current tab. Skip `showBars()` here (unlike
        // `refreshNonAITab`) — at app launch this runs before `SwipeTabsCoordinator`'s
        // collection is ready and would assert.
        reconcileToolbarVisibilityForCurrentTab()
        reconcileVoiceModeChromeForCurrentTab()
    }

    func refreshAITab(
        tab: TabViewController,
        coordinator: UnifiedToggleInputCoordinator,
        behavior: AITabRefreshBehavior
    ) -> Bool {
        let hasExistingChat = (tab.url ?? tab.link?.url)?.duckAIChatID != nil
        bindAITabIfPossible(tab: tab, coordinator: coordinator, hasExistingChat: hasExistingChat)
        reconcileToolbarVisibilityForCurrentTab()
        reconcileVoiceModeChromeForCurrentTab()
        // Reset the pending voice-mode signal once chrome has reconciled — subsequent refreshes
        // can rely on `tab.url`'s `isDuckAIVoiceMode` (URL is the source of truth once committed).
        // A stale flag only matters if voice navigation is cancelled before the URL commits.
        tab.isVoiceModeRequested = false

        if case .preserveCurrentPresentation(let allowsEarlyReturn) = behavior, allowsEarlyReturn {
            syncPreservedAITabPresentation(coordinator: coordinator)
            return false
        }

        ensureStandardChromeVisibleForAITabRefresh()
        tab.webView.scrollView.contentInset = .zero
        // We're swapping into AI-tab layout, not dismissing the omnibar in place.
        // Skip the dismiss animation — otherwise it runs concurrently with the AI-tab show
        // and the user perceives a top-to-bottom slide.
        coordinator.deactivateToOmnibar(animateDismiss: false)
        viewCoordinator.showAITabChrome()
        applyUnifiedInputChromeBackground(.aiTabChatChromeHidden)

        applyAITabRefreshBehavior(behavior, coordinator: coordinator)

        updateUnifiedInputContentVisibility(for: coordinator)
        refreshAIChatTabChatHeaderSubscriptionState()
        tab.borderView.isTopVisible = false
        tab.borderView.isBottomVisible = false
        return true
    }

    func bindAITabIfPossible(tab: TabViewController, coordinator: UnifiedToggleInputCoordinator, hasExistingChat: Bool) {
        if let userScript = tab.userScripts?.aiChatUserScript {
            coordinator.bindToTab(userScript, hasExistingChat: hasExistingChat)
        }
    }

    func ensureStandardChromeVisibleForAITabRefresh() {
        guard swipeTabsCoordinator?.tabsModel != nil else { return }
        showBars()
    }
}

extension MainViewController {

    func aiTabChromeBackgroundState(for renderState: UTIRenderState) -> UnifiedInputChromeBackgroundState {
        renderState.isContentVisible ? .aiTabSearchChromeHidden : .aiTabChatChromeHidden
    }
}

private extension MainViewController {

    func installAITabToolbarObserverIfNeeded() {
        if objc_getAssociatedObject(self, &toolbarIsHiddenObservationKey) != nil {
            return
        }

        let observation = viewCoordinator.toolbar.observe(\.isHidden, options: [.new]) { [weak self] _, change in
            guard let self, change.newValue == false, self.currentTab?.isAITab == true else { return }

            let stack = Thread.callStackSymbols.dropFirst(5).prefix(25).joined(separator: "\n")
            aiTabToolbarLogger.error("BUG: toolbar.isHidden became false on AI tab stack=\(stack, privacy: .public)")
        }

        objc_setAssociatedObject(self, &toolbarIsHiddenObservationKey, observation, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        // Tripwire for the regression where the omnibar / navigationBarContainer disappears on
        // a fresh app launch. Logs every transition with stack so we can identify the path that
        // hides it incorrectly.
        if objc_getAssociatedObject(self, &navBarContainerHiddenObservationKey) == nil {
            let navObservation = viewCoordinator.navigationBarContainer.observe(\.isHidden, options: [.old, .new]) { [weak self] _, change in
                guard let self else { return }
                let stack = Thread.callStackSymbols.dropFirst(5).prefix(25).joined(separator: "\n")
                aiTabToolbarLogger.error("[navBarDiag] navigationBarContainer.isHidden \(change.oldValue ?? false, privacy: .public)→\(change.newValue ?? false, privacy: .public) currentTabIsAITab=\(self.currentTab?.isAITab == true, privacy: .public) stack=\(stack, privacy: .public)")
            }
            objc_setAssociatedObject(self, &navBarContainerHiddenObservationKey, navObservation, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    func syncPreservedAITabPresentation(coordinator: UnifiedToggleInputCoordinator) {
        let renderState = coordinator.computeRenderState()
        let chromeBackgroundState = aiTabChromeBackgroundState(for: renderState)
        applyUnifiedInputChromeBackground(chromeBackgroundState)
        updateUnifiedInputContentVisibility(for: coordinator)
        refreshAIChatTabChatHeaderSubscriptionState()
    }

    func applyAITabRefreshBehavior(_ behavior: AITabRefreshBehavior, coordinator: UnifiedToggleInputCoordinator) {
        switch behavior {
        case .preserveCurrentPresentation:
            break
        case .showCollapsed(let expandAfterRefresh):
            coordinator.showCollapsed()
            guard expandAfterRefresh else { return }
            DispatchQueue.main.async { [weak coordinator] in
                guard let coordinator, coordinator.isAITabState else { return }
                coordinator.showExpanded(inputMode: .aiChat)
            }
        }
    }

    func refreshNonAITab(tab: TabViewController, coordinator: UnifiedToggleInputCoordinator) {
        viewCoordinator.hideAITabChrome()
        viewCoordinator.moveAddressBarToPosition(appSettings.currentAddressBarPosition)
        refreshViewsBasedOnAddressBarPosition(appSettings.currentAddressBarPosition)
        applyUnifiedInputChromeBackground(.standardChrome)
        tab.borderView.updateForAddressBarPosition(appSettings.currentAddressBarPosition)
        tab.borderView.isBottomVisible = true
        reconcileToolbarVisibilityForCurrentTab()
        reconcileVoiceModeChromeForCurrentTab()
        showBars()
        if coordinator.isActive {
            coordinator.deactivateToOmnibar()
            coordinator.hide()
            coordinator.unbind()
        }
    }

    func setUpAIChatTabChatHeader() {
        let headerView = AIChatTabChatHeaderView()
        headerView.delegate = self
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.tabSwitcherButton.delegate = self
        headerView.tabSwitcherButton.showMenuOnLongPress = fireModeCapability.isFireModeEnabled
        viewCoordinator.aiChatTabChatHeaderContainer.addSubview(headerView)
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: viewCoordinator.aiChatTabChatHeaderContainer.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: viewCoordinator.aiChatTabChatHeaderContainer.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: viewCoordinator.aiChatTabChatHeaderContainer.trailingAnchor),
            headerView.bottomAnchor.constraint(equalTo: viewCoordinator.aiChatTabChatHeaderContainer.bottomAnchor),
        ])
        self.aiChatTabChatHeaderView = headerView
    }

    func refreshAIChatTabChatHeaderSubscriptionState() {
        Task { @MainActor [weak self] in
            let isActive = (try? await AppDependencyProvider.shared.subscriptionManager.isFeatureEnabled(.paidAIChat)) ?? false
            self?.aiChatTabChatHeaderView?.configure(isSubscriptionActive: isActive)
        }
    }
}

extension MainViewController {

    func updateUnifiedInputContentVisibility(for coordinator: UnifiedToggleInputCoordinator) {
        updateUnifiedInputContentVisibility(for: coordinator, renderState: coordinator.computeRenderState())
    }

    func updateUnifiedInputContentVisibility(for coordinator: UnifiedToggleInputCoordinator, renderState: UTIRenderState) {
        let isOnAITab = currentTab?.isAITab == true
        coordinator.contentViewController.forceBottomBarLayout = coordinator.isAITabState

        let isAITabCollapsed = coordinator.isAITabState && !renderState.isExpanded
        coordinator.viewController.setAITabCollapsedFooterPoseActive(isAITabCollapsed)
        viewCoordinator.setAITabCollapsedTopSeparatorVisible(isAITabCollapsed)

        applyTopChromeState(renderState: renderState, isOnAITab: isOnAITab, coordinator: coordinator)
    }

    func applyTopChromeState(renderState: UTIRenderState, isOnAITab: Bool, coordinator: UnifiedToggleInputCoordinator) {
        if isOnAITab, viewCoordinator.isNavigationChromeHidden {
            let chromeBackgroundState = aiTabChromeBackgroundState(for: renderState)
            applyUnifiedInputChromeBackground(chromeBackgroundState, updateWebView: false)
        }

        viewCoordinator.updateUnifiedToggleInputColors(
            inputView: coordinator.viewController.view
        )

        if renderState.isContentVisible {
            coordinator.contentViewController.setActive(true)
            coordinator.syncContentInputMode(renderState.contentInputMode, animated: false)
            coordinator.pushContentInsets()
            viewCoordinator.showUnifiedInputContent()
            coordinator.contentViewController.refreshVisibleContentIfNeeded()
        } else {
            coordinator.contentViewController.setActive(false)
            viewCoordinator.hideUnifiedInputContent()
        }

        if isOnAITab {
            if renderState.isContentVisible {
                viewCoordinator.hideAIChatTabChatHeader()
            } else {
                viewCoordinator.showAIChatTabChatHeader()
            }
            if viewIfLoaded?.window != nil {
                view.layoutIfNeeded()
            }
        }
    }

    func installUnifiedInputContentViewController() {
        guard let coordinator = unifiedToggleInputCoordinator,
              let container = viewCoordinator.unifiedInputContentContainer else {
            return
        }

        let contentVC = coordinator.contentViewController
        contentVC.suggestionTrayDependencies = suggestionTrayDependencies
        contentVC.delegate = self
        contentVC.onDismissRequested = { [weak self] in
            guard let self, let coordinator = self.unifiedToggleInputCoordinator else { return }
            if coordinator.isOmnibarSession {
                self.dismissUnifiedToggleInputToOmnibar(coordinator: coordinator)
            } else if coordinator.isAITabExpanded {
                coordinator.showCollapsed()
            }
        }
        contentVC.onSwipeDownRequested = { [weak self] in
            guard let self, let coordinator = self.unifiedToggleInputCoordinator else { return }
            coordinator.dismissOmnibarKeyboard()
        }
        contentVC.isSwipeEnabled = coordinator.isToggleEnabled

        addChild(contentVC)
        contentVC.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentVC.view)
        NSLayoutConstraint.activate([
            contentVC.view.topAnchor.constraint(equalTo: container.topAnchor),
            contentVC.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentVC.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentVC.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        contentVC.didMove(toParent: self)
    }

    func installFloatingSubmitViewController() {
        guard let coordinator = unifiedToggleInputCoordinator else { return }

        let floatingVC = coordinator.floatingSubmitViewController
        floatingVC.delegate = self

        addChild(floatingVC)
        floatingVC.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingVC.view)
        NSLayoutConstraint.activate([
            floatingVC.view.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
            floatingVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        floatingVC.didMove(toParent: self)
        floatingVC.subscribe(to: coordinator.textChangePublisher)
        floatingVC.view.isHidden = true
    }

    func updateFloatingSubmitVisibility() {
        guard let coordinator = unifiedToggleInputCoordinator else { return }
        let renderState = coordinator.computeRenderState()
        coordinator.floatingSubmitViewController.view.isHidden = !renderState.isFloatingSubmitVisible
    }
}

private extension MainViewController {

    func dismissUnifiedToggleInputToOmnibar(coordinator: UnifiedToggleInputCoordinator) {
        applyUnifiedInputChromeBackground(.standardChrome)
        // Resign up-front so the keyboard descent runs concurrent with the bar collapse.
        coordinator.viewController.deactivateInput()
        let omnibarPlaceholderWindowX = currentOmnibarPlaceholderWindowX()
        let omnibarPlaceholderColor = currentOmnibarPlaceholderColor()
        let utiPlaceholderColor = coordinator.viewController.defaultPlaceholderColor
        let duration = Constants.omnibarTransitionDuration(isBottom: coordinator.cardPosition.isBottom)
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: .curveEaseOut,
            animations: { [weak self] in
                guard let self else { return }
                coordinator.viewController.applyOmnibarEditingDismissPose()
                self.viewCoordinator.animateUnifiedToggleInputOmnibarDismissLayout()
                self.viewCoordinator.unifiedInputContentContainer.alpha = 0
                if let omnibarPlaceholderWindowX {
                    coordinator.viewController.alignPlaceholderHorizontally(toWindowX: omnibarPlaceholderWindowX)
                }
            },
            completion: { [weak self] _ in
                guard let self, let coordinator = self.unifiedToggleInputCoordinator else { return }
                self.viewCoordinator.unifiedInputContentContainer.isHidden = true
                self.viewCoordinator.unifiedInputContentContainer.alpha = 1
                coordinator.viewController.setTextHorizontalShift(0)
                coordinator.deactivateToOmnibar(resetView: false, animateDismiss: false)
                coordinator.viewController.finalizeOmnibarEditingDismiss()
                // The user can land here on a non-AI tab (e.g. NTP via the after-idle escape
                // hatch) while the toolbar is still hidden from a prior Duck.ai session.
                // Reconcile against the *current* tab — idempotent and AI-tab paths re-hide
                // the toolbar on their own.
                self.reconcileToolbarVisibilityForCurrentTab()
            }
        )

        if let omnibarPlaceholderColor {
            coordinator.viewController.animatePlaceholderColorTransition(
                from: utiPlaceholderColor,
                to: omnibarPlaceholderColor,
                duration: duration
            )
        }
    }

    func handleUnifiedToggleInputSearchSubmission(_ query: String) {
        let isAITabSubmission = currentTab?.isAITab == true
        if isAITabSubmission {
            viewCoordinator.hideAITabChrome()
            applyUnifiedInputChromeBackground(.standardChrome, updateWebView: false)
            // Preempt any synchronous UI refresh triggered by loadQuery so the presentation stays mapped to standard chrome.
        }
        loadQuery(query)
        if isAITabSubmission {
            applyUnifiedInputChromeBackground(.standardChrome)
        }
    }

}

// MARK: - UnifiedToggleInputOmnibarActivating

extension MainViewController: UnifiedToggleInputOmnibarActivating {

    func activateFromOmnibarIfNeeded(currentText: String?) -> UnifiedToggleInputActivationDecision {
        guard let coordinator = unifiedToggleInputCoordinator,
              currentTab?.isAITab != true else {
            return .allowDefault
        }
        let position: UnifiedToggleInputCardPosition = appSettings.currentAddressBarPosition == .bottom ? .bottom : .top
        let inputMode = tabManager.currentTabsModel.currentTab?.unifiedInputState.preferredTextEntryMode ?? .search
        coordinator.activateFromOmnibar(prefilledText: currentText, inputMode: inputMode, cardPosition: position)
        return .intercept
    }
}

// MARK: - UnifiedToggleInputDelegate

extension MainViewController: UnifiedToggleInputDelegate {

    func unifiedToggleInputDidCommitMode(_ mode: TextEntryMode) {
        tabManager.currentTabsModel.currentTab?.unifiedInputState.preferredTextEntryMode = mode
    }

    func unifiedToggleInputDidSubmitPrompt(_ prompt: String, modelId: String?, tools: [AIChatRAGTool]?, reasoningEffort: AIChatReasoningEffort?, images: [AIChatNativePrompt.NativePromptImage]?, files: [AIChatNativePrompt.NativePromptFile]?) {
        openAIChat(prompt, autoSend: true, tools: tools, modelId: modelId, reasoningEffort: reasoningEffort, images: images, files: files)
    }

    func unifiedToggleInputDidSubmitQuery(_ query: String) {
        handleUnifiedToggleInputSearchSubmission(query)
    }

    func unifiedToggleInputDidRequestVoiceSearch() {
        let mode = unifiedToggleInputCoordinator?.inputMode ?? .search
        if mode == .aiChat && voiceShortcutFeature.isAvailable {
            onDuckAIVoiceModeRequested()
        } else {
            handleVoiceSearchOpenRequest(preferredTarget: mode == .aiChat ? .AIChat : .SERP)
        }
    }

    func unifiedToggleInputDidRequestAIChat() {
        onAIChatPressed()
    }

    func unifiedToggleInputDidChangeHeight() {
        recomputeNavigationBarContainerHeightIfNeeded()
    }

    func unifiedToggleInputDidRequestFire() {
        onFirePressed()
    }

    func unifiedToggleInputDidRequestDuckAIVoiceMode() {
        onDuckAIVoiceModeRequested()
    }
}

// MARK: - UnifiedInputContentContainerViewControllerDelegate

extension MainViewController: UnifiedInputContentContainerViewControllerDelegate {

    func unifiedInputEditingStateDidSubmitQuery(_ query: String) {
        unifiedToggleInputCoordinator?.clearText()
        unifiedToggleInputCoordinator?.handleExternalSubmission(.query)
        handleUnifiedToggleInputSearchSubmission(query)
    }

    func unifiedInputEditingStateDidSubmitPrompt(_ query: String, tools: [AIChatRAGTool]?) {
        let submissionConfiguration = unifiedToggleInputCoordinator?.prepareExternalPromptSubmission()
        unifiedToggleInputCoordinator?.clearText()
        unifiedToggleInputCoordinator?.handleExternalSubmission(.prompt)
        openAIChat(
            query,
            autoSend: true,
            tools: tools,
            modelId: submissionConfiguration?.modelId,
            reasoningEffort: submissionConfiguration?.reasoningEffort
        )
    }

    func unifiedInputEditingStateDidSelectFavorite(_ favorite: BookmarkEntity) {
        handleFavoriteSelected(favorite)
    }

    func unifiedInputEditingStateDidEditFavorite(_ favorite: BookmarkEntity) {
        segueToEditBookmark(favorite)
    }

    func unifiedInputEditingStateDidSelectSuggestion(_ suggestion: Suggestion) {
        handleSuggestionSelected(suggestion)
    }

    func unifiedInputEditingStateDidSelectChatHistory(url: URL) {
        onChatHistorySelected(url: url)
    }

    func unifiedInputEditingStateDidRequestSwitchTab(_ tab: Tab) {
        onSwitchToTab(tab)
    }

    func unifiedInputEditingStateDidRequestTryFireMode() {
        unifiedToggleInputCoordinator?.contentViewController.dismissAnimated()
        showTabSwitcher(forceFireTabsTip: true)
    }

    func unifiedInputEditingStateDidChangeMode(_ mode: TextEntryMode) {
        unifiedToggleInputCoordinator?.syncInputModeFromExternalSource(mode)
    }
}

// MARK: - AIChatTabChatHeaderViewDelegate

extension MainViewController: AIChatTabChatHeaderViewDelegate {

    func aiChatTabChatHeaderDidTapChatList() {
        unifiedToggleInputCoordinator?.showCollapsed()
        currentTab?.submitToggleSidebarAction()
    }

    func aiChatTabChatHeaderDidTapNewChat() {
        unifiedToggleInputCoordinator?.startNewChat()
        unifiedToggleInputCoordinator?.showExpanded(inputMode: .aiChat)
        currentTab?.submitStartChatAction()
    }

    func aiChatTabChatHeaderDidTapUpgrade() {
        NotificationCenter.default.post(
            name: .settingsDeepLinkNotification,
            object: SettingsViewModel.SettingsDeepLinkSection.subscriptionFlow()
        )
    }

    func aiChatTabChatHeaderDidTapAppMenu() {
        onMenuPressed()
    }

    func aiChatTabChatHeaderDidTapBack() {
        onBackPressed()
    }

    func aiChatTabChatHeaderDidTapForward() {
        onForwardPressed()
    }
}

// MARK: - UnifiedToggleInputFloatingSubmitDelegate

extension MainViewController: UnifiedToggleInputFloatingSubmitDelegate {

    func floatingSubmitDidTapSubmit() {
        guard let coordinator = unifiedToggleInputCoordinator else { return }
        let text = coordinator.currentText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        coordinator.switchBarHandler.submitText(text)
    }

    func floatingSubmitDidTapVoice() {
        onDuckAIVoiceModeRequested()
    }
}
