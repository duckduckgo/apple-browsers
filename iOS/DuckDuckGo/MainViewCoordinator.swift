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
    var focusedStateBackground: UIView!
    var suggestionTrayContainer: UIView!
    var tabBarContainer: UIView!
    var aiChatTabChatHeaderContainer: UIView!
    var unifiedToggleInputContainer: UIView!
    var aiTabCollapsedTopSeparator: UIView!
    private var aiTabCollapsedTopSeparatorLogicallyVisible = false
    var unifiedInputContentContainer: UIView!
    /// Owned so a subsequent show can cancel an in-flight dismiss and skip the stale completion.
    private var omnibarDismissAnimator: UIViewPropertyAnimator?
    var toolbar: BrowserToolbarView!
    var toolbarSpacer: UIView!
    var toolbarBackButton: BrowserChromeButton { toolbarHandler.backButton }
    var toolbarFireButton: BrowserChromeButton { toolbarHandler.fireButton }
    var toolbarForwardButton: BrowserChromeButton { toolbarHandler.forwardButton }
    var toolbarTabSwitcherView: UIView { toolbarHandler.tabSwitcherView }
    var menuToolbarButton: BrowserChromeButton { toolbarHandler.browserMenuButton }
    var toolbarPasswordsButton: BrowserChromeButton { toolbarHandler.passwordsButton }
    var toolbarBookmarksButton: BrowserChromeButton { toolbarHandler.bookmarkButton }

    let constraints = Constraints()
    var toolbarHandler: ToolbarStateHandling!
    private var standardStatusBackgroundColor: UIColor?
    private var statusBackgroundPresentation: StatusBackgroundPresentation = .standard
    private var statusBackgroundPresentationBeforeOmnibarEditing: StatusBackgroundPresentation?
    private(set) var isNavigationChromeHidden = false
    private var isNavBarContainerBottomKeyboardBased = false
    private(set) var isOmnibarInToolbar = false
    private var isFloatingUIEnabled = false
    private(set) var isInMinimalChromeLayout = false

    var isNavigationBarContainerBottomKeyboardBased: Bool {
        isNavBarContainerBottomKeyboardBased
    }

    var isUnifiedToggleInputVisible: Bool {
        !(unifiedToggleInputContainer?.isHidden ?? true) && (unifiedToggleInputContainer?.alpha ?? 0) > 0.01
    }

    func setFloatingUIEnabled(_ enabled: Bool) {
        isFloatingUIEnabled = enabled
    }

    func setMinimalChromeLayout(_ enabled: Bool) {
        isInMinimalChromeLayout = enabled
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
        // `UIToolbar` separator/shadow removed with custom `BrowserToolbarView`.
    }

    class Constraints {

        var navigationBarContainerTop: NSLayoutConstraint!
        var navigationBarContainerBottom: NSLayoutConstraint!
        var navigationBarContainerBottomSafeAreaFloor: NSLayoutConstraint?
        var navigationBarContainerHeight: NSLayoutConstraint!
        var navigationBarContainerMinHeight: NSLayoutConstraint!
        var navigationBarCollectionViewSafeAreaBottom: NSLayoutConstraint!
        var toolbarBottom: NSLayoutConstraint!
        var toolbarHeight: NSLayoutConstraint!
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
        var contentContainerTopToSuperview: NSLayoutConstraint!
        var contentContainerTopToAIChatHeader: NSLayoutConstraint!

    }

    func updateToolbarLayoutForAddressBarPosition(_ position: AddressBarPosition) {
        addressBarPosition = position
        applyContentContainerTopAnchorForCurrentState()
        guard isFloatingUIEnabled else {
            toolbar.setOmnibarView(nil, height: 0)
            constraints.toolbarHeight.constant = BrowserToolbarView.totalHeight(withOmnibarHeight: 0, isFloating: isFloatingUIEnabled)
            navigationBarContainer.isHidden = false
            navigationBarContainer.alpha = 1
            navigationBarContainer.isUserInteractionEnabled = true
            if position.isBottom {
                setContentContainerBottomAnchorMode(.toolbar)
            }
            isOmnibarInToolbar = false
            return
        }

        navigationBarContainer.backgroundColor = .clear

        switch position {
        case .top:
            toolbar.setOmnibarView(nil, height: 0)
            constraints.toolbarHeight.constant = BrowserToolbarView.totalHeight(withOmnibarHeight: 0, isFloating: isFloatingUIEnabled)
            omniBar.barView.makeGlass()
            navigationBarContainer.isHidden = false
            navigationBarContainer.alpha = 1
            navigationBarContainer.isUserInteractionEnabled = true
            // Span content full-bleed to the main view bottom (behind the floating toolbar) so the
            // web scroll edge sits at the screen bottom and content doesn't move when the bars hide.
            setContentContainerBottomAnchorMode(preferredBottomContentAnchorModeForVisibleChrome())
            isOmnibarInToolbar = false
        case .bottom:
            guard FloatingUILayoutPolicy.shouldHostOmnibarInFloatingToolbar(
                isFloatingUIEnabled: isFloatingUIEnabled,
                addressBarPosition: position,
                isUnifiedToggleInputVisible: isUnifiedToggleInputVisible,
                isMinimalChromeLayout: isInMinimalChromeLayout
            ) else {
                toolbar.setOmnibarView(nil, height: 0)
                constraints.toolbarHeight.constant = BrowserToolbarView.totalHeight(withOmnibarHeight: 0, isFloating: isFloatingUIEnabled)
                navigationBarContainer.isHidden = false
                navigationBarContainer.alpha = 1
                navigationBarContainer.isUserInteractionEnabled = true
                isOmnibarInToolbar = false
                return
            }
            toolbar.setOmnibarView(omniBar.barView, height: omniBar.barView.expectedHeight)
            constraints.toolbarHeight.constant = BrowserToolbarView.totalHeight(withOmnibarHeight: omniBar.barView.expectedHeight, isFloating: isFloatingUIEnabled)
            omniBar.barView.makeOpaque()
            omniBar.barView.alpha = 1
            omniBar.barView.isUserInteractionEnabled = true
            navigationBarContainer.isHidden = true
            navigationBarContainer.alpha = 0
            navigationBarContainer.isUserInteractionEnabled = false
            superview.bringSubviewToFront(toolbar)
            setContentContainerBottomAnchorMode(preferredBottomContentAnchorModeForVisibleChrome())
            isOmnibarInToolbar = true
        }
    }

    func ensureBottomOmnibarAttachedToToolbarIfNeeded() {
        guard FloatingUILayoutPolicy.shouldHostOmnibarInFloatingToolbar(
            isFloatingUIEnabled: isFloatingUIEnabled,
            addressBarPosition: addressBarPosition,
            isUnifiedToggleInputVisible: isUnifiedToggleInputVisible,
            isMinimalChromeLayout: isInMinimalChromeLayout
        ) else { return }
        guard !toolbar.isHostingOmnibarView(omniBar.barView) else { return }

        toolbar.setOmnibarView(omniBar.barView, height: omniBar.barView.expectedHeight)
        constraints.toolbarHeight.constant = BrowserToolbarView.totalHeight(withOmnibarHeight: omniBar.barView.expectedHeight, isFloating: isFloatingUIEnabled)
        omniBar.barView.alpha = 1
        omniBar.barView.isUserInteractionEnabled = true
        navigationBarContainer.isHidden = true
        navigationBarContainer.alpha = 0
        navigationBarContainer.isUserInteractionEnabled = false
        superview.bringSubviewToFront(toolbar)
        isOmnibarInToolbar = true
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
            if isFloatingUIEnabled {
                omniBar.barView.makeGlass()
            }
            setAddressBarBottomActive(false)
            setAddressBarTopActive(true)
        case .bottom:
            if isFloatingUIEnabled {
                omniBar.barView.makeOpaque()
            }
            setAddressBarTopActive(false)
            setAddressBarBottomActive(true)
        }

        addressBarPosition = position
        applyContentContainerTopAnchorForCurrentState()
    }

    func hideNavigationBarWithBottomPosition() {
        guard addressBarPosition.isBottom else { return }

        if isUnifiedToggleInputVisible {
            navigationBarContainer.isHidden = false
            setContentContainerBottomAnchorMode(.unifiedToggleInput)
            return
        }

        if isFloatingUIEnabled, isOmnibarInToolbar {
            // Keep the bottom omnibar attached while hiding chrome.
            // Visibility is handled via alpha/offset animations in MainViewController.
        } else {
            navigationBarContainer.isHidden = true
        }

        setContentContainerBottomAnchorMode(.safeArea)
    }

    func showNavigationBarWithBottomPosition() {
        guard addressBarPosition.isBottom else { return }

        if isUnifiedToggleInputVisible {
            navigationBarContainer.isHidden = false
            navigationBarContainer.alpha = 1
            navigationBarContainer.isUserInteractionEnabled = true
            setContentContainerBottomAnchorMode(.unifiedToggleInput)
            return
        }

        if isFloatingUIEnabled, isOmnibarInToolbar {
            ensureBottomOmnibarAttachedToToolbarIfNeeded()
        } else {
            navigationBarContainer.isHidden = false
            navigationBarContainer.alpha = 1
            navigationBarContainer.isUserInteractionEnabled = true
        }

        if isNavigationChromeHidden {
            setContentContainerBottomAnchorMode(.unifiedToggleInput)
        } else {
            setContentContainerBottomAnchorMode(preferredBottomContentAnchorModeForVisibleChrome())
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

    func ensureNavContainerOwnershipForUnifiedToggleInputIfNeeded() {
        guard isFloatingUIEnabled, addressBarPosition.isBottom else { return }
        returnOmnibarToNavigationContainerIfNeeded()
    }

    /// Detaches the bottom omnibar from the toolbar back into the nav container (used by minimal
    /// chrome, where the toolbar is hidden, and the unified toggle input flow).
    func returnOmnibarToNavigationContainerIfNeeded() {
        guard isOmnibarInToolbar else { return }
        toolbar.setOmnibarView(nil, height: 0)
        constraints.toolbarHeight.constant = BrowserToolbarView.totalHeight(withOmnibarHeight: 0, isFloating: isFloatingUIEnabled)
        navigationBarContainer.isHidden = false
        navigationBarContainer.alpha = 1
        navigationBarContainer.isUserInteractionEnabled = true
        isOmnibarInToolbar = false
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
        showFocusedStateBackground()

        navigationBarContainer.backgroundColor = .clear

        navigationBarContainer.bringSubviewToFront(unifiedToggleInputContainer)

        if addressBarPosition == .top {
            setAddressBarBottomActive(false)
            setNavBarContainerBottomToToolbar(active: false)
            setAddressBarTopActive(true)
        }
        constraints.navigationBarContainerHeight.constant = expandedHeight
        superview.layoutIfNeeded()
    }

    func updateUnifiedToggleInputColors(inputView: UIView?) {
        inputView?.backgroundColor = .clear
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
        // Hidden toolbars keep their 49pt frame in auto layout — pinning the UTI above an
        // invisible toolbar (landscape minimal chrome) would leave a toolbar-sized gap, so
        // fall back to the safe-area floor when there's no visible toolbar to respect.
        let floor: NSLayoutYAxisAnchor? = toolbar.isHidden ? nil : toolbar.topAnchor
        setNavBarContainerBottomToKeyboard(floorAnchor: floor)
    }


    func hideUnifiedToggleInput() {
        unifiedToggleInputContainer.isHidden = true
        setAITabCollapsedTopSeparatorVisible(false)
        unifiedToggleInputContainer.backgroundColor = .clear
        hideFocusedStateBackground()
        setNavBarContainerBottomToToolbar()
        if addressBarPosition == .top {
            setAddressBarBottomActive(false)
            setAddressBarTopActive(true)
        }
        constraints.navigationBarContainerHeight.constant = standardNavigationBarContainerHeight
    }

    func setAITabCollapsedTopSeparatorVisible(_ visible: Bool) {
        aiTabCollapsedTopSeparatorLogicallyVisible = visible
        applyAITabCollapsedTopSeparatorVisibility()
    }

    /// Enforces the invariant: the separator can only be visible above a visible chrome. The
    /// separator is anchored to the safe area, not to `navigationBarContainer`, so hiding the
    /// chrome doesn't hide the separator transitively — we have to re-apply on either change.
    private func applyAITabCollapsedTopSeparatorVisibility() {
        let visible = aiTabCollapsedTopSeparatorLogicallyVisible && !navigationBarContainer.isHidden
        guard aiTabCollapsedTopSeparator.isHidden == visible else { return }
        aiTabCollapsedTopSeparator.isHidden = !visible
        if visible {
            superview.bringSubviewToFront(aiTabCollapsedTopSeparator)
        }
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

    /// Hides chrome and puts the omnibar collection above UTI, but keeps it invisible until
    /// `finalizeInlineDismissOmnibarReveal` snaps it in at the end of the transition.
    func prepareOmnibarForInlineDismissReveal() {
        guard !isNavigationChromeHidden, let barView = omniBar?.barView else { return }
        barView.hideBarChrome()
        navigationBarCollectionView.alpha = 0
        navigationBarContainer.bringSubviewToFront(navigationBarCollectionView)
    }

    /// Snaps omnibar visibility once the UTI collapse finishes to avoid a layered overlap.
    func finalizeInlineDismissOmnibarReveal() {
        guard !isNavigationChromeHidden else { return }
        navigationBarCollectionView.alpha = 1
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
        hideFocusedStateBackground()
        navigationBarCollectionView.isUserInteractionEnabled = true

        if isNavigationChromeHidden {
            navigationBarCollectionView.alpha = 0
            unifiedToggleInputContainer.isHidden = false
            unifiedToggleInputContainer.alpha = 1
        } else {
            // Snap chrome (pill + text field) back now that UTI is gone; icons faded in alongside the collapse.
            navigationBarCollectionView.alpha = 1
            unifiedToggleInputContainer.isHidden = true
            unifiedToggleInputContainer.alpha = 1
            omniBar?.barView.restoreBarChrome()
            omniBar?.barView.setIconContainersAlpha(1)
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
        hideFocusedStateBackground()
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
        cancelInFlightLayoutAnimations()
        hideAIChatTabChatHeader()
        setNavigationChromeHidden(false)
    }

    /// Hides the bottom `navigationBarContainer` (the flanked UTI on AI tabs) and re-anchors the
    /// content container to the safe area, giving voice mode the full height between the AI
    /// header and the home indicator. Idempotent.
    func setAITabBottomChromeHidden(_ hidden: Bool) {
        guard navigationBarContainer.isHidden != hidden else { return }
        navigationBarContainer.isHidden = hidden
        applyAITabCollapsedTopSeparatorVisibility()
        if hidden {
            setContentContainerBottomAnchorMode(.safeArea)
        } else if isNavigationChromeHidden {
            setContentContainerBottomAnchorMode(.unifiedToggleInput)
        } else {
            setContentContainerBottomAnchorMode(.toolbar)
        }
    }

    func showAIChatTabChatHeader() {
        aiChatTabChatHeaderContainer.isHidden = false
        guard isNavigationChromeHidden else { return }
        setContentContainerTopAnchorMode(.aiChatHeader)
    }

    func hideAIChatTabChatHeader() {
        aiChatTabChatHeaderContainer.isHidden = true
        guard isNavigationChromeHidden else { return }
        setContentContainerTopAnchorMode(.safeArea)
    }

    /// Hides the OmniBar collection view (not the container) so that the UTI inside the container
    /// remains visible when the AI tab chrome is shown. Uses alpha + interaction instead of isHidden
    /// so the pan gesture for tab swiping stays intact.
    func setNavigationChromeHidden(_ hidden: Bool) {
        if hidden {
            isNavigationChromeHidden = true
            navigationBarCollectionView.alpha = 0
            navigationBarCollectionView.isUserInteractionEnabled = false
            if constraints.contentContainerTopToAIChatHeader != nil, !aiChatTabChatHeaderContainer.isHidden {
                setContentContainerTopAnchorMode(.aiChatHeader)
            } else {
                setContentContainerTopAnchorMode(.safeArea)
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
            activateBaseContentContainerTopAnchor()
            if !addressBarPosition.isBottom {
                constraints.statusBackgroundBottomToSafeAreaTop.isActive = false
                constraints.statusBackgroundToNavigationBarContainerBottom.isActive = true
            } else {
                constraints.navigationBarContainerBottom.constant = 0
            }
            if navigationBarContainer.isHidden {
                setContentContainerBottomAnchorMode(.safeArea)
            } else {
                setContentContainerBottomAnchorMode(preferredBottomContentAnchorModeForVisibleChrome())
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
        if isFloatingUIEnabled {
            // The floating omnibar is self-contained glass, so the status strip behind it must stay
            // clear to let content underflow it. The unified toggle input (the floating search bar)
            // is visible at rest on the new tab page, so we can't gate on its visibility here — only
            // the AI-tab chrome-hidden editing surfaces paint a dedicated backdrop.
            switch statusBackgroundPresentation {
            case .standard, .omnibarEditing:
                return .clear
            case .aiTabSearchChromeHidden:
                return UIColor(designSystemColor: .panel)
            case .aiTabChatChromeHidden:
                return UIColor(designSystemColor: .surfaceCanvas)
            }
        }

        switch statusBackgroundPresentation {
        case .standard:
            return standardStatusBackgroundColor ?? UIColor(designSystemColor: .background)
        case .omnibarEditing, .aiTabSearchChromeHidden:
            return UIColor(designSystemColor: .panel)
        case .aiTabChatChromeHidden:
            return UIColor(designSystemColor: .surfaceCanvas)
        }
    }

    private func showFocusedStateBackground() {
        guard isFloatingUIEnabled else { return }
        focusedStateBackground.isHidden = false
        superview.insertSubview(focusedStateBackground, belowSubview: unifiedInputContentContainer)
    }

    private func hideFocusedStateBackground() {
        focusedStateBackground.isHidden = true
    }

    func setNavBarContainerBottomToKeyboard(floorAnchor: NSLayoutYAxisAnchor? = nil) {
        constraints.navigationBarContainerBottom.isActive = false
        constraints.navigationBarContainerBottomSafeAreaFloor?.isActive = false

        constraints.navigationBarContainerBottom = navigationBarContainer.bottomAnchor
            .constraint(equalTo: superview.keyboardLayoutGuide.topAnchor)
        constraints.navigationBarContainerBottom.priority = .defaultHigh
        constraints.navigationBarContainerBottom.isActive = true

        // Cap how far the nav bar can follow the keyboard guide down. Default floor is the
        // safe-area bottom (AI tab — toolbar is hidden, so the UTI is meant to sit at the
        // screen bottom). Callers anchored above a visible toolbar pass `toolbar.topAnchor`
        // so the UTI doesn't slide over the toolbar when the keyboard is dragged off-screen.
        let floor = floorAnchor ?? superview.safeAreaLayoutGuide.bottomAnchor
        let safeAreaFloor = navigationBarContainer.bottomAnchor
            .constraint(lessThanOrEqualTo: floor)
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

    /// Anchors the contentContainer to the UTI's top — except when the bottom chrome is hidden
    /// (voice / FE-hidden chat input), in which case the UTI's frame still sits at the bottom of
    /// the screen and anchoring there would leave a gap below the webview. Falls through to
    /// `.safeArea` then, matching what `setAITabBottomChromeHidden(true)` would set.
    func anchorContentContainerToInputTop() {
        if navigationBarContainer.isHidden {
            setContentContainerBottomAnchorMode(.safeArea)
        } else {
            setContentContainerBottomAnchorMode(.unifiedToggleInput)
        }
    }

    private func setContentContainerBottomAnchorMode(_ mode: ContentContainerBottomAnchorMode) {
        constraints.contentContainerBottomToToolbarTop.isActive = mode == .toolbar
        constraints.contentContainerBottomToUnifiedToggleInputTop.isActive = mode == .unifiedToggleInput
        constraints.contentContainerBottomToSafeArea.isActive = mode == .safeArea
    }

    /// Activates the resting content-container top anchor for the current mode. In floating top
    /// mode the content spans behind the glass omnibar (safe-area top) so it can underflow on
    /// scroll; otherwise it sits below the chrome (topSlide/navBar bottom). AI-tab chrome-hidden
    /// and chat-header states own the top anchor themselves, so this is a no-op while those are
    /// active.
    func applyContentContainerTopAnchorForCurrentState() {
        guard !isNavigationChromeHidden else { return }
        activateBaseContentContainerTopAnchor()
    }

    private func activateBaseContentContainerTopAnchor() {
        let useFloatingTop = isFloatingUIEnabled
            && addressBarPosition == .top
            && !isUnifiedToggleInputVisible
            && (aiChatTabChatHeaderContainer?.isHidden ?? true)
        // Floating top spans to the screen edge (behind the status bar) so content can underflow all
        // the way up; otherwise content sits below the chrome via the topSlide anchor.
        setContentContainerTopAnchorMode(useFloatingTop ? .floatingBehindBar : .standard)
    }

    private enum ContentContainerTopAnchorMode {
        /// Below the chrome (topSlide / navBar bottom) — the default non-floating layout.
        case standard
        /// Safe-area top — AI-tab chrome-hidden state.
        case safeArea
        /// Below the AI chat header — AI-tab chat-header state.
        case aiChatHeader
        /// Screen top, behind the status bar — floating top so content underflows to the edge.
        case floatingBehindBar
    }

    private func setContentContainerTopAnchorMode(_ mode: ContentContainerTopAnchorMode) {
        constraints.contentContainerTop.isActive = mode == .standard
        constraints.contentContainerTopToSafeArea.isActive = mode == .safeArea
        constraints.contentContainerTopToAIChatHeader?.isActive = mode == .aiChatHeader
        constraints.contentContainerTopToSuperview?.isActive = mode == .floatingBehindBar
    }

    /// Floating-bottom chrome is overlaid above the page surface, so content should extend to
    /// the safe area floor. Legacy and non-floating bottom chrome remains toolbar-anchored.
    private func preferredBottomContentAnchorModeForVisibleChrome() -> ContentContainerBottomAnchorMode {
        if isFloatingUIEnabled {
            return .safeArea
        }
        return .toolbar
    }

    private func setNavBarContainerBottomToToolbar(active: Bool = true) {
        constraints.navigationBarContainerBottom.isActive = false
        constraints.navigationBarContainerBottomSafeAreaFloor?.isActive = false
        constraints.navigationBarContainerBottomSafeAreaFloor = nil
        constraints.navigationBarContainerBottom = navigationBarContainer.bottomAnchor
            .constraint(equalTo: toolbar.topAnchor)
        constraints.navigationBarContainerBottom.constant = 0
        constraints.navigationBarContainerBottom.isActive = active
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
