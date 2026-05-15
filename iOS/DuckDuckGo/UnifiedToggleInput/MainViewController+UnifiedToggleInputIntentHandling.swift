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
            handleShowCollapsedIntent(animationStyle: intent.animationStyle(layoutTarget: viewCoordinator.superview))
        case .showExpanded:
            handleShowExpandedIntent(animationStyle: intent.animationStyle(layoutTarget: viewCoordinator.superview))
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
        updateFloatingReturnKeyVisibility()
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

    /// Returns the NTP view's center Y in window coordinates, or nil if not available.
    func ntpLogoWindowCenterY() -> CGFloat? {
        guard let ntpView = newTabPageViewController?.view,
              let window = ntpView.window else { return nil }
        return ntpView.convert(CGPoint(x: 0, y: ntpView.bounds.midY), to: window).y
    }
}

private extension MainViewController {

    func handleShowCollapsedIntent(animationStyle: UTIAnimationStyle) {
        animationStyle.perform { [self] in
            applyAITabCollapsedPose()
        }
    }

    /// The visual end-state for `.aiTab(.collapsed)`: chrome background, content anchored to UTI
    /// top, container shown at the bottom anchored to the keyboard guide, and the card in the
    /// collapsed pose with footer accessories. Whether this snaps or animates is decided by the
    /// caller (which wraps this in `UTIAnimationStyle.perform`).
    private func applyAITabCollapsedPose() {
        if unifiedToggleInputCoordinator?.isAITabState == true {
            applyUnifiedInputChromeBackground(.aiTabChatChromeHidden)
            viewCoordinator.anchorContentContainerToInputTop()
        }
        viewCoordinator.showUnifiedToggleInput()
        if let coordinator = unifiedToggleInputCoordinator,
           coordinator.isAITabState,
           coordinator.cardPosition == .bottom {
            viewCoordinator.setNavBarContainerBottomToKeyboard()
        }
        viewCoordinator.suggestionTrayContainer.isHidden = true
        if let coordinator = unifiedToggleInputCoordinator {
            coordinator.viewController.apply(coordinator.computeRenderState().viewConfig, animated: false)
            updateUnifiedInputContentVisibility(for: coordinator)
        } else {
            viewCoordinator.hideUnifiedInputContent()
        }
    }

    func handleShowExpandedIntent(animationStyle: UTIAnimationStyle) {
        // WKWebView snaps to the new size in one frame while the outer layer animates; mask the
        // gap with a snapshot of the chat at its old visual state.
        let snapshotMask = installContentContainerSnapshotMaskForAITabExpandIfNeeded()
        animationStyle.perform({ [self] in
            applyAITabExpandedPose()
        }, completion: { _ in
            snapshotMask?.removeFromSuperview()
        })
        adjustUI(withKeyboardFrame: latestKeyboardFrame, in: animationStyle.duration, animationCurve: .curveEaseInOut)
    }

    /// Captures a snapshot of `contentContainer` at its current (pre-expand) size and pins a
    /// clipping wrapper that follows the container's frame. Caller removes the wrapper on
    /// animation completion.
    private func installContentContainerSnapshotMaskForAITabExpandIfNeeded() -> UIView? {
        guard let coordinator = unifiedToggleInputCoordinator,
              coordinator.isAITabState,
              let target = viewCoordinator.contentContainer,
              let parent = target.superview,
              let snapshot = target.snapshotView(afterScreenUpdates: false) else { return nil }

        let oldSize = target.bounds.size

        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.clipsToBounds = true
        wrapper.isUserInteractionEnabled = false

        snapshot.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(snapshot)
        // Sit just above `target` — masks the WKWebView's model-layer snap, but stays below the
        // AI-tab header so the pill drop shadows that bleed into the content area aren't clipped.
        parent.insertSubview(wrapper, aboveSubview: target)

        NSLayoutConstraint.activate([
            wrapper.topAnchor.constraint(equalTo: target.topAnchor),
            wrapper.leadingAnchor.constraint(equalTo: target.leadingAnchor),
            wrapper.trailingAnchor.constraint(equalTo: target.trailingAnchor),
            wrapper.bottomAnchor.constraint(equalTo: target.bottomAnchor),

            snapshot.topAnchor.constraint(equalTo: wrapper.topAnchor),
            snapshot.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            snapshot.widthAnchor.constraint(equalToConstant: oldSize.width),
            snapshot.heightAnchor.constraint(equalToConstant: oldSize.height)
        ])
        parent.layoutIfNeeded()
        return wrapper
    }

    /// Visual end-state for `.aiTab(.expanded)`: container shown, chrome and content anchor
    /// configured for the AI-tab pose, card applied to expanded layout, content visibility
    /// updated. Whether this snaps or animates is decided by the caller (which wraps this in
    /// `UTIAnimationStyle.perform`).
    private func applyAITabExpandedPose() {
        viewCoordinator.showUnifiedToggleInput()
        guard let coordinator = unifiedToggleInputCoordinator else { return }
        let renderState = coordinator.computeRenderState()
        if coordinator.isAITabState {
            if coordinator.cardPosition == .bottom {
                viewCoordinator.setNavBarContainerBottomToKeyboard()
            }
            applyUnifiedInputChromeBackground(aiTabChromeBackgroundState(for: renderState))
            viewCoordinator.anchorContentContainerToInputTop()
        }
        coordinator.viewController.apply(renderState.viewConfig, animated: false)
        updateUnifiedInputContentVisibility(for: coordinator, renderState: renderState)
    }

    func handleShowOmnibarEditingIntent(height: CGFloat, pendingHeight: CGFloat?) {
        guard let coordinator = unifiedToggleInputCoordinator else { return }

        let omnibarPlaceholderWindowX = currentOmnibarPlaceholderWindowX()
        let omnibarPlaceholderColor = currentOmnibarPlaceholderColor()
        let utiPlaceholderColor = coordinator.viewController.defaultPlaceholderColor

        let isLogoToLogo = newTabPageViewController?.isShowingLogo == true
        let ntpStartCenterY = ntpLogoWindowCenterY()
        let isBottom = coordinator.cardPosition.isBottom

        viewCoordinator.showUnifiedToggleInputOmnibar(expandedHeight: height)
        viewCoordinator.suggestionTrayContainer.isHidden = true
        updateUnifiedInputContentVisibility(for: coordinator)

        if !isLogoToLogo {
            viewCoordinator.unifiedInputContentContainer.alpha = 0
        }

        if let omnibarPlaceholderWindowX {
            coordinator.viewController.alignPlaceholderHorizontally(toWindowX: omnibarPlaceholderWindowX)
        }

        // For logo-to-logo: place the UTI Logo at the NTP Logo's position, swap visibility
        // in one frame, then let the animation drive the UTI Logo to its final position.
        if isLogoToLogo,
           let ntpY = ntpStartCenterY,
           let utiY = coordinator.contentViewController.daxLogoManager.logoWindowCenterY {
            let bottomLogoOffset = isBottom ? Constants.bottomDaxLogoTransitionYOffset : 0
            let offset = ntpY - utiY + bottomLogoOffset
            let naturalOffset = coordinator.contentViewController.daxLogoManager.logoYOffset
            coordinator.contentViewController.daxLogoManager.setLogoYOffset(naturalOffset + offset)
            coordinator.contentViewController.view.layoutIfNeeded()

            coordinator.contentViewController.setLogoHidden(false)
            newTabPageViewController?.setLogoHidden(true)
            viewCoordinator.unifiedInputContentContainer.alpha = 1
        }

        let duration = Constants.omnibarTransitionDuration(isBottom: isBottom)
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
                // Reset top-bar handoff so the animation interpolates the logo from its
                // SWAP position to its natural position. Bottom bar keeps the offset and
                // lets the keyboard guide handle final positioning.
                if isLogoToLogo, !isBottom {
                    coordinator.contentViewController.daxLogoManager.setLogoYOffset(0)
                }
                self.viewCoordinator.superview.layoutIfNeeded()
                coordinator.pushContentInsets()
                if !isLogoToLogo {
                    self.viewCoordinator.unifiedInputContentContainer.alpha = 1
                }
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
