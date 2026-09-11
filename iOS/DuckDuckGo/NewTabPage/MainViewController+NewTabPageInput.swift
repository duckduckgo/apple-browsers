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

    private var isAddressBarSuppressedByNewTabPage: Bool {
        guard newTabPageViewController?.hasInlineSearchInput == true else { return false }

        let isEditing = viewCoordinator.omniBar.isTextFieldEditing
            || unifiedToggleInputCoordinator?.isOmnibarSession == true
        return !isEditing && !isAddressBarHandOffInProgress
    }

    func updateAddressBarSuppressionForNewTabPage() {
        viewCoordinator.setUsesInlineNewTabPageInput(
            newTabPageViewController?.hasInlineSearchInput == true && unifiedToggleInputCoordinator != nil)
        setAddressBarSuppressed(isAddressBarSuppressedByNewTabPage)
    }

    func revealAddressBarForEditing() {
        guard viewCoordinator.isAddressBarSuppressed else { return }
        isAddressBarHandOffInProgress = true
        setAddressBarSuppressed(false)
        view.layoutIfNeeded()
        // Keep layout reconciliation from hiding the bar before becomeFirstResponder or the
        // unified-input intercept has established the session. Also recover if focus is refused.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isAddressBarHandOffInProgress = false
            updateAddressBarSuppressionForNewTabPage()
        }
    }

    private func setAddressBarSuppressed(_ suppressed: Bool) {
        guard viewCoordinator.isAddressBarSuppressed != suppressed else { return }
        viewCoordinator.setAddressBarSuppressed(suppressed)
        adjustNewTabPageSafeAreaInsets(for: appSettings.currentAddressBarPosition)
    }

    func adjustNewTabPageSafeAreaInsets(for addressBarPosition: AddressBarPosition) {
        let bottomInset = newTabPageBottomAdditionalSafeAreaInset(for: addressBarPosition)
        switch addressBarPosition {
        case .top:
            // Reserve space for visible floating chrome while allowing content to scroll behind it.
            let topInset = isFloatingTopContentBehindBar && !viewCoordinator.isAddressBarSuppressed && !viewCoordinator.usesInlineNewTabPageInput
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
        guard isFloatingTopContentBehindBar, !viewCoordinator.isAddressBarSuppressed, !viewCoordinator.usesInlineNewTabPageInput else { return }
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
        viewCoordinator.omniBar.beginEditing(animated: true, forTextEntryMode: textEntryMode)
    }
}
