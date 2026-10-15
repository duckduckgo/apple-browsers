//
//  MainViewController+NewTabPageInput.swift
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

import AIChat
import UIKit

extension MainViewController {

    var newTabPageInputPresentation: NewTabPageInputPresentation {
        // Large width iPad keeps its bar and buttons on the New Tab Page; only the search field hides.
        // Compact width iPad falls back to the iPhone presentation.
        guard !AppWidthObserver.shared.isLargeWidth else { return .browser }
        let hasInlineInput = newTabPageViewController?.hasInlineSearchInput == true
        return NewTabPageInputPresentation.resolve(
            hasInlineInput: hasInlineInput,
            usesUnifiedInput: unifiedToggleInputCoordinator != nil,
            isLegacyInputEditing: hasInlineInput && viewCoordinator.omniBar.isTextFieldEditing,
            isUnifiedInputEditing: unifiedToggleInputCoordinator?.isOmnibarSession == true,
            isHandingOff: isAddressBarHandOffInProgress || isPerformingOnboardingInputHandoff,
            isDismissing: viewCoordinator.isInlineInputDismissInProgress,
            isPresentingOnboardingDialog: newTabPageViewController?.isPresentingOnboardingDialog == true)
    }

    func newTabPageDidChangeOnboardingPresentation(_ controller: any NewTabPage) {
        guard controller === newTabPageViewController else { return }
        updateAddressBarSuppressionForNewTabPage()
        controller.refreshContextualOnboardingDialogLayout()
    }

    /// Dismisses the onboarding dialog and activates inline input without the resting-to-focused animation.
    func performOnboardingInputHandoff(for page: any NewTabPage,
                                       dismissDialog: () -> Void,
                                       activateInput: () -> Void) -> Bool {
        guard page === newTabPageViewController,
              page.parent === self,
              page.hasInlineSearchInput,
              let coordinator = unifiedToggleInputCoordinator,
              !coordinator.isOmnibarSession,
              currentTab?.isAITab != true else { return false }

        // Keep editing chrome selected while dismissal restores the modules so they cannot flash before focus.
        let wasPerformingHandoff = isPerformingOnboardingInputHandoff
        isPerformingOnboardingInputHandoff = true
        restingNewTabPageSnapshot = nil
        defer {
            isPerformingOnboardingInputHandoff = wasPerformingHandoff
            updateAddressBarSuppressionForNewTabPage()
        }
        dismissDialog()
        activateInput()
        return true
    }

    func updateAddressBarSuppressionForNewTabPage() {
        updatePadNewTabPageSearchFieldVisibility()
        let presentation = newTabPageInputPresentation
        // Update even when chrome is unchanged: the shared controller may now belong to another tab.
        updateUnifiedInputContentPresentation(presentation: presentation, isOnAITab: currentTab?.isAITab == true)
        guard viewCoordinator.newTabPageInputPresentation != presentation else { return }
        if presentation.hidesNavigationContainer || presentation.transition != .inlineInput {
            restingNewTabPageSnapshot = nil
        }
        let transitionSource = newTabPageViewController as? NewTabPageInputTransitionSource
        if !presentation.hidesNavigationContainer {
            // Capture the scrolled resting layout before chrome changes the page's viewport.
            transitionSource?.setSearchInputEditing(true)
        }
        viewCoordinator.setNewTabPageInputPresentation(presentation)
        adjustNewTabPageSafeAreaInsets(for: appSettings.currentAddressBarPosition)
        if presentation.hidesNavigationContainer {
            // Restore scrolling only after the resting chrome and safe area have settled.
            view.layoutIfNeeded()
            transitionSource?.setSearchInputEditing(false)
        }
    }

    /// Hides the large width iPad address bar search field while the New Tab Page's own search input is on screen.
    func updatePadNewTabPageSearchFieldVisibility(animated: Bool = false) {
        guard isPad else { return }
        let usesPadLayout = AppWidthObserver.shared.isLargeWidth
        let inputSource = newTabPageViewController as? NewTabPageInputTransitionSource
        let isEditing = viewCoordinator.omniBar.isTextFieldEditing
        // Compact width restores both, so a resize mid-session leaves nothing hidden for the iPhone path.
        inputSource?.setInlineInputHidden(usesPadLayout && isEditing, animated: animated)
        // Measure after the inline input is restored, so its frame reflects the resting layout.
        newTabPageViewController?.view.layoutIfNeeded()
        let hidesSearchField = usesPadLayout
            && newTabPageViewController?.parent === self
            && newTabPageViewController?.hasInlineSearchInput == true
            && !isEditing
            && inputSource?.isSearchInputVisible == true
        let searchField = viewCoordinator.omniBar.barView.searchContainer
        let targetAlpha: CGFloat = hidesSearchField ? 0 : 1
        searchField?.isUserInteractionEnabled = !hidesSearchField
        guard searchField?.alpha != targetAlpha else { return }
        guard animated else {
            searchField?.alpha = targetAlpha
            return
        }
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
            searchField?.alpha = targetAlpha
        }
    }

    func revealAddressBarForEditing() {
        guard viewCoordinator.newTabPageInputPresentation.hidesNavigationContainer else { return }
        if unifiedToggleInputCoordinator != nil {
            captureRestingNewTabPageSnapshot()
        }
        isAddressBarHandOffInProgress = true
        updateAddressBarSuppressionForNewTabPage()
        view.layoutIfNeeded()
    }

    func finishNewTabPageInputHandoff() {
        guard isAddressBarHandOffInProgress else { return }
        isAddressBarHandOffInProgress = false
        updateAddressBarSuppressionForNewTabPage()
    }

    func adjustNewTabPageSafeAreaInsets(for addressBarPosition: AddressBarPosition) {
        let bottomInset = newTabPageBottomAdditionalSafeAreaInset(for: addressBarPosition)
        switch addressBarPosition {
        case .top:
            // Reserve space for visible floating chrome while allowing content to scroll behind it.
            let topInset = isFloatingTopContentBehindBar && viewCoordinator.newTabPageInputPresentation.reservesAddressBarSpace
                ? viewCoordinator.omniBar.barView.expectedHeight * currentBarsVisibility
                : 0
            newTabPageViewController?.additionalSafeAreaInsets = .init(top: topInset, left: 0, bottom: bottomInset, right: 0)
        case .bottom:
            newTabPageViewController?.additionalSafeAreaInsets = .init(top: 0, left: 0, bottom: bottomInset, right: 0)
        }
    }

    func newTabPageBottomAdditionalSafeAreaInset(for addressBarPosition: AddressBarPosition) -> CGFloat {
        FloatingUILayoutPolicy.newTabPageBottomAdditionalSafeAreaInset(
            isFloatingUIEnabled: isFloatingUIEnabled,
            addressBarPosition: addressBarPosition,
            floatingBottomObscuredHeight: floatingWebViewBottomObscuredHeight(for: 1),
            safeAreaBottom: view.safeAreaInsets.bottom,
            omnibarHeight: viewCoordinator.omniBar.barView.expectedHeight,
            reservesAddressBarSpace: viewCoordinator.newTabPageInputPresentation.reservesAddressBarSpace
        )
    }

    /// Scales the floating-top NTP content inset with chrome visibility so it collapses to zero in
    /// lock-step as the bar hides, matching the web view's underflow behaviour. No-op outside
    /// floating top mode.
    func updateFloatingTopNewTabPageInset(for barsVisibilityPercent: CGFloat) {
        guard isFloatingTopContentBehindBar, viewCoordinator.newTabPageInputPresentation.reservesAddressBarSpace else { return }
        newTabPageViewController?.additionalSafeAreaInsets.top = viewCoordinator.omniBar.barView.expectedHeight * barsVisibilityPercent
    }

    func newTabPageDidRequestVoiceSearch(_ controller: any NewTabPage, textEntryMode: TextEntryMode) {
        handleVoiceSearchOpenRequest(preferredTarget: textEntryMode == .aiChat ? .AIChat : .SERP)
    }

    func newTabPageDidRequestSearch(_ controller: any NewTabPage, textEntryMode: TextEntryMode) {
        if textEntryMode == .aiChat, !aiChatSettings.isAIChatSearchInputUserSettingsEnabled {
            // Unified input locks to search when the toggle is disabled.
            recordNewTabPageSessionAction { $0.tapDuckaiButton() }
            openAIChatFromAddressBar(prefilledText: nil)
            return
        }
        // beginEditing treats focus as programmatic, so record the originating tap here.
        onExperimentalAddressBarTapped()
        revealAddressBarForEditing()
        defer { finishNewTabPageInputHandoff() }
        // The inline field must not depend on the hidden legacy text field becoming first responder.
        if controller.hasInlineSearchInput,
           activateFromOmnibarIfNeeded(currentText: nil, tapped: false, textEntryMode: textEntryMode,
                                      isRequestValid: { true }, onFocus: nil) == .intercept {
            return
        }
        viewCoordinator.omniBar.beginEditing(animated: true, forTextEntryMode: textEntryMode)
    }
}
