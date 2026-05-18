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
import Subscription
import Suggestions
import UIKit
import WebKit

// MARK: - Unified Toggle Input Setup

extension MainViewController {

    enum Constants {
        static let floatingReturnKeyKeyboardBottomConstraintIdentifier = "UnifiedToggleInput.FloatingReturnKey.KeyboardBottom"
        static let floatingReturnKeyInputTopConstraintIdentifier = "UnifiedToggleInput.FloatingReturnKey.InputTop"
        static let floatingReturnKeyActiveAnchorPriority = UILayoutPriority(999)
        static let floatingReturnKeyInactiveAnchorPriority = UILayoutPriority(250)

        // Bottom is longer to accommodate concurrent keyboard descent.
        static func omnibarTransitionDuration(isBottom: Bool) -> TimeInterval {
            isBottom ? 0.35 : 0.25
        }

        static let bottomDaxLogoTransitionYOffset: CGFloat = -DefaultOmniBarView.expectedHeight / 2
        static let topDaxLogoTransitionYOffset: CGFloat = 2
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

        let initialToggleEnabled = isAIChatSearchInputToggleEnabledForCurrentOnboardingState()
        let coordinator = UnifiedToggleInputCoordinator(
            host: .omnibar,
            isToggleEnabled: initialToggleEnabled,
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
        coordinator.onAnimatedDismissToOmnibar = { [weak self] completion in
            guard let self, let coordinator = self.unifiedToggleInputCoordinator else { return }
            self.dismissUnifiedToggleInputOmnibarSession(coordinator: coordinator, completion: completion)
        }
        self.unifiedToggleInputCoordinator = coordinator

        installUnifiedToggleInputViewController(coordinator.viewController)

        if let omniBarVC = viewCoordinator.omniBar as? DefaultOmniBarViewController {
            omniBarVC.unifiedToggleInputOmnibarActivating = self
        }

        setUpAIChatTabChatHeader()
        installUnifiedInputContentViewController()
        installFloatingReturnKeyViewController()
        installSwipeTabsGesturesForUnifiedInput()

        subscribeToIntentPublisher(coordinator)
        subscribeToModeChanges(coordinator)
        subscribeToSystemEvents()
        subscribeToToggleSettings()
    }

    func updateUnifiedToggleInputKeyboardVisibility(_ keyboardVisible: Bool) {
        unifiedToggleInputCoordinator?.updateOmnibarInputVisibility(keyboardVisible)
        updateFloatingReturnKeyVisibility()
    }

    var isCurrentTabUsingUnifiedInputAIChrome: Bool {
        unifiedToggleInputFeature.isAvailable && currentTab?.isAITab == true
    }

    /// True when FE has asked us to hide the native chat input for the current AI tab via
    /// `hideChatInput`. Persisted per tab in `TabInputState`.
    var isAIChatInputHiddenForCurrentTab: Bool {
        guard currentTab?.isAITab == true else { return false }
        return unifiedToggleInputCoordinator?.aiChatInputBoxVisibility == .hidden
    }

    /// True when FE has signalled a voice session is in progress on the current AI tab via
    /// `voiceSessionStarted`. Persisted per tab in `TabInputState`.
    var isVoiceSessionActiveForCurrentTab: Bool {
        guard currentTab?.isAITab == true else { return false }
        return unifiedToggleInputCoordinator?.isVoiceSessionActive == true
    }

    /// Hides the bottom UTI input bar when FE asks to hide the chat input. Idempotent.
    func reconcileAIChatInputChromeForCurrentTab() {
        viewCoordinator.setAITabBottomChromeHidden(isAIChatInputHiddenForCurrentTab)
    }

    /// Hides the header chats/compose pill while a voice session is in progress. Idempotent.
    func reconcileVoiceSessionChromeForCurrentTab() {
        aiChatTabChatHeaderView?.setVoiceSessionActive(isVoiceSessionActiveForCurrentTab)
    }

    /// Applies both AI-chrome reconciles together — call from every refresh path so adding a new
    /// per-tab signal doesn't require remembering all three call sites.
    func reconcileAIChromeForCurrentTab() {
        reconcileAIChatInputChromeForCurrentTab()
        reconcileVoiceSessionChromeForCurrentTab()
    }

    /// Force-shows the header back arrow when the toggle UI is unavailable so the user always
    /// has an exit. Wraps the onboarding-aware lookup so both callers (refreshControls + the
    /// settings sink) stay in sync — keeps the raw setting and the onboarding-deferred value
    /// from racing during onboarding hand-off.
    func reconcileBackArrowForceVisibility() {
        aiChatTabChatHeaderView?.setForceBackButtonVisible(!isAIChatSearchInputToggleEnabledForCurrentOnboardingState())
    }

    /// Programmatic dismiss of an active UTI omnibar session (the intent-path used by
    /// `dismissOmniBar`, toolbar buttons, etc.). On a Duck.ai tab this routes through the snap
    /// dismiss so the AI tab's auto-expand doesn't bring the keyboard back up.
    func deactivateUnifiedToggleInputOmnibarSession() {
        guard let coordinator = unifiedToggleInputCoordinator, coordinator.isOmnibarSession else { return }
        if currentTab?.isAITab == true {
            dismissFocusedOmnibarToAITabChrome(coordinator: coordinator)
        } else {
            coordinator.deactivateToOmnibar()
        }
    }

    /// Hides the toolbar on AI tabs; restores it on non-AI tabs. The focused omnibar session
    /// opened from a Duck.ai tab counts as "tab-like" — keep the toolbar so the user has the
    /// standard browser controls while searching. Idempotent; safe with the feature flag off.
    func reconcileToolbarVisibilityForCurrentTab() {
        let isFocusedOmnibarSession = unifiedToggleInputCoordinator?.isOmnibarSession == true
        if isCurrentTabUsingUnifiedInputAIChrome && !isFocusedOmnibarSession {
            viewCoordinator.toolbar.isHidden = true
        } else {
            viewCoordinator.toolbar.isHidden = AppWidthObserver.shared.isLargeWidth || isInMinimalChromeLayout
        }
    }

    func refreshUnifiedToggleInput(for tab: TabViewController) {
        guard unifiedToggleInputFeature.isAvailable,
              let coordinator = unifiedToggleInputCoordinator else {
            return
        }

        // Capture the current tab's screen snapshot regardless of which refresh branch we
        // take — `.unbindInactiveNonAITab` early-returns without falling through, but we
        // still want a fresh snapshot for the swipe overlay every time the tab becomes the
        // active one. `captureCurrentTabScreenSnapshotIfPossible` defers to the next runloop
        // so any layout changes the branches apply have settled by capture time.
        defer {
            captureCurrentTabScreenSnapshotIfPossible(tabUID: tab.tabModel.uid)
        }

        coordinator.activateForTab(tab.tabModel.uid)

        let action = refreshAction(for: tab, coordinator: coordinator)

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
        let unifiedToggleInputContainerColor: UIColor
        let webViewBackgroundColor: UIColor?

        switch state {
        case .standardChrome:
            statusBackgroundPresentation = .standard
            rootBackgroundColor = ThemeManager.shared.currentTheme.mainViewBackgroundColor
            navigationBarContainerColor = nil
            inputContentContainerColor = .clear
            unifiedToggleInputContainerColor = .clear
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
            unifiedToggleInputContainerColor = .clear
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
                unifiedToggleInputContainerColor = .clear
                webViewBackgroundColor = rootBackgroundColor
            } else {
                // Match Figma's `--ds-surface-tertiary` (#3D3D3D dark / white light) so the chrome
                // is the same tone as the card. The card defines itself via its halo rim shadow.
                rootBackgroundColor = UIColor(designSystemColor: .backgroundTertiary)
                navigationBarContainerColor = .clear
                unifiedToggleInputContainerColor = .clear
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
        viewCoordinator.unifiedToggleInputContainer.backgroundColor = unifiedToggleInputContainerColor
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

    /// While Dax Dialogs are still in progress, the onboarding Search vs Search & Duck.ai choice
    /// is not applied to AIChatSettings yet. Use that pending choice for UTI presentation so
    /// Search-only hides the toggle, while Search & Duck.ai keeps it visible.
    func isAIChatSearchInputToggleEnabledForCurrentOnboardingState() -> Bool {
        onboardingSearchExperienceSettingsResolver.deferredValue ?? aiChatSettings.isAIChatSearchInputUserSettingsEnabled
    }

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
                updateFloatingReturnKeyVisibility()
            }
            .store(in: &unifiedToggleInputCancellables)

        coordinator.textChangePublisher
            .sink { [weak self] _ in
                self?.updateFloatingReturnKeyVisibility()
            }
            .store(in: &unifiedToggleInputCancellables)

        // AI-tab search mode swaps suggestions in/out at the empty↔non-empty text boundary.
        coordinator.textChangePublisher
            .map { $0.isEmpty }
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, let coordinator = self.unifiedToggleInputCoordinator,
                      coordinator.isAITabExpanded, coordinator.inputMode == .search else { return }
                self.updateUnifiedInputContentVisibility(for: coordinator)
            }
            .store(in: &unifiedToggleInputCancellables)

        // Refresh Dax overlay visibility while onboarding as omnibar text changes.
        coordinator.textChangePublisher
            .sink { [weak self] _ in
                guard let self, let coordinator = self.unifiedToggleInputCoordinator,
                      !self.daxDialogsManager.hasSeenOnboarding,
                      coordinator.isOmnibarSession else { return }
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
        updateFloatingReturnKeyVisibility()
    }

    func handleOmnibarModeChange(_ mode: TextEntryMode, coordinator: UnifiedToggleInputCoordinator) {
        let previousLottieProgress = coordinator.contentViewController.daxLogoManager.lottieProgress
        let wasLogoVisible = coordinator.contentViewController.daxLogoManager.isLogoVisible
        // If the swipe gesture already drove progress to the target, skip the
        // programmatic animation — the swipe handled the visual transition.
        let swipeProgress = coordinator.contentViewController.daxLogoManager.currentProgress
        let targetProgress: CGFloat = mode == .aiChat ? 1 : 0
        let wasSwipeDriven = abs(swipeProgress - targetProgress) < 0.01

        updateUnifiedInputContentVisibility(for: coordinator)
        syncBottomOmnibarAnchorIfNeeded(for: coordinator)
        adjustUI(withKeyboardFrame: latestKeyboardFrame, in: 0.2, animationCurve: .curveEaseInOut)
        unifiedToggleInputCoordinator?.syncContentInputMode(mode)
        if !wasSwipeDriven {
            coordinator.contentViewController.daxLogoManager.animateLogoTransition(
                toMode: mode,
                fromProgress: previousLottieProgress,
                wasLogoVisible: wasLogoVisible)
        }
        updateFloatingReturnKeyVisibility()
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

        // Live `hideChatInput` / `showChatInput` updates from FE on the currently bound tab.
        // Tab-switch reconciles already happen via the refresh path.
        unifiedToggleInputCoordinator?.aiChatInputBoxVisibilityPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reconcileAIChatInputChromeForCurrentTab()
            }
            .store(in: &unifiedToggleInputCancellables)

        unifiedToggleInputCoordinator?.isVoiceSessionActivePublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reconcileVoiceSessionChromeForCurrentTab()
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

        // Per-tab so background voice tabs persist their state until re-activated.
        NotificationCenter.default.publisher(for: .aiChatVoiceSessionStarted)
            .compactMap { $0.object as? WKWebView }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] webView in
                self?.updateVoiceSessionActive(true, for: webView)
            }
            .store(in: &unifiedToggleInputCancellables)

        NotificationCenter.default.publisher(for: .aiChatVoiceSessionEnded)
            .compactMap { $0.object as? WKWebView }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] webView in
                self?.updateVoiceSessionActive(false, for: webView)
            }
            .store(in: &unifiedToggleInputCancellables)
    }

    private func updateVoiceSessionActive(_ active: Bool, for webView: WKWebView) {
        guard let controller = tabManager.controller(forWebView: webView) else { return }
        if controller === currentTab, let coordinator = unifiedToggleInputCoordinator {
            applyVoiceSessionTransition(active: active, to: coordinator)
            return
        }
        guard let stateStore = unifiedInputStateStore else { return }
        let current = stateStore.state(for: controller.tabModel.uid)
        let updated = current.applyingVoiceSessionTransition(active: active)
        if updated != current {
            stateStore.update(updated, for: controller.tabModel.uid)
        }
    }

    private func applyVoiceSessionTransition(active: Bool, to coordinator: UnifiedToggleInputCoordinator) {
        coordinator.isVoiceSessionActive = active
        if !active, coordinator.aiChatInputBoxVisibility == .hidden {
            coordinator.aiChatInputBoxVisibility = .visible
        }
    }

    func subscribeToToggleSettings() {
        NotificationCenter.default.publisher(for: .aiChatSettingsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let coordinator = self.unifiedToggleInputCoordinator else { return }
                let enabled = self.isAIChatSearchInputToggleEnabledForCurrentOnboardingState()
                self.reconcileBackArrowForceVisibility()
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
        reconcileAIChromeForCurrentTab()
    }

    func refreshAITab(
        tab: TabViewController,
        coordinator: UnifiedToggleInputCoordinator,
        behavior: AITabRefreshBehavior
    ) -> Bool {
        let tabURL = tab.url ?? tab.link?.url
        let hasExistingChat = tabURL?.duckAIChatID != nil
        bindAITabIfPossible(tab: tab, coordinator: coordinator, hasExistingChat: hasExistingChat)
        // Assert input-hidden synchronously for voice-mode tabs so the bottom chrome doesn't
        // flash visible during the FE's "Connecting…" window. The FE's `hideChatInput` is
        // idempotent over this. Persisted per tab in `TabInputState`.
        if tabURL?.isDuckAIVoiceMode == true || tab.isVoiceModeRequested {
            coordinator.aiChatInputBoxVisibility = .hidden
        }
        // Before the early-return so AI→AI tab transitions (`preserveCurrentPresentation`) also
        // override the `UIView`-default-visible borders on a freshly-bound tab.
        tab.borderView.isTopVisible = false
        tab.borderView.isBottomVisible = false
        reconcileToolbarVisibilityForCurrentTab()
        reconcileAIChromeForCurrentTab()

        if case .preserveCurrentPresentation(let allowsEarlyReturn) = behavior, allowsEarlyReturn {
            syncPreservedAITabPresentation(coordinator: coordinator)
            return false
        }

        // Clear after the link==nil bridge so an in-flight voice request survives the transient.
        tab.isVoiceModeRequested = false
        ensureStandardChromeVisibleForAITabRefresh()
        tab.webView.scrollView.contentInset = .zero
        // We're swapping into AI-tab layout, not dismissing the omnibar in place.
        // Skip the dismiss animation — otherwise it runs concurrently with the AI-tab show
        // and the user perceives a top-to-bottom slide.
        coordinator.deactivateToOmnibar(animateDismiss: false)
        viewCoordinator.showAITabChrome()
        applyUnifiedInputChromeBackground(.aiTabChatChromeHidden)

        applyAITabRefreshBehavior(behavior, coordinator: coordinator)
        // Re-run: the early reconcile read pre-transition coordinator state.
        reconcileToolbarVisibilityForCurrentTab()

        updateUnifiedInputContentVisibility(for: coordinator)
        refreshAIChatTabChatHeaderSubscriptionState()
        return true
    }

    func bindAITabIfPossible(tab: TabViewController, coordinator: UnifiedToggleInputCoordinator, hasExistingChat: Bool) {
        if let userScript = tab.userScripts?.aiChatUserScript {
            coordinator.bindToTab(userScript, hasExistingChat: hasExistingChat)
            if hasExistingChat, let chatID = tab.webView.url?.duckAIChatID {
                coordinator.restoreLastUsedModel(forChatID: chatID)
            }
            if let chatUpdatesPublisher = tab.userScripts?.duckAiNativeStorageUserScript?.chatUpdatesPublisher {
                coordinator.observeChatUpdates(chatUpdatesPublisher)
            }
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
        reconcileAIChromeForCurrentTab()
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
                self.dismissUnifiedToggleInputOmnibarSession(coordinator: coordinator)
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

    func installFloatingReturnKeyViewController() {
        guard let coordinator = unifiedToggleInputCoordinator else { return }

        let floatingVC = coordinator.floatingReturnKeyViewController
        floatingVC.delegate = self

        addChild(floatingVC)
        floatingVC.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingVC.view)
        let keyboardBottomConstraint = floatingVC.view.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8)
        keyboardBottomConstraint.identifier = Constants.floatingReturnKeyKeyboardBottomConstraintIdentifier
        keyboardBottomConstraint.priority = Constants.floatingReturnKeyActiveAnchorPriority
        let inputTopConstraint = floatingVC.view.bottomAnchor.constraint(equalTo: viewCoordinator.unifiedToggleInputContainer.topAnchor, constant: -8)
        inputTopConstraint.identifier = Constants.floatingReturnKeyInputTopConstraintIdentifier
        inputTopConstraint.priority = Constants.floatingReturnKeyInactiveAnchorPriority
        unifiedToggleInputFloatingReturnKeyKeyboardBottomConstraint = keyboardBottomConstraint
        unifiedToggleInputFloatingReturnKeyInputTopConstraint = inputTopConstraint
        NSLayoutConstraint.activate([
            keyboardBottomConstraint,
            inputTopConstraint,
            floatingVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        floatingVC.didMove(toParent: self)
        floatingVC.view.isHidden = true
    }

    func updateFloatingReturnKeyVisibility() {
        guard let coordinator = unifiedToggleInputCoordinator else { return }
        let renderState = coordinator.computeRenderState()
        updateFloatingReturnKeyAnchor(aboveUnifiedInput: renderState.isFloatingReturnKeyVisible && renderState.cardPosition == .bottom)
        coordinator.floatingReturnKeyViewController.view.isHidden = !renderState.isFloatingReturnKeyVisible
    }

    func updateFloatingReturnKeyAnchor(aboveUnifiedInput: Bool) {
        unifiedToggleInputFloatingReturnKeyKeyboardBottomConstraint?.priority = aboveUnifiedInput
            ? Constants.floatingReturnKeyInactiveAnchorPriority
            : Constants.floatingReturnKeyActiveAnchorPriority
        unifiedToggleInputFloatingReturnKeyInputTopConstraint?.priority = aboveUnifiedInput
            ? Constants.floatingReturnKeyActiveAnchorPriority
            : Constants.floatingReturnKeyInactiveAnchorPriority
    }
}

private extension MainViewController {

    func dismissUnifiedToggleInputToOmnibar(coordinator: UnifiedToggleInputCoordinator,
                                            completion: (() -> Void)? = nil) {
        applyUnifiedInputChromeBackground(.standardChrome)
        // Resign up-front so the keyboard descent runs concurrent with the bar collapse.
        coordinator.viewController.deactivateInput()
        let omnibarPlaceholderWindowX = currentOmnibarPlaceholderWindowX()
        let omnibarPlaceholderColor = currentOmnibarPlaceholderColor()
        let utiPlaceholderColor = coordinator.viewController.defaultPlaceholderColor
        let duration = Constants.omnibarTransitionDuration(isBottom: coordinator.cardPosition.isBottom)

        let isLogoToLogo = newTabPageViewController?.isShowingLogo == true
        let utiStartCenterY = coordinator.contentViewController.daxLogoManager.logoWindowCenterY
        let ntpStartCenterY = ntpLogoWindowCenterY()
        let isBottom = coordinator.cardPosition.isBottom

        // For logo-to-logo: keep the UTI Logo visible and animate it to the NTP Logo's
        // natural (post-dismiss) position.
        if isLogoToLogo,
           let utiY = utiStartCenterY {
            let ntpNaturalY: CGFloat
            if isBottom {
                // The bottom UTI logo is centered against a guide ending one omnibar-height
                // below the keyboard; compensate by half that height to match the NTP logo.
                ntpNaturalY = (ntpStartCenterY ?? utiY) + Constants.bottomDaxLogoTransitionYOffset
            } else {
                // Top bar: the nav bar shrinks back to standard height, making the
                // contentContainer taller and shifting the NTP Logo center up by half the delta.
                let navHeightDelta = viewCoordinator.constraints.navigationBarContainerHeight.constant
                    - viewCoordinator.standardNavigationBarContainerHeight
                ntpNaturalY = (ntpStartCenterY ?? utiY) - navHeightDelta / 2 + Constants.topDaxLogoTransitionYOffset
            }

            // How far the UTI Logo needs to move to land at the NTP Logo's final position.
            let offset = ntpNaturalY - utiY

            // Hide the NTP Logo — the UTI Logo takes over for the duration of the animation.
            newTabPageViewController?.setLogoHidden(true)

            // If the UTI Logo is showing the duck.ai state, morph it to the search state
            // so it matches the NTP Logo by the time the swap happens.
            if coordinator.contentViewController.daxLogoManager.lottieProgress > 0 {
                coordinator.contentViewController.daxLogoManager.animateProgress(to: 0)
            }

            // Shift the UTI Logo's centering constraint so the dismiss animation drives it
            // to the NTP Logo's post-dismiss position.
            let currentOffset = coordinator.contentViewController.daxLogoManager.logoYOffset
            coordinator.contentViewController.daxLogoManager.setLogoYOffset(currentOffset + offset)
        }

         let shouldCrossfadeOmnibar = !viewCoordinator.isNavigationChromeHidden
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: .curveEaseOut,
            animations: { [weak self] in
                guard let self else { return }
                coordinator.viewController.applyOmnibarEditingDismissPose()
                self.viewCoordinator.animateUnifiedToggleInputOmnibarDismissLayout()
                // Mirror the focus path: push updated content insets so the suggestion
                // tray content (including the escape hatch) animates with the bar collapse.
                coordinator.pushContentInsets()
                if !isLogoToLogo {
                    self.viewCoordinator.unifiedInputContentContainer.alpha = 0
                }
                if shouldCrossfadeOmnibar {
                    self.viewCoordinator.navigationBarCollectionView.alpha = 1
                    self.viewCoordinator.unifiedToggleInputContainer.alpha = 0
                }
                if let omnibarPlaceholderWindowX {
                    coordinator.viewController.alignPlaceholderHorizontally(toWindowX: omnibarPlaceholderWindowX)
                }
            },
            completion: { [weak self] _ in
                guard let self, let coordinator = self.unifiedToggleInputCoordinator else { return }
                // Reveal the NTP Logo and force a layout pass before hiding the UTI
                // content container, so the NTP Logo is rendered in the same frame
                // and there's no one-frame gap where neither logo is visible.
                self.newTabPageViewController?.setLogoHidden(false)
                self.newTabPageViewController?.view.setNeedsLayout()
                self.newTabPageViewController?.view.layoutIfNeeded()
                self.viewCoordinator.unifiedInputContentContainer.isHidden = true
                self.viewCoordinator.unifiedInputContentContainer.alpha = 1
                coordinator.contentViewController.daxLogoManager.setLogoYOffset(0)
                coordinator.contentViewController.setLogoHidden(false)
                coordinator.viewController.setTextHorizontalShift(0)
                coordinator.deactivateToOmnibar(resetView: false, animateDismiss: false)
                coordinator.viewController.finalizeOmnibarEditingDismiss()
                // The user can land here on a non-AI tab (e.g. NTP via the after-idle escape
                // hatch) while the toolbar is still hidden from a prior Duck.ai session.
                // Reconcile against the *current* tab — idempotent and AI-tab paths re-hide
                // the toolbar on their own.
                self.reconcileToolbarVisibilityForCurrentTab()
                completion?()
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

    /// Routes a UTI omnibar-session dismiss to the matching chrome — Duck.ai header restore for
    /// AI tabs, standard omnibar morph for everything else.
    func dismissUnifiedToggleInputOmnibarSession(coordinator: UnifiedToggleInputCoordinator,
                                                 completion: (() -> Void)? = nil) {
        if currentTab?.isAITab == true {
            dismissFocusedOmnibarToAITabChrome(coordinator: coordinator, completion: completion)
        } else {
            dismissUnifiedToggleInputToOmnibar(coordinator: coordinator, completion: completion)
        }
    }

    /// Snaps back to AI tab chrome — the two surfaces share no visual element, so a crossfade
    /// would briefly show both. Pins coordinator to `.aiTab(.collapsed)` so refresh routes to
    /// `.preserveCurrentPresentation` and skips the auto-expand.
    func dismissFocusedOmnibarToAITabChrome(coordinator: UnifiedToggleInputCoordinator,
                                            completion: (() -> Void)? = nil) {
        viewCoordinator.unifiedInputContentContainer.isHidden = true
        viewCoordinator.showAIChatTabChatHeader()
        viewCoordinator.animateUnifiedToggleInputOmnibarDismissLayout()
        coordinator.deactivateToOmnibar(resetView: false, animateDismiss: false)
        coordinator.showCollapsed()
        if let tab = currentTab {
            refreshUnifiedToggleInput(for: tab)
        }
        completion?()
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
        let isToggleEnabled = isAIChatSearchInputToggleEnabledForCurrentOnboardingState()
        coordinator.updateToggleEnabled(isToggleEnabled)
        coordinator.contentViewController.isSwipeEnabled = isToggleEnabled
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
        handleVoiceSearchOpenRequest(preferredTarget: mode == .aiChat ? .AIChat : .SERP)
    }

    func unifiedToggleInputDidRequestAIVoiceChat() {
        onDuckAIVoiceModeRequested()
    }

    func unifiedToggleInputDidRequestAIChat(prefilledText: String) {
        let trimmed = prefilledText.trimmingWhitespace()
        unifiedToggleInputCoordinator?.clearText()
        unifiedToggleInputCoordinator?.handleExternalSubmission(.prompt)
        // On a Duck.ai tab, load a new chat URL here so the previous chat goes into WebView back-history.
        if currentTab?.isAITab == true {
            currentTab?.load(trimmed.isEmpty ? nil : trimmed, autoSend: !trimmed.isEmpty)
            return
        }
        onAIChatPressed(prefilledText: trimmed.isEmpty ? nil : trimmed)
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

    func unifiedToggleInputDismissSnapshot() -> UTIDismissSnapshot {
        let preferredMode = preferredTextEntryModeForCurrentTab() ?? .search
        let tab = tabManager.currentTabsModel.currentTab
        // AI tab reuses the same textView for the flanked input — text here bleeds past the
        // collapse. AI-mode tabs likewise show a placeholder rather than the URL.
        let isAIDestination = tab?.isAITab == true || preferredMode == .aiChat
        let placeholderMode: TextEntryMode = isAIDestination ? .aiChat : preferredMode
        let text = isAIDestination ? "" : AddressDisplayHelper.plainDisplayString(for: tab?.link?.url)
        return UTIDismissSnapshot(text: text, placeholderMode: placeholderMode)
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

    func unifiedInputEditingStateDidRequestTabSwitcher() {
        requestTabSwitcher()
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
        if currentTab?.canGoBack == true {
            onBackPressed()
        } else {
            presentFocusedOmnibarFromAITab()
        }
    }

    func aiChatTabChatHeaderDidTapForward() {
        onForwardPressed()
    }

    /// Hides only the AI Chat header (NOT the nav chrome via `hideAITabChrome()`) so the standard
    /// omnibar stays suppressed and dismiss skips its omnibar crossfade.
    private func presentFocusedOmnibarFromAITab() {
        guard let coordinator = unifiedToggleInputCoordinator else { return }
        viewCoordinator.hideAIChatTabChatHeader()
        applyUnifiedInputChromeBackground(.standardChrome)

        let position: UnifiedToggleInputCardPosition = appSettings.currentAddressBarPosition == .bottom ? .bottom : .top
        coordinator.activateFromOmnibar(prefilledText: nil, inputMode: .search, cardPosition: position)
        reconcileToolbarVisibilityForCurrentTab()
    }
}

// MARK: - UnifiedToggleInputFloatingReturnKeyDelegate

extension MainViewController: UnifiedToggleInputFloatingReturnKeyDelegate {

    func floatingReturnKeyDidTap() {
        guard let coordinator = unifiedToggleInputCoordinator else { return }
        coordinator.insertNewlineFromFloatingReturnKey()
    }

}
