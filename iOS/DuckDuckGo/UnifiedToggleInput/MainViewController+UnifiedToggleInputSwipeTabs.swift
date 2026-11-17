//
//  MainViewController+UnifiedToggleInputSwipeTabs.swift
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

import UIKit
import AIChat

final class UnifiedInputSwipeTabsPanGestureRecognizer: UIPanGestureRecognizer {}

extension MainViewController {

    func installSwipeTabsGesturesForUnifiedInput() {
        viewCoordinator.unifiedToggleInputContainer.addGestureRecognizer(makeSwipeTabsPanGesture())
        viewCoordinator.aiChatTabChatHeaderContainer.addGestureRecognizer(makeSwipeTabsPanGesture())
        viewCoordinator.toolbar.addGestureRecognizer(makeSwipeTabsPanGesture())
        swipeTabsCoordinator?.auxiliarySwipeViews = [
            viewCoordinator.unifiedToggleInputContainer,
            viewCoordinator.aiChatTabChatHeaderContainer,
        ]
        swipeTabsCoordinator?.liveSwipeChromeViews = [
            viewCoordinator.unifiedToggleInputContainer,
            viewCoordinator.aiChatTabChatHeaderContainer,
            viewCoordinator.unifiedInputContentContainer,
            viewCoordinator.navigationBarCollectionView,
            viewCoordinator.toolbar,
        ]
        swipeTabsCoordinator?.onSwipeWillLand = { [weak self] tab in
            self?.crossfadeDuckAIPlaceholder(toMatch: tab)
        }
    }

    private func makeSwipeTabsPanGesture() -> UnifiedInputSwipeTabsPanGestureRecognizer {
        let pan = UnifiedInputSwipeTabsPanGestureRecognizer(target: self, action: #selector(handleUnifiedInputSwipeTabsPan(_:)))
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        return pan
    }

    @objc func handleUnifiedInputSwipeTabsPan(_ gesture: UnifiedInputSwipeTabsPanGestureRecognizer) {
        swipeTabsCoordinator?.handleExternalPan(gesture)
    }

    func shouldBeginUnifiedInputSwipeTabsPan(_ pan: UIPanGestureRecognizer) -> Bool {
        guard let swipeTabsCoordinator, swipeTabsCoordinator.isEnabled else {
            return false
        }
        guard let coordinator = unifiedToggleInputCoordinator else {
            return false
        }

        if coordinator.isOmnibarEditing {
            return false
        }
        if coordinator.viewController.isInputFirstResponder, !allowsSwipeWithFocusedInput(pan) {
            return false
        }

        let velocity = pan.velocity(in: pan.view)
        let allow = abs(velocity.x) > abs(velocity.y)
        return allow
    }

    /// A swipe may pass through several tabs, so the Duck.ai keyboard drops as soon as it starts.
    func collapseDuckAIInputForTabSwipe() {
        guard featureFlagger.isAIChatSwipeChromeRefinementsEnabled,
              let coordinator = unifiedToggleInputCoordinator,
              coordinator.isAITabExpanded else { return }
        coordinator.showCollapsed()
    }

    /// Duck.ai tabs share one input, so its placeholder switches to the tab a swipe settles on before it gets there.
    func crossfadeDuckAIPlaceholder(toMatch tab: Tab) {
        guard featureFlagger.isAIChatSwipeChromeRefinementsEnabled,
              tab.isAITab,
              tabManager.currentTabsModel.currentTab?.isAITab == true,
              let coordinator = unifiedToggleInputCoordinator else { return }
        coordinator.viewController.crossfadePlaceholder(to: duckAIPlaceholderState(for: tab))
    }

    /// The input's own state for the tab it shows, since the stored state is only written when leaving a tab.
    func duckAIPlaceholderState(for tab: Tab) -> AIChatPlaceholderState {
        if let coordinator = unifiedToggleInputCoordinator, coordinator.currentTabUID == tab.uid {
            return coordinator.viewController.placeholderState
        }
        let tabURL = tabManager.controller(for: tab)?.url ?? tab.link?.url
        let selectedTool = unifiedInputStateStore?.state(for: tab.uid).selectedTool
        return AIChatPlaceholderState(hasSubmittedPrompt: tabURL?.duckAIChatID != nil,
                                      isImageGenerationSelected: selectedTool == .imageGeneration)
    }

    /// The Duck.ai header holds no text, so swiping it can't interfere with editing the focused chat input.
    private func allowsSwipeWithFocusedInput(_ pan: UIPanGestureRecognizer) -> Bool {
        featureFlagger.isAIChatSwipeChromeRefinementsEnabled && pan.view === viewCoordinator.aiChatTabChatHeaderContainer
    }
}
