//
//  TabSwitcherBarsStateHandler.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit

class TabSwitcherBarsStateHandler {

    let plusButton = UIBarButtonItem()
    let fireButton = UIBarButtonItem()
    let doneButton = UIBarButtonItem()
    let closeTabsButton = UIBarButtonItem()
    let menuButton = UIBarButtonItem()
    let addAllBookmarksButton = UIBarButtonItem()
    let tabSwitcherStyleButton = UIBarButtonItem()
    let editButton = UIBarButtonItem()
    let selectAllButton = UIBarButtonItem()
    let deselectAllButton = UIBarButtonItem()
    let duckChatButton = UIBarButtonItem()

    private(set) var bottomBarItems = [UIBarButtonItem]()
    private(set) var isBottomBarHidden = false
    private(set) var topBarLeftButtonItems = [UIBarButtonItem]()
    private(set) var topBarRightButtonItems = [UIBarButtonItem]()

    private(set) var interfaceMode: TabSwitcherViewController.InterfaceMode = .regularSize
    private(set) var selectedTabsCount: Int = 0
    private(set) var totalTabsCount: Int = 0
    private(set) var containsWebPages = false
    private(set) var showAIChatButton = false
    private(set) var canShowEditButton = false

    private(set) var isFirstUpdate = true

    private let themingProperties: ExperimentalThemingProperties
    private var isExperimentalThemingEnabled: Bool {
        themingProperties.isExperimentalThemingEnabled
    }

    init(themingProperties: ExperimentalThemingProperties = ThemeManager.shared.properties) {
        self.themingProperties = themingProperties
    }

    func update(_ interfaceMode: TabSwitcherViewController.InterfaceMode,
                selectedTabsCount: Int,
                totalTabsCount: Int,
                containsWebPages: Bool,
                showAIChatButton: Bool) {

        guard isFirstUpdate
                || interfaceMode != self.interfaceMode
                || selectedTabsCount != self.selectedTabsCount
                || totalTabsCount != self.totalTabsCount
                || containsWebPages != self.containsWebPages
                || showAIChatButton != self.showAIChatButton
        else {
            // If nothing has changed, don't update
            return
        }

        self.isFirstUpdate = false
        self.interfaceMode = interfaceMode
        self.selectedTabsCount = selectedTabsCount
        self.totalTabsCount = totalTabsCount
        self.containsWebPages = containsWebPages
        self.showAIChatButton = showAIChatButton

        self.fireButton.accessibilityLabel = "Close all tabs and clear data"
        self.tabSwitcherStyleButton.accessibilityLabel = "Toggle between grid and list view"
        self.duckChatButton.accessibilityLabel = UserText.aiChatFeatureName

        self.canShowEditButton = self.totalTabsCount > 1 || containsWebPages

        updateBottomBar()
        updateTopLeftButtons()
        updateTopRightButtons()
    }

    func updateBottomBar() {
        var newItems: [UIBarButtonItem]

        let regularItemWidth: CGFloat = 34
        let leadingSideWidthDifference: CGFloat = isExperimentalThemingEnabled ? 6 : 11

        switch interfaceMode {
        case .regularSize:

            newItems = [
                tabSwitcherStyleButton,

                .flexibleSpace(),
                .fixedSpace(leadingSideWidthDifference),
                .flexibleSpace(),

                fireButton,

                .flexibleSpace(),
                showAIChatButton ? duckChatButton : .fixedSpace(regularItemWidth),
                .flexibleSpace(),

                plusButton
            ].compactMap { $0 }

            isBottomBarHidden = false

        case .editingRegularSize:
            newItems = [
                closeTabsButton,
                UIBarButtonItem.flexibleSpace(),
                menuButton,
            ]
            isBottomBarHidden = false

        case .editingLargeSize,
                .largeSize:
            newItems = []
            isBottomBarHidden = true
        }

        if !newItems.isEmpty && isExperimentalThemingEnabled {
            // This aligns items with the toolbar on main screen,
            // which is supposed to be aligned with Omnibar buttons.
            newItems = [.additionalFixedSpaceItem()] + newItems + [.additionalFixedSpaceItem()]
        }

        bottomBarItems = newItems
    }

    func updateTopLeftButtons() {

        switch interfaceMode {

        case .regularSize:
            topBarLeftButtonItems = [
                canShowEditButton ? editButton : nil,
            ].compactMap { $0 }

        case .largeSize:
            topBarLeftButtonItems = [
                canShowEditButton ? editButton : nil,
                tabSwitcherStyleButton,
            ].compactMap { $0 }

        case .editingRegularSize:
            topBarLeftButtonItems = [
                doneButton
            ]

        case .editingLargeSize:
            topBarLeftButtonItems = [
                doneButton,
            ]

        }
    }

    func updateTopRightButtons() {

        switch interfaceMode {

        case .largeSize:
            topBarRightButtonItems = [
                doneButton,
                fireButton,
                plusButton,
                showAIChatButton ? duckChatButton : nil,
            ].compactMap { $0 }

        case .regularSize:
            topBarRightButtonItems = [
                doneButton
            ]

        case .editingRegularSize:
            topBarRightButtonItems = [
                selectedTabsCount == totalTabsCount ? deselectAllButton : selectAllButton,
            ]

        case .editingLargeSize:
            topBarRightButtonItems = [
                menuButton,
            ]

        }
    }
}

private extension UIBarButtonItem {
    private static let additionalHorizontalSpace = 10.0

    static func additionalFixedSpaceItem() -> UIBarButtonItem {
        .fixedSpace(additionalHorizontalSpace)
    }
}
