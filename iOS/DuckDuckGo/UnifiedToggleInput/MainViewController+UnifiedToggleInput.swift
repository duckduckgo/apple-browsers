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

    func setUpUnifiedToggleInputIfNeeded() {
        guard unifiedToggleInputFeature.isAvailable else { return }

        let coordinator = UnifiedToggleInputCoordinator(isToggleEnabled: aiChatSettings.isAIChatSearchInputUserSettingsEnabled)
        coordinator.delegate = self
        coordinator.updateVoiceSearchAvailability(voiceSearchHelper.isVoiceSearchEnabled)
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

    private func installUnifiedToggleInputViewController(_ inputVC: UnifiedToggleInputViewController) {
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

    private func subscribeToIntentPublisher(_ coordinator: UnifiedToggleInputCoordinator) {
        coordinator.intentPublisher
            .sink { [weak self] intent in
                self?.handleUnifiedToggleInputIntent(intent)
            }
            .store(in: &unifiedToggleInputCancellables)
    }

    private func subscribeToModeChanges(_ coordinator: UnifiedToggleInputCoordinator) {
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

    private func handleModeChange(_ mode: TextEntryMode) {
        guard let coordinator = unifiedToggleInputCoordinator else { return }
        if coordinator.isOmnibarSession {
            handleOmnibarModeChange(mode, coordinator: coordinator)
        } else if coordinator.isAITabExpanded {
            handleAITabModeChange(mode, coordinator: coordinator)
        } else if coordinator.isAITabState && mode == .aiChat {
            coordinator.showExpanded(inputMode: .aiChat)
        }
    }

    private func handleOmnibarModeChange(_ mode: TextEntryMode, coordinator: UnifiedToggleInputCoordinator) {
        updateUnifiedInputContentVisibility(for: coordinator)
        adjustUI(withKeyboardFrame: latestKeyboardFrame, in: 0.2, animationCurve: .curveEaseInOut)
        unifiedToggleInputCoordinator?.syncContentInputMode(mode)
        updateFloatingSubmitVisibility()
    }

    private func handleAITabModeChange(_: TextEntryMode, coordinator: UnifiedToggleInputCoordinator) {
        UIView.performWithoutAnimation {
            updateUnifiedInputContentVisibility(for: coordinator)
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

    func updateUnifiedToggleInputKeyboardVisibility(_ keyboardVisible: Bool) {
        unifiedToggleInputCoordinator?.updateOmnibarInputVisibility(keyboardVisible)
    }

    private func subscribeToSystemEvents() {
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

    private func subscribeToToggleSettings() {
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

    func refreshUnifiedToggleInput(for tab: TabViewController) {
        guard unifiedToggleInputFeature.isAvailable,
              let coordinator = unifiedToggleInputCoordinator else { return }

        if !tab.isAITab && !coordinator.isActive &&
            viewCoordinator.aiChatTabChatHeaderContainer.isHidden {
            coordinator.unbind()
            viewCoordinator.moveAddressBarToPosition(appSettings.currentAddressBarPosition)
            refreshViewsBasedOnAddressBarPosition(appSettings.currentAddressBarPosition)
            tab.updateWebViewBottomAnchor(for: viewCoordinator.toolbar.alpha)
            return
        }

        if tab.isAITab {
            viewCoordinator.statusBackground.backgroundColor = UIColor(singleUseColor: .duckAIContextualSheetBackground)
            let hadSubmittedPrompt = coordinator.hasSubmittedPrompt
            if let userScript = tab.userScripts?.aiChatUserScript {
                let hasExistingChat = tab.url?.duckAIChatID != nil
                coordinator.bindToTab(userScript, hasExistingChat: hasExistingChat)
            }
            if coordinator.isAITabState && viewCoordinator.isNavigationChromeHidden {
                return
            }
            if viewCoordinator.navigationBarContainer.alpha < 0.99 ||
                viewCoordinator.toolbar.alpha < 0.99 ||
                viewCoordinator.tabBarContainer.alpha < 0.99 {
                showBars()
            }
            tab.webView.scrollView.contentInset = .zero
            coordinator.deactivateToOmnibar()
            viewCoordinator.showAITabChrome()
            if !coordinator.isAITabState {
                let hasExistingChat = tab.url?.duckAIChatID != nil
                coordinator.showCollapsed()
                if !hasExistingChat && !hadSubmittedPrompt {
                    DispatchQueue.main.async { [weak coordinator] in
                        guard let coordinator, coordinator.isAITabState else { return }
                        coordinator.showExpanded(inputMode: .aiChat)
                    }
                }
            }
            updateUnifiedInputContentVisibility(for: coordinator)
            refreshAIChatTabChatHeaderSubscriptionState()
            tab.borderView.isTopVisible = false
            tab.borderView.isBottomVisible = false
        } else {
            coordinator.deactivateToOmnibar()
            coordinator.hide()
            coordinator.unbind()
            viewCoordinator.hideAITabChrome()
            viewCoordinator.moveAddressBarToPosition(appSettings.currentAddressBarPosition)
            refreshViewsBasedOnAddressBarPosition(appSettings.currentAddressBarPosition)
            refreshStatusBarBackgroundAfterAIChrome()
            tab.borderView.updateForAddressBarPosition(appSettings.currentAddressBarPosition)
            tab.borderView.isBottomVisible = true
        }

        tab.updateWebViewBottomAnchor(for: viewCoordinator.toolbar.alpha)
    }

    private func setUpAIChatTabChatHeader() {
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

    private func refreshAIChatTabChatHeaderSubscriptionState() {
        Task { @MainActor [weak self] in
            let isActive = (try? await AppDependencyProvider.shared.subscriptionManager.isFeatureEnabled(.paidAIChat)) ?? false
            self?.aiChatTabChatHeaderView?.configure(isSubscriptionActive: isActive)
        }
    }

    private func updateUnifiedInputContentVisibility(for coordinator: UnifiedToggleInputCoordinator) {
        let isOnAITab = currentTab?.isAITab == true
        let renderState = coordinator.computeRenderState(isOnAITab: isOnAITab)
        if coordinator.isAITabState {
            coordinator.contentViewController.forceBottomBarLayout = true
        } else {
            coordinator.contentViewController.forceBottomBarLayout = false
        }

        applyTopChromeState(renderState: renderState, isOnAITab: isOnAITab, coordinator: coordinator)
    }

    private func applyTopChromeState(renderState: UTIRenderState, isOnAITab: Bool, coordinator: UnifiedToggleInputCoordinator) {
        let overlaysHeader = isOnAITab
            && renderState.isExpanded
            && renderState.isContentVisible
            && renderState.headerDisplayMode != .hidden
        let targetStatusBackgroundColor: UIColor? = {
            guard isOnAITab else { return nil }
            if overlaysHeader {
                return UIColor(designSystemColor: .panel)
            }
            if viewCoordinator.isNavigationChromeHidden {
                return UIColor(singleUseColor: .duckAIContextualSheetBackground)
            }
            return nil
        }()

        if let targetStatusBackgroundColor {
            viewCoordinator.statusBackground.backgroundColor = targetStatusBackgroundColor
        }

        if coordinator.isAITabState {
            coordinator.applyContentHeaderFromRenderState(isOnAITab: isOnAITab)
            viewCoordinator.updateUnifiedToggleInputColors(
                isExpanded: renderState.isExpanded,
                inputView: coordinator.viewController.view
            )
        } else {
            viewCoordinator.updateUnifiedToggleInputColors(
                isExpanded: renderState.isExpanded,
                inputView: coordinator.viewController.view
            )
        }

        if renderState.isContentVisible {
            coordinator.syncContentInputMode(renderState.contentInputMode, animated: false)
            viewCoordinator.showUnifiedInputContent()
        } else {
            viewCoordinator.hideUnifiedInputContent()
        }

        if isOnAITab {
            if overlaysHeader {
                viewCoordinator.hideAIChatTabChatHeader()
            } else {
                viewCoordinator.showAIChatTabChatHeader()
            }
            /// Guard: layoutIfNeeded on view crashes during cold launch before the view is in a window
            if viewIfLoaded?.window != nil {
                view.layoutIfNeeded()
            }
        }
    }

    private func installUnifiedInputContentViewController() {
        guard let coordinator = unifiedToggleInputCoordinator,
              let container = viewCoordinator.unifiedInputContentContainer else { return }

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

    private func installFloatingSubmitViewController() {
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

    private func updateFloatingSubmitVisibility() {
        guard let coordinator = unifiedToggleInputCoordinator else { return }
        let renderState = coordinator.computeRenderState()
        coordinator.floatingSubmitViewController.view.isHidden = !renderState.isFloatingSubmitVisible
    }

    private func handleUnifiedToggleInputIntent(_ intent: UnifiedToggleInputIntent) {
        switch intent {
        case .showCollapsed:
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
                updateUnifiedInputContentVisibility(for: coordinator)
            }
            adjustUI(withKeyboardFrame: latestKeyboardFrame, in: 0, animationCurve: .curveEaseInOut)
        case .showOmnibarEditing(let height):
            viewCoordinator.showUnifiedToggleInputOmnibar(expandedHeight: height)
            viewCoordinator.suggestionTrayContainer.isHidden = true
            let isTopPosition = unifiedToggleInputCoordinator?.cardPosition == .top
            if let coordinator = unifiedToggleInputCoordinator {
                updateUnifiedInputContentVisibility(for: coordinator)
                if isTopPosition && coordinator.isToggleEnabled {
                    let targetHeight = coordinator.pendingExpandedHeight
                    coordinator.pendingExpandedHeight = nil
                    self.viewCoordinator.unifiedInputContentContainer.alpha = 0
                    coordinator.animateOmnibarExpansion { [weak self] in
                        guard let self else { return }
                        if let targetHeight {
                            self.viewCoordinator.constraints.navigationBarContainerHeight.constant = targetHeight
                            self.viewCoordinator.superview.layoutIfNeeded()
                        }
                        self.viewCoordinator.unifiedInputContentContainer.alpha = 1
                    }
                } else if isTopPosition {
                    self.viewCoordinator.unifiedInputContentContainer.alpha = 0
                    coordinator.viewController.animateDismissReveal(additionalAnimations: { [weak self] in
                        self?.viewCoordinator.unifiedInputContentContainer.alpha = 1
                    })
                }
            }
        case .showOmnibarInactive:
            viewCoordinator.restoreNavBarToToolbarForOmnibarInactive()
            recomputeOmnibarEditingHeightIfNeeded()
        case .showOmnibarActive:
            viewCoordinator.restoreNavBarToToolbarForOmnibarInactive()
            recomputeOmnibarEditingHeightIfNeeded()
        case .hideOmnibarEditing:
            viewCoordinator.hideUnifiedToggleInputOmnibar()
            viewCoordinator.hideUnifiedInputContent()
            hideSuggestionTray()
            viewCoordinator.suggestionTrayContainer.backgroundColor = .clear
            viewCoordinator.suggestionTrayContainer.isHidden = false
        case .hide:
            unifiedToggleInputCoordinator?.viewController.view.backgroundColor = .clear
            viewCoordinator.hideUnifiedToggleInput()
            viewCoordinator.hideUnifiedInputContent()
            hideSuggestionTray()
            viewCoordinator.suggestionTrayContainer.isHidden = false
        }
        updateFloatingSubmitVisibility()
    }

    func recomputeOmnibarEditingHeightIfNeeded() {
        guard let coordinator = unifiedToggleInputCoordinator,
              coordinator.isOmnibarSession else { return }
        let height = coordinator.omnibarEditingHeight()
        viewCoordinator.constraints.navigationBarContainerHeight.constant = height
    }

    private func dismissUnifiedToggleInputToOmnibar(coordinator: UnifiedToggleInputCoordinator) {
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
                coordinator.deactivateToOmnibarWithoutViewReset()
            })
        } else if isTopPosition {
            coordinator.viewController.animateDismissHide(additionalAnimations: { [weak self] in
                self?.viewCoordinator.unifiedInputContentContainer.alpha = 0
            }, completion: { [weak self] in
                guard let self, let coordinator = self.unifiedToggleInputCoordinator else { return }
                self.viewCoordinator.unifiedInputContentContainer.isHidden = true
                self.viewCoordinator.unifiedInputContentContainer.alpha = 1
                coordinator.deactivateToOmnibarWithoutViewReset()
            })
        } else {
            coordinator.deactivateToOmnibar()
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
        coordinator.activateFromOmnibar(prefilledText: currentText, inputMode: .search, cardPosition: position)
        return .intercept
    }
}

// MARK: - UnifiedToggleInputDelegate

extension MainViewController: UnifiedToggleInputDelegate {

    func unifiedToggleInputDidSubmitPrompt(_ prompt: String, modelId: String?, images: [AIChatNativePrompt.NativePromptImage]?) {
        openAIChat(prompt, autoSend: true, modelId: modelId, images: images)
    }

    func unifiedToggleInputDidSubmitQuery(_ query: String) {
        handleUnifiedToggleInputSearchSubmission(query)
    }

    func unifiedToggleInputDidRequestVoiceSearch() {
        let mode = unifiedToggleInputCoordinator?.inputMode ?? .search
        handleVoiceSearchOpenRequest(preferredTarget: mode == .aiChat ? .AIChat : .SERP)
    }
}

// MARK: - UnifiedInputContentContainerViewControllerDelegate

extension MainViewController: UnifiedInputContentContainerViewControllerDelegate {

    func unifiedInputEditingStateDidSubmitQuery(_ query: String) {
        unifiedToggleInputCoordinator?.clearText()
        unifiedToggleInputCoordinator?.handleExternalQuerySubmission()
        handleUnifiedToggleInputSearchSubmission(query)
    }

    func unifiedInputEditingStateDidSubmitPrompt(_ query: String, tools: [AIChatRAGTool]?) {
        unifiedToggleInputCoordinator?.clearText()
        unifiedToggleInputCoordinator?.handleExternalPromptSubmission()
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

    func unifiedInputEditingStateDidChangeMode(_ mode: TextEntryMode) {
        unifiedToggleInputCoordinator?.syncInputModeFromExternalSource(mode)
    }
}

private extension MainViewController {
    func handleUnifiedToggleInputSearchSubmission(_ query: String) {
        if currentTab?.isAITab == true {
            viewCoordinator.hideAITabChrome()
            refreshStatusBarBackgroundAfterAIChrome()
        }
        loadQuery(query)
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
        // Voice search wiring deferred
    }
}
