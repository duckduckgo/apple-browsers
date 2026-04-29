//
//  MainViewController+UnifiedToggleInputIntentHandling.swift
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

extension MainViewController {

    func handleUnifiedToggleInputIntent(_ intent: UnifiedToggleInputIntent) {
        switch intent {
        case .showCollapsed:
            handleShowCollapsedIntent()
        case .showExpanded:
            handleShowExpandedIntent()
        case .showOmnibarEditing(let height, let pendingHeight):
            handleShowOmnibarEditingIntent(height: height, pendingHeight: pendingHeight)
        case .showOmnibarInactive:
            applyBottomOmnibarVisibility(.inactive)
        case .showOmnibarActive:
            applyBottomOmnibarVisibility(.active)
        case .hideOmnibarEditing(let animated):
            handleHideOmnibarEditingIntent(animated: animated)
        case .hide:
            handleHideIntent()
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
}

private extension MainViewController {

    func handleShowCollapsedIntent() {
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
    }

    func handleShowExpandedIntent() {
        viewCoordinator.showUnifiedToggleInput()
        if let coordinator = unifiedToggleInputCoordinator {
            if coordinator.isAITabState {
                if coordinator.cardPosition == .bottom {
                    viewCoordinator.setNavBarContainerBottomToKeyboard()
                }
                let chromeBackgroundState = aiTabChromeBackgroundState(for: coordinator.computeRenderState())
                applyUnifiedInputChromeBackground(chromeBackgroundState)
                viewCoordinator.extendContentContainerBehindInput()
            }
            updateUnifiedInputContentVisibility(for: coordinator)
        }
        adjustUI(withKeyboardFrame: latestKeyboardFrame, in: 0, animationCurve: .curveEaseInOut)
    }

    func handleShowOmnibarEditingIntent(height: CGFloat, pendingHeight: CGFloat?) {
        viewCoordinator.showUnifiedToggleInputOmnibar(expandedHeight: height)
        viewCoordinator.suggestionTrayContainer.isHidden = true
        let isTopPosition = unifiedToggleInputCoordinator?.cardPosition == .top
        guard let coordinator = unifiedToggleInputCoordinator else { return }

        if !isTopPosition {
            applyBottomOmnibarVisibility(.active)
        }
        updateUnifiedInputContentVisibility(for: coordinator)

        if isTopPosition && coordinator.isToggleEnabled {
            animateTopOmnibarExpansion(pendingHeight: pendingHeight, coordinator: coordinator)
        } else if isTopPosition {
            fadeInUnifiedInputContent()
        }
    }

    func animateTopOmnibarExpansion(pendingHeight: CGFloat?, coordinator: UnifiedToggleInputCoordinator) {
        viewCoordinator.unifiedInputContentContainer.alpha = 0
        coordinator.animateOmnibarExpansion { [weak self] in
            guard let self else { return }
            if let pendingHeight {
                self.viewCoordinator.constraints.navigationBarContainerHeight.constant = pendingHeight
                self.viewCoordinator.superview.layoutIfNeeded()
            }
            self.unifiedToggleInputCoordinator?.pushContentInsets()
            self.viewCoordinator.unifiedInputContentContainer.alpha = 1
        }
    }

    func fadeInUnifiedInputContent() {
        viewCoordinator.unifiedInputContentContainer.alpha = 0
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) { [weak self] in
            self?.viewCoordinator.unifiedInputContentContainer.alpha = 1
        }
    }

    func handleHideOmnibarEditingIntent(animated: Bool) {
        let onDismissed: () -> Void = { [weak self] in
            self?.unifiedToggleInputCoordinator?.clearText()
        }
        if animated {
            viewCoordinator.hideUnifiedToggleInputOmnibar(completion: onDismissed)
        } else {
            viewCoordinator.finishUnifiedToggleInputOmnibarDismiss()
            onDismissed()
        }
        resetUnifiedInputContentAfterHide()
        viewCoordinator.suggestionTrayContainer.backgroundColor = .clear
    }

    func handleHideIntent() {
        unifiedToggleInputCoordinator?.viewController.view.backgroundColor = .clear
        viewCoordinator.hideUnifiedToggleInput()
        resetUnifiedInputContentAfterHide()
        // Avoid leaking text into the next input session.
        unifiedToggleInputCoordinator?.clearText()
    }

    func resetUnifiedInputContentAfterHide() {
        unifiedToggleInputCoordinator?.contentViewController.setActive(false)
        viewCoordinator.hideUnifiedInputContent()
        unifiedToggleInputCoordinator?.contentViewController.setContentInset(top: 0, bottom: 0)
        hideSuggestionTray()
    }

    func applyBottomOmnibarVisibility(_ state: UnifiedToggleInputDisplayState.OmnibarState) {
        guard let coordinator = unifiedToggleInputCoordinator,
              coordinator.cardPosition == .bottom,
              viewCoordinator.addressBarPosition.isBottom else {
            recomputeNavigationBarContainerHeightIfNeeded()
            return
        }
        applyBottomOmnibarAnchor(state)
        viewCoordinator.navigationBarContainer.superview?.layoutIfNeeded()
        recomputeNavigationBarContainerHeightIfNeeded()
    }

    func applyBottomOmnibarAnchor(_ state: UnifiedToggleInputDisplayState.OmnibarState) {
        switch state {
        case .active:
            viewCoordinator.restoreNavBarToKeyboardForOmnibarActive()
        case .inactive:
            viewCoordinator.restoreNavBarToToolbarForOmnibarInactive()
        }
    }
}
