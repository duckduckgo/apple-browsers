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
        let hasInlineInput = newTabPageViewController?.hasInlineSearchInput == true
        return NewTabPageInputPresentation.resolve(
            hasInlineInput: hasInlineInput,
            usesUnifiedInput: unifiedToggleInputCoordinator != nil && !isIPadFullTabChatInput,
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
        defer {
            isPerformingOnboardingInputHandoff = wasPerformingHandoff
            updateAddressBarSuppressionForNewTabPage()
        }
        dismissDialog()
        activateInput()
        return true
    }

    func updateAddressBarSuppressionForNewTabPage() {
        let presentation = newTabPageInputPresentation
        // Update even when chrome is unchanged: the shared controller may now belong to another tab.
        updateUnifiedInputContentPresentation(presentation: presentation, isOnAITab: currentTab?.isAITab == true)
        guard viewCoordinator.newTabPageInputPresentation != presentation else { return }
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

extension MainViewController {

    var redesignedNewTabPage: RedesignedNewTabPageViewController? {
        newTabPageViewController as? RedesignedNewTabPageViewController
    }

    var redesignedNewTabPageSlotIfHosted: NewTabPageInputSlotViewController? {
        guard let page = redesignedNewTabPage, page.parent === self else { return nil }
        return page.inputSlot
    }

    func refreshUnifiedToggleInputPlacement() {
        guard let coordinator = unifiedToggleInputCoordinator, !isIPadFullTabChatInput else { return }
        switch UnifiedToggleInputPlacement.resolve(slot: redesignedNewTabPageSlotIfHosted,
                                                   isSessionActive: coordinator.isActive,
                                                   restingSurface: coordinator.restingSurface) {
        case .keepCurrent:
            return
        case .newTabPage(let slot):
            parkUnifiedToggleInput(in: slot, coordinator: coordinator)
        case .chrome:
            placeUnifiedToggleInputInChrome()
        }
    }

    /// Moves the input back to the chrome. Runs strictly before focus, because moving a first responder resigns it.
    func placeUnifiedToggleInputInChrome() {
        guard let coordinator = unifiedToggleInputCoordinator else { return }
        let inputViewController = coordinator.viewController
        if inputViewController.parent !== self {
            inputViewController.detachFromParent()
            installUnifiedToggleInputViewController(inputViewController)
        }
        coordinator.unparkFromNewTabPage()
    }

    func resizeParkedNewTabPageInputSlot() {
        guard unifiedToggleInputCoordinator?.isParkedOnNewTabPage == true else { return }
        resizeNewTabPageInputSlot()
    }

    func resizeNewTabPageInputSlotForReturn() {
        resizeNewTabPageInputSlot()?.view.layoutIfNeeded()
    }

    /// Returns true when focus on the parked input is refused and an omnibar session is started instead.
    func refuseRestingFocusAndActivate() -> Bool {
        guard unifiedToggleInputCoordinator?.isParkedOnNewTabPage == true else { return false }
        scheduleRestingNewTabPageActivation()
        return true
    }

    /// The single way a resting pick (tap, mode, attachment) starts a session.
    func scheduleRestingNewTabPageActivation() {
        // The resting card never edits in place: the session runs in the chrome. The text control must finish
        // refusing focus before the input is moved there, and a mode pick arrives inside the toggle's own
        // animation, where starting the travel would animate its starting pose too.
        DispatchQueue.main.async { [weak self] in
            self?.activateRestingNewTabPageInput()
        }
    }

    private func activateRestingNewTabPageInput() {
        guard let coordinator = unifiedToggleInputCoordinator, coordinator.isParkedOnNewTabPage,
              let page = newTabPageViewController else { return }
        newTabPageDidRequestSearch(page, textEntryMode: coordinator.inputMode)
    }

    private func parkUnifiedToggleInput(in slot: NewTabPageInputSlotViewController, coordinator: UnifiedToggleInputCoordinator) {
        let inputViewController = coordinator.viewController
        guard !(coordinator.isParkedOnNewTabPage && slot.parkedViewController === inputViewController) else { return }
        let mode = tabManager.currentTabsModel.currentTab.map { initialOmnibarToggleMode(for: $0) } ?? .search
        coordinator.parkOnNewTabPage(inputMode: mode)
        slot.park(inputViewController)
        resizeNewTabPageInputSlot()
    }

    @discardableResult
    private func resizeNewTabPageInputSlot() -> RedesignedNewTabPageViewController? {
        guard let coordinator = unifiedToggleInputCoordinator,
              let page = redesignedNewTabPage,
              let slot = page.inputSlot else { return nil }
        slot.setHeight(restingFittingHeight(of: coordinator.viewController.view, in: slot))
        return page
    }

    private func restingFittingHeight(of inputView: UIView, in slot: NewTabPageInputSlotViewController) -> CGFloat {
        let slotWidth = slot.view.bounds.width
        let width = slotWidth > 0 ? slotWidth : view.bounds.width
        return inputView.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                 withHorizontalFittingPriority: .required,
                                                 verticalFittingPriority: .fittingSizeLevel).height
    }
}

/// Where the UTI view controller is parented.
enum UnifiedToggleInputPlacement: Equatable {
    case chrome
    case newTabPage(NewTabPageInputSlotViewController)
    /// A return travel owns the card until it lands or is abandoned.
    case keepCurrent

    /// `slot` is non-nil only while the redesigned New Tab Page is hosted by the main view controller.
    static func resolve(slot: NewTabPageInputSlotViewController?,
                        isSessionActive: Bool,
                        restingSurface: UTIRestingSurface) -> UnifiedToggleInputPlacement {
        if isSessionActive, restingSurface == .returningToNewTabPage {
            return .keepCurrent
        }
        if !isSessionActive, let slot {
            return .newTabPage(slot)
        }
        return .chrome
    }
}

extension UIViewController {

    func detachFromParent() {
        willMove(toParent: nil)
        view.removeFromSuperview()
        removeFromParent()
    }
}
