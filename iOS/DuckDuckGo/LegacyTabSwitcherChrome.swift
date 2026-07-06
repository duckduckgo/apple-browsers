//
//  LegacyTabSwitcherChrome.swift
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
import Core
import DesignResourcesKit

/// The production tab switcher chrome: a custom top title bar plus a `BrowserToolbarView` bottom
/// bar, driven by `DefaultTabSwitcherBarsStateHandler`. This preserves the existing behaviour;
/// it is the path used whenever floating UI is disabled.
///
/// The bottom bar reuses the browser's `BrowserToolbarView` (rather than the storyboard `UIToolbar`)
/// so the button positions line up exactly with the browser/NTP toolbar during the tab-switcher
/// transition. The storyboard `UIToolbar` is removed from the hierarchy and otherwise unused.
@MainActor
final class LegacyTabSwitcherChrome: TabSwitcherChrome {

    private let titleBarView = TabSwitcherTitleBarView()
    private lazy var borderView = StyledTopBottomBorderView()
    private let bottomToolbar = BrowserToolbarView()
    private let toolbar: UIToolbar
    private let appSettings: AppSettings
    private var barsHandler: TabSwitcherBarsStateHandling

    private weak var hostView: UIView?
    private weak var contentView: UIScrollView?
    private weak var centerView: UIView?

    var actions = TabSwitcherChromeActions() {
        didSet { wireActions() }
    }

    var fireButton: UIBarButtonItem {
        barsHandler.fireButton
    }

    init(toolbar: UIToolbar,
         appSettings: AppSettings,
         barsHandler: TabSwitcherBarsStateHandling = DefaultTabSwitcherBarsStateHandler()) {
        self.toolbar = toolbar
        self.appSettings = appSettings
        self.barsHandler = barsHandler
    }

    func install(in view: UIView, contentView: UIScrollView) {
        self.hostView = view
        self.contentView = contentView
    }

    func setCenterView(_ view: UIView?) {
        centerView = view
    }

    func setTitle(_ title: String?) {
        titleBarView.titleLabel.text = title
    }

    func configurePlusButtonLongPressMenu(isFireModeEnabled: Bool) {
        barsHandler.configurePlusButtonLongPressMenu(isFireModeEnabled: isFireModeEnabled)
    }

    func decorate(theme: Theme) {
        titleBarView.tintColor = theme.barTintColor
        bottomToolbar.setLegacyBackgroundTransparent(true)
        bottomToolbar.tintColor = UIColor(singleUseColor: .toolbarButton)
    }

    func update(state: TabSwitcherToolbarState,
                tabsStyle: TabSwitcherViewController.TabsStyle,
                canShowSelectionMenu: Bool,
                isEditing: Bool) {
        barsHandler.update(state)
        barsHandler.configureButtonActions(tabsStyle: tabsStyle, canShowSelectionMenu: canShowSelectionMenu)

        titleBarView.setCenterView(isEditing ? nil : centerView)
        titleBarView.setLeadingButtons(barsHandler.topBarLeftButtons)
        titleBarView.setTrailingButtons(barsHandler.topBarRightButtons)
        bottomToolbar.setToolbarButtons(barsHandler.bottomBarButtonViews)
        bottomToolbar.isHidden = barsHandler.isBottomBarHidden
    }

    func applyCollectionContentInset(to collectionView: UICollectionView) {
        collectionView.contentInset.bottom = barsHandler.isBottomBarHidden ? 0 : bottomToolbar.frame.height
    }

    func layout(addressBarPosition: AddressBarPosition,
                interfaceMode: TabSwitcherViewController.InterfaceMode) {
        guard let hostView, let contentView else {
            assertionFailure("LegacyTabSwitcherChrome.layout called before install")
            return
        }

        // Remove existing constraints to avoid conflicts
        borderView.translatesAutoresizingMaskIntoConstraints = false
        titleBarView.translatesAutoresizingMaskIntoConstraints = false
        bottomToolbar.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false

        // Drop the storyboard UIToolbar from the hierarchy; `bottomToolbar` replaces it.
        toolbar.removeFromSuperview()

        let viewsToRemoveConstraintsFor: [UIView] = [titleBarView, bottomToolbar, contentView, borderView]
        viewsToRemoveConstraintsFor.forEach { targetView in
            targetView.removeFromSuperview()
        }

        hostView.addSubview(titleBarView)
        hostView.addSubview(bottomToolbar)
        hostView.addSubview(contentView)
        hostView.addSubview(borderView)

        // Keep the bar transparent (the tab switcher provides its own backdrop) and matched to
        // the browser's button layout.
        bottomToolbar.setFloatingStyleEnabled(false)
        bottomToolbar.setLegacyBackgroundTransparent(true)
        borderView.updateForAddressBarPosition(addressBarPosition)
        titleBarView.updateForAddressBarPosition(isBottom: addressBarPosition.isBottom)
        // On large ipad view don't show the bottom divider
        borderView.isBottomVisible = !interfaceMode.isLarge
        activateLayoutConstraintsBasedOnBarPosition(addressBarPosition: addressBarPosition,
                                                    interfaceMode: interfaceMode,
                                                    hostView: hostView,
                                                    contentView: contentView)
    }

    private func activateLayoutConstraintsBasedOnBarPosition(addressBarPosition: AddressBarPosition,
                                                             interfaceMode: TabSwitcherViewController.InterfaceMode,
                                                             hostView view: UIView,
                                                             contentView pagingScrollView: UIView) {
        let isBottomBar = addressBarPosition.isBottom

        let isiOS26: Bool
        if #available(iOS 26, *) {
            isiOS26 = true
        } else {
            isiOS26 = false
        }

        // Changing this?  Best change MainView too
        let toolbarWidthMod = isiOS26 ? 14.0 : 4.0

        // On iOS 26 iPad, use the margins layout guide to avoid the native window ornaments
        // (traffic-light buttons). Mirrors the approach in MainView.constrainNavigationBarContainer()
        // and MainView.constrainTabBarContainer().
        let topGuide: UILayoutGuide
        if #available(iOS 26, *), UIDevice.current.userInterfaceIdiom == .pad {
            topGuide = view.layoutGuide(for: .margins(cornerAdaptation: .vertical))
        } else {
            topGuide = view.safeAreaLayoutGuide
        }

        // The constants here are to force the ai button to align between the tab switcher and this view
        NSLayoutConstraint.activate([
            titleBarView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            titleBarView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            isBottomBar ? titleBarView.bottomAnchor.constraint(equalTo: bottomToolbar.topAnchor) : nil,
            !isBottomBar ? titleBarView.topAnchor.constraint(equalTo: topGuide.topAnchor) : nil,

            pagingScrollView.topAnchor.constraint(equalTo: isBottomBar ? topGuide.topAnchor : titleBarView.bottomAnchor),
            pagingScrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            pagingScrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),

            interfaceMode.isLarge ? pagingScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor) :
                pagingScrollView.bottomAnchor.constraint(equalTo: isBottomBar ? titleBarView.topAnchor : bottomToolbar.topAnchor),

            borderView.topAnchor.constraint(equalTo: isBottomBar ? topGuide.topAnchor : titleBarView.bottomAnchor),
            borderView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            borderView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // On iPad large mode constrain to the bottom as the toolbar is hidden
            interfaceMode.isLarge ? borderView.bottomAnchor.constraint(equalTo: view.bottomAnchor) :
                borderView.bottomAnchor.constraint(equalTo: isBottomBar ? titleBarView.topAnchor : bottomToolbar.topAnchor),

            // Always at the bottom
            bottomToolbar.constrainView(view, by: .width, constant: toolbarWidthMod),
            bottomToolbar.constrainView(view, by: .centerX),
            bottomToolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ].compactMap { $0 })
    }

    private func wireActions() {
        barsHandler.onPlusButtonTapped = actions.onPlusTapped
        barsHandler.onNewFireTabTapped = actions.onNewFireTabTapped
        barsHandler.onNewNormalTabTapped = actions.onNewNormalTabTapped
        barsHandler.onFireButtonTapped = actions.onFireTapped
        barsHandler.onDoneButtonTapped = actions.onDoneTapped
        barsHandler.onEditButtonTapped = actions.onEditMenuRequested
        barsHandler.onTabStyleButtonTapped = actions.onToggleTabsStyle
        barsHandler.onSelectAllTapped = actions.onSelectAllTapped
        barsHandler.onDeselectAllTapped = actions.onDeselectAllTapped
        barsHandler.onMenuButtonTapped = actions.onMultiSelectMenuRequested
        barsHandler.onCloseTabsTapped = actions.onCloseTabsTapped
        barsHandler.onDuckChatTapped = actions.onDuckChatTapped
    }
}
