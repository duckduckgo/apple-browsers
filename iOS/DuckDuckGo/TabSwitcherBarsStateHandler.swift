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
    case regularSize(selectedCount: Int, totalCount: Int, containsWebPages: Bool, showAIChat: Bool, canDismissOnEmpty: Bool)
    case largeSize(selectedCount: Int, totalCount: Int, containsWebPages: Bool, showAIChat: Bool, canDismissOnEmpty: Bool)
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

    lazy var plusButton = BrowserChromeButton.createToolbarButtonItem(title: UserText.keyCommandNewTab, image: DesignSystemImages.Glyphs.Size24.add) { [weak self] in
        self?.onPlusButtonTapped?()
    }

    lazy var fireButton = BrowserChromeButton.createToolbarButtonItem(title: "Close all tabs and clear data", image: DesignSystemImages.Glyphs.Size24.fireSolid) { [weak self] in
        self?.onFireButtonTapped?()
    }

    lazy var doneButton = BrowserChromeButton.createToolbarButtonItem(title: UserText.navigationTitleDone, image: nil) { [weak self] in
        self?.onDoneButtonTapped?()
    }

    lazy var closeTabsButton = BrowserChromeButton.createToolbarButtonItem(title: "", image: DesignSystemImages.Glyphs.Size24.trash) { [weak self] in
        self?.onCloseTabsTapped?()
    }

    // No action as this is a menu
    lazy var menuButton = BrowserChromeButton.createToolbarButtonItem(title: "More Menu", image: DesignSystemImages.Glyphs.Size24.moreApple)

    lazy var tabSwitcherStyleButton = BrowserChromeButton.createToolbarButtonItem(title: "", image: nil) { [weak self] in
        self?.onTabStyleButtonTapped?()
    }

    // No action as shows a menu instead
    lazy var editButton = BrowserChromeButton.createToolbarButtonItem(title: UserText.actionGenericEdit, image: DesignSystemImages.Glyphs.Size24.menuDotsVertical)

    lazy var selectAllButton = BrowserChromeButton.createToolbarButtonItem(title: UserText.selectAllTabs, image: nil) { [weak self] in
        self?.onSelectAllTapped?()
    }

    lazy var deselectAllButton = BrowserChromeButton.createToolbarButtonItem(title: UserText.deselectAllTabs, image: nil) { [weak self] in
        self?.onDeselectAllTapped?()
    }

    lazy var duckChatButton = BrowserChromeButton.createToolbarButtonItem(title: UserText.duckAiFeatureName, image: DesignSystemImages.Glyphs.Size24.aiChat) { [weak self] in
        self?.onDuckChatTapped?()
    }

    private(set) var bottomBarItems = [UIBarButtonItem]()
    private(set) var isBottomBarHidden = false
    private(set) var topBarLeftButtonItems = [UIBarButtonItem]()
    private(set) var topBarRightButtonItems = [UIBarButtonItem]()

    private var params = StateParameters()

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

        self.params = StateParameters(from: state)

        configureButtons()
        updateBottomBar()
        updateTopLeftButtons()
        updateTopRightButtons()
    }

    func configureButtonActions(tabsStyle: TabSwitcherViewController.TabsStyle,
                                canShowSelectionMenu: Bool) {
        // Configure tab style button with dynamic image
        if let button = tabSwitcherStyleButton.customView as? BrowserChromeButton {
            button.setImage(tabsStyle.image)
        }
        tabSwitcherStyleButton.accessibilityLabel = tabsStyle.accessibilityLabel

        // Configure edit button with menu
        if let button = editButton.customView as? BrowserChromeButton {
            button.menu = onEditButtonTapped?()
            button.showsMenuAsPrimaryAction = true
        }

        // Configure menu button with menu
        if let button = menuButton.customView as? BrowserChromeButton {
            button.menu = onMenuButtonTapped?()
            button.showsMenuAsPrimaryAction = true
            button.isEnabled = canShowSelectionMenu
        }

    }

    private func configureButtons() {
        // Configure accessibility labels
        self.fireButton.accessibilityLabel = "Close all tabs and clear data"
        self.fireButton.accessibilityIdentifier = "Browser.Toolbar.Button.Fire"
        self.duckChatButton.accessibilityLabel = UserText.duckAiFeatureName
        self.plusButton.accessibilityLabel = UserText.keyCommandNewTab
        self.doneButton.accessibilityLabel = UserText.navigationTitleDone
        self.editButton.accessibilityLabel = UserText.actionGenericEdit
        self.selectAllButton.accessibilityLabel = UserText.selectAllTabs
        self.deselectAllButton.accessibilityLabel = UserText.deselectAllTabs
        self.menuButton.accessibilityLabel = "More Menu"

        self.editButton.isEnabled = params.totalCount > 1 || params.containsWebPages
        self.closeTabsButton.isEnabled = params.selectedCount > 0
        self.doneButton.isEnabled = params.canDismissOnEmpty || params.totalCount > 0

        if params.interfaceMode.isLarge {
            configureDoneButtonAsText()
        } else {
            configureDoneButtonAsBackArrow()
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
            button.setTitle("", for: .normal)
            button.setImage(DesignSystemImages.Glyphs.Size24.arrowLeft)
        }
    }

    func updateBottomBar() {
        var newItems: [UIBarButtonItem]

        switch params.interfaceMode {
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

        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            newItems.forEach {
                $0.sharesBackground = false
                $0.hidesSharedBackground = true
            }
        }
        #endif

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
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            barItem.sharesBackground = false
            barItem.hidesSharedBackground = true
        }
#endif

        return barItem
    }

    func updateTopLeftButtons() {

        switch params.interfaceMode {

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

        switch params.interfaceMode {

        case .largeSize:
            topBarRightButtonItems = [
                doneButton,
                fireButton,
                plusButton,
                params.showAIChat ? duckChatButton : nil,
            ].compactMap { $0 }

        case .regularSize:
            topBarRightButtonItems = [
                params.showAIChat ? duckChatButton : nil,
            ].compactMap { $0 }

        case .editingRegularSize:
            topBarRightButtonItems = [
                params.selectedCount == params.totalCount ? deselectAllButton : selectAllButton,
            ]

        case .editingLargeSize:
            topBarRightButtonItems = [
                menuButton,
            ]

        }
    }
}

extension DefaultTabSwitcherBarsStateHandler {
    private struct StateParameters {
        var selectedCount: Int = 0
        var totalCount: Int = 0
        var containsWebPages: Bool = false
        var showAIChat: Bool = false
        var canDismissOnEmpty: Bool = true
        var interfaceMode: TabSwitcherViewController.InterfaceMode = .regularSize

        init() { }

        init(from state: TabSwitcherToolbarState) {
            switch state {
            case .regularSize(let selectedCount, let totalCount, let containsWebPages, let showAIChat, let canDismissOnEmpty),
                 .largeSize(let selectedCount, let totalCount, let containsWebPages, let showAIChat, let canDismissOnEmpty):
                self.selectedCount = selectedCount
                self.totalCount = totalCount
                self.containsWebPages = containsWebPages
                self.showAIChat = showAIChat
                self.canDismissOnEmpty = canDismissOnEmpty
            case .editingRegularSize(let selectedCount, let totalCount),
                 .editingLargeSize(let selectedCount, let totalCount):
                self.selectedCount = selectedCount
                self.totalCount = totalCount
            }
            self.interfaceMode = state.interfaceMode
        }
    }
}
