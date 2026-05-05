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
import UIKit

class MainViewCoordinator {

    enum StatusBackgroundPresentation: Equatable {
        case standard
        case omnibarEditing
        case aiTabSearchChromeHidden
        case aiTabChatChromeHidden
    }

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

    /// Owned so a subsequent show can cancel an in-flight dismiss and skip the stale completion.
    private var omnibarDismissAnimator: UIViewPropertyAnimator?
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
    private var standardStatusBackgroundColor: UIColor?
    private var statusBackgroundPresentation: StatusBackgroundPresentation = .standard
    private var statusBackgroundPresentationBeforeOmnibarEditing: StatusBackgroundPresentation?
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
        var navigationBarContainerBottomSafeAreaFloor: NSLayoutConstraint?
        var navigationBarContainerHeight: NSLayoutConstraint!
        var navigationBarContainerMinHeight: NSLayoutConstraint!
        var navigationBarCollectionViewSafeAreaBottom: NSLayoutConstraint!
        var toolbarBottom: NSLayoutConstraint!
        var toolbarHeightConstraint: NSLayoutConstraint!
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
    }

    func hideNavigationBarWithBottomPosition() {
        guard addressBarPosition.isBottom else { return }

        navigationBarContainer.isHidden = true

        setContentContainerBottomAnchorMode(.safeArea)
    }

    func showNavigationBarWithBottomPosition() {
        guard addressBarPosition.isBottom else { return }

        navigationBarContainer.isHidden = false

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
    }

    func setAddressBarBottomActive(_ active: Bool) {
        constraints.progressBarBottom?.isActive = active
        constraints.navigationBarContainerBottom.isActive = active
        constraints.topSlideContainerBottomToStatusBackgroundBottom.isActive = active
        constraints.statusBackgroundBottomToSafeAreaTop.isActive = active
    }

    func updateToolbarWithState(_ state: ToolbarContentState) {
        toolbarHandler.updateToolbarWithState(state)
    }

    // MARK: - AI Tab Native Input Layout

    func showUnifiedToggleInput() {
        setAddressBarTopActive(false)
        setAddressBarBottomActive(true)
        setNavBarContainerBottomToToolbar()
        constraints.navigationBarContainerHeight.constant = standardNavigationBarContainerHeight
        unifiedToggleInputContainer.isHidden = false
        unifiedToggleInputContainer.alpha = 1
        updateUnifiedToggleInputColors(inputView: nil)
        navigationBarContainer.bringSubviewToFront(unifiedToggleInputContainer)
    }

    @MainActor
    func showUnifiedToggleInputOmnibar(expandedHeight: CGFloat) {
        omnibarDismissAnimator?.stopAnimation(true)
        omnibarDismissAnimator = nil
        navigationBarCollectionView.layer.removeAllAnimations()
        unifiedToggleInputContainer.layer.removeAllAnimations()
        navigationBarCollectionView.isUserInteractionEnabled = false

        // Snap omnibar out, no fade — mirror of `finishUnifiedToggleInputOmnibarDismiss`.
        navigationBarCollectionView.alpha = 0
        unifiedToggleInputContainer.alpha = 1
        unifiedToggleInputContainer.isHidden = false
        unifiedToggleInputContainer.backgroundColor = .clear

        beginOmnibarStatusBackgroundPresentation()
        let inlineBackground = UIColor(designSystemColor: .panel)
        suggestionTrayContainer.backgroundColor = inlineBackground

        navigationBarContainer.backgroundColor = .clear

        navigationBarContainer.bringSubviewToFront(unifiedToggleInputContainer)

        constraints.navigationBarContainerHeight.constant = expandedHeight
        superview.layoutIfNeeded()
    }

    func updateUnifiedToggleInputColors(inputView: UIView?) {
        inputView?.backgroundColor = .clear
        unifiedToggleInputContainer.backgroundColor = .clear
    }

    @MainActor
    func restoreNavBarToToolbarForOmnibarInactive() {
        guard addressBarPosition.isBottom else { return }
        if !constraints.navigationBarContainerBottom.isActive {
            constraints.navigationBarContainerBottom.isActive = true
        }
        setNavBarContainerBottomToToolbar()
    }

    @MainActor
    func restoreNavBarToKeyboardForOmnibarActive() {
        guard addressBarPosition.isBottom else { return }
        if !constraints.navigationBarContainerBottom.isActive {
            constraints.navigationBarContainerBottom.isActive = true
        }
        setNavBarContainerBottomToKeyboard()
    }


    func hideUnifiedToggleInput() {
        unifiedToggleInputContainer.isHidden = true
        unifiedToggleInputContainer.backgroundColor = .clear
        setNavBarContainerBottomToToolbar()
        if addressBarPosition == .top {
            setAddressBarBottomActive(false)
            setAddressBarTopActive(true)
        }
        constraints.navigationBarContainerHeight.constant = standardNavigationBarContainerHeight
    }

    // MARK: - Omnibar Editing Layout

    @MainActor
    func hideUnifiedToggleInputOmnibar(additionalAnimations: (() -> Void)? = nil, completion: (() -> Void)? = nil) {
        omnibarDismissAnimator?.stopAnimation(true)

        let animator = UIViewPropertyAnimator(duration: MainViewController.Constants.omnibarTransitionDuration(isBottom: addressBarPosition.isBottom), curve: .easeOut) { [weak self] in
            self?.animateUnifiedToggleInputOmnibarDismissLayout()
            additionalAnimations?()
        }
        animator.addCompletion { [weak self] position in
            guard let self else { return }
            self.omnibarDismissAnimator = nil
            // Skip cleanup if the animation was superseded — otherwise it stomps fresh state from a concurrent show.
            guard position == .end else { return }
            self.finishUnifiedToggleInputOmnibarDismiss()
            completion?()
        }
        omnibarDismissAnimator = animator
        animator.startAnimation()
    }

    /// Call inside an animation context — alpha swap is deferred to completion to avoid a crossfade gap.
    func animateUnifiedToggleInputOmnibarDismissLayout() {
        if addressBarPosition.isBottom {
            setNavBarContainerBottomToToolbar()
        }
        constraints.navigationBarContainerHeight.constant = standardNavigationBarContainerHeight
        superview.layoutIfNeeded()
    }

    func finishUnifiedToggleInputOmnibarDismiss() {
        endOmnibarStatusBackgroundPresentation()
        navigationBarContainer.backgroundColor = nil
        suggestionTrayContainer.backgroundColor = .clear
        navigationBarCollectionView.isUserInteractionEnabled = true

        if isNavigationChromeHidden {
            navigationBarCollectionView.alpha = 0
            unifiedToggleInputContainer.isHidden = false
            unifiedToggleInputContainer.alpha = 1
        } else {
            // Snap omnibar in, no fade — crossfading would produce visible double-text mid-dismiss.
            navigationBarCollectionView.alpha = 1
            unifiedToggleInputContainer.isHidden = true
            unifiedToggleInputContainer.alpha = 1
        }
    }

    func setStandardStatusBackgroundColor(_ color: UIColor) {
        standardStatusBackgroundColor = color
        applyResolvedStatusBackgroundColor()
    }

    func setStatusBackgroundPresentation(_ presentation: StatusBackgroundPresentation) {
        statusBackgroundPresentation = presentation
        applyResolvedStatusBackgroundColor()
    }

    @MainActor
    func showUnifiedInputContent() {
        unifiedInputContentContainer.isHidden = false
        superview.insertSubview(statusBackground, belowSubview: unifiedInputContentContainer)
    }

    @MainActor
    func hideUnifiedInputContent() {
        unifiedInputContentContainer.isHidden = true
        superview.insertSubview(statusBackground, aboveSubview: topSlideContainer)
    }

    // MARK: - AI Tab Chrome

    func showAITabChrome() {
        cancelInFlightLayoutAnimations()
        showAIChatTabChatHeader()
        setNavigationChromeHidden(true)
    }

    private func cancelInFlightLayoutAnimations() {
        contentContainer.layer.removeAllAnimations()
        navigationBarContainer.layer.removeAllAnimations()
        statusBackground.layer.removeAllAnimations()
        superview.layer.removeAllAnimations()
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
            isNavigationChromeHidden = true
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
            isNavigationChromeHidden = false
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

    private func beginOmnibarStatusBackgroundPresentation() {
        if statusBackgroundPresentationBeforeOmnibarEditing == nil {
            statusBackgroundPresentationBeforeOmnibarEditing = statusBackgroundPresentation
        }
        setStatusBackgroundPresentation(.omnibarEditing)
    }

    private func endOmnibarStatusBackgroundPresentation() {
        guard statusBackgroundPresentation == .omnibarEditing else {
            statusBackgroundPresentationBeforeOmnibarEditing = nil
            return
        }
        let restoredPresentation = statusBackgroundPresentationBeforeOmnibarEditing ?? .standard
        statusBackgroundPresentationBeforeOmnibarEditing = nil
        setStatusBackgroundPresentation(restoredPresentation)
    }

    private func applyResolvedStatusBackgroundColor() {
        statusBackground.backgroundColor = resolvedStatusBackgroundColor()
    }

    private func resolvedStatusBackgroundColor() -> UIColor {
        switch statusBackgroundPresentation {
        case .standard:
            standardStatusBackgroundColor ?? UIColor(designSystemColor: .background)
        case .omnibarEditing, .aiTabSearchChromeHidden:
            UIColor(designSystemColor: .panel)
        case .aiTabChatChromeHidden:
            UIColor(singleUseColor: .duckAIContextualSheetBackground)
        }
    }

    func setNavBarContainerBottomToKeyboard() {
        constraints.navigationBarContainerBottom.isActive = false
        constraints.navigationBarContainerBottomSafeAreaFloor?.isActive = false

        constraints.navigationBarContainerBottom = navigationBarContainer.bottomAnchor
            .constraint(equalTo: superview.keyboardLayoutGuide.topAnchor)
        constraints.navigationBarContainerBottom.priority = .defaultHigh
        constraints.navigationBarContainerBottom.isActive = true

        // Prevent the nav bar from going below safe area when keyboard is hidden
        let safeAreaFloor = navigationBarContainer.bottomAnchor
            .constraint(lessThanOrEqualTo: superview.safeAreaLayoutGuide.bottomAnchor)
        safeAreaFloor.isActive = true
        constraints.navigationBarContainerBottomSafeAreaFloor = safeAreaFloor

        isNavBarContainerBottomKeyboardBased = true
    }

    // MARK: - Private Helpers

    private enum ContentContainerBottomAnchorMode: String {
        case toolbar
        case unifiedToggleInput
        case safeArea
    }

    func anchorContentContainerToInputTop() {
        setContentContainerBottomAnchorMode(.unifiedToggleInput)
    }

    private func setContentContainerBottomAnchorMode(_ mode: ContentContainerBottomAnchorMode) {
        constraints.contentContainerBottomToToolbarTop.isActive = mode == .toolbar
        constraints.contentContainerBottomToUnifiedToggleInputTop.isActive = mode == .unifiedToggleInput
        constraints.contentContainerBottomToSafeArea.isActive = mode == .safeArea
    }

    private func setNavBarContainerBottomToToolbar() {
        constraints.navigationBarContainerBottom.isActive = false
        constraints.navigationBarContainerBottomSafeAreaFloor?.isActive = false
        constraints.navigationBarContainerBottomSafeAreaFloor = nil
        constraints.navigationBarContainerBottom = navigationBarContainer.bottomAnchor
            .constraint(equalTo: toolbar.topAnchor)
        constraints.navigationBarContainerBottom.constant = 0
        constraints.navigationBarContainerBottom.isActive = true
        isNavBarContainerBottomKeyboardBased = false
    }

    /// Sets up nav bar for minimal chrome with bottom address bar:
    /// keyboard-based bottom, expandable height, screen-edge bottom limit.
    func applyMinimalChromeBottomLayout() {
        // Bottom: keyboard-based
        constraints.navigationBarContainerBottom.isActive = false
        constraints.navigationBarContainerBottomSafeAreaFloor?.isActive = false
        constraints.navigationBarContainerBottom = navigationBarContainer.bottomAnchor
            .constraint(equalTo: superview.keyboardLayoutGuide.topAnchor)
        constraints.navigationBarContainerBottom.priority = .defaultHigh
        constraints.navigationBarContainerBottom.isActive = true
        isNavBarContainerBottomKeyboardBased = true

        // Bottom limit: screen edge (extends past safe area for home indicator)
        let limit = navigationBarContainer.bottomAnchor
            .constraint(lessThanOrEqualTo: superview.bottomAnchor)
        limit.isActive = true
        constraints.navigationBarContainerBottomSafeAreaFloor = limit

        // Height: expandable
        constraints.navigationBarContainerHeight.isActive = false
        constraints.navigationBarContainerMinHeight.isActive = true
        constraints.navigationBarCollectionViewSafeAreaBottom.isActive = true
    }

    /// Resets nav bar from minimal chrome to default layout.
    func resetMinimalChromeLayout() {
        // Height: fixed
        constraints.navigationBarContainerHeight.isActive = true
        constraints.navigationBarContainerMinHeight.isActive = false
        constraints.navigationBarCollectionViewSafeAreaBottom.isActive = false

        // Bottom: toolbar-based, active only for bottom address bar
        constraints.navigationBarContainerBottom.isActive = false
        constraints.navigationBarContainerBottomSafeAreaFloor?.isActive = false
        constraints.navigationBarContainerBottomSafeAreaFloor = nil
        constraints.navigationBarContainerBottom = navigationBarContainer.bottomAnchor
            .constraint(equalTo: toolbar.topAnchor)
        constraints.navigationBarContainerBottom.isActive = addressBarPosition.isBottom
        isNavBarContainerBottomKeyboardBased = false
    }

    /// Switches to expandable height so the container can grow past the safe area
    /// while the collection view (content) stays above it.
    func setNavBarContainerExpandableHeight(_ expandable: Bool) {
        let wasExpandable = constraints.navigationBarContainerMinHeight.isActive
        constraints.navigationBarContainerHeight.isActive = !expandable
        constraints.navigationBarContainerMinHeight.isActive = expandable
        constraints.navigationBarCollectionViewSafeAreaBottom.isActive = expandable

        if !expandable && wasExpandable {
            setNavBarContainerBottomToToolbar()
        }
    }

}

extension MainViewCoordinator {

    private func decorate() {
        let theme = ThemeManager.shared.currentTheme
        superview.backgroundColor = theme.mainViewBackgroundColor
        logoText.tintColor = theme.ddgTextTintColor
    }

}
