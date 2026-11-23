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
        let showsFocusedSurfaceDirectly = isPerformingOnboardingInputHandoff || isPresentingNewTabInputDirectly
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
        let transitionSource = newTabPageViewController as? NewTabPageInputTransitionSource
        transitionSource?.onFocusedModeSwitchSwipe = { [weak coordinator] mode in
            coordinator?.contentViewController.switchMode(to: mode)
        }
        let focusedPose = measureFocusedPose(coordinator: coordinator, transitionSource: transitionSource)
            ?? unmeasuredFocusedPose(coordinator: coordinator, transitionSource: transitionSource)
        if !showsFocusedSurfaceDirectly, !UIAccessibility.isReduceMotionEnabled, let focusedPose {
            inputContainer.transform = focusedPose.focusedInputRestingTransform
        }
        inputContainer.alpha = 0
        let restingInput = transitionSource?.searchInputView
        let restingCardHandoff = RestingSearchCardHandoff(cardPosition: coordinator.cardPosition)
        restingInput?.alpha = 1

        let contentOffset = UIAccessibility.isReduceMotionEnabled ? 0 : InlineNTPTransitionMetrics.contentTravel
        contentContainer.transform = CGAffineTransform(translationX: 0, y: contentOffset)
        let duration = UIAccessibility.isReduceMotionEnabled ? 0 : Constants.omnibarTransitionDuration(
            isBottom: coordinator.cardPosition.isBottom, isFloatingUIEnabled: isFloatingUIEnabled)
        let animations = { [weak self] in
            inputContainer.transform = .identity
            UIView.animateOnOwnTiming(duration: NewTabPageInputPresentation.inlineInputCardSwapDuration, options: .curveEaseOut) {
                inputContainer.alpha = 1
            }
            self?.viewCoordinator.focusedStateBackground.alpha = 1
            contentContainer.alpha = 1
            contentContainer.transform = .identity
            transitionSource?.setFocusedPose(focusedPose)
            restingCardHandoff.fadeOutWhileShowing(restingInput, transitionDuration: duration)
        }
        if showsFocusedSurfaceDirectly {
            // Automatic new-tab focus and onboarding handoffs must not fade through resting modules.
            // Stage the opaque focused pose synchronously.
            UIView.performWithoutAnimation(animations)
            restingInput?.alpha = 0
            transitionSource?.settleFocusedPose()
            refreshFloatingToolbarBackdrop()
            return
        }
        let animator = UIViewPropertyAnimator(duration: duration, curve: .easeInOut, animations: animations)
        animator.addCompletion { [weak self] position in
            restingInput?.alpha = 0
            if position == .end {
                transitionSource?.settleFocusedPose()
            }
            self?.refreshFloatingToolbarBackdrop()
        }
        animator.startAnimation()
    }

    func dismissInlineNewTabPageInput(coordinator: UnifiedToggleInputCoordinator,
                                      animated: Bool,
                                      completion: (() -> Void)? = nil) {
        let inputContainer: UIView = viewCoordinator.unifiedToggleInputContainer
        let transitionSource = newTabPageViewController as? NewTabPageInputTransitionSource
        let source = transitionSource?.searchInputView
        let measuredPose = measureFocusedPose(coordinator: coordinator, transitionSource: transitionSource)
        let restingTransform = measuredPose?.focusedInputRestingTransform ?? .identity
        let contentContainer: UIView = viewCoordinator.unifiedInputContentContainer
        let contentOffset = UIAccessibility.isReduceMotionEnabled ? 0 : InlineNTPTransitionMetrics.contentTravel
        let finish: () -> Void = { [weak self] in
            inputContainer.transform = .identity
            contentContainer.transform = .identity
            self?.finishUnifiedToggleInputToOmnibarDismiss(completion: completion)
        }
        guard animated && !UIAccessibility.isReduceMotionEnabled else {
            coordinator.viewController.deactivateInput()
            viewCoordinator.finishUnifiedToggleInputOmnibarDismiss()
            finish()
            return
        }

        // Resigning the input can change the live host's safe area and scroll layout.
        // Keep the outgoing focused layer in its current screen position while those updates settle.
        let focusedSnapshot = contentContainer.snapshotView(afterScreenUpdates: false)
        if let focusedSnapshot {
            focusedSnapshot.frame = contentContainer.convert(contentContainer.bounds, to: view)
            focusedSnapshot.isUserInteractionEnabled = false
            focusedSnapshot.accessibilityElementsHidden = true
            view.insertSubview(focusedSnapshot, aboveSubview: contentContainer)
            contentContainer.alpha = 0
        }
        let outgoingContent = focusedSnapshot ?? contentContainer
        if let measuredPose, let currentPose = transitionSource?.focusedPose, measuredPose != currentPose {
            // The bottom input's pose is measured at focus before the keyboard rises.
            // Start the resting card's return from where the focused card is now.
            UIView.performWithoutAnimation { transitionSource?.setFocusedPose(measuredPose) }
        }
        let focusedPose = transitionSource?.focusedPose
        // The resting card carries the dismiss travel, as the focused card fades out at the start.
        source?.alpha = 1

        viewCoordinator.hideUnifiedToggleInputOmnibar(
            transition: .inlineInput,
            contentSnapshot: focusedSnapshot,
            additionalAnimations: {
                inputContainer.transform = restingTransform
                outgoingContent.transform = CGAffineTransform(translationX: 0, y: contentOffset)
                transitionSource?.setFocusedPose(nil)
            },
            inlineInputHandoffAnimations: {
                outgoingContent.alpha = 0
            },
            interruptCleanup: { [weak self, weak coordinator] in
                inputContainer.transform = .identity
                contentContainer.transform = .identity
                coordinator?.clearText()
                self?.viewCoordinator.unifiedInputContentContainer.alpha = 1
                self?.viewCoordinator.unifiedToggleInputContainer.alpha = 1
                self?.viewCoordinator.focusedStateBackground.alpha = 1
                source?.alpha = 0
                transitionSource?.setFocusedPose(focusedPose)
                transitionSource?.settleFocusedPose()
            },
            resigningInput: { [weak coordinator] in
                coordinator?.viewController.deactivateInput()
            },
            completion: finish)
    }

    func refreshFocusedNewTabPagePose() {
        guard let transitionSource = newTabPageViewController as? NewTabPageInputTransitionSource,
              let currentPose = transitionSource.focusedPose,
              let coordinator = unifiedToggleInputCoordinator else { return }
        view.layoutIfNeeded()
        let pose = measureFocusedPose(coordinator: coordinator, transitionSource: transitionSource, ignoresFocusedScroll: true)
            ?? poseKeepingOffsets(of: currentPose, coordinator: coordinator)
        guard pose != currentPose else { return }
        guard !UIAccessibility.isReduceMotionEnabled else {
            transitionSource.setFocusedPose(pose)
            return
        }
        UIView.animate(withDuration: InlineNTPTransitionMetrics.focusedPoseRefreshDuration,
                       delay: 0,
                       options: [.beginFromCurrentState, .curveEaseInOut]) {
            transitionSource.setFocusedPose(pose)
        }
    }

    /// With the resting card scrolled out of view there is nothing to measure the offsets against, but the
    /// modules must still hide or show with the mode.
    private func poseKeepingOffsets(of pose: NewTabPageFocusedPose, coordinator: UnifiedToggleInputCoordinator) -> NewTabPageFocusedPose {
        var updatedPose = pose
        updatedPose.showsModules = coordinator.contentViewController.isShowingRedesignedSearchModules
        return updatedPose
    }

    /// Editing that starts with the resting card scrolled out of view keeps the page where it is, so its modules
    /// still show and take taps. An onboarding dialog keeps the page at rest.
    private func unmeasuredFocusedPose(coordinator: UnifiedToggleInputCoordinator,
                                       transitionSource: NewTabPageInputTransitionSource?) -> NewTabPageFocusedPose? {
        guard let page = transitionSource as? RedesignedNewTabPageViewController, page.canAnimateSearchInput else { return nil }
        return NewTabPageFocusedPose(inputOffset: 0,
                                     modulesOffset: 0,
                                     showsModules: coordinator.contentViewController.isShowingRedesignedSearchModules)
    }

    private func measureFocusedPose(coordinator: UnifiedToggleInputCoordinator,
                                    transitionSource: NewTabPageInputTransitionSource?,
                                    ignoresFocusedScroll: Bool = false) -> NewTabPageFocusedPose? {
        guard let transitionSource else { return nil }
        let restingFrame = ignoresFocusedScroll
            ? transitionSource.focusedPoseSearchInputFrame(in: view)
            : transitionSource.searchInputTransitionFrame(in: view)
        guard let restingFrame else { return nil }
        let inputContainer: UIView = viewCoordinator.unifiedToggleInputContainer
        let focusedFrame = inputContainer.untransformedFrame(of: coordinator.viewController.inputCardFrame(in: inputContainer), in: view)
        return NewTabPageFocusedPose(restingInputFrame: restingFrame,
                                     focusedInputFrame: focusedFrame,
                                     cardPosition: coordinator.cardPosition,
                                     safeAreaTop: view.safeAreaInsets.top,
                                     bottomInputHeight: coordinator.editingHeight(),
                                     showsModules: coordinator.contentViewController.isShowingRedesignedSearchModules)
    }
}

enum RestingSearchCardHandoff: Equatable {
    case staysUnderTravellingCard
    case swapsWithFocusedCard

    init(cardPosition: UnifiedToggleInputCardPosition) {
        self = cardPosition.isBottom ? .swapsWithFocusedCard : .staysUnderTravellingCard
    }

    func showFadeTiming(transitionDuration: TimeInterval) -> (delay: TimeInterval, duration: TimeInterval) {
        let swapDuration = min(NewTabPageInputPresentation.inlineInputCardSwapDuration, transitionDuration)
        switch self {
        case .swapsWithFocusedCard:
            // The bottom focused card is measured before the keyboard rises, so a travelling resting card would
            // drift away from it. The focused card carries the travel instead.
            return (0, swapDuration)
        case .staysUnderTravellingCard:
            return (swapDuration, transitionDuration - swapDuration)
        }
    }

    func fadeOutWhileShowing(_ restingInput: UIView?, transitionDuration: TimeInterval) {
        let timing = showFadeTiming(transitionDuration: transitionDuration)
        UIView.animateOnOwnTiming(duration: timing.duration, delay: timing.delay, options: .curveEaseInOut) {
            restingInput?.alpha = 0
        }
    }
}

extension NewTabPageInputPresentation {
    static let inlineInputCardSwapDuration: TimeInterval = 0.1
}

private enum InlineNTPTransitionMetrics {
    static let contentTravel: CGFloat = 12
    static let focusedPoseRefreshDuration: TimeInterval = 0.2
}

extension UIView {

    static func animateOnOwnTiming(duration: TimeInterval,
                                   delay: TimeInterval = 0,
                                   options: UIView.AnimationOptions,
                                   animations: @escaping () -> Void) {
        animate(withDuration: duration,
                delay: delay,
                options: options.union([.overrideInheritedDuration, .overrideInheritedCurve]),
                animations: animations)
    }

    func untransformedFrame(of rect: CGRect, in targetView: UIView) -> CGRect {
        guard let superview else { return rect }
        let origin = CGPoint(x: center.x - bounds.width * layer.anchorPoint.x,
                             y: center.y - bounds.height * layer.anchorPoint.y)
        let rectInSuperview = rect.offsetBy(dx: origin.x - bounds.origin.x, dy: origin.y - bounds.origin.y)
        return superview.convert(rectInSuperview, to: targetView)
    }
}
