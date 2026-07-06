//
//  TabSwitcherChrome.swift
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

/// Callbacks the tab switcher chrome invokes in response to user interaction.
/// The view controller owns the behaviour; the chrome only owns presentation.
struct TabSwitcherChromeActions {
    var onPlusTapped: (() -> Void)?
    var onNewFireTabTapped: (() -> Void)?
    var onNewNormalTabTapped: (() -> Void)?
    var onFireTapped: (() -> Void)?
    /// Done / Cancel / X — exits multi-select when editing, otherwise dismisses.
    var onDoneTapped: (() -> Void)?
    var onEditMenuRequested: (() -> UIMenu?)?
    /// Sets a specific grid/list style (used by the floating menu).
    var onSelectTabsStyle: ((TabSwitcherViewController.TabsStyle) -> Void)?
    /// Toggles grid/list (used by the legacy single toggle button).
    var onToggleTabsStyle: (() -> Void)?
    var onSelectAllTapped: (() -> Void)?
    var onDeselectAllTapped: (() -> Void)?
    var onMultiSelectMenuRequested: (() -> UIMenu?)?
    var onCloseTabsTapped: (() -> Void)?
    var onDuckChatTapped: (() -> Void)?
}

/// Abstraction over the tab switcher's bars and layout so the view controller can swap
/// between the production chrome and the floating ("liquid glass") chrome without changing
/// its own behaviour.
@MainActor
protocol TabSwitcherChrome: AnyObject {

    var actions: TabSwitcherChromeActions { get set }

    /// Anchor used for the fire confirmation popover and the fire button highlight pulse.
    var fireButton: UIBarButtonItem { get }

    /// Adds the chrome's bars and the provided content view to the host view.
    func install(in view: UIView, contentView: UIScrollView)

    /// (Re)applies the layout constraints for the current address bar position and interface mode.
    func layout(addressBarPosition: AddressBarPosition,
                interfaceMode: TabSwitcherViewController.InterfaceMode)

    /// Updates the bar contents for the current toolbar state.
    func update(state: TabSwitcherToolbarState,
                tabsStyle: TabSwitcherViewController.TabsStyle,
                canShowSelectionMenu: Bool,
                isEditing: Bool)

    /// The center accessory for the top bar (the Fire/Normal segmented picker host).
    func setCenterView(_ view: UIView?)

    /// The text title shown when no center accessory is visible.
    func setTitle(_ title: String?)

    func decorate(theme: Theme)

    func configurePlusButtonLongPressMenu(isFireModeEnabled: Bool)

    /// Applies the appropriate content insets so collection content clears the bars.
    func applyCollectionContentInset(to collectionView: UICollectionView)

    /// Points the system scroll-edge glass effect at the scroll view the user actually scrolls
    /// (the active page's collection view), so the effect tracks vertical tab scrolling rather
    /// than the horizontally-paging container.
    func trackScrollEdge(of scrollView: UIScrollView)
}

extension TabSwitcherChrome {
    func trackScrollEdge(of scrollView: UIScrollView) {}
}

/// Selects the chrome implementation based on whether floating UI is enabled.
enum TabSwitcherChromeFactory {

    @MainActor
    static func makeChrome(isFloatingUIEnabled: Bool,
                           toolbar: UIToolbar,
                           appSettings: AppSettings) -> TabSwitcherChrome {
        if isFloatingUIEnabled {
            return FloatingTabSwitcherChrome()
        }
        return LegacyTabSwitcherChrome(toolbar: toolbar, appSettings: appSettings)
    }
}
