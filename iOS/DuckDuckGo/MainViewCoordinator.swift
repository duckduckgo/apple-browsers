//
//  MainViewCoordinator.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import DesignResourcesKit
import os.log
import UIKit

private let utiLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "UTI-Constraint")

class MainViewCoordinator {

    weak var parentController: UIViewController?
    let superview: UIView

    var contentContainer: UIView!
    var logo: UIImageView!
    var logoContainer: UIView!
    var topSlideContainer: UIView!
    var logoText: UIImageView!
    var navigationBarContainer: MainViewFactory.NavigationBarContainer!
    var navigationBarCollectionView: MainViewFactory.NavigationBarCollectionView!
    var notificationBarContainer: UIView!
    var omniBar: OmniBar!
    var progress: ProgressView!
    var statusBackground: UIView!
    var suggestionTrayContainer: UIView!
    var tabBarContainer: UIView!
    var aiChatTabChatHeaderContainer: UIView!
    var unifiedToggleInputContainer: UIView!
    var unifiedInputContentContainer: UIView!
    var unifiedInputTopHeaderView: UnifiedInputTopHeaderView!
    var unifiedInputSectionTitleView: UnifiedInputSectionTitleView!
    var toolbar: UIToolbar!
    var toolbarSpacer: UIView!
    var toolbarBackButton: UIBarButtonItem { toolbarHandler.backButton }
    var toolbarFireBarButtonItem: UIBarButtonItem { toolbarHandler.fireBarButtonItem }
    var toolbarForwardButton: UIBarButtonItem { toolbarHandler.forwardButton }
    var toolbarTabSwitcherButton: UIBarButtonItem { toolbarHandler.tabSwitcherButton }
    var menuToolbarButton: UIBarButtonItem { toolbarHandler.browserMenuButton }
    var toolbarPasswordsButton: UIBarButtonItem { toolbarHandler.passwordsButton }
    var toolbarBookmarksButton: UIBarButtonItem { toolbarHandler.bookmarkButton }

    let constraints = Constraints()
    var toolbarHandler: ToolbarStateHandling!
    private var savedStatusBackgroundColor: UIColor?
    private var inlineEditingStatusBackgroundColor: UIColor?
    private(set) var isNavigationChromeHidden = false
    private var isNavBarContainerBottomKeyboardBased = false

    var isNavigationBarContainerBottomKeyboardBased: Bool {
        isNavBarContainerBottomKeyboardBased
    }

    // The default after creating the hiearchy is top
    var addressBarPosition: AddressBarPosition = .top

    var standardNavigationBarContainerHeight: CGFloat {
        omniBar.barView.expectedHeight
    }

    /// STOP - why are you instanciating this?
    init(parentController: UIViewController) {
        self.parentController = parentController
        self.superview = parentController.view
    }

    func hideToolbarSeparator() {
        toolbar.setShadowImage(UIImage(), forToolbarPosition: .any)
    }

    class Constraints {

        var navigationBarContainerTop: NSLayoutConstraint!
        var navigationBarContainerBottom: NSLayoutConstraint!
        var navigationBarContainerKeyboardHeight: NSLayoutConstraint!
        var navigationBarContainerHeight: NSLayoutConstraint!
        var toolbarBottom: NSLayoutConstraint!
        var contentContainerTop: NSLayoutConstraint!
        var tabBarContainerTop: NSLayoutConstraint!
        var progressBarTop: NSLayoutConstraint?
        var progressBarBottom: NSLayoutConstraint?
        var statusBackgroundToNavigationBarContainerBottom: NSLayoutConstraint!
        var statusBackgroundBottomToSafeAreaTop: NSLayoutConstraint!
        var contentContainerBottomToToolbarTop: NSLayoutConstraint!
        var contentContainerBottomToSafeArea: NSLayoutConstraint!
        var topSlideContainerBottomToNavigationBarBottom: NSLayoutConstraint!
        var topSlideContainerBottomToStatusBackgroundBottom: NSLayoutConstraint!
        var topSlideContainerTopToNavigationBar: NSLayoutConstraint!
        var topSlideContainerTopToStatusBackground: NSLayoutConstraint!
        var topSlideContainerHeight: NSLayoutConstraint!
        var toolbarSpacerHeight: NSLayoutConstraint!
        var contentContainerBottomToUnifiedToggleInputTop: NSLayoutConstraint!
        var contentContainerTopToSafeArea: NSLayoutConstraint!
        var contentContainerTopToAIChatHeader: NSLayoutConstraint!

    }

    func showTopSlideContainer() {
        if addressBarPosition == .top {
            constraints.topSlideContainerBottomToNavigationBarBottom.isActive = false
            constraints.topSlideContainerTopToNavigationBar.isActive = true
        } else {
            constraints.topSlideContainerBottomToStatusBackgroundBottom.isActive = false
            constraints.topSlideContainerTopToStatusBackground.isActive = true
        }
    }

    func hideTopSlideContainer() {
        if addressBarPosition == .top {
            constraints.topSlideContainerTopToNavigationBar.isActive = false
            constraints.topSlideContainerBottomToNavigationBarBottom.isActive = true
        } else {
            constraints.topSlideContainerTopToStatusBackground.isActive = false
            constraints.topSlideContainerBottomToStatusBackgroundBottom.isActive = true
        }
    }

    func moveAddressBarToPosition(_ position: AddressBarPosition) {
        guard position != addressBarPosition else { return }
        logUTIState("moveAddressBarToPosition:start from=\(String(describing: addressBarPosition)) to=\(String(describing: position))")
        hideTopSlideContainer()

        switch position {
        case .top:
            setAddressBarBottomActive(false)
            setAddressBarTopActive(true)
        case .bottom:
            setAddressBarTopActive(false)
            setAddressBarBottomActive(true)
        }

        addressBarPosition = position
        logUTIState("moveAddressBarToPosition:end to=\(String(describing: position))")
    }

    func hideNavigationBarWithBottomPosition() {
        guard addressBarPosition.isBottom else {
            return
        }

        // Hiding the container won't suffice as it still defines the contentContainer.bottomY through constraints
        navigationBarContainer.isHidden = true

        setContentContainerBottomAnchorMode(.safeArea)

    }

    func showNavigationBarWithBottomPosition() {
        guard addressBarPosition.isBottom else {
            return
        }

        navigationBarContainer.isHidden = false
        constraints.navigationBarContainerBottom.constant = 0

        if isNavigationChromeHidden {
            setContentContainerBottomAnchorMode(.unifiedToggleInput)
        } else {
            setContentContainerBottomAnchorMode(.toolbar)
        }
    }

    func setAddressBarTopActive(_ active: Bool) {
        constraints.navigationBarContainerTop.isActive = active
        constraints.progressBarTop?.isActive = active
        constraints.topSlideContainerBottomToNavigationBarBottom.isActive = active
        constraints.statusBackgroundToNavigationBarContainerBottom.isActive = active
        logUTIState("setAddressBarTopActive active=\(active)")
    }

    func setAddressBarBottomActive(_ active: Bool) {
        constraints.progressBarBottom?.isActive = active
        constraints.navigationBarContainerBottom.isActive = active
        constraints.topSlideContainerBottomToStatusBackgroundBottom.isActive = active
        constraints.statusBackgroundBottomToSafeAreaTop.isActive = active
        logUTIState("setAddressBarBottomActive active=\(active)")
    }

    func updateToolbarWithState(_ state: ToolbarContentState) {
        toolbarHandler.updateToolbarWithState(state)
    }

    // MARK: - AI Tab Native Input Layout

    func showUnifiedToggleInput(aboveKeyboard: Bool) {
        logUTIState("showUnifiedToggleInput:start aboveKeyboard=\(aboveKeyboard)")
        navigationBarCollectionView.layer.removeAllAnimations()
        unifiedToggleInputContainer.layer.removeAllAnimations()
        // AI tab always positions the nav bar at the bottom, regardless of user's bar setting.
        constraints.navigationBarContainerTop.isActive = false
        if !constraints.navigationBarContainerBottom.isActive {
            constraints.navigationBarContainerBottom.isActive = true
        }
        if aboveKeyboard {
            setNavBarContainerBottomToKeyboard()
        } else {
            setNavBarContainerBottomToToolbar()
        }
        constraints.navigationBarContainerHeight.constant = standardNavigationBarContainerHeight
        unifiedToggleInputContainer.isHidden = false
        unifiedToggleInputContainer.alpha = 1
        navigationBarContainer.bringSubviewToFront(unifiedToggleInputContainer)
        logUTIState("showUnifiedToggleInput:end aboveKeyboard=\(aboveKeyboard)")
    }

    @MainActor
    func restoreNavBarToToolbarForInlineInactive() {
        guard addressBarPosition.isBottom else { return }
        logUTIState("restoreNavBarToToolbarForInlineInactive")
        setNavBarContainerBottomToToolbar()
        logUTIState("restoreNavBarToToolbarForInlineInactive:done")
    }

    @MainActor
    func restoreNavBarToKeyboardForInlineActive() {
        guard addressBarPosition.isBottom else { return }
        logUTIState("restoreNavBarToKeyboardForInlineActive")
        setNavBarContainerBottomToKeyboard()
        logUTIState("restoreNavBarToKeyboardForInlineActive:done")
    }

    @MainActor
    func anchorUnifiedToggleInputToKeyboardPreservingHeight() {
        logUTIState("anchorUnifiedToggleInputToKeyboardPreservingHeight:start")
        navigationBarCollectionView.layer.removeAllAnimations()
        unifiedToggleInputContainer.layer.removeAllAnimations()
        constraints.navigationBarContainerTop.isActive = false
        if !constraints.navigationBarContainerBottom.isActive {
            constraints.navigationBarContainerBottom.isActive = true
        }
        setNavBarContainerBottomToKeyboard()
        unifiedToggleInputContainer.isHidden = false
        unifiedToggleInputContainer.alpha = 1
        navigationBarContainer.bringSubviewToFront(unifiedToggleInputContainer)
        logUTIState("anchorUnifiedToggleInputToKeyboardPreservingHeight:end")
    }

    func hideUnifiedToggleInput() {
        logUTIState("hideUnifiedToggleInput:start")
        unifiedToggleInputContainer.isHidden = true
        if addressBarPosition == .top {
            setNavBarContainerBottomToToolbar()
            constraints.navigationBarContainerBottom.isActive = false
            constraints.navigationBarContainerTop.isActive = true
        } else {
            setNavBarContainerBottomToToolbar()
        }
        constraints.navigationBarContainerHeight.constant = standardNavigationBarContainerHeight
        logUTIState("hideUnifiedToggleInput:end")
    }

    // MARK: - Inline Editing Layout

    @MainActor
    func showUnifiedToggleInputInline(expandedHeight: CGFloat) {
        logUTIState("showUnifiedToggleInputInline:start expandedHeight=\(expandedHeight)")
        navigationBarCollectionView.layer.removeAllAnimations()
        unifiedToggleInputContainer.layer.removeAllAnimations()
        navigationBarCollectionView.isUserInteractionEnabled = false
        unifiedToggleInputContainer.alpha = 0
        unifiedToggleInputContainer.isHidden = false
        unifiedToggleInputContainer.backgroundColor = .clear
        inlineEditingStatusBackgroundColor = statusBackground.backgroundColor
        let inlineBackground = UIColor(designSystemColor: .panel)
        statusBackground.backgroundColor = inlineBackground
        navigationBarContainer.backgroundColor = inlineBackground
        suggestionTrayContainer.backgroundColor = inlineBackground

        if addressBarPosition.isBottom {
            setNavBarContainerBottomToKeyboard()
        }

        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
            self.navigationBarCollectionView.alpha = 0
            self.unifiedToggleInputContainer.alpha = 1
            self.constraints.navigationBarContainerHeight.constant = expandedHeight
            self.superview.layoutIfNeeded()
        }
        navigationBarContainer.bringSubviewToFront(unifiedToggleInputContainer)
        logUTIState("showUnifiedToggleInputInline:end expandedHeight=\(expandedHeight)")
    }

    @MainActor
    func hideUnifiedToggleInputInline() {
        logUTIState("hideUnifiedToggleInputInline:start")
        if addressBarPosition.isBottom {
            setNavBarContainerBottomToToolbar()
        }

        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut) {
            self.navigationBarCollectionView.alpha = 1
            self.unifiedToggleInputContainer.alpha = 0
            self.constraints.navigationBarContainerHeight.constant = self.standardNavigationBarContainerHeight
            self.superview.layoutIfNeeded()
        } completion: { finished in
            guard finished else {
                self.logUTIState("hideUnifiedToggleInputInline:completionSkipped finished=false")
                return
            }
            if self.isNavigationChromeHidden {
                // Ignore stale inline-hide completion when AI chrome has taken over.
                self.navigationBarCollectionView.alpha = 0
                self.unifiedToggleInputContainer.isHidden = false
                self.unifiedToggleInputContainer.alpha = 1
                self.logUTIState("hideUnifiedToggleInputInline:completionSkipped aiChromeActive")
                return
            }
            self.unifiedToggleInputContainer.isHidden = true
            self.unifiedToggleInputContainer.alpha = 1
            self.navigationBarCollectionView.isUserInteractionEnabled = true
            self.statusBackground.backgroundColor = self.inlineEditingStatusBackgroundColor
            self.inlineEditingStatusBackgroundColor = nil
            self.navigationBarContainer.backgroundColor = nil
            self.suggestionTrayContainer.backgroundColor = .clear
            self.logUTIState("hideUnifiedToggleInputInline:completion")
        }
    }

    @MainActor
    func showTopHeaderView(title: String?, active: Bool = true) {
        guard addressBarPosition.isBottom else { return }
        unifiedInputTopHeaderView.configure(title: title)
        unifiedInputTopHeaderView.setActive(active)
        unifiedInputTopHeaderView.isHidden = false
    }

    @MainActor
    func updateTopHeaderTitle(_ title: String?) {
        guard addressBarPosition.isBottom else { return }
        unifiedInputTopHeaderView.configure(title: title)
    }

    @MainActor
    func hideTopHeaderView() {
        unifiedInputTopHeaderView.isHidden = true
    }

    @MainActor
    func showUnifiedInputSectionTitle(title: String?) {
        guard !addressBarPosition.isBottom, let title, !title.isEmpty else {
            unifiedInputSectionTitleView.isHidden = true
            return
        }
        unifiedInputSectionTitleView.configure(title: title)
        unifiedInputSectionTitleView.isHidden = false
    }

    @MainActor
    func hideUnifiedInputSectionTitle() {
        unifiedInputSectionTitleView.isHidden = true
    }

    @MainActor
    func showUnifiedInputContent() {
        unifiedInputContentContainer.isHidden = false
    }

    @MainActor
    func hideUnifiedInputContent() {
        unifiedInputContentContainer.isHidden = true
    }

    // MARK: - AI Tab Chrome

    func showAITabChrome() {
        showAIChatTabChatHeader()
        setNavigationChromeHidden(true)
    }

    func hideAITabChrome() {
        hideAIChatTabChatHeader()
        setNavigationChromeHidden(false)
    }

    func showAIChatTabChatHeader() {
        aiChatTabChatHeaderContainer.isHidden = false
        guard isNavigationChromeHidden else { return }
        constraints.contentContainerTop.isActive = false
        constraints.contentContainerTopToSafeArea.isActive = false
        constraints.contentContainerTopToAIChatHeader?.isActive = true
    }

    func hideAIChatTabChatHeader() {
        aiChatTabChatHeaderContainer.isHidden = true
        guard isNavigationChromeHidden else { return }
        constraints.contentContainerTop.isActive = false
        constraints.contentContainerTopToAIChatHeader?.isActive = false
        constraints.contentContainerTopToSafeArea.isActive = true
    }

    /// Hides the OmniBar collection view (not the container) so that the UTI inside the container
    /// remains visible when the AI tab chrome is shown. Uses alpha + interaction instead of isHidden
    /// so the pan gesture for tab swiping stays intact.
    func setNavigationChromeHidden(_ hidden: Bool) {
        if hidden {
            if !isNavigationChromeHidden {
                savedStatusBackgroundColor = statusBackground.backgroundColor
            }
            isNavigationChromeHidden = true
            statusBackground.backgroundColor = UIColor(singleUseColor: .duckAIContextualSheetBackground)
            navigationBarContainer.backgroundColor = .clear
            navigationBarCollectionView.alpha = 0
            navigationBarCollectionView.isUserInteractionEnabled = false
            constraints.contentContainerTop.isActive = false
            if constraints.contentContainerTopToAIChatHeader != nil, !aiChatTabChatHeaderContainer.isHidden {
                constraints.contentContainerTopToSafeArea.isActive = false
                constraints.contentContainerTopToAIChatHeader.isActive = true
            } else {
                constraints.contentContainerTopToSafeArea.isActive = true
            }
            if !addressBarPosition.isBottom {
                constraints.statusBackgroundToNavigationBarContainerBottom.isActive = false
                constraints.statusBackgroundBottomToSafeAreaTop.isActive = true
            }
            if navigationBarContainer.isHidden {
                setContentContainerBottomAnchorMode(.safeArea)
            } else {
                setContentContainerBottomAnchorMode(.unifiedToggleInput)
            }
        } else {
            if isNavigationChromeHidden {
                statusBackground.backgroundColor = savedStatusBackgroundColor
                savedStatusBackgroundColor = nil
            }
            isNavigationChromeHidden = false
            navigationBarContainer.backgroundColor = nil
            navigationBarCollectionView.alpha = 1
            navigationBarCollectionView.isUserInteractionEnabled = true
            constraints.contentContainerTopToSafeArea.isActive = false
            constraints.contentContainerTopToAIChatHeader?.isActive = false
            constraints.contentContainerTop.isActive = true
            if !addressBarPosition.isBottom {
                constraints.statusBackgroundBottomToSafeAreaTop.isActive = false
                constraints.statusBackgroundToNavigationBarContainerBottom.isActive = true
            } else {
                constraints.navigationBarContainerBottom.constant = 0
            }
            if navigationBarContainer.isHidden {
                setContentContainerBottomAnchorMode(.safeArea)
            } else {
                setContentContainerBottomAnchorMode(.toolbar)
            }
        }
    }

    // MARK: - Private Helpers

    private enum ContentContainerBottomAnchorMode: String {
        case toolbar
        case unifiedToggleInput
        case safeArea
    }

    private func setContentContainerBottomAnchorMode(_ mode: ContentContainerBottomAnchorMode) {
        constraints.contentContainerBottomToToolbarTop.isActive = mode == .toolbar
        constraints.contentContainerBottomToUnifiedToggleInputTop.isActive = mode == .unifiedToggleInput
        constraints.contentContainerBottomToSafeArea.isActive = mode == .safeArea
        logUTIState("setContentContainerBottomAnchorMode mode=\(mode.rawValue)")
    }

    private func setNavBarContainerBottomToKeyboard() {
        logUTIState("setNavBarContainerBottomToKeyboard:start")
        constraints.navigationBarContainerBottom.isActive = false
        constraints.navigationBarContainerBottom = navigationBarContainer.bottomAnchor
            .constraint(equalTo: superview.keyboardLayoutGuide.topAnchor)
        constraints.navigationBarContainerBottom.constant = 0
        constraints.navigationBarContainerBottom.isActive = true
        isNavBarContainerBottomKeyboardBased = true
        logUTIState("setNavBarContainerBottomToKeyboard:end")
    }

    private func setNavBarContainerBottomToToolbar() {
        logUTIState("setNavBarContainerBottomToToolbar:start")
        constraints.navigationBarContainerBottom.isActive = false
        constraints.navigationBarContainerBottom = navigationBarContainer.bottomAnchor
            .constraint(equalTo: toolbar.topAnchor)
        constraints.navigationBarContainerBottom.constant = 0
        constraints.navigationBarContainerBottom.isActive = true
        isNavBarContainerBottomKeyboardBased = false
        logUTIState("setNavBarContainerBottomToToolbar:end")
    }

    private func logUTIState(_ event: String) {
        let keyboardTop = superview.keyboardLayoutGuide.layoutFrame.minY
        let navTopActive = constraints.navigationBarContainerTop?.isActive ?? false
        let navBottomActive = constraints.navigationBarContainerBottom?.isActive ?? false
        let navBottomConstant = constraints.navigationBarContainerBottom?.constant ?? -9999
        let navHeightConstant = constraints.navigationBarContainerHeight?.constant ?? -9999
        let navMinY = navigationBarContainer?.frame.minY ?? -9999
        let navMaxY = navigationBarContainer?.frame.maxY ?? -9999
        let utiHidden = unifiedToggleInputContainer?.isHidden ?? true
        utiLog.debug(
            "UTILogging | \(event, privacy: .public) | addressBarPosition=\(String(describing: self.addressBarPosition), privacy: .public) keyboardBased=\(self.isNavBarContainerBottomKeyboardBased) navTopActive=\(navTopActive) navBottomActive=\(navBottomActive) navBottomConstant=\(navBottomConstant) navHeightConstant=\(navHeightConstant) navMinY=\(navMinY) navMaxY=\(navMaxY) keyboardTop=\(keyboardTop) utiHidden=\(utiHidden)"
        )
    }

}

extension MainViewCoordinator {

    private func decorate() {
        let theme = ThemeManager.shared.currentTheme
        superview.backgroundColor = theme.mainViewBackgroundColor
        logoText.tintColor = theme.ddgTextTintColor
    }

}
