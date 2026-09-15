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

    func updateAddressBarSuppressionForNewTabPage() {
        let hasInlineInput = newTabPageViewController?.hasInlineSearchInput == true
        let presentation = NewTabPageInputPresentation.resolve(
            hasInlineInput: hasInlineInput,
            usesUnifiedInput: unifiedToggleInputCoordinator != nil,
            isLegacyInputEditing: hasInlineInput && viewCoordinator.omniBar.isTextFieldEditing,
            isUnifiedInputEditing: unifiedToggleInputCoordinator?.isOmnibarSession == true,
            isHandingOff: isAddressBarHandOffInProgress)
        guard viewCoordinator.newTabPageInputPresentation != presentation else { return }
        viewCoordinator.setNewTabPageInputPresentation(presentation)
        (newTabPageViewController as? NewTabPageInputTransitionSource)?.setSearchInputEditing(
            !presentation.hidesNavigationContainer)
        adjustNewTabPageSafeAreaInsets(for: appSettings.currentAddressBarPosition)
    }

    func revealAddressBarForEditing() {
        guard viewCoordinator.newTabPageInputPresentation.hidesNavigationContainer else { return }
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
            omnibarHeight: viewCoordinator.omniBar.barView.expectedHeight
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
            openAIChatFromAddressBar(prefilledText: nil)
            return
        }
        revealAddressBarForEditing()
        defer { finishNewTabPageInputHandoff() }
        viewCoordinator.omniBar.beginEditing(animated: true, forTextEntryMode: textEntryMode)
    }
}
