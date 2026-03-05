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
    var keyboardSeamView: UIView!
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
    private(set) var isNavigationChromeHidden = false

    // The default after creating the hiearchy is top
    var addressBarPosition: AddressBarPosition = .top

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
        var unifiedToggleInputBottom: NSLayoutConstraint!
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
        guard addressBarPosition.isBottom else {
            return
        }

        // Hiding the container won't suffice as it still defines the contentContainer.bottomY through constraints
        navigationBarContainer.isHidden = true

        constraints.contentContainerBottomToToolbarTop.isActive = false
        constraints.contentContainerBottomToSafeArea.isActive = true

    }

    func showNavigationBarWithBottomPosition() {
        guard addressBarPosition.isBottom else {
            return
        }

        navigationBarContainer.isHidden = false
        constraints.navigationBarContainerBottom.constant = 0

        constraints.contentContainerBottomToToolbarTop.isActive = true
        constraints.contentContainerBottomToSafeArea.isActive = false
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

    // MARK: - Native Input Layout

    func showUnifiedToggleInput(aboveKeyboard: Bool) {
        constraints.unifiedToggleInputBottom.isActive = false

        if aboveKeyboard {
            constraints.unifiedToggleInputBottom = unifiedToggleInputContainer.bottomAnchor
                .constraint(equalTo: superview.keyboardLayoutGuide.topAnchor)
        } else {
            constraints.unifiedToggleInputBottom = unifiedToggleInputContainer.bottomAnchor
                .constraint(equalTo: toolbar.topAnchor)
        }
        constraints.contentContainerBottomToUnifiedToggleInputTop.constant = aboveKeyboard ? 30 : 0

        constraints.unifiedToggleInputBottom.isActive = true
        unifiedToggleInputContainer.isHidden = false
        keyboardSeamView.isHidden = !aboveKeyboard
    }

    func hideUnifiedToggleInput() {
        unifiedToggleInputContainer.isHidden = true
        keyboardSeamView.isHidden = true
        constraints.contentContainerBottomToUnifiedToggleInputTop.constant = 0
    }

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
    }

    func hideAIChatTabChatHeader() {
        aiChatTabChatHeaderContainer.isHidden = true
    }

    /// Uses alpha + interaction instead of isHidden so the collection view stays laid out
    /// and its pan gesture can be relocated to drive tab swiping.
    func setNavigationChromeHidden(_ hidden: Bool) {
        if hidden {
            if !isNavigationChromeHidden {
                savedStatusBackgroundColor = statusBackground.backgroundColor
            }
            isNavigationChromeHidden = true
            statusBackground.backgroundColor = UIColor(singleUseColor: .duckAIContextualSheetBackground)
            navigationBarContainer.alpha = 0
            navigationBarContainer.isUserInteractionEnabled = false
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
            constraints.contentContainerBottomToToolbarTop.isActive = false
            constraints.contentContainerBottomToUnifiedToggleInputTop.isActive = true
        } else {
            if isNavigationChromeHidden {
                statusBackground.backgroundColor = savedStatusBackgroundColor
                savedStatusBackgroundColor = nil
            }
            isNavigationChromeHidden = false
            navigationBarContainer.alpha = 1
            navigationBarContainer.isUserInteractionEnabled = true
            constraints.contentContainerTopToSafeArea.isActive = false
            constraints.contentContainerTopToAIChatHeader?.isActive = false
            constraints.contentContainerTop.isActive = true
            if !addressBarPosition.isBottom {
                constraints.statusBackgroundBottomToSafeAreaTop.isActive = false
                constraints.statusBackgroundToNavigationBarContainerBottom.isActive = true
            } else {
                constraints.navigationBarContainerBottom.constant = 0
            }
            constraints.contentContainerBottomToUnifiedToggleInputTop.isActive = false
            constraints.contentContainerBottomToToolbarTop.isActive = true
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
