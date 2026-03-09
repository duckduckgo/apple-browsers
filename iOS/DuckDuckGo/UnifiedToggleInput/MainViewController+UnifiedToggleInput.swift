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
        self.unifiedToggleInputCoordinator = coordinator

        installUnifiedToggleInputViewController(coordinator.viewController)

        if let omniBarVC = viewCoordinator.omniBar as? DefaultOmniBarViewController {
            omniBarVC.unifiedToggleInputInlineActivating = self
        }

        setUpAIChatTabChatHeader()
        setUpUnifiedInputContentViewController()

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
            inputVC.view.bottomAnchor.constraint(equalTo: viewCoordinator.unifiedToggleInputContainer.bottomAnchor),
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
    }

    private func handleModeChange(_ mode: TextEntryMode) {
        guard let coordinator = unifiedToggleInputCoordinator else { return }
        if coordinator.isInlineEditingActive {
            handleInlineEditingModeChange(mode, coordinator: coordinator)
        } else if case .aiTab(.expanded) = coordinator.displayState {
            handleAITabModeChange(mode, coordinator: coordinator)
        }
    }

    private func handleInlineEditingModeChange(_ mode: TextEntryMode, coordinator: UnifiedToggleInputCoordinator) {
        let height = coordinator.inlineEditingHeight()
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.viewCoordinator.constraints.navigationBarContainerHeight.constant = height
            self.viewCoordinator.superview.layoutIfNeeded()
        }
        unifiedInputContentViewController?.setInputMode(mode)
    }

    private func handleAITabModeChange(_: TextEntryMode, coordinator: UnifiedToggleInputCoordinator) {
        updateUnifiedInputContentVisibility(for: coordinator)
        reconcileUnifiedToggleInputLayout(reason: .modeChange)
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
                guard let self, self.currentTab?.isAITab == true else { return }
                self.refreshAIChatTabChatHeaderSubscriptionState()
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
                self.unifiedInputContentViewController?.isSwipeEnabled = enabled
            }
            .store(in: &unifiedToggleInputCancellables)
    }

    func refreshUnifiedToggleInput(for tab: TabViewController) {
        guard unifiedToggleInputFeature.isAvailable,
              let coordinator = unifiedToggleInputCoordinator else { return }

        if !tab.isAITab && coordinator.displayState == .hidden &&
            viewCoordinator.aiChatTabChatHeaderContainer.isHidden {
            // Ensure stale AI tab bindings are always cleared when leaving AI pages,
            // even on the early-return path where no chrome transition is needed.
            coordinator.unbind()
            viewCoordinator.moveAddressBarToPosition(appSettings.currentAddressBarPosition)
            refreshViewsBasedOnAddressBarPosition(appSettings.currentAddressBarPosition)
            tab.updateWebViewBottomAnchor(for: viewCoordinator.toolbar.alpha)
            return
        }

        if tab.isAITab {
            if let userScript = tab.userScripts?.aiChatUserScript {
                coordinator.bindToTab(userScript)
            }
            if viewCoordinator.navigationBarContainer.alpha < 0.99 ||
                viewCoordinator.toolbar.alpha < 0.99 ||
                viewCoordinator.tabBarContainer.alpha < 0.99 {
                showBars()
            }
            tab.webView.scrollView.contentInset = .zero
            coordinator.deactivateInlineEditing()
            switch coordinator.displayState {
            case .aiTab: break
            default: coordinator.showCollapsed()
            }
            viewCoordinator.showAITabChrome()
            updateUnifiedInputContentVisibility(for: coordinator)
            reconcileUnifiedToggleInputLayout(reason: .aiTabRefresh)
            refreshAIChatTabChatHeaderSubscriptionState()
            tab.borderView.isTopVisible = false
            tab.borderView.isBottomVisible = false
        } else {
            coordinator.deactivateInlineEditing()
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

    private func shouldShowUnifiedInputContent(for coordinator: UnifiedToggleInputCoordinator) -> Bool {
        let isAITab = currentTab?.isAITab == true

        switch coordinator.displayState {
        case .hidden, .aiTab(.collapsed):
            return false
        case .inline:
            return true
        case .aiTab(.expanded):
            return !(isAITab && coordinator.inputMode == .aiChat)
        }
    }

    private func shouldOverlayAIChatHeader(for coordinator: UnifiedToggleInputCoordinator) -> Bool {
        guard currentTab?.isAITab == true else { return false }
        guard case .aiTab(.expanded) = coordinator.displayState else { return false }
        return coordinator.inputMode == .search && shouldShowUnifiedInputContent(for: coordinator)
    }

    private func updateAITabHeaderVisibility(for coordinator: UnifiedToggleInputCoordinator) {
        guard currentTab?.isAITab == true else { return }
        if shouldOverlayAIChatHeader(for: coordinator) {
            viewCoordinator.hideAIChatTabChatHeader()
        } else {
            viewCoordinator.showAIChatTabChatHeader()
        }
    }

    private func updateStatusBarBackgroundForAITabOverlay(for coordinator: UnifiedToggleInputCoordinator) {
        guard currentTab?.isAITab == true else { return }

        if shouldOverlayAIChatHeader(for: coordinator) {
            viewCoordinator.statusBackground.backgroundColor = UIColor(designSystemColor: .panel)
        } else if viewCoordinator.isNavigationChromeHidden {
            viewCoordinator.statusBackground.backgroundColor = UIColor(singleUseColor: .duckAIContextualSheetBackground)
        }
    }

    private func updateUnifiedInputContentVisibility(for coordinator: UnifiedToggleInputCoordinator) {
        updateAITabHeaderVisibility(for: coordinator)
        updateStatusBarBackgroundForAITabOverlay(for: coordinator)

        if case .aiTab = coordinator.displayState {
            let shouldShowInlineHeader = shouldOverlayAIChatHeader(for: coordinator)
            unifiedInputContentViewController?.setInlineHeaderDisplayMode(shouldShowInlineHeader ? .active : .hidden)
        }

        if shouldShowUnifiedInputContent(for: coordinator) {
            unifiedInputContentViewController?.setInputMode(coordinator.inputMode, animated: false)
            viewCoordinator.showUnifiedInputContent()
        } else {
            viewCoordinator.hideUnifiedInputContent()
        }
    }

    private func setUpUnifiedInputContentViewController() {
        guard let switchBarHandler = unifiedToggleInputCoordinator?.switchBarHandler else { return }

        let contentVC = UnifiedInputContentContainerViewController(switchBarHandler: switchBarHandler)
        contentVC.suggestionTrayDependencies = suggestionTrayDependencies
        contentVC.delegate = self
        contentVC.onDismissRequested = { [weak self] in
            guard let self, let coordinator = self.unifiedToggleInputCoordinator else { return }
            switch coordinator.displayState {
            case .inline:
                coordinator.deactivateInlineEditing()
            case .aiTab(.expanded):
                coordinator.showCollapsed()
            default:
                break
            }
        }
        contentVC.isSwipeEnabled = unifiedToggleInputCoordinator?.isToggleEnabled ?? true
        unifiedInputContentViewController = contentVC

        guard let container = viewCoordinator.unifiedInputContentContainer else { return }
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

    private func handleUnifiedToggleInputIntent(_ intent: UnifiedToggleInputIntent) {
        switch intent {
        case .showCollapsed:
            viewCoordinator.showUnifiedToggleInput()
            viewCoordinator.suggestionTrayContainer.isHidden = true
            if let coordinator = unifiedToggleInputCoordinator {
                updateUnifiedInputContentVisibility(for: coordinator)
            } else {
                viewCoordinator.hideUnifiedInputContent()
                unifiedInputContentViewController?.setInlineHeaderDisplayMode(.hidden)
            }
            reconcileUnifiedToggleInputLayout(reason: .intent)
        case .showExpanded:
            viewCoordinator.showUnifiedToggleInput()
            if let coordinator = unifiedToggleInputCoordinator {
                updateUnifiedInputContentVisibility(for: coordinator)
            }
            reconcileUnifiedToggleInputLayout(reason: .intent)
        case .showInlineEditing(let height):
            viewCoordinator.showUnifiedToggleInputInline(expandedHeight: height)
            viewCoordinator.suggestionTrayContainer.isHidden = true
            if let coordinator = unifiedToggleInputCoordinator {
                updateUnifiedInputContentVisibility(for: coordinator)
            }
            unifiedInputContentViewController?.setInlineHeaderDisplayMode(.active)
        case .hideInlineEditing:
            unifiedInputContentViewController?.setInlineHeaderDisplayMode(.hidden)
            viewCoordinator.hideUnifiedToggleInputInline()
            viewCoordinator.hideUnifiedInputContent()
            hideSuggestionTray()
            viewCoordinator.suggestionTrayContainer.isHidden = false
        case .hide:
            unifiedInputContentViewController?.setInlineHeaderDisplayMode(.hidden)
            viewCoordinator.hideUnifiedToggleInput()
            viewCoordinator.hideUnifiedInputContent()
            viewCoordinator.suggestionTrayContainer.isHidden = false
        }
    }

    func recomputeInlineEditingHeightIfNeeded() {
        guard let coordinator = unifiedToggleInputCoordinator,
              coordinator.isInlineEditingActive else { return }
        let height = coordinator.inlineEditingHeight()
        viewCoordinator.constraints.navigationBarContainerHeight.constant = height
    }
}

// MARK: - UnifiedToggleInputInlineActivating

extension MainViewController: UnifiedToggleInputInlineActivating {

    func activateInlineEditingIfNeeded(currentText: String?) -> UnifiedToggleInputActivationDecision {
        guard let coordinator = unifiedToggleInputCoordinator,
              currentTab?.isAITab != true else {
            return .allowDefault
        }
        let position: UnifiedToggleInputCardPosition = appSettings.currentAddressBarPosition == .bottom ? .bottom : .top
        coordinator.activateInlineEditing(prefilledText: currentText, inputMode: .search, cardPosition: position)
        return .intercept
    }
}

// MARK: - UnifiedToggleInputDelegate

extension MainViewController: UnifiedToggleInputDelegate {

    func unifiedToggleInputDidSubmitPrompt(_ prompt: String) {
        openAIChat(prompt, autoSend: true)
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

    func unifiedInputEditingStateDidRequestSwitchTab(toIndex index: Int) {
        onSwitchTabToIndex(index)
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
        currentTab?.submitStartChatAction()
    }

    func aiChatTabChatHeaderDidTapUpgrade() {
        NotificationCenter.default.post(
            name: .settingsDeepLinkNotification,
            object: SettingsViewModel.SettingsDeepLinkSection.subscriptionFlow()
        )
    }
}
