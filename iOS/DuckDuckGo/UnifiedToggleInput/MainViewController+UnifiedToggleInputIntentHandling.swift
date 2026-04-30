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

    func currentOmnibarPlaceholderWindowX() -> CGFloat? {
        guard let textField = viewCoordinator.omniBar.barView.textField,
              textField.window != nil else { return nil }
        let placeholderRect = textField.placeholderRect(forBounds: textField.bounds)
        return textField.convert(placeholderRect.origin, to: nil).x
    }

    func currentOmnibarPlaceholderColor() -> UIColor? {
        guard let textField = viewCoordinator.omniBar.barView.textField,
              let attributed = textField.attributedPlaceholder,
              attributed.length > 0 else { return nil }
        return attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
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
        guard let coordinator = unifiedToggleInputCoordinator else { return }

        let omnibarPlaceholderWindowX = currentOmnibarPlaceholderWindowX()
        let omnibarPlaceholderColor = currentOmnibarPlaceholderColor()
        let utiPlaceholderColor = coordinator.viewController.defaultPlaceholderColor

        viewCoordinator.showUnifiedToggleInputOmnibar(expandedHeight: height)
        viewCoordinator.suggestionTrayContainer.isHidden = true
        updateUnifiedInputContentVisibility(for: coordinator)
        viewCoordinator.unifiedInputContentContainer.alpha = 0

        if let omnibarPlaceholderWindowX {
            coordinator.viewController.alignPlaceholderHorizontally(toWindowX: omnibarPlaceholderWindowX)
        }

        let duration = Constants.omnibarTransitionDuration(isBottom: coordinator.cardPosition.isBottom)
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: .curveEaseOut,
            animations: { [weak self] in
                guard let self else { return }
                coordinator.viewController.applyOmnibarEditingShowPose()
                if coordinator.cardPosition == .bottom {
                    self.applyBottomOmnibarVisibility(.active)
                }
                if let pendingHeight {
                    self.viewCoordinator.constraints.navigationBarContainerHeight.constant = pendingHeight
                }
                // Lay out before pushContentInsets — it reads bar.frame.height.
                self.viewCoordinator.superview.layoutIfNeeded()
                coordinator.pushContentInsets()
                self.viewCoordinator.unifiedInputContentContainer.alpha = 1
                coordinator.viewController.setTextHorizontalShift(0)
            }
        )

        if let omnibarPlaceholderColor {
            coordinator.viewController.animatePlaceholderColorTransition(
                from: omnibarPlaceholderColor,
                to: utiPlaceholderColor,
                duration: duration
            )
        }
    }

    func handleHideOmnibarEditingIntent(animated: Bool) {
        let coordinator = unifiedToggleInputCoordinator
        let onDismissed: () -> Void = { [weak coordinator] in
            coordinator?.viewController.setTextHorizontalShift(0)
            coordinator?.viewController.finalizeOmnibarEditingDismiss()
            coordinator?.clearText()
        }
        if animated {
            let omnibarPlaceholderWindowX = currentOmnibarPlaceholderWindowX()
            let omnibarPlaceholderColor = currentOmnibarPlaceholderColor()
            let utiPlaceholderColor = coordinator?.viewController.defaultPlaceholderColor
            let duration = Constants.omnibarTransitionDuration(isBottom: viewCoordinator.addressBarPosition.isBottom)
            let slideUTIText: () -> Void = { [weak coordinator] in
                guard let coordinator, let omnibarPlaceholderWindowX else { return }
                coordinator.viewController.alignPlaceholderHorizontally(toWindowX: omnibarPlaceholderWindowX)
            }
            viewCoordinator.hideUnifiedToggleInputOmnibar(additionalAnimations: slideUTIText, completion: onDismissed)
            if let coordinator, let omnibarPlaceholderColor, let utiPlaceholderColor {
                coordinator.viewController.animatePlaceholderColorTransition(
                    from: utiPlaceholderColor,
                    to: omnibarPlaceholderColor,
                    duration: duration
                )
            }
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
