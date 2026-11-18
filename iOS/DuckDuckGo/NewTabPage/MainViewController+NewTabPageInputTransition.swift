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
        let focusedPose = measureFocusedPose(coordinator: coordinator, transitionSource: transitionSource)
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
        let restingTransform = measureFocusedPose(coordinator: coordinator, transitionSource: transitionSource)?
            .focusedInputRestingTransform ?? .identity
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
        let focusedPose = transitionSource?.focusedPose
        source?.alpha = RestingSearchCardHandoff(cardPosition: coordinator.cardPosition).alphaWhenDismissStarts

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
                source?.alpha = 1
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

    /// Re-measures the page's focused pose after the input or its modules change while focused.
    func refreshFocusedNewTabPagePose() {
        guard let transitionSource = newTabPageViewController as? NewTabPageInputTransitionSource,
              let currentPose = transitionSource.focusedPose,
              let coordinator = unifiedToggleInputCoordinator else { return }
        view.layoutIfNeeded()
        guard let pose = measureFocusedPose(coordinator: coordinator, transitionSource: transitionSource), pose != currentPose else { return }
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

    /// The page's pose that follows the focused input, independent of transforms on either card.
    private func measureFocusedPose(coordinator: UnifiedToggleInputCoordinator,
                                    transitionSource: NewTabPageInputTransitionSource?) -> NewTabPageFocusedPose? {
        guard let transitionSource, let restingFrame = transitionSource.searchInputTransitionFrame(in: view) else { return nil }
        let inputContainer: UIView = viewCoordinator.unifiedToggleInputContainer
        let focusedFrame = inputContainer.untransformedFrame(of: coordinator.viewController.inputCardFrame(in: inputContainer), in: view)
        return NewTabPageFocusedPose(restingInputFrame: restingFrame,
                                     focusedInputFrame: focusedFrame,
                                     cardPosition: coordinator.cardPosition,
                                     safeAreaTop: view.safeAreaInsets.top,
                                     showsModules: coordinator.contentViewController.isShowingRedesignedSearchModules)
    }
}

/// How the page's resting search card gives way to the focused card and comes back.
enum RestingSearchCardHandoff: Equatable {
    /// Top input: the focused card travels to and from the resting card, which stays beneath it until the cards swap.
    case staysUnderTravellingCard
    /// Bottom input: the keyboard carries the focused card, so the resting card hides as the focused card appears.
    case hidesWithFocusedCard

    init(cardPosition: UnifiedToggleInputCardPosition) {
        self = cardPosition.isBottom ? .hidesWithFocusedCard : .staysUnderTravellingCard
    }

    /// The resting card's fade out on show, as a delay and a duration within a transition of `transitionDuration`.
    func showFadeTiming(transitionDuration: TimeInterval) -> (delay: TimeInterval, duration: TimeInterval) {
        switch self {
        case .hidesWithFocusedCard:
            return (0, transitionDuration)
        case .staysUnderTravellingCard:
            let swapDuration = min(NewTabPageInputPresentation.inlineInputCardSwapDuration, transitionDuration)
            return (swapDuration, transitionDuration - swapDuration)
        }
    }

    /// Fades the resting card out. Call inside the show animation.
    func fadeOutWhileShowing(_ restingInput: UIView?, transitionDuration: TimeInterval) {
        let timing = showFadeTiming(transitionDuration: transitionDuration)
        UIView.animateOnOwnTiming(duration: timing.duration, delay: timing.delay, options: .curveEaseInOut) {
            restingInput?.alpha = 0
        }
    }

    /// The resting card's alpha while the focused card leaves.
    var alphaWhenDismissStarts: CGFloat {
        switch self {
        case .staysUnderTravellingCard: 1
        case .hidesWithFocusedCard: 0
        }
    }
}

extension NewTabPageInputPresentation {
    /// How long the resting and focused cards overlap while one replaces the other.
    static let inlineInputCardSwapDuration: TimeInterval = 0.1
}

private enum InlineNTPTransitionMetrics {
    /// A small directional cue for the focused layer's own content.
    static let contentTravel: CGFloat = 12
    static let focusedPoseRefreshDuration: TimeInterval = 0.2
}

extension UIView {

    /// Animates with its own duration and curve, even when called inside another animation.
    static func animateOnOwnTiming(duration: TimeInterval,
                                   delay: TimeInterval = 0,
                                   options: UIView.AnimationOptions,
                                   animations: @escaping () -> Void) {
        animate(withDuration: duration,
                delay: delay,
                options: options.union([.overrideInheritedDuration, .overrideInheritedCurve]),
                animations: animations)
    }

    /// Where `rect`, in this view's coordinates, would sit in `targetView` if this view had no transform.
    func untransformedFrame(of rect: CGRect, in targetView: UIView) -> CGRect {
        guard let superview else { return rect }
        let origin = CGPoint(x: center.x - bounds.width * layer.anchorPoint.x,
                             y: center.y - bounds.height * layer.anchorPoint.y)
        let rectInSuperview = rect.offsetBy(dx: origin.x - bounds.origin.x, dy: origin.y - bounds.origin.y)
        return superview.convert(rectInSuperview, to: targetView)
    }
}
