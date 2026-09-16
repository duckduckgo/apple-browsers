//
//  MainViewController+NewTabPageInputTransition.swift
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

    func showInlineNewTabPageInput(coordinator: UnifiedToggleInputCoordinator, height: CGFloat, pendingHeight: CGFloat?) {
        let restingSnapshot = makeRestingNewTabPageSnapshot()
        coordinator.contentViewController.refreshSuggestionsCaches()
        coordinator.viewController.omnibarPillWindowFrame = nil
        coordinator.cacheOmnibarPlaceholderWindowX(nil, windowSize: view.window?.bounds.size)
        viewCoordinator.ensureNavContainerOwnershipForUnifiedToggleInputIfNeeded()

        let contentContainer: UIView = viewCoordinator.unifiedInputContentContainer
        viewCoordinator.focusedStateBackground.alpha = 0
        contentContainer.alpha = 0
        contentContainer.transform = .identity
        viewCoordinator.showUnifiedToggleInputOmnibar(expandedHeight: height)
        viewCoordinator.suggestionTrayContainer.isHidden = true
        updateUnifiedInputContentVisibility(for: coordinator)

        // Resolve the editor's layout before starting the transition.
        coordinator.viewController.applyOmnibarEditingShowPose()
        if coordinator.cardPosition.isBottom {
            applyBottomOmnibarVisibility(.active)
            if isFloatingUIEnabled {
                viewCoordinator.applyDetachedToolbarHeight()
            }
        }
        if let pendingHeight {
            viewCoordinator.constraints.navigationBarContainerHeight.constant = pendingHeight
        }
        coordinator.viewController.setTextHorizontalShift(0)
        view.layoutIfNeeded()
        coordinator.pushContentInsets()
        let inputContainer: UIView = viewCoordinator.unifiedToggleInputContainer
        inputContainer.transform = .identity
        let source = (newTabPageViewController as? NewTabPageInputTransitionSource)?.searchInputView
        // The keyboard already moves bottom input. Translating it from the resting card as
        // well makes it travel down before reversing direction as the keyboard arrives.
        if let source, !coordinator.cardPosition.isBottom, !UIAccessibility.isReduceMotionEnabled {
            let restingFrame = source.convert(source.bounds, to: view)
            let editingFrame = coordinator.viewController.inputCardFrame(in: view)
            inputContainer.transform = CGAffineTransform(translationX: 0, y: restingFrame.midY - editingFrame.midY)
        }
        inputContainer.alpha = 0
        if let restingSnapshot {
            view.addSubview(restingSnapshot)
        }

        let duration = UIAccessibility.isReduceMotionEnabled ? 0 : Constants.omnibarTransitionDuration(
            isBottom: coordinator.cardPosition.isBottom, isFloatingUIEnabled: isFloatingUIEnabled)
        UIView.animate(withDuration: duration,
                       delay: 0,
                       options: [.beginFromCurrentState, .curveEaseInOut, .allowUserInteraction], animations: { [weak self] in
            inputContainer.transform = .identity
            self?.viewCoordinator.unifiedToggleInputContainer.alpha = 1
            self?.viewCoordinator.focusedStateBackground.alpha = 1
            contentContainer.alpha = 1
            restingSnapshot?.alpha = 0
        }, completion: { [weak self] _ in
            restingSnapshot?.removeFromSuperview()
            self?.refreshFloatingToolbarBackdrop()
        })
    }

    func dismissInlineNewTabPageInput(coordinator: UnifiedToggleInputCoordinator,
                                      animated: Bool,
                                      completion: (() -> Void)? = nil) {
        let inputContainer: UIView = viewCoordinator.unifiedToggleInputContainer
        let source = (newTabPageViewController as? NewTabPageInputTransitionSource)?.searchInputView
        var restingTransform = CGAffineTransform.identity
        if let source, !coordinator.cardPosition.isBottom, !UIAccessibility.isReduceMotionEnabled {
            let restingFrame = source.convert(source.bounds, to: view)
            let editingFrame = coordinator.viewController.inputCardFrame(in: view)
            restingTransform = CGAffineTransform(translationX: 0, y: restingFrame.midY - editingFrame.midY)
        }
        let finish: () -> Void = { [weak self] in
            inputContainer.transform = .identity
            self?.finishUnifiedToggleInputToOmnibarDismiss(completion: completion)
        }
        guard animated else {
            coordinator.viewController.deactivateInput()
            viewCoordinator.finishUnifiedToggleInputOmnibarDismiss()
            finish()
            return
        }

        let restingSnapshot = makeRestingNewTabPageSnapshot()
        if let restingSnapshot {
            restingSnapshot.alpha = 0
            view.addSubview(restingSnapshot)
        }

        viewCoordinator.hideUnifiedToggleInputOmnibar(
            transition: .inlineInput,
            contentSnapshot: restingSnapshot,
            additionalAnimations: { [weak self] in
                inputContainer.transform = restingTransform
                self?.viewCoordinator.unifiedInputContentContainer.alpha = 0
                restingSnapshot?.alpha = 1
            },
            interruptCleanup: { [weak self] in
                restingSnapshot?.removeFromSuperview()
                inputContainer.transform = .identity
                self?.viewCoordinator.unifiedInputContentContainer.alpha = 1
                self?.viewCoordinator.unifiedToggleInputContainer.alpha = 1
            },
            resigningInput: { [weak coordinator] in
                coordinator?.viewController.deactivateInput()
            },
            completion: {
                finish()
                restingSnapshot?.removeFromSuperview()
            })
    }

    private func makeRestingNewTabPageSnapshot() -> UIView? {
        guard let page = newTabPageViewController,
              let source = page as? NewTabPageInputTransitionSource else { return nil }

        // Keep the resting page visible through the handoff without moving a live view
        // whose layout is also being driven by the keyboard.
        source.setSearchInputEditing(false)
        defer { source.setSearchInputEditing(true) }
        guard let snapshot = page.view.snapshotView(afterScreenUpdates: true) else { return nil }
        snapshot.frame = page.view.convert(page.view.bounds, to: view)
        snapshot.isUserInteractionEnabled = false
        snapshot.accessibilityElementsHidden = true
        return snapshot
    }
}
