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

// MARK: - Unified Toggle Input Setup

extension MainViewController {

    enum UnifiedInputChromeBackgroundState: String {
        case standardChrome
        case aiTabSearchChromeHidden
        case aiTabChatChromeHidden
    }

    func setUpUnifiedToggleInputIfNeeded() {
        guard unifiedToggleInputFeature.isAvailable else { return }

        let coordinator = UnifiedToggleInputCoordinator(isToggleEnabled: aiChatSettings.isAIChatSearchInputUserSettingsEnabled)
        coordinator.delegate = self
        coordinator.updateVoiceSearchAvailability(voiceSearchHelper.isVoiceSearchEnabled)
        coordinator.updateAIVoiceChatAvailability(voiceShortcutFeature.isAvailable)
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

    func refreshUnifiedToggleInput(for tab: TabViewController) {
        guard unifiedToggleInputFeature.isAvailable,
              let coordinator = unifiedToggleInputCoordinator else {
            return
        }

        let action = refreshAction(for: tab, coordinator: coordinator)

        switch action {
        case .unbindInactiveNonAITab:
            refreshInactiveNonAITab(tab: tab, coordinator: coordinator)
            tab.updateWebViewBottomAnchor(for: viewCoordinator.toolbar.alpha)
            return
        case .refreshAITab(let behavior):
            let completedRefresh = refreshAITab(tab: tab, coordinator: coordinator, behavior: behavior)
            if !completedRefresh {
                return
            }
        case .refreshNonAITab:
            refreshNonAITab(tab: tab, coordinator: coordinator)
        }

        tab.updateWebViewBottomAnchor(for: viewCoordinator.toolbar.alpha)
    }

    func applyUnifiedInputChromeBackground(_ state: UnifiedInputChromeBackgroundState, updateWebView: Bool = true) {

        let statusBackgroundPresentation: MainViewCoordinator.StatusBackgroundPresentation
        let containerBackgroundColor: UIColor?
        let webViewBackgroundColor: UIColor?

        switch state {
        case .standardChrome:
            statusBackgroundPresentation = .standard
            containerBackgroundColor = nil
            webViewBackgroundColor = nil
        case .aiTabSearchChromeHidden:
            statusBackgroundPresentation = .aiTabSearchChromeHidden
            containerBackgroundColor = .clear
            webViewBackgroundColor = .clear
        case .aiTabChatChromeHidden:
            statusBackgroundPresentation = .aiTabChatChromeHidden
            containerBackgroundColor = .clear
            webViewBackgroundColor = .clear
        }

        viewCoordinator.setStatusBackgroundPresentation(statusBackgroundPresentation)
        if case .standardChrome = state {
            refreshStatusBarBackgroundAfterAIChrome()
        }

        viewCoordinator.navigationBarContainer.backgroundColor = containerBackgroundColor
        viewCoordinator.unifiedInputContentContainer?.backgroundColor = containerBackgroundColor ?? .clear
        viewCoordinator.unifiedToggleInputContainer.backgroundColor = .clear
        unifiedToggleInputCoordinator?.viewController.view.backgroundColor = .clear

        guard updateWebView else { return }
        if let webView = currentTab?.webView {
            webView.backgroundColor = webViewBackgroundColor
            webView.scrollView.backgroundColor = webViewBackgroundColor
            webView.underPageBackgroundColor = webViewBackgroundColor
        }
    }

    func recomputeOmnibarEditingHeightIfNeeded() {
        guard let coordinator = unifiedToggleInputCoordinator,
              coordinator.isOmnibarSession else {
            return
        }
        let height = coordinator.omnibarEditingHeight()
        guard viewCoordinator.constraints.navigationBarContainerHeight.constant != height else { return }
        viewCoordinator.constraints.navigationBarContainerHeight.constant = height
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
                if coordinator.isAITabExpanded || coordinator.isOmnibarSession {
                    adjustUI(withKeyboardFrame: latestKeyboardFrame, in: 0.2, animationCurve: .curveEaseInOut)
                }
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
        adjustUI(withKeyboardFrame: latestKeyboardFrame, in: 0, animationCurve: .curveEaseInOut)

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

    }

    func subscribeToToggleSettings() {
        NotificationCenter.default.publisher(for: .aiChatSettingsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let coordinator = self.unifiedToggleInputCoordinator else { return }
                let enabled = self.aiChatSettings.isAIChatSearchInputUserSettingsEnabled
                coordinator.updateToggleEnabled(enabled)
                coordinator.contentViewController.isSwipeEnabled = enabled
            }
            .store(in: &unifiedToggleInputCancellables)
    }

    func refreshAction(for tab: TabViewController, coordinator: UnifiedToggleInputCoordinator) -> UnifiedToggleInputRefreshAction {
        if !tab.isAITab {
            if !coordinator.isActive && viewCoordinator.aiChatTabChatHeaderContainer.isHidden {
                return .unbindInactiveNonAITab
            }
            return .refreshNonAITab
        }

        if coordinator.isAITabState {
            return .refreshAITab(.preserveCurrentPresentation(allowsEarlyReturn: viewCoordinator.isNavigationChromeHidden))
        }

        let hasExistingChat = tab.url?.duckAIChatID != nil
        let tabURL = tab.url ?? tab.link?.url
        let isVoiceMode = tabURL?.isDuckAIVoiceMode == true || tab.isVoiceModeRequested
        tab.isVoiceModeRequested = false
        let shouldExpandAfterRefresh = !hasExistingChat && !coordinator.hasSubmittedPrompt && !isVoiceMode
        return .refreshAITab(.showCollapsed(expandAfterRefresh: shouldExpandAfterRefresh))
    }

    func refreshInactiveNonAITab(tab: TabViewController, coordinator: UnifiedToggleInputCoordinator) {
        coordinator.unbind()
        viewCoordinator.hideAITabChrome()
        applyUnifiedInputChromeBackground(.standardChrome)
        viewCoordinator.moveAddressBarToPosition(appSettings.currentAddressBarPosition)
        refreshViewsBasedOnAddressBarPosition(appSettings.currentAddressBarPosition)
    }

    func refreshAITab(
        tab: TabViewController,
        coordinator: UnifiedToggleInputCoordinator,
        behavior: AITabRefreshBehavior
    ) -> Bool {
        let hasExistingChat = tab.url?.duckAIChatID != nil
        bindAITabIfPossible(tab: tab, coordinator: coordinator, hasExistingChat: hasExistingChat)

        if case .preserveCurrentPresentation(let allowsEarlyReturn) = behavior, allowsEarlyReturn {
            syncPreservedAITabPresentation(coordinator: coordinator)
            return false
        }

        ensureStandardChromeVisibleForAITabRefresh()
        tab.webView.scrollView.contentInset = .zero
        coordinator.deactivateToOmnibar()
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

    func aiTabChromeBackgroundState(for renderState: UTIRenderState) -> UnifiedInputChromeBackgroundState {
        renderState.isContentVisible ? .aiTabSearchChromeHidden : .aiTabChatChromeHidden
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
        coordinator.deactivateToOmnibar()
        coordinator.hide()
        coordinator.unbind()
        viewCoordinator.hideAITabChrome()
        viewCoordinator.moveAddressBarToPosition(appSettings.currentAddressBarPosition)
        refreshViewsBasedOnAddressBarPosition(appSettings.currentAddressBarPosition)
        applyUnifiedInputChromeBackground(.standardChrome)
        tab.borderView.updateForAddressBarPosition(appSettings.currentAddressBarPosition)
        tab.borderView.isBottomVisible = true
    }

    func setUpAIChatTabChatHeader() {
        let headerView = AIChatTabChatHeaderView()
        headerView.delegate = self
        headerView.translatesAutoresizingMaskIntoConstraints = false
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

    func updateUnifiedInputContentVisibility(for coordinator: UnifiedToggleInputCoordinator) {
        let isOnAITab = currentTab?.isAITab == true
        let renderState = coordinator.computeRenderState()
        if coordinator.isAITabState {
            coordinator.contentViewController.forceBottomBarLayout = true
        } else {
            coordinator.contentViewController.forceBottomBarLayout = false
        }

        applyTopChromeState(renderState: renderState, isOnAITab: isOnAITab, coordinator: coordinator)
    }

    func applyTopChromeState(renderState: UTIRenderState, isOnAITab: Bool, coordinator: UnifiedToggleInputCoordinator) {
        if isOnAITab, viewCoordinator.isNavigationChromeHidden {
            let chromeBackgroundState = aiTabChromeBackgroundState(for: renderState)
            applyUnifiedInputChromeBackground(chromeBackgroundState, updateWebView: false)
        }

        if coordinator.isAITabState {
            coordinator.applyDismissButtonVisibility()
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
                // Restore the tab's committed mode — the user toggled but didn't submit.
                if let tabMode = self.tabManager.currentTabsModel.currentTab?.preferredTextEntryMode {
                    coordinator.updateInputMode(tabMode, animated: false)
                }
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

    func handleUnifiedToggleInputIntent(_ intent: UnifiedToggleInputIntent) {
        switch intent {
        case .showCollapsed:
            if unifiedToggleInputCoordinator?.isAITabState == true {
                applyUnifiedInputChromeBackground(.aiTabChatChromeHidden)
                viewCoordinator.stopContentContainerBehindInput()
            }
            viewCoordinator.showUnifiedToggleInput()
            viewCoordinator.suggestionTrayContainer.isHidden = true
            if let coordinator = unifiedToggleInputCoordinator {
                updateUnifiedInputContentVisibility(for: coordinator)
            } else {
                viewCoordinator.hideUnifiedInputContent()
            }
        case .showExpanded:
            viewCoordinator.showUnifiedToggleInput()
            if let coordinator = unifiedToggleInputCoordinator {
                if coordinator.isAITabState {
                    let chromeBackgroundState = aiTabChromeBackgroundState(for: coordinator.computeRenderState())
                    applyUnifiedInputChromeBackground(chromeBackgroundState)
                    viewCoordinator.extendContentContainerBehindInput()
                }
                updateUnifiedInputContentVisibility(for: coordinator)
            }
            adjustUI(withKeyboardFrame: latestKeyboardFrame, in: 0, animationCurve: .curveEaseInOut)
        case .showOmnibarEditing(let height, let pendingHeight):
            viewCoordinator.showUnifiedToggleInputOmnibar(expandedHeight: height)
            viewCoordinator.suggestionTrayContainer.isHidden = true
            let isTopPosition = unifiedToggleInputCoordinator?.cardPosition == .top
            if let coordinator = unifiedToggleInputCoordinator {
                updateUnifiedInputContentVisibility(for: coordinator)
                if isTopPosition && coordinator.isToggleEnabled {
                    let targetHeight = pendingHeight
                    self.viewCoordinator.unifiedInputContentContainer.alpha = 0
                    coordinator.animateOmnibarExpansion { [weak self] in
                        guard let self else { return }
                        if let targetHeight {
                            self.viewCoordinator.constraints.navigationBarContainerHeight.constant = targetHeight
                            self.viewCoordinator.superview.layoutIfNeeded()
                        }
                        self.unifiedToggleInputCoordinator?.pushContentInsets()
                        self.viewCoordinator.unifiedInputContentContainer.alpha = 1
                    }
                } else if isTopPosition {
                    self.viewCoordinator.unifiedInputContentContainer.alpha = 0
                    UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) { [weak self] in
                        self?.viewCoordinator.unifiedInputContentContainer.alpha = 1
                    }
                }
            }
        case .showOmnibarInactive:
            applyBottomOmnibarVisibility(.inactive)
        case .showOmnibarActive:
            applyBottomOmnibarVisibility(.active)
        case .hideOmnibarEditing:
            viewCoordinator.hideUnifiedToggleInputOmnibar()
            unifiedToggleInputCoordinator?.contentViewController.setActive(false)
            viewCoordinator.hideUnifiedInputContent()
            unifiedToggleInputCoordinator?.contentViewController.setContentInset(top: 0, bottom: 0)
            hideSuggestionTray()
            viewCoordinator.suggestionTrayContainer.backgroundColor = .clear
            viewCoordinator.suggestionTrayContainer.isHidden = false
        case .hide:
            unifiedToggleInputCoordinator?.viewController.view.backgroundColor = .clear
            viewCoordinator.hideUnifiedToggleInput()
            unifiedToggleInputCoordinator?.contentViewController.setActive(false)
            viewCoordinator.hideUnifiedInputContent()
            unifiedToggleInputCoordinator?.contentViewController.setContentInset(top: 0, bottom: 0)
            hideSuggestionTray()
            viewCoordinator.suggestionTrayContainer.isHidden = false
        }
        updateFloatingSubmitVisibility()
    }

    func syncBottomOmnibarAnchorIfNeeded(for coordinator: UnifiedToggleInputCoordinator) {
        guard coordinator.cardPosition == .bottom,
              case .omnibar(let state) = coordinator.displayState,
              viewCoordinator.addressBarPosition.isBottom else {
            return
        }
        applyBottomOmnibarAnchor(state)
        viewCoordinator.navigationBarContainer.superview?.layoutIfNeeded()
    }

    func applyBottomOmnibarVisibility(_ state: UnifiedToggleInputDisplayState.OmnibarState) {
        guard let coordinator = unifiedToggleInputCoordinator,
              coordinator.cardPosition == .bottom,
              viewCoordinator.addressBarPosition.isBottom else {
            recomputeOmnibarEditingHeightIfNeeded()
            return
        }
        applyBottomOmnibarAnchor(state)
        viewCoordinator.navigationBarContainer.superview?.layoutIfNeeded()
        recomputeOmnibarEditingHeightIfNeeded()
    }

    func applyBottomOmnibarAnchor(_ state: UnifiedToggleInputDisplayState.OmnibarState) {
        switch state {
        case .active:
            viewCoordinator.restoreNavBarToKeyboardForOmnibarActive()
        case .inactive:
            viewCoordinator.restoreNavBarToToolbarForOmnibarInactive()
        }
    }

    func dismissUnifiedToggleInputToOmnibar(coordinator: UnifiedToggleInputCoordinator) {
        applyUnifiedInputChromeBackground(.standardChrome)
        let isTopPosition = coordinator.cardPosition == .top
        if isTopPosition && coordinator.isToggleEnabled {
            coordinator.viewController.animateToggleHide(additionalAnimations: { [weak self] in
                guard let self else { return }
                self.viewCoordinator.constraints.navigationBarContainerHeight.constant = self.viewCoordinator.standardNavigationBarContainerHeight
                self.viewCoordinator.superview.layoutIfNeeded()
                self.viewCoordinator.unifiedInputContentContainer.alpha = 0
            }, completion: { [weak self] in
                guard let self, let coordinator = self.unifiedToggleInputCoordinator else { return }
                self.viewCoordinator.unifiedInputContentContainer.isHidden = true
                self.viewCoordinator.unifiedInputContentContainer.alpha = 1
                coordinator.deactivateToOmnibar(resetView: false)
            })
        } else if isTopPosition {
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut, animations: { [weak self] in
                self?.viewCoordinator.unifiedInputContentContainer.alpha = 0
            }, completion: { [weak self] _ in
                guard let self, let coordinator = self.unifiedToggleInputCoordinator else { return }
                self.viewCoordinator.unifiedInputContentContainer.isHidden = true
                self.viewCoordinator.unifiedInputContentContainer.alpha = 1
                coordinator.deactivateToOmnibar(resetView: false)
            })
        } else {
            coordinator.deactivateToOmnibar()
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

    func commitUnifiedToggleStateToCurrentTab() {
        guard let mode = unifiedToggleInputCoordinator?.inputMode else { return }
        commitToggleMode(mode)
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
        let inputMode = tabManager.currentTabsModel.currentTab?.preferredTextEntryMode ?? .search
        coordinator.activateFromOmnibar(prefilledText: currentText, inputMode: inputMode, cardPosition: position)
        return .intercept
    }
}

// MARK: - UnifiedToggleInputDelegate

extension MainViewController: UnifiedToggleInputDelegate {

    func unifiedToggleInputDidSubmitPrompt(_ prompt: String, modelId: String?, images: [AIChatNativePrompt.NativePromptImage]?) {
        commitUnifiedToggleStateToCurrentTab()
        openAIChat(prompt, autoSend: true, modelId: modelId, images: images)
    }

    func unifiedToggleInputDidSubmitQuery(_ query: String) {
        commitUnifiedToggleStateToCurrentTab()
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

    func unifiedToggleInputDidChangeHeight() {
        if unifiedToggleInputCoordinator?.isOmnibarSession == true {
            recomputeOmnibarEditingHeightIfNeeded()
        } else {
            unifiedToggleInputCoordinator?.pushContentInsets()
        }
    }
}

// MARK: - UnifiedInputContentContainerViewControllerDelegate

extension MainViewController: UnifiedInputContentContainerViewControllerDelegate {

    func unifiedInputEditingStateDidSubmitQuery(_ query: String) {
        commitUnifiedToggleStateToCurrentTab()
        unifiedToggleInputCoordinator?.clearText()
        unifiedToggleInputCoordinator?.handleExternalSubmission(.query)
        handleUnifiedToggleInputSearchSubmission(query)
    }

    func unifiedInputEditingStateDidSubmitPrompt(_ query: String, tools: [AIChatRAGTool]?) {
        commitUnifiedToggleStateToCurrentTab()
        unifiedToggleInputCoordinator?.clearText()
        unifiedToggleInputCoordinator?.handleExternalSubmission(.prompt)
        openAIChat(query, autoSend: true, tools: tools)
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

    func unifiedInputEditingStateDidRequestFireMode() {
        unifiedToggleInputCoordinator?.contentViewController.dismissAnimated()
        navigateToFireMode()
    }

    func unifiedInputEditingStateDidChangeMode(_ mode: TextEntryMode) {
        unifiedToggleInputCoordinator?.syncInputModeFromExternalSource(mode)
    }
}

// MARK: - AIChatTabChatHeaderViewDelegate

extension MainViewController: AIChatTabChatHeaderViewDelegate {

    func aiChatTabChatHeaderDidTapSettings() {
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
