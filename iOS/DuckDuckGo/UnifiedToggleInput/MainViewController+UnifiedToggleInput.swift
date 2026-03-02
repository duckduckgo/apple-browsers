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
    }

    func refreshUnifiedToggleInput(for tab: TabViewController) {
        guard unifiedToggleInputFeature.isAvailable,
              let coordinator = unifiedToggleInputCoordinator else { return }

        if !tab.isAITab && coordinator.displayState == .hidden { return }

        if tab.isAITab {
            if let userScript = tab.userScripts?.aiChatUserScript {
                coordinator.bindToTab(userScript)
            }
            tab.webView.scrollView.contentInset = .zero
            coordinator.showCollapsed()
            viewCoordinator.setNavigationChromeHidden(true)
            tab.borderView.isTopVisible = false
            tab.borderView.isBottomVisible = false
        } else {
            coordinator.hide()
            coordinator.unbind()
            tab.borderView.updateForAddressBarPosition(appSettings.currentAddressBarPosition)
            tab.borderView.isBottomVisible = true
            viewCoordinator.setNavigationChromeHidden(false)
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
        viewCoordinator.setNavigationChromeHidden(false)
        loadQuery(query)
    }

    func unifiedToggleInputDidRequestVoiceSearch() {
        let mode = unifiedToggleInputCoordinator?.inputMode ?? .search
        handleVoiceSearchOpenRequest(preferredTarget: mode == .aiChat ? .AIChat : .SERP)
    }
}
