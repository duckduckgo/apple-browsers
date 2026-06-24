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
import Core
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

        /// Gap kept between the bottom of the expanded UTI and the top of the keyboard when
        /// constraining the UTI's growth to the available space (landscape).
        static let utiLandscapeKeyboardGap: CGFloat = 8

        // Bottom is longer to accommodate concurrent keyboard descent.
        static func omnibarTransitionDuration(isBottom: Bool) -> TimeInterval {
            isBottom ? 0.35 : 0.25
        }

        /// Stretch the icon fade-in past UTI's collapse so the build-up reads rather than front-loading.
        static let omnibarIconFadeInDurationMultiplier: Double = 1.2
    }

    enum UnifiedInputChromeBackgroundState: String {
        case standardChrome
        case aiTabSearchChromeHidden
        case aiTabChatChromeHidden
    }

    func setUpUnifiedToggleInputIfNeeded() {
        // Idempotent: callable from viewDidLoad, MainCoordinator.startOnboardingFlowIfNotSeenBefore,
        // and onboardingCompleted — first call that passes the gates wins.
        guard unifiedToggleInputCoordinator == nil,
              unifiedToggleInputFeature.isAvailable else { return }

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
            hidesToggleOnDuckAITab: unifiedToggleInputFeature.isToggleHiddenOnDuckAITab,
            duckAiNativeStorageHandler: duckAiNativeStorageHandler,
            preferences: aiChatPreferences,
            toggleModeStorage: toggleModeStorage,
            stateStore: stateStore,
            syncService: syncService,
            aiChatSyncCleaner: aiChatSyncCleaner,
            duckAIWideEventInstrumentation: duckAIWideEventInstrumentation
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

        // If the Duck.ai fire onboarding flow armed its lock before the coordinator existed
        // (coordinator creation is deferred until after linear onboarding completes), sync
        // the persisted lock state to both freshly-created objects now.
        if duckAIFireOnboardingFlow.controlsLocked {
            coordinator.setOnboardingControlsLocked(true)
            aiChatTabChatHeaderView?.setOnboardingLocked(true)
        }
        installUnifiedInputContentViewController()
        installFloatingReturnKeyViewController()
        installSwipeTabsGesturesForUnifiedInput()

        subscribeToIntentPublisher(coordinator)
        subscribeToModeChanges(coordinator)
        subscribeToSystemEvents()
        subscribeToToggleSettings()

        // Immediately reconcile chrome for the already-selected tab. If a tab was
        // selected before UTI existed (e.g. a duck.ai tab opened from onboarding
        // before linear onboarding completed), the legacy nav bar would otherwise
        // remain visible until the next tab-change event triggered a refresh.
        if let currentTab {
            refreshUnifiedToggleInput(for: currentTab)
        }
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
        let wasHidden = viewCoordinator.toolbar.isHidden
        if isCurrentTabUsingUnifiedInputAIChrome && !isFocusedOmnibarSession {
            viewCoordinator.toolbar.isHidden = true
        } else {
            viewCoordinator.toolbar.isHidden = AppWidthObserver.shared.isLargeWidth || isInMinimalChromeLayout
            // Self-heal a stale clamp. `updateToolbarConstant` deliberately pushes the
            // toolbar's constraint off-screen whenever `toolbar.isHidden == true`. This
            // is required for iPad and minimal-chrome layouts, where the toolbar is
            // permanently hidden and its off-screen layout slot acts as a spacer.
            //
            // The UTI AI-tab phase reuses `isHidden = true` *transiently*. Any
            // `setBarsVisibility(1)` call during that phase (refreshAITab, BarsAnimator,
            // applyDuckAIFireChromeState, etc.) writes the same off-screen
            // value via the clamp. When `isHidden` flips back to false here, nothing
            // else recomputes the constant; the toolbar is unhidden but laid out
            // off-screen. Snap it back to 0.
            //
            // `alpha == 1` excludes mid-scroll partial-hides. `BarsAnimator` writes
            // matching `alpha` and `constant` values together, so they can only
            // disagree when the clamp suppressed a write.
            if !viewCoordinator.toolbar.isHidden
                && viewCoordinator.toolbar.alpha == 1.0
                && viewCoordinator.constraints.toolbarBottom.constant != 0 {
                viewCoordinator.constraints.toolbarBottom.constant = 0
            }
        }
        // `toolbarBottom.constant` is derived from `isHidden`; recompute when it flips.
        if wasHidden != viewCoordinator.toolbar.isHidden {
            setBarsVisibility(currentBarsVisibility, animated: false, animationDuration: nil)
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
        case .preserveOmnibarSession:
            return
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
            navigationBarContainerColor = ThemeManager.shared.currentTheme.barBackgroundColor
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
                rootBackgroundColor = UIColor(designSystemColor: .surfaceCanvas)
                navigationBarContainerColor = .clear
                unifiedToggleInputContainerColor = UIColor(designSystemColor: .surfaceCanvas)
                webViewBackgroundColor = UIColor(designSystemColor: .surfaceCanvas)
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
        updateLandscapeEditingCap()
        var height = coordinator.editingHeight()
        if let cap = landscapeEditingHeightCap {
            height = min(height, cap)
        }
        guard viewCoordinator.constraints.navigationBarContainerHeight.constant != height else { return }
        viewCoordinator.constraints.navigationBarContainerHeight.constant = height
        viewCoordinator.navigationBarContainer.superview?.layoutIfNeeded()
        coordinator.pushContentInsets()
    }

    /// Caps the expandable editing field to the space above the keyboard in landscape (the field
    /// scrolls internally), and lifts the cap in portrait. The single source of truth for the cap;
    /// call it from any path that changes the keyboard, orientation, or content.
    func updateLandscapeEditingCap() {
        guard let coordinator = unifiedToggleInputCoordinator, coordinator.isInputEditing else { return }
        coordinator.viewController.setAvailableExpandedHeight(landscapeEditingHeightCap)
    }

    /// Height budget above the keyboard the expanded UTI must fit within, or nil when unconstrained.
    var landscapeEditingHeightCap: CGFloat? {
        isPhoneLandscape ? availableUTIEditingHeight() : nil
    }

    private func availableUTIEditingHeight() -> CGFloat {
        // Measure from the top safe-area edge — a stable reference. The container's own top moves
        // with its height when it's keyboard-anchored from the bottom, so it can't be used here.
        let keyboardTopY = view.keyboardLayoutGuide.layoutFrame.minY
        let safeAreaTopY = view.safeAreaInsets.top
        return max(0, keyboardTopY - safeAreaTopY - Constants.utiLandscapeKeyboardGap)
    }

}

// MARK: - UTI Refresh-Action Decision (pure)

enum UnifiedToggleInputRefreshAction: Equatable {
    case unbindInactiveNonAITab
    case refreshAITab(AITabRefreshBehavior)
    case refreshNonAITab
    /// The coordinator is mid-omnibar session on a non-AI tab — leave it alone.
    case preserveOmnibarSession
}

enum AITabRefreshBehavior: Equatable {
    case preserveCurrentPresentation(allowsEarlyReturn: Bool)
    case showCollapsed(expandAfterRefresh: Bool)
}

struct UnifiedToggleInputRefreshActionInputs: Equatable {
    let tabIsAITab: Bool
    let tabURL: URL?
    let tabLinkURL: URL?
    let tabIsVoiceModeRequested: Bool
    let coordinatorIsAITabState: Bool
    let coordinatorIsActive: Bool
    let coordinatorIsOmnibarSession: Bool
    let coordinatorHasSubmittedPrompt: Bool
    let isAITabChatHeaderContainerHidden: Bool
    let isNavigationChromeHidden: Bool
}

extension MainViewController {

    static func decideRefreshAction(for inputs: UnifiedToggleInputRefreshActionInputs) -> UnifiedToggleInputRefreshAction {
        // During a fresh navigation (e.g. opening a chat in a new tab), `tabModel.link` is briefly
        // set to nil before WebView reports the new URL. `tab.isAITab` is link-derived, so it would
        // momentarily report false and route us through `refreshNonAITab` → `coordinator.hide()`,
        // tearing down the UTI we just set up. Preserve the current AI presentation through that
        // window — the next refresh, after WebView reports the URL, resolves correctly.
        if inputs.tabLinkURL == nil && inputs.coordinatorIsAITabState {
            return .refreshAITab(.preserveCurrentPresentation(allowsEarlyReturn: true))
        }

        if !inputs.tabIsAITab {
            if !inputs.coordinatorIsActive && inputs.isAITabChatHeaderContainerHidden {
                return .unbindInactiveNonAITab
            }
            if inputs.coordinatorIsOmnibarSession {
                return .preserveOmnibarSession
            }
            return .refreshNonAITab
        }

        // `tab.url` lags behind `tab.link?.url` during a freshly-opened tab; use the same
        // fallback for hasExistingChat so we don't spuriously auto-expand the UTI on top of
        // an existing-chat URL whose query string only just arrived.
        let resolvedURL = inputs.tabURL ?? inputs.tabLinkURL
        let isVoiceMode = resolvedURL?.isDuckAIVoiceMode == true || inputs.tabIsVoiceModeRequested

        if inputs.coordinatorIsAITabState {
            // Voice never inherits an expanded chat presentation: voice hides the input box, so once it ends the bottom chrome would render expanded (no fire button / app menu) over a non-focused tab. Force collapse so the standard collapsed accessories return on dismiss.
            if isVoiceMode {
                return .refreshAITab(.showCollapsed(expandAfterRefresh: false))
            }
            return .refreshAITab(.preserveCurrentPresentation(allowsEarlyReturn: inputs.isNavigationChromeHidden))
        }

        let hasExistingChat = resolvedURL?.duckAIChatID != nil
        let isSidebarOpen = resolvedURL?.isDuckAISidebarOpen == true
        let isSettingsOpen = resolvedURL?.isDuckAISettingsOpen == true
        let shouldExpandAfterRefresh = !hasExistingChat && !inputs.coordinatorHasSubmittedPrompt && !isVoiceMode && !isSidebarOpen && !isSettingsOpen
        return .refreshAITab(.showCollapsed(expandAfterRefresh: shouldExpandAfterRefresh))
    }
}

private extension MainViewController {

    /// While Dax Dialogs are still in progress, the onboarding Search vs Search & Duck.ai choice
    /// is not applied to AIChatSettings yet. Use that pending choice for UTI presentation so
    /// Search-only hides the toggle, while Search & Duck.ai keeps it visible.
    func isAIChatSearchInputToggleEnabledForCurrentOnboardingState() -> Bool {
        onboardingSearchExperienceSettingsResolver.deferredValue ?? aiChatSettings.isAIChatSearchInputUserSettingsEnabled
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
                    // Attachments grow the card, so re-cap before sizing or it overflows in landscape.
                    updateLandscapeEditingCap()
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

        if let tab = tabManager.currentTabsModel.currentTab, tab.link == nil {
            ntpAfterIdleInstrumentation.toggleUsedFromNTP(afterIdle: tab.openedAfterIdle)
        }
        postIdleSessionInstrumentation.toggleUsed()

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
        // The empty-state logo morph is driven by the SwiftUI host (`FocusedLogoModel`) off the committed
        // mode — no manager animation here.
        updateUnifiedInputContentVisibility(for: coordinator)
        syncBottomOmnibarAnchorIfNeeded(for: coordinator)
        adjustUI(withKeyboardFrame: latestKeyboardFrame, in: 0.2, animationCurve: .curveEaseInOut)
        unifiedToggleInputCoordinator?.syncContentInputMode(mode)
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

        NotificationCenter.default.publisher(for: .aiChatNewImageGenerationChatStarted)
            .compactMap { $0.object as? WKWebView }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] webView in
                self?.handleNewImageGenerationChatStarted(for: webView)
            }
            .store(in: &unifiedToggleInputCancellables)

        NotificationCenter.default.publisher(for: .aiChatShowModelPicker)
            .compactMap { $0.object as? WKWebView }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] webView in
                self?.handleShowModelPicker(for: webView)
            }
            .store(in: &unifiedToggleInputCancellables)
    }

    /// Routes the FE's `showModelPicker` to the foreground Duck.ai tab's UTI so the user can pick a
    /// supported model for the active chat (recovery-card "Switch Model" CTA). No-op when there's no
    /// foreground Duck.ai UTI.
    private func handleShowModelPicker(for webView: WKWebView) {
        let isCurrent = tabManager.controller(forWebView: webView) === currentTab
        let isAITab = currentTab?.isAITab == true
        guard isCurrent, isAITab, let coordinator = unifiedToggleInputCoordinator else {
            return
        }
        coordinator.presentModelPickerForActiveChat()
    }

    /// Updates the foreground tab's UTI to reflect an FE-initiated image-generation chat.
    /// Backgrounded tabs without a live coordinator are intentionally ignored — revisit if
    /// the FE starts firing this for non-foreground chats.
    private func handleNewImageGenerationChatStarted(for webView: WKWebView) {
        guard let controller = tabManager.controller(forWebView: webView),
              controller === currentTab,
              unifiedToggleInputCoordinator != nil else { return }
        // Mirror the New-Chat-from-sidebar path (`aiChatContentHandlerDidReceiveNewChatCreated`):
        // defer so the URL-change refresh lands first, then run `startNewChat` + `showExpanded`
        // on a clean state. `selectTool` slots between them because `startNewChat` resets tools.
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let coordinator = self.unifiedToggleInputCoordinator,
                  self.tabManager.controller(forWebView: webView) === self.currentTab else { return }
            coordinator.startNewChat()
            coordinator.selectTool(.imageGeneration)
            coordinator.showExpanded(inputMode: .aiChat)
        }
    }

    private func updateVoiceSessionActive(_ active: Bool, for webView: WKWebView) {
        guard let controller = tabManager.controller(forWebView: webView) else { return }
        if controller === currentTab, let coordinator = unifiedToggleInputCoordinator {
            coordinator.isVoiceSessionActive = active
            return
        }
        guard let stateStore = unifiedInputStateStore else { return }
        let current = stateStore.state(for: controller.tabModel.uid)
        var updated = current
        updated.isVoiceSessionActive = active
        if updated != current {
            stateStore.update(updated, for: controller.tabModel.uid)
        }
    }

    func subscribeToToggleSettings() {
        NotificationCenter.default.publisher(for: .aiChatSettingsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let coordinator = self.unifiedToggleInputCoordinator else { return }
                let enabled = self.isAIChatSearchInputToggleEnabledForCurrentOnboardingState()
                coordinator.updateToggleEnabled(enabled)
                coordinator.updateAIChatShortcutAvailability(self.aiChatAddressBarExperience.shouldShowDuckAIAddressBarButton)
            }
            .store(in: &unifiedToggleInputCancellables)
    }

    func refreshAction(for tab: TabViewController, coordinator: UnifiedToggleInputCoordinator) -> UnifiedToggleInputRefreshAction {
        let inputs = UnifiedToggleInputRefreshActionInputs(
            tabIsAITab: tab.isAITab,
            tabURL: tab.url,
            tabLinkURL: tab.link?.url,
            tabIsVoiceModeRequested: tab.isVoiceModeRequested,
            coordinatorIsAITabState: coordinator.isAITabState,
            coordinatorIsActive: coordinator.isActive,
            coordinatorIsOmnibarSession: coordinator.isOmnibarSession,
            coordinatorHasSubmittedPrompt: coordinator.hasSubmittedPrompt,
            isAITabChatHeaderContainerHidden: viewCoordinator.aiChatTabChatHeaderContainer.isHidden,
            isNavigationChromeHidden: viewCoordinator.isNavigationChromeHidden
        )
        return MainViewController.decideRefreshAction(for: inputs)
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
        // flash visible during the FE's "Connecting…" window. One-shot intent — consume the
        // flag here so later refreshes (e.g. AI→AI navigation taking the preserve-current
        // path) don't re-hide the UTI after the FE has shown it.
        if tab.isVoiceModeRequested, coordinator.aiChatInputBoxVisibility != .hidden {
            coordinator.aiChatInputBoxVisibility = .hidden
        }
        tab.isVoiceModeRequested = false
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
                coordinator.restoreLastUsedReasoningMode(forChatID: chatID)
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
        // Snap chrome revealed — prior chat-scroll could have hidden bars under the AI header, so without this the omnibar flies in on return.
        chromeManager.reset(animated: false)
        if coordinator.isActive {
            coordinator.deactivateToOmnibar()
            coordinator.hide()
            coordinator.unbind()
        }
    }

    func setUpAIChatTabChatHeader() {
        let headerView = AIChatTabChatHeaderView(isFireModeEnabled: fireModeCapability.isFireModeEnabled)
        headerView.delegate = self
        headerView.translatesAutoresizingMaskIntoConstraints = false
        viewCoordinator.aiChatTabChatHeaderContainer.addSubview(headerView)
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: viewCoordinator.aiChatTabChatHeaderContainer.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: viewCoordinator.aiChatTabChatHeaderContainer.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: viewCoordinator.aiChatTabChatHeaderContainer.trailingAnchor),
            headerView.bottomAnchor.constraint(equalTo: viewCoordinator.aiChatTabChatHeaderContainer.bottomAnchor),
        ])
        headerView.setTabIconState(
            count: tabManager.currentTabsModel.count,
            hasUnread: tabManager.currentTabsModel.hasUnread,
            isFireMode: tabManager.currentBrowsingMode == .fire
        )
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
                if let tab = self.tabManager.currentTabsModel.currentTab, tab.link == nil {
                    self.ntpAfterIdleInstrumentation.backButtonUsedFromNTP(afterIdle: tab.openedAfterIdle)
                }
                self.postIdleSessionInstrumentation.backPressed()
                self.dismissUnifiedToggleInputOmnibarSession(coordinator: coordinator)
            } else if coordinator.isAITabExpanded {
                coordinator.showCollapsed()
            }
        }
        contentVC.onSwipeDownRequested = { [weak self] in
            guard let self, let coordinator = self.unifiedToggleInputCoordinator else { return }
            coordinator.dismissOmnibarKeyboard()
        }

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
        // In phone landscape the return key moves into the tools toolbar (between the model
        // chip and submit) so it clears the Dynamic Island; otherwise it floats above the UTI.
        let useInlineToolbarReturnKey = renderState.isFloatingReturnKeyVisible && isPhoneLandscape
        let showFloating = renderState.isFloatingReturnKeyVisible && !isPhoneLandscape
        updateFloatingReturnKeyAnchor(aboveUnifiedInput: showFloating && renderState.cardPosition == .bottom)
        coordinator.floatingReturnKeyViewController.view.isHidden = !showFloating
        coordinator.viewController.isToolbarReturnKeyHidden = !useInlineToolbarReturnKey
    }

    var isPhoneLandscape: Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
        return view.window?.windowScene?.interfaceOrientation.isLandscape ?? false
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

extension MainViewController {

    func dismissUnifiedToggleInputToOmnibar(coordinator: UnifiedToggleInputCoordinator,
                                            completion: (() -> Void)? = nil) {
        applyUnifiedInputChromeBackground(.standardChrome)
        // Resign up-front so the keyboard descent runs concurrent with the bar collapse.
        coordinator.viewController.deactivateInput()
        let omnibarPlaceholderWindowX = currentOmnibarPlaceholderWindowX()
        let omnibarPlaceholderColor = currentOmnibarPlaceholderColor()
        let utiPlaceholderColor = coordinator.viewController.defaultPlaceholderColor
        let duration = Constants.omnibarTransitionDuration(isBottom: coordinator.cardPosition.isBottom)

        // Pick the NTP handoff from the host's current content + the NTP's *resting* content (the NTP's
        // `isShowing*` is unreliable here — the focus handoff hid one for the session). logo→logo morphs
        // to the Dax mark, favorites→favorites hands the embedded copy over, everything else fades.
        let isLogoToLogo = coordinator.contentViewController.isShowingLogoContent
            && newTabPageViewController?.restingContentIsLogo == true
        let isFavoritesToFavorites = coordinator.contentViewController.isShowingFavoritesContent
            && newTabPageViewController?.restingContentIsFavorites == true

        if isLogoToLogo {
            newTabPageViewController?.setLogoHidden(true)
            coordinator.contentViewController.morphLogoHomeForDismiss(matching: duration)
        } else if isFavoritesToFavorites {
            newTabPageViewController?.setFavoritesHidden(true)
        } else {
            coordinator.contentViewController.beginDismissFade()
        }

        viewCoordinator.prepareOmnibarForInlineDismissReveal()
        let revealBarView = viewCoordinator.omniBar?.barView

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: .curveEaseOut,
            animations: { [weak self] in
                guard let self else { return }
                coordinator.viewController.applyOmnibarEditingDismissPose()
                self.viewCoordinator.animateUnifiedToggleInputOmnibarDismissLayout()
                // Mirror the focus path: settle the collapsed bar layout first so `pushContentInsets`
                // reads the *target* (collapsed) height, then push insets so the favorites/hatch
                // animate with the collapse instead of snapping.
                self.viewCoordinator.superview.layoutIfNeeded()
                coordinator.pushContentInsets()
                // (Favorites case no longer fades the container — the embedded favorites stay visible
                // and animate; the real NTP favorites, hidden above, are revealed at completion.)
                if let omnibarPlaceholderWindowX {
                    coordinator.viewController.alignVisibleTextLeadingEdge(toWindowX: omnibarPlaceholderWindowX)
                }
            },
            completion: { [weak self] _ in
                guard let self, let coordinator = self.unifiedToggleInputCoordinator else { return }
                // Reveal the NTP Logo and force a layout pass before hiding the UTI
                // content container, so the NTP Logo is rendered in the same frame
                // and there's no one-frame gap where neither logo is visible.
                self.newTabPageViewController?.setLogoHidden(false)
                self.newTabPageViewController?.setFavoritesHidden(false)
                self.newTabPageViewController?.view.setNeedsLayout()
                self.newTabPageViewController?.view.layoutIfNeeded()
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

        // Snap alpha to 0 outside the surrounding dismiss animate so the fade animator captures
        // `from = 0`. Without `performWithoutAnimation`, the alpha set would interpolate with
        // the dismiss transaction and the icons would briefly become visible mid-collapse.
        UIView.performWithoutAnimation {
            revealBarView?.setIconContainersAlpha(0)
        }
        UIView.animate(
            withDuration: duration * Constants.omnibarIconFadeInDurationMultiplier,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction],
            animations: { revealBarView?.setIconContainersAlpha(1) }
        )
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

    func focusUnifiedToggleInputForActiveChat(from webView: WKWebView) {
        guard let controller = tabManager.controller(forWebView: webView),
              controller === currentTab,
              let coordinator = unifiedToggleInputCoordinator,
              coordinator.isAITabState else { return }
        coordinator.showExpanded(inputMode: .aiChat)
    }

    func handleUnifiedToggleInputSearchSubmission(_ query: String) {
        fireDirectDuckAINavigationPixelIfNeeded(for: query)
        if let tab = tabManager.currentTabsModel.currentTab, tab.link == nil {
            ntpAfterIdleInstrumentation.barUsedFromNTP(afterIdle: tab.openedAfterIdle)
        }
        postIdleSessionInstrumentation.sessionEnded(reason: .barUsed)
        loadQuery(query)
    }

    /// Fires when Duck.ai is disabled under AI Features settings yet the user still reaches Duck.ai by
    /// typing its address into the UTI. Counts those direct navigations to gauge residual Duck.ai
    /// demand among users who have turned it off. (Disabling Duck.ai also forces the Search↔Duck.ai
    /// toggle off, so the `isAIChatEnabled` check is sufficient.) Mirrors `loadQuery`'s URL resolution
    /// so detection matches what actually gets navigated.
    private func fireDirectDuckAINavigationPixelIfNeeded(for query: String) {
        guard !aiChatSettings.isAIChatEnabled,
              let url = URL.makeSearchURL(query: query,
                                          useUnifiedLogic: isUnifiedURLPredictionEnabled,
                                          queryContext: currentTab?.url),
              url.isDuckAIURL else { return }
        DailyPixel.fireDailyAndCount(pixel: .unifiedToggleInputDuckAIDirectNavigation)
    }

}

// MARK: - UnifiedToggleInputOmnibarActivating

extension MainViewController: UnifiedToggleInputOmnibarActivating {

    func activateFromOmnibarIfNeeded(currentText: String?, tapped: Bool, textEntryMode: TextEntryMode?) -> UnifiedToggleInputActivationDecision {
        guard let coordinator = unifiedToggleInputCoordinator,
              currentTab?.isAITab != true else {
            return .allowDefault
        }
        if tapped {
            onExperimentalAddressBarTapped()
        }
        let position: UnifiedToggleInputCardPosition = appSettings.currentAddressBarPosition == .bottom ? .bottom : .top
        let inputMode = textEntryMode
            ?? tabManager.currentTabsModel.currentTab.map { initialOmnibarToggleMode(for: $0) }
            ?? .search
        coordinator.updateInputMode(inputMode, animated: false)
        let isToggleEnabled = isAIChatSearchInputToggleEnabledForCurrentOnboardingState()
        coordinator.updateToggleEnabled(isToggleEnabled)
        coordinator.activateFromOmnibar(prefilledText: currentText, inputMode: inputMode, cardPosition: position)
        return .intercept
    }
}

// MARK: - UnifiedToggleInputDelegate

extension MainViewController: UnifiedToggleInputDelegate {

    func unifiedToggleInputDidCommitMode(_ mode: TextEntryMode) {
        // No per-tab persistence: existing tabs read from URL; new tabs read from setting + app-wide last-used.
        // The app-wide last-used is written through `UnifiedInputStateStore.commitToggleMode` on submit, which fires this delegate.
    }

    func unifiedToggleInputDidSubmitPrompt(_ prompt: String, modelId: String?, tools: [AIChatRAGTool]?, reasoningEffort: AIChatReasoningEffort?, images: [AIChatNativePrompt.NativePromptImage]?, files: [AIChatNativePrompt.NativePromptFile]?) {
        // Match omnibar toggle: URL-shaped submissions from non-Duck.ai origin load the URL even when toggle is Duck.ai. Attachments suppress (no sensible URL-load with attachments).
        // On a Duck.ai tab, keep prompt semantics so users can ask the model about a URL by name.
        if currentTab?.isAITab != true,
           images?.isEmpty ?? true, files?.isEmpty ?? true,
           let url = URL(trimmedAddressBarString: prompt, useUnifiedLogic: isUnifiedURLPredictionEnabled),
           url.isValid(usingUnifiedLogic: isUnifiedURLPredictionEnabled) {
            unifiedToggleInputCoordinator?.recordDuckAIPromptInterpretedAsURL()
            loadUrlRespectingAIBoundary(url)
            return
        }
        openAIChat(prompt, autoSend: true, tools: tools, modelId: modelId, reasoningEffort: reasoningEffort, images: images, files: files)
    }

    func unifiedToggleInputDidSubmitQuery(_ query: String) {
        handleUnifiedToggleInputSearchSubmission(query)
    }

    func unifiedToggleInputDidTapClearText() {
        onExperimentalAddressBarClearPressed()
    }

    func unifiedToggleInputDidTapToActivate() {
        onExperimentalAddressBarTapped()
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
        // On a Duck.ai tab, route through openAIChat so the "new tab when current has content" rule applies.
        // This opens the chip handoff in a fresh chat tab and avoids the contextual-sheet branch in onAIChatPressed.
        if currentTab?.isAITab == true {
            if trimmed.isEmpty {
                openAIChat()
            } else {
                openAIChat(trimmed, autoSend: true)
            }
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

    func unifiedToggleInputDidRequestAppMenu() {
        onMenuPressed()
    }

    func unifiedToggleInputDismissSnapshot() -> UTIDismissSnapshot {
        let tab = tabManager.currentTabsModel.currentTab
        // AI tab reuses the same textView for the flanked input — populating it with the URL
        // would bleed past the collapse, so match the AI chrome (empty + aiChat placeholder).
        if tab?.isAITab == true {
            return UTIDismissSnapshot(text: "", placeholderMode: .aiChat)
        }
        return UTIDismissSnapshot(
            text: AddressDisplayHelper.plainDisplayString(for: tab?.link?.url),
            placeholderMode: preferredTextEntryModeForCurrentTab() ?? .search
        )
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

    func unifiedInputEditingStateDidRequestTextUpdate(_ text: String) {
        unifiedToggleInputCoordinator?.setText(text)
    }

    func unifiedInputEditingStateDidSelectChatHistory(url: URL) {
        onChatHistorySelected(url: url)
    }

    func unifiedInputEditingStateDidSelectViewAllChats() {
        openAIChatHistory(source: .addressBar)
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
        // Route through the same path as a toggle tap so the toggle indicator, content swap, and
        // input-height all animate together in one transaction (a swipe is a user-driven switch).
        unifiedToggleInputCoordinator?.updateInputMode(mode, animated: true)
    }

    func unifiedInputEditingStateDidRequestSyncSetup() {
        unifiedToggleInputCoordinator?.contentViewController.dismissAnimated()
        segueToSettingsSync(with: SyncSettingsViewController.SourceConstants.aiChatPromotion)
    }
}

// MARK: - AIChatTabChatHeaderViewDelegate

extension MainViewController: AIChatTabChatHeaderViewDelegate {

    func aiChatTabChatHeaderDidTapChatList() {
        DailyPixel.fireDailyAndCount(pixel: .aiChatOmnibarSidebarButtonTapped)
        unifiedToggleInputCoordinator?.showCollapsed()
        currentTab?.submitToggleSidebarAction()
    }

    func aiChatTabChatHeaderDidTapUpgrade() {
        if let subscriptionState = unifiedToggleInputCoordinator?.subscriptionState, !subscriptionState.hasActiveSubscription {
            Pixel.fire(pixel: .unifiedToggleInputChatHeaderUpgradeTapped)
        }
        NotificationCenter.default.post(
            name: .settingsDeepLinkNotification,
            object: SettingsViewModel.SettingsDeepLinkSection.subscriptionFlow()
        )
    }

    /// Close the chat tab. Selection follows the tab-switcher rule; chat is recoverable via Duck.ai → Recent chats.
    func aiChatTabChatHeaderDidTapClose() {
        guard let tab = currentTab?.tabModel else {
            // The X is only visible from a Duck.ai tab header, which is only attached when a
            // current tab exists — nil here means the header outlived its tab. Surface it.
            assertionFailure("aiChatTabChatHeaderDidTapClose fired with no currentTab")
            newTab(reuseExisting: true, allowingKeyboard: true)
            return
        }
        // Snapshot the chat tab view before swapping tabs and fade it out on top of the
        // destination so chrome + content transition feels gradual instead of an instant pop.
        let snapshot = view.snapshotView(afterScreenUpdates: false)
        if let snapshot {
            snapshot.isUserInteractionEnabled = false
            snapshot.frame = view.bounds
            snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(snapshot)
        }
        closeTab(tab, behavior: .onlyClose)
        guard let snapshot else { return }
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut], animations: {
            snapshot.alpha = 0
        }, completion: { _ in
            snapshot.removeFromSuperview()
        })
    }

    func aiChatTabChatHeaderDidTapNewChat() {
        unifiedToggleInputCoordinator?.startNewChat()
        unifiedToggleInputCoordinator?.showExpanded(inputMode: .aiChat)
        currentTab?.submitStartChatAction()
    }

    func aiChatTabChatHeaderDidTapNewVoiceChat() {
        onDuckAIVoiceModeRequested()
    }

    func aiChatTabChatHeaderDidTapNewTab() {
        newTab(reuseExisting: false, allowingKeyboard: false)
    }

    /// Force-search NTP. Override mode without committing — preserved toggle preference must survive.
    func aiChatTabChatHeaderDidTapNewSearch() {
        newTab(reuseExisting: false, allowingKeyboard: true)
        unifiedToggleInputCoordinator?.syncInputModeFromExternalSource(.search)
    }

    func aiChatTabChatHeaderDidTapNewFireTab() {
        tabManager.setBrowsingMode(.fire, source: .aiChatHeaderPlusMenu)
        newTab(reuseExisting: false, allowingKeyboard: true)
    }

    func aiChatTabChatHeaderDidTapTabSwitcher() {
        // Via `requestTabSwitcher()` not `showTabSwitcher()` — fires the same pixels as every other entry point.
        requestTabSwitcher()
    }
}

// MARK: - UnifiedToggleInputFloatingReturnKeyDelegate

extension MainViewController: UnifiedToggleInputFloatingReturnKeyDelegate {

    func floatingReturnKeyDidTap() {
        guard let coordinator = unifiedToggleInputCoordinator else { return }
        coordinator.insertNewlineFromFloatingReturnKey()
    }

}
