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
import Combine
import Subscription
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
    }

    private func handleAITabModeChange(_ mode: TextEntryMode, coordinator: UnifiedToggleInputCoordinator) {
        let height = coordinator.inlineEditingHeight()
        viewCoordinator.constraints.navigationBarContainerHeight.constant = max(height, viewCoordinator.standardNavigationBarContainerHeight)
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

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in
                guard let self,
                      let coordinator = self.unifiedToggleInputCoordinator,
                      case .aiTab(.expanded) = coordinator.displayState,
                      self.keyboardShowing else { return }
                coordinator.showCollapsed()
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
            }
            .store(in: &unifiedToggleInputCancellables)
    }

    func refreshUnifiedToggleInput(for tab: TabViewController) {
        guard unifiedToggleInputFeature.isAvailable,
              let coordinator = unifiedToggleInputCoordinator else { return }

        if !tab.isAITab && coordinator.displayState == .hidden &&
            viewCoordinator.aiChatTabChatHeaderContainer.isHidden {
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
            refreshAIChatTabChatHeaderSubscriptionState()
            tab.borderView.isTopVisible = false
            tab.borderView.isBottomVisible = false
        } else {
            coordinator.deactivateInlineEditing()
            coordinator.hide()
            coordinator.unbind()
            viewCoordinator.hideAITabChrome()
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

    private func handleUnifiedToggleInputIntent(_ intent: UnifiedToggleInputIntent) {
        switch intent {
        case .showCollapsed:
            viewCoordinator.showUnifiedToggleInput(aboveKeyboard: false)
            viewCoordinator.suggestionTrayContainer.isHidden = true
        case .showExpanded:
            viewCoordinator.anchorUnifiedToggleInputToKeyboardPreservingHeight()
            if let coordinator = unifiedToggleInputCoordinator {
                let height = coordinator.inlineEditingHeight()
                viewCoordinator.constraints.navigationBarContainerHeight.constant = max(height, viewCoordinator.standardNavigationBarContainerHeight)
            }
        case .showInlineEditing(let height):
            viewCoordinator.showUnifiedToggleInputInline(expandedHeight: height)
            viewCoordinator.suggestionTrayContainer.isHidden = true
        case .hideInlineEditing:
            viewCoordinator.hideUnifiedToggleInputInline()
            hideSuggestionTray()
            viewCoordinator.suggestionTrayContainer.isHidden = false
        case .hide:
            viewCoordinator.hideUnifiedToggleInput()
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
