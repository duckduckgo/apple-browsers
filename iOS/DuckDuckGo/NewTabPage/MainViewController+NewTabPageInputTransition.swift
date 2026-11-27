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
        // A focus that interrupts a dismiss takes the input over from that dismiss's hold.
        releaseAnyBottomInputHold()
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
        if !showsFocusedSurfaceDirectly {
            holdBottomInputAtPredictedKeyboardTop(coordinator: coordinator)
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
        inputContainer.alpha = 1

        let contentOffset = UIAccessibility.isReduceMotionEnabled ? 0 : InlineNTPTransitionMetrics.contentTravel
        contentContainer.transform = CGAffineTransform(translationX: 0, y: contentOffset)
        let duration = UIAccessibility.isReduceMotionEnabled ? 0 : Constants.omnibarTransitionDuration(
            isBottom: coordinator.cardPosition.isBottom, isFloatingUIEnabled: isFloatingUIEnabled)
        let animations = { [weak self] in
            inputContainer.transform = .identity
            self?.viewCoordinator.focusedStateBackground.alpha = 1
            contentContainer.alpha = 1
            contentContainer.transform = .identity
            transitionSource?.setFocusedPose(focusedPose)
        }
        if showsFocusedSurfaceDirectly {
            // Automatic new-tab focus and onboarding handoffs must not fade through resting modules.
            // Stage the opaque focused pose synchronously.
            UIView.performWithoutAnimation(animations)
            transitionSource?.settleFocusedPose()
            refreshFloatingToolbarBackdrop()
            return
        }
        let animator = UIViewPropertyAnimator(duration: duration, curve: .easeInOut, animations: animations)
        animator.addCompletion { [weak self] position in
            if position == .end {
                transitionSource?.settleFocusedPose()
            }
            self?.releaseBottomInputHoldWhenKeyboardShows()
            self?.refreshFloatingToolbarBackdrop()
        }
        animator.startAnimation()
    }

    private func holdBottomInputAtPredictedKeyboardTop(coordinator: UnifiedToggleInputCoordinator) {
        // The keyboard starts rising only once focus lands, after the travel has started. Following it would carry
        // the card toward the toolbar first and then up.
        guard coordinator.cardPosition.isBottom, !isInMinimalChromeLayout, lastShownKeyboardHeight > 0,
              !UIAccessibility.isReduceMotionEnabled else { return }
        holdBottomInput(distanceFromScreenBottom: lastShownKeyboardHeight, for: .focus)
    }

    var isBottomInputHeldForTravel: Bool {
        if case .transition = viewCoordinator.navigationBarContainerBottomAnchor { return true }
        return false
    }

    private func holdBottomInput(distanceFromScreenBottom distance: CGFloat, for transition: BottomInputTransition) {
        removeBottomInputHoldKeyboardObserver()
        viewCoordinator.holdNavBarContainerBottom(distanceFromScreenBottom: distance, for: transition)
    }

    private func releaseBottomInputHoldWhenKeyboardShows() {
        guard viewCoordinator.navigationBarContainerBottomAnchor == .transition(.focus) else { return }
        guard !keyboardShowing else {
            releaseBottomInputHold(heldBy: .focus)
            return
        }
        removeBottomInputHoldKeyboardObserver()
        bottomInputHoldKeyboardObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { [weak self] _ in
            self?.releaseBottomInputHold(heldBy: .focus)
        }
        // A hardware keyboard or a refused focus never shows the software keyboard, which would leave the hold in place.
        let timeout = DispatchWorkItem { [weak self] in
            self?.releaseBottomInputHold(heldBy: .focus)
        }
        bottomInputHoldTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + InlineNTPTransitionMetrics.bottomInputHoldKeyboardTimeout, execute: timeout)
    }

    /// Releases only while `transition` still owns the hold.
    private func releaseBottomInputHold(heldBy transition: BottomInputTransition) {
        if transition == .focus {
            removeBottomInputHoldKeyboardObserver()
        }
        guard viewCoordinator.navigationBarContainerBottomAnchor == .transition(transition) else { return }
        restoreBottomInputAnchorAfterHold()
    }

    func releaseAnyBottomInputHold() {
        removeBottomInputHoldKeyboardObserver()
        guard isBottomInputHeldForTravel else { return }
        restoreBottomInputAnchorAfterHold()
    }

    private func restoreBottomInputAnchorAfterHold() {
        guard let coordinator = unifiedToggleInputCoordinator, coordinator.isOmnibarSession else {
            viewCoordinator.restoreNavBarToKeyboardForOmnibarActive()
            return
        }
        let state: UnifiedToggleInputDisplayState.OmnibarState = coordinator.isOmnibarEditing ? .active : .inactive
        // The visibility pass skips the anchor while the hold stands, and for a card already moved to the top.
        switch state {
        case .active:
            viewCoordinator.restoreNavBarToKeyboardForOmnibarActive()
        case .inactive:
            viewCoordinator.restoreNavBarToToolbarForOmnibarInactive()
        }
        applyBottomOmnibarVisibility(state)
    }

    private func removeBottomInputHoldKeyboardObserver() {
        bottomInputHoldKeyboardObserver.map(NotificationCenter.default.removeObserver)
        bottomInputHoldKeyboardObserver = nil
        bottomInputHoldTimeout?.cancel()
        bottomInputHoldTimeout = nil
    }

    func dismissInlineNewTabPageInput(coordinator: UnifiedToggleInputCoordinator,
                                      animated: Bool,
                                      completion: (() -> Void)? = nil) {
        let inputContainer: UIView = viewCoordinator.unifiedToggleInputContainer
        let transitionSource = newTabPageViewController as? NewTabPageInputTransitionSource
        let measuredPose = measureFocusedPose(coordinator: coordinator, transitionSource: transitionSource)
        let restingTransform = measuredPose?.focusedInputRestingTransform ?? .identity
        let contentContainer: UIView = viewCoordinator.unifiedInputContentContainer
        let contentOffset = UIAccessibility.isReduceMotionEnabled ? 0 : InlineNTPTransitionMetrics.contentTravel
        // The coordinator may already have reset its card position for the dismiss, so the bar position decides.
        if animated, viewCoordinator.addressBarPosition.isBottom, !isInMinimalChromeLayout {
            // Resigning drops the keyboard; the card travels to the slot from where it is now instead of falling with it.
            holdBottomInput(distanceFromScreenBottom: view.bounds.maxY - viewCoordinator.navigationBarContainer.frame.maxY,
                            for: .dismiss)
        }
        let restingMode = tabManager.currentTabsModel.currentTab.map { initialOmnibarToggleMode(for: $0) } ?? coordinator.inputMode
        let finish: () -> Void = { [weak self] in
            inputContainer.transform = .identity
            contentContainer.transform = .identity
            self?.releaseBottomInputHold(heldBy: .dismiss)
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
        coordinator.beginReturnToNewTabPage(inputMode: restingMode)

        viewCoordinator.hideUnifiedToggleInputOmnibar(
            transition: .inlineInput,
            contentSnapshot: focusedSnapshot,
            additionalAnimations: { [weak self, weak coordinator] in
                inputContainer.transform = restingTransform
                coordinator?.applyRenderStateForReturnTravel()
                self?.resizeNewTabPageInputSlotForReturn()
                outgoingContent.transform = CGAffineTransform(translationX: 0, y: contentOffset)
                transitionSource?.setFocusedPose(nil)
            },
            inlineInputHandoffAnimations: {
                outgoingContent.alpha = 0
            },
            interruptCleanup: { [weak self, weak coordinator] in
                self?.releaseBottomInputHold(heldBy: .dismiss)
                coordinator?.abandonReturnToNewTabPage()
                coordinator?.viewController.recommitCardCornerRadius()
                inputContainer.transform = .identity
                contentContainer.transform = .identity
                coordinator?.clearText()
                self?.viewCoordinator.unifiedInputContentContainer.alpha = 1
                self?.viewCoordinator.unifiedToggleInputContainer.alpha = 1
                self?.viewCoordinator.focusedStateBackground.alpha = 1
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
        var pose = NewTabPageFocusedPose(restingInputFrame: restingFrame,
                                         focusedInputFrame: focusedFrame,
                                         cardPosition: coordinator.cardPosition,
                                         safeAreaTop: view.safeAreaInsets.top,
                                         bottomInputHeight: coordinator.editingHeight(),
                                         showsModules: coordinator.contentViewController.isShowingRedesignedSearchModules)
        // The same input view travels between the chrome and the slot, top pinned in both, and its height changes with the
        // mode. Aligning its top keeps it landing on the slot whatever height it had when the slot was measured.
        let focusedInputViewFrame = inputContainer.untransformedFrame(of: inputContainer.bounds, in: view)
        pose.inputOffset = focusedInputViewFrame.minY - restingFrame.minY
        return pose
    }
}

private enum InlineNTPTransitionMetrics {
    static let contentTravel: CGFloat = 12
    static let focusedPoseRefreshDuration: TimeInterval = 0.2
    static let bottomInputHoldKeyboardTimeout: TimeInterval = 1
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
