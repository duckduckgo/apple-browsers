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

    /// Window-space frame of the resting omnibar pill (the visible search-area container). Used by
    /// the bottom-position UTI to disguise its collapsed pose as the floating omnibar at hand-off.
    func currentOmnibarPillWindowFrame() -> CGRect? {
        guard let pill = viewCoordinator.omniBar.barView.searchContainer,
              pill.window != nil else { return nil }
        return pill.convert(pill.bounds, to: nil)
    }

    func currentOmnibarPlaceholderColor() -> UIColor? {
        guard let textField = viewCoordinator.omniBar.barView.textField,
              let attributed = textField.attributedPlaceholder,
              attributed.length > 0 else { return nil }
        return attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
    }

    func reconcileFloatingLayoutAfterUTIExit() {
        guard FloatingUILayoutPolicy.shouldHostOmnibarInFloatingToolbar(
            isFloatingUIEnabled: isFloatingUIEnabled,
            addressBarPosition: appSettings.currentAddressBarPosition,
            isUnifiedToggleInputVisible: false
        ),
              currentTab?.isAITab != true else {
            return
        }
        refreshViewsBasedOnAddressBarPosition(appSettings.currentAddressBarPosition)
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
        viewCoordinator.ensureNavContainerOwnershipForUnifiedToggleInputIfNeeded()
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
        viewCoordinator.ensureNavContainerOwnershipForUnifiedToggleInputIfNeeded()
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

        coordinator.contentViewController.refreshSuggestionsCaches()

        // Measure the resting omnibar pill + placeholder text before ownership transfer detaches the
        // omnibar from the toolbar (bottom floating), so the collapsed UTI pose and its text can
        // align to them with no hand-off snap. Measured live first; once detached it reads `nil`.
        let omnibarPillWindowFrame = coordinator.cardPosition.isBottom ? currentOmnibarPillWindowFrame() : nil
        coordinator.viewController.omnibarPillWindowFrame = omnibarPillWindowFrame
        let omnibarPlaceholderWindowX = currentOmnibarPlaceholderWindowX()
        // Cached so the symmetric dismiss can slide the text back onto the omnibar even though the
        // omnibar is no longer in the toolbar by then.
        coordinator.cachedOmnibarPlaceholderWindowX = omnibarPlaceholderWindowX

        viewCoordinator.ensureNavContainerOwnershipForUnifiedToggleInputIfNeeded()

        let omnibarPlaceholderColor = currentOmnibarPlaceholderColor()
        let utiPlaceholderColor = coordinator.viewController.defaultPlaceholderColor

        let isLogoToLogo = newTabPageViewController?.isShowingLogo == true
        // Favorites hand off seamlessly too: the embedded grid is already laid out where the NTP grid is,
        // so it slides in without the container's fade (which otherwise reads as a flash over the slide).
        let isFavoritesToFavorites = newTabPageViewController?.isShowingFavorites == true
        let isBottom = coordinator.cardPosition.isBottom

        viewCoordinator.showUnifiedToggleInputOmnibar(expandedHeight: height)
        viewCoordinator.suggestionTrayContainer.isHidden = true
        updateUnifiedInputContentVisibility(for: coordinator)

        // The container is now laid out at its editing-start frame; pin the collapsed card to the
        // measured pill so frame 0 of the focus animation matches the omnibar exactly (bottom only).
        if coordinator.cardPosition == .bottom {
            coordinator.viewController.captureOmnibarMatchedInsets()
        }

        if !isLogoToLogo {
            // Hide the real NTP favorites while focusing so the UTI's embedded favorites don't
            // cross-dissolve against them (mirrors the defocus hide-reveal). Revealed again on dismiss.
            newTabPageViewController?.setFavoritesHidden(true)
        }
        // Seamless handoffs (logo/favorites) show the content immediately; only other content fades in.
        let isSeamlessHandoff = isLogoToLogo || isFavoritesToFavorites
        viewCoordinator.unifiedInputContentContainer.alpha = isSeamlessHandoff ? 1 : 0

        if let omnibarPlaceholderWindowX {
            coordinator.viewController.alignVisibleTextLeadingEdge(toWindowX: omnibarPlaceholderWindowX)
        }

        if isLogoToLogo {
            // Hide the NTP logo during the seamless logo→logo focus so it doesn't double with the
            // focused SwiftUI logo; revealed again on dismiss. (Alpha is already 1 via the seamless
            // handoff above — the focused logo rests at the NTP anchor by construction, no manual swap.)
            newTabPageViewController?.setLogoHidden(true)
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
                self.viewCoordinator.superview.layoutIfNeeded()
                coordinator.pushContentInsets()
                if !isSeamlessHandoff {
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
            // Bottom floating: the omnibar is detached from the toolbar by now, so fall back to the
            // placeholder X captured at focus (live read is nil).
            let omnibarPlaceholderWindowX = currentOmnibarPlaceholderWindowX() ?? coordinator?.cachedOmnibarPlaceholderWindowX
            let omnibarPlaceholderColor = currentOmnibarPlaceholderColor()
            let utiPlaceholderColor = coordinator?.viewController.defaultPlaceholderColor
            let duration = Constants.omnibarTransitionDuration(isBottom: viewCoordinator.addressBarPosition.isBottom)
            let slideUTIText: () -> Void = { [weak coordinator] in
                guard let coordinator, let omnibarPlaceholderWindowX else { return }
                coordinator.viewController.alignVisibleTextLeadingEdge(toWindowX: omnibarPlaceholderWindowX)
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
        reconcileFloatingLayoutAfterUTIExit()
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
        viewCoordinator.ensureNavContainerOwnershipForUnifiedToggleInputIfNeeded()
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
