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

import Combine
import Subscription
import UIKit

// MARK: - Unified Toggle Input Setup

extension MainViewController {

    func setUpUnifiedToggleInputIfNeeded() {
        guard unifiedToggleInputFeature.isAvailable else { return }

        let coordinator = UnifiedToggleInputCoordinator()
        coordinator.delegate = self
        coordinator.viewController.isVoiceSearchAvailable = voiceSearchHelper.isVoiceSearchEnabled
        self.unifiedToggleInputCoordinator = coordinator

        let inputVC = coordinator.viewController
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

        setUpAIChatTabChatHeader()

        coordinator.intentPublisher
            .sink { [weak self] intent in
                self?.handleUnifiedToggleInputIntent(intent)
            }
            .store(in: &unifiedToggleInputCancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in
                guard let self,
                      let coordinator = self.unifiedToggleInputCoordinator,
                      coordinator.displayState == .expanded,
                      self.keyboardShowing else { return }
                coordinator.showCollapsed()
            }
            .store(in: &unifiedToggleInputCancellables)

        NotificationCenter.default.publisher(for: .speechRecognizerDidChangeAvailability)
            .sink { [weak self] _ in
                guard let self else { return }
                self.unifiedToggleInputCoordinator?.viewController.isVoiceSearchAvailable = self.voiceSearchHelper.isVoiceSearchEnabled
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

    func refreshUnifiedToggleInput(for tab: TabViewController) {
        guard unifiedToggleInputFeature.isAvailable,
              let coordinator = unifiedToggleInputCoordinator else { return }

        if !tab.isAITab && coordinator.displayState == .hidden &&
            viewCoordinator.aiChatTabChatHeaderContainer.isHidden { return }

        if tab.isAITab {
            if let userScript = tab.userScripts?.aiChatUserScript {
                coordinator.bindToTab(userScript)
            }
            tab.webView.scrollView.contentInset = .zero
            coordinator.showCollapsed()
            viewCoordinator.showAITabChrome()
            refreshAIChatTabChatHeaderSubscriptionState()
            tab.borderView.isTopVisible = false
            tab.borderView.isBottomVisible = false
        } else {
            coordinator.hide()
            coordinator.unbind()
            viewCoordinator.hideAITabChrome()
            refreshStatusBarBackgroundAfterAIChrome()
            tab.borderView.updateForAddressBarPosition(appSettings.currentAddressBarPosition)
            tab.borderView.isBottomVisible = true
        }
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
        case .showExpanded:
            viewCoordinator.showUnifiedToggleInput(aboveKeyboard: true)
        case .hide:
            viewCoordinator.hideUnifiedToggleInput()
        }
    }
}

// MARK: - UnifiedToggleInputDelegate

extension MainViewController: UnifiedToggleInputDelegate {

    func unifiedToggleInputDidSubmitPrompt(_ prompt: String) {
        openAIChat(prompt, autoSend: true)
    }

    func unifiedToggleInputDidSubmitQuery(_ query: String) {
        unifiedToggleInputCoordinator?.hide()
        viewCoordinator.hideAITabChrome()
        refreshStatusBarBackgroundAfterAIChrome()
        loadQuery(query)
    }

    func unifiedToggleInputDidRequestVoiceSearch() {
        let mode = unifiedToggleInputCoordinator?.inputMode ?? .search
        handleVoiceSearchOpenRequest(preferredTarget: mode == .aiChat ? .AIChat : .SERP)
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
