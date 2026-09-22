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
            view.insertSubview(restingSnapshot, aboveSubview: viewCoordinator.unifiedInputContentContainer)
        }

        let contentOffset = UIAccessibility.isReduceMotionEnabled ? 0 : InlineNTPTransitionMetrics.contentTravel
        contentContainer.transform = CGAffineTransform(translationX: 0, y: contentOffset)
        let duration = UIAccessibility.isReduceMotionEnabled ? 0 : Constants.omnibarTransitionDuration(
            isBottom: coordinator.cardPosition.isBottom, isFloatingUIEnabled: isFloatingUIEnabled)
        UIView.animate(withDuration: duration,
                       delay: 0,
                       options: [.beginFromCurrentState, .curveEaseInOut, .allowUserInteraction], animations: { [weak self] in
            inputContainer.transform = .identity
            self?.viewCoordinator.unifiedToggleInputContainer.alpha = 1
            self?.viewCoordinator.focusedStateBackground.alpha = 1
            contentContainer.alpha = 1
            contentContainer.transform = .identity
            restingSnapshot?.alpha = 0
            restingSnapshot?.transform = CGAffineTransform(translationX: 0, y: -contentOffset)
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
        let contentContainer: UIView = viewCoordinator.unifiedInputContentContainer
        let contentOffset = UIAccessibility.isReduceMotionEnabled ? 0 : InlineNTPTransitionMetrics.contentTravel
        let finish: () -> Void = { [weak self] in
            inputContainer.transform = .identity
            contentContainer.transform = .identity
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
            restingSnapshot.transform = CGAffineTransform(translationX: 0, y: -contentOffset)
            view.insertSubview(restingSnapshot, aboveSubview: viewCoordinator.unifiedInputContentContainer)
        }

        viewCoordinator.hideUnifiedToggleInputOmnibar(
            transition: .inlineInput,
            contentSnapshot: restingSnapshot,
            additionalAnimations: { [weak self] in
                inputContainer.transform = restingTransform
                self?.viewCoordinator.unifiedInputContentContainer.alpha = 0
                contentContainer.transform = CGAffineTransform(translationX: 0, y: contentOffset)
                restingSnapshot?.alpha = 1
                restingSnapshot?.transform = .identity
            },
            interruptCleanup: { [weak self] in
                restingSnapshot?.removeFromSuperview()
                inputContainer.transform = .identity
                contentContainer.transform = .identity
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

    func captureRestingNewTabPageSnapshot() {
        restingNewTabPageSnapshot = nil
        guard let page = newTabPageViewController, page.hasInlineSearchInput else { return }
        (page as? RedesignedNewTabPageViewController)?.finishEntranceAnimation()
        view.layoutIfNeeded()
        let bounds = page.view.bounds
        guard !bounds.isEmpty else { return }

        // Capture before editing hides the resting controls. Dismissal must not reveal the
        // live search field just to build its transition overlay.
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        var didDraw = false
        let image = renderer.image { _ in
            didDraw = page.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        guard didDraw else { return }
        restingNewTabPageSnapshot = (image, page.view.convert(bounds, to: view), view.bounds.size)
    }

    private func makeRestingNewTabPageSnapshot() -> UIView? {
        guard let cached = restingNewTabPageSnapshot else { return nil }
        // Rotation or resizing invalidates the captured layout; use the live-page handoff instead.
        guard cached.viewportSize == view.bounds.size else {
            restingNewTabPageSnapshot = nil
            return nil
        }
        let snapshot = UIImageView(image: cached.image)
        snapshot.frame = cached.frame
        snapshot.isUserInteractionEnabled = false
        snapshot.accessibilityElementsHidden = true
        return snapshot
    }
}

private enum InlineNTPTransitionMetrics {
    /// A small directional cue without trying to morph duplicate controls between layouts.
    static let contentTravel: CGFloat = 12
}
