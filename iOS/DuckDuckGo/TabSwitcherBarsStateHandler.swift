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
import DesignResourcesKitIcons

enum TabSwitcherToolbarState: Equatable {
    case regularSize(selectedCount: Int, totalCount: Int, containsWebPages: Bool, showAIChat: Bool)
    case largeSize(selectedCount: Int, totalCount: Int, containsWebPages: Bool, showAIChat: Bool)
    case editingRegularSize(selectedCount: Int, totalCount: Int)
    case editingLargeSize(selectedCount: Int, totalCount: Int)

    var interfaceMode: TabSwitcherViewController.InterfaceMode {
        switch self {
        case .regularSize: return .regularSize
        case .largeSize: return .largeSize
        case .editingRegularSize: return .editingRegularSize
        case .editingLargeSize: return .editingLargeSize
        }
    }
}

protocol TabSwitcherBarsStateHandling {

    var plusButton: UIBarButtonItem { get }
    var fireButton: UIBarButtonItem { get }
    var doneButton: UIBarButtonItem { get }
    var closeTabsButton: UIBarButtonItem { get }
    var menuButton: UIBarButtonItem { get }
    var addAllBookmarksButton: UIBarButtonItem { get }
    var tabSwitcherStyleButton: UIBarButtonItem { get }
    var editButton: UIBarButtonItem { get }
    var selectAllButton: UIBarButtonItem { get }
    var deselectAllButton: UIBarButtonItem { get }
    var duckChatButton: UIBarButtonItem { get }

    var bottomBarItems: [UIBarButtonItem] { get }
    var topBarLeftButtonItems: [UIBarButtonItem] { get }
    var topBarRightButtonItems: [UIBarButtonItem] { get }

    var isBottomBarHidden: Bool { get }

    var onPlusButtonTapped: (() -> Void)? { get set }
    var onFireButtonTapped: (() -> Void)? { get set }
    var onDoneButtonTapped: (() -> Void)? { get set }
    var onEditButtonTapped: (() -> UIMenu?)? { get set }
    var onTabStyleButtonTapped: (() -> Void)? { get set }
    var onSelectAllTapped: (() -> Void)? { get set }
    var onDeselectAllTapped: (() -> Void)? { get set }
    var onMenuButtonTapped: (() -> UIMenu?)? { get set }
    var onCloseTabsTapped: (() -> Void)? { get set }
    var onDuckChatTapped: (() -> Void)? { get set }

    func update(_ state: TabSwitcherToolbarState)

    func configureButtonActions(tabsStyle: TabSwitcherViewController.TabsStyle,
                                canShowSelectionMenu: Bool)

}

/// This is what we hope will be the new version long term.
class DefaultTabSwitcherBarsStateHandler: TabSwitcherBarsStateHandling {

    lazy var plusButton = BrowserChromeButton.createToolbarButtonItem(title: UserText.keyCommandNewTab, image: DesignSystemImages.Glyphs.Size24.add)
    lazy var fireButton = BrowserChromeButton.createToolbarButtonItem(title: "Close all tabs and clear data", image: DesignSystemImages.Glyphs.Size24.fireSolid)
    lazy var doneButton = BrowserChromeButton.createToolbarButtonItem(title: UserText.navigationTitleDone, image: nil)
    lazy var closeTabsButton = BrowserChromeButton.createToolbarButtonItem(title: "", image: nil)
    lazy var menuButton = BrowserChromeButton.createToolbarButtonItem(title: "More Menu", image: DesignSystemImages.Glyphs.Size24.moreApple)
    lazy var addAllBookmarksButton = BrowserChromeButton.createToolbarButtonItem(title: UserText.bookmarkAllTabs, image: DesignSystemImages.Glyphs.Size24.bookmarkNew)
    lazy var tabSwitcherStyleButton = BrowserChromeButton.createToolbarButtonItem(title: "", image: nil)
    lazy var editButton = BrowserChromeButton.createToolbarButtonItem(title: UserText.actionGenericEdit, image: DesignSystemImages.Glyphs.Size24.menuDotsVertical)
    lazy var selectAllButton = BrowserChromeButton.createToolbarButtonItem(title: UserText.selectAllTabs, image: nil)
    lazy var deselectAllButton = BrowserChromeButton.createToolbarButtonItem(title: UserText.deselectAllTabs, image: nil)
    lazy var duckChatButton = BrowserChromeButton.createToolbarButtonItem(title: UserText.duckAiFeatureName, image: DesignSystemImages.Glyphs.Size24.aiChat)

    private(set) var bottomBarItems = [UIBarButtonItem]()
    private(set) var isBottomBarHidden = false
    private(set) var topBarLeftButtonItems = [UIBarButtonItem]()
    private(set) var topBarRightButtonItems = [UIBarButtonItem]()

    private(set) var interfaceMode: TabSwitcherViewController.InterfaceMode = .regularSize
    private(set) var selectedTabsCount: Int = 0
    private(set) var totalTabsCount: Int = 0
    private(set) var containsWebPages = false
    private(set) var showAIChatButton = false

    private(set) var isFirstUpdate = true

    var onPlusButtonTapped: (() -> Void)?
    var onFireButtonTapped: (() -> Void)?
    var onDoneButtonTapped: (() -> Void)?
    var onEditButtonTapped: (() -> UIMenu?)?
    var onTabStyleButtonTapped: (() -> Void)?
    var onSelectAllTapped: (() -> Void)?
    var onDeselectAllTapped: (() -> Void)?
    var onMenuButtonTapped: (() -> UIMenu?)?
    var onCloseTabsTapped: (() -> Void)?
    var onDuckChatTapped: (() -> Void)?

    init() { }

    private var currentState: TabSwitcherToolbarState?

    func update(_ state: TabSwitcherToolbarState) {
        guard currentState != state else { return }
        currentState = state

        // Extract parameters from state
        let (selectedCount, totalCount, containsWebPages, showAIChatButton) = extractParameters(from: state)

        self.interfaceMode = state.interfaceMode
        self.selectedTabsCount = selectedCount
        self.totalTabsCount = totalCount
        self.containsWebPages = containsWebPages
        self.showAIChatButton = showAIChatButton

        configureButtons(for: state)
        updateBottomBar()
        updateTopLeftButtons()
        updateTopRightButtons()
    }

    private func extractParameters(from state: TabSwitcherToolbarState) -> (Int, Int, Bool, Bool) {
        switch state {
        case .regularSize(let selectedCount, let totalCount, let containsWebPages, let showAIChat):
            return (selectedCount, totalCount, containsWebPages, showAIChat)
        case .largeSize(let selectedCount, let totalCount, let containsWebPages, let showAIChat):
            return (selectedCount, totalCount, containsWebPages, showAIChat)
        case .editingRegularSize(let selectedCount, let totalCount):
            return (selectedCount, totalCount, false, false)
        case .editingLargeSize(let selectedCount, let totalCount):
            return (selectedCount, totalCount, false, false)
        }
    }

    func configureButtonActions(tabsStyle: TabSwitcherViewController.TabsStyle,
                                canShowSelectionMenu: Bool) {
        // Configure tab style button with dynamic image
        if let button = tabSwitcherStyleButton.customView as? BrowserChromeButton {
            button.setImage(tabsStyle.image)
            button.removeTarget(nil, action: nil, for: .allEvents)
            if let action = onTabStyleButtonTapped {
                button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            }
        }

        // Configure plus button
        if let button = plusButton.customView as? BrowserChromeButton {
            button.removeTarget(nil, action: nil, for: .allEvents)
            if let action = onPlusButtonTapped {
                button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            }
        }

        // Configure fire button
        if let button = fireButton.customView as? BrowserChromeButton {
            button.removeTarget(nil, action: nil, for: .allEvents)
            if let action = onFireButtonTapped {
                button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            }
        }

        // Configure done button
        if let button = doneButton.customView as? BrowserChromeButton {
            button.removeTarget(nil, action: nil, for: .allEvents)
            if let action = onDoneButtonTapped {
                button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            }
        }

        // Configure edit button with menu
        if let button = editButton.customView as? BrowserChromeButton {
            button.setImage(DesignSystemImages.Glyphs.Size24.menuDotsVertical)
            button.menu = onEditButtonTapped?()
            button.showsMenuAsPrimaryAction = true
        }

        // Configure select all button
        if let button = selectAllButton.customView as? BrowserChromeButton {
            button.removeTarget(nil, action: nil, for: .allEvents)
            if let action = onSelectAllTapped {
                button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            }
        }

        // Configure deselect all button
        if let button = deselectAllButton.customView as? BrowserChromeButton {
            button.removeTarget(nil, action: nil, for: .allEvents)
            if let action = onDeselectAllTapped {
                button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            }
        }

        // Configure menu button with menu
        if let button = menuButton.customView as? BrowserChromeButton {
            button.setImage(DesignSystemImages.Glyphs.Size24.moreApple)
            button.menu = onMenuButtonTapped?()
            button.showsMenuAsPrimaryAction = true
            button.isEnabled = canShowSelectionMenu
        }

        // Configure close tabs button
        if let button = closeTabsButton.customView as? BrowserChromeButton {
            button.removeTarget(nil, action: nil, for: .allEvents)
            if let action = onCloseTabsTapped {
                button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            }
        }

        // Configure duck chat button
        if let button = duckChatButton.customView as? BrowserChromeButton {
            button.removeTarget(nil, action: nil, for: .allEvents)
            if let action = onDuckChatTapped {
                button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            }
        }
    }

    private func configureButtons(for state: TabSwitcherToolbarState) {
        // Configure accessibility labels
        self.fireButton.accessibilityLabel = "Close all tabs and clear data"
        self.fireButton.accessibilityIdentifier = "Browser.Toolbar.Button.Fire"
        self.tabSwitcherStyleButton.accessibilityLabel = "Toggle between grid and list view"
        self.duckChatButton.accessibilityLabel = UserText.duckAiFeatureName
        self.plusButton.accessibilityLabel = UserText.keyCommandNewTab
        self.doneButton.accessibilityLabel = UserText.navigationTitleDone
        self.editButton.accessibilityLabel = UserText.actionGenericEdit
        self.selectAllButton.accessibilityLabel = UserText.selectAllTabs
        self.deselectAllButton.accessibilityLabel = UserText.deselectAllTabs
        self.menuButton.accessibilityLabel = "More Menu"

        // Configure enabled states
        let (selectedCount, totalCount, containsWebPages, _) = extractParameters(from: state)
        self.editButton.isEnabled = totalCount > 1 || containsWebPages
        self.closeTabsButton.isEnabled = selectedCount > 0

        // Configure button titles based on state
        if case .largeSize = state.interfaceMode {
            configureDoneButtonAsText()
        } else {
            configureDoneButtonAsBackArrow()
        }

        // Configure close tabs button title
        configureCloseTabsButton(selectedCount: selectedCount)

        // Configure tint colors
        if let button = tabSwitcherStyleButton.customView as? BrowserChromeButton {
            button.tintColor = UIColor(designSystemColor: .icons)
        }
        if let button = menuButton.customView as? BrowserChromeButton {
            button.tintColor = UIColor(designSystemColor: .icons)
        }
        if let button = duckChatButton.customView as? BrowserChromeButton {
            button.tintColor = UIColor(designSystemColor: .icons)
        }
    }

    private func configureDoneButtonAsText() {
        if let button = doneButton.customView as? BrowserChromeButton {
            button.setTitle(UserText.navigationTitleDone, for: .normal)
            button.setImage(nil)
        }
    }

    private func configureDoneButtonAsBackArrow() {
        if let button = doneButton.customView as? BrowserChromeButton {
            button.setTitle(nil, for: .normal)
            button.setImage(DesignSystemImages.Glyphs.Size24.arrowLeft)
        }
    }

    private func configureCloseTabsButton(selectedCount: Int) {
        if let button = closeTabsButton.customView as? BrowserChromeButton {
            button.setTitle(UserText.closeTabs(withCount: selectedCount), for: .normal)
        }
    }

    func updateBottomBar() {
        var newItems: [UIBarButtonItem]

        switch interfaceMode {
        case .regularSize:

            newItems = [
                tabSwitcherStyleButton,

                .flexibleSpace(),

                invisibleBalancingButton(),

                .flexibleSpace(),

                fireButton,

                .flexibleSpace(),

                plusButton,

                .flexibleSpace(),

                editButton,
            ].compactMap { $0 }

            isBottomBarHidden = false

        case .editingRegularSize:
            newItems = [
                closeTabsButton,
                .flexibleSpace(),
                menuButton,
            ]
            isBottomBarHidden = false

        case .editingLargeSize,
                .largeSize:
            newItems = []
            isBottomBarHidden = true
        }

        if #available(iOS 26, *) {
            newItems.forEach {
                $0.sharesBackground = false
                $0.hidesSharedBackground = true
            }
        }

        bottomBarItems = newItems
    }

    private func invisibleBalancingButton() -> UIBarButtonItem {
        // Creates an invisible button to balance the toolbar layout and center the fire button
        let button = BrowserChromeButton(.primary)
        button.setImage(DesignSystemImages.Glyphs.Size24.shield)
        button.alpha = 0
        button.isUserInteractionEnabled = false
        button.frame = CGRect(x: 0, y: 0, width: 34, height: 44)

        let barItem = UIBarButtonItem(customView: button)
        if #available(iOS 26.0, *) {
            barItem.sharesBackground = false
            barItem.hidesSharedBackground = true
        }

        return barItem
    }

    func updateTopLeftButtons() {

        switch interfaceMode {

        case .regularSize:
            topBarLeftButtonItems = [
                doneButton,
            ]

        case .largeSize:
            topBarLeftButtonItems = [
                editButton,
                tabSwitcherStyleButton,
            ]

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
                showAIChatButton ? duckChatButton : nil,
            ].compactMap { $0 }

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
