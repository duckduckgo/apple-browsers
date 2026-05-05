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
import Core
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
    var doneIconButton: UIBarButtonItem { get }
    var doneTextButton: UIBarButtonItem { get }
    var doneButton: UIBarButtonItem { get }
    var closeTabsButton: UIBarButtonItem { get }
    var menuButton: UIBarButtonItem { get }
    var tabSwitcherStyleButton: UIBarButtonItem { get }
    var editButton: UIBarButtonItem { get }
    var selectAllButton: UIBarButtonItem { get }
    var deselectAllButton: UIBarButtonItem { get }
    var duckChatButton: UIBarButtonItem { get }

    var bottomBarItems: [UIBarButtonItem] { get }
    var topBarLeftButtons: [UIView] { get }
    var topBarRightButtons: [UIView] { get }

    var isBottomBarHidden: Bool { get }

    var onPlusButtonTapped: (() -> Void)? { get set }
    var onNewFireTabTapped: (() -> Void)? { get set }
    var onNewNormalTabTapped: (() -> Void)? { get set }
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

    func configurePlusButtonLongPressMenu(isFireModeEnabled: Bool)

}

/// This is what we hope will be the new version long term.
class DefaultTabSwitcherBarsStateHandler: TabSwitcherBarsStateHandling {

    lazy var plusButton: UIBarButtonItem = {
        let item = BrowserChromeButton.createToolbarButtonItem(title: UserText.keyCommandNewTab, image: DesignSystemImages.Glyphs.Size24.add) { [weak self] in
            self?.onPlusButtonTapped?()
        }
        return item
    }()

    lazy var fireButton: UIBarButtonItem = {
        let item = BrowserChromeButton.createToolbarButtonItem(title: "Close all tabs and clear data", image: DesignSystemImages.Glyphs.Size24.fireSolid) { [weak self] in
            self?.onFireButtonTapped?()
        }
        return item
    }()

    lazy var doneIconButton: UIBarButtonItem = {
        let item = BrowserChromeButton.createToolbarButtonItem(title: UserText.navigationTitleDone, image: DesignSystemImages.Glyphs.Size24.arrowLeft) { [weak self] in
            self?.onDoneButtonTapped?()
        }
        return item
    }()

    lazy var doneTextButton: UIBarButtonItem = {
        let item = BrowserChromeButton.createToolbarButtonItem(title: UserText.navigationTitleDone, image: nil) { [weak self] in
            self?.onDoneButtonTapped?()
        }
        (item.customView as? BrowserChromeButton)?.setTitle(UserText.navigationTitleDone, for: .normal)
        Self.applyTextConstraints(to: item)
        return item
    }()

    var doneButton: UIBarButtonItem {
        params.interfaceMode.isLarge ? doneTextButton : doneIconButton
    }

    lazy var closeTabsButton = BrowserChromeButton.createToolbarButtonItem(title: "", image: DesignSystemImages.Glyphs.Size24.trash) { [weak self] in
        self?.onCloseTabsTapped?()
    }

    lazy var menuButton: UIBarButtonItem = {
        let item = BrowserChromeButton.createToolbarButtonItem(title: "More Menu", image: DesignSystemImages.Glyphs.Size24.moreApple)
        return item
    }()

    lazy var tabSwitcherStyleButton: UIBarButtonItem = {
        let item = BrowserChromeButton.createToolbarButtonItem(title: "", image: nil) { [weak self] in
            self?.onTabStyleButtonTapped?()
        }
        return item
    }()

    lazy var editButton: UIBarButtonItem = {
        let item = BrowserChromeButton.createToolbarButtonItem(title: UserText.actionGenericEdit, image: DesignSystemImages.Glyphs.Size24.menuDotsVertical)
        return item
    }()

    lazy var selectAllButton: UIBarButtonItem = {
        let item = BrowserChromeButton.createToolbarButtonItem(title: UserText.selectAllTabs, image: nil) { [weak self] in
            self?.onSelectAllTapped?()
        }
        Self.applyTextConstraints(to: item)
        return item
    }()

    lazy var deselectAllButton: UIBarButtonItem = {
        let item = BrowserChromeButton.createToolbarButtonItem(title: UserText.deselectAllTabs, image: nil) { [weak self] in
            self?.onDeselectAllTapped?()
        }
        Self.applyTextConstraints(to: item)
        return item
    }()

    lazy var duckChatButton: UIBarButtonItem = {
        let item = BrowserChromeButton.createToolbarButtonItem(title: UserText.duckAiFeatureName, image: DesignSystemImages.Glyphs.Size24.aiChat) { [weak self] in
            self?.onDuckChatTapped?()
        }
        return item
    }()

    private(set) var bottomBarItems = [UIBarButtonItem]()
    private(set) var isBottomBarHidden = false
    private(set) var topBarLeftButtons = [UIView]()
    private(set) var topBarRightButtons = [UIView]()

    private var params = StateParameters()

    private(set) var isFirstUpdate = true

    var onPlusButtonTapped: (() -> Void)?
    var onNewFireTabTapped: (() -> Void)?
    var onNewNormalTabTapped: (() -> Void)?
    var onFireButtonTapped: (() -> Void)?
    var onDoneButtonTapped: (() -> Void)?
    var onEditButtonTapped: (() -> UIMenu?)?
    var onTabStyleButtonTapped: (() -> Void)?
    var onSelectAllTapped: (() -> Void)?
    var onDeselectAllTapped: (() -> Void)?
    var onMenuButtonTapped: (() -> UIMenu?)?
    var onCloseTabsTapped: (() -> Void)?
    var onDuckChatTapped: (() -> Void)?

    private static let buttonSize: CGFloat = 44

    init() { }

    private static func applyTextConstraints(to item: UIBarButtonItem) {
        guard let view = item.customView else { return }
        view.widthAnchor.constraint(greaterThanOrEqualToConstant: buttonSize).isActive = true
    }

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
        if let button = tabSwitcherStyleButton.customView as? BrowserChromeButton {
            button.setImage(tabsStyle.image)
            button.accessibilityLabel = tabsStyle.accessibilityLabel
        }

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

    func configurePlusButtonLongPressMenu(isFireModeEnabled: Bool) {
        guard let button = plusButton.customView as? BrowserChromeButton else { return }
        guard isFireModeEnabled else {
            button.menu = nil
            return
        }

        let menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                Pixel.fire(pixel: .tabLongPressMenuDisplayed, withAdditionalParameters: [
                    PixelParameters.source: "tab_switcher"
                ])
                completion([
                    UIAction(title: UserText.actionNewFireTab,
                             image: DesignSystemImages.Glyphs.Size16.fireWindow) { [weak self] _ in
                                 Pixel.fire(pixel: .tabLongPressMenuNewFireTab, withAdditionalParameters: [
                                     PixelParameters.source: "tab_switcher"
                                 ])
                                 self?.onNewFireTabTapped?()
                             },
                    UIAction(title: UserText.actionNewTab,
                             image: DesignSystemImages.Glyphs.Size16.add) { [weak self] _ in
                                 Pixel.fire(pixel: .tabLongPressMenuNewNormalTab, withAdditionalParameters: [
                                     PixelParameters.source: "tab_switcher"
                                 ])
                                 self?.onNewNormalTabTapped?()
                             }
                ])
            }
        ])

        button.menu = menu
        button.showsMenuAsPrimaryAction = false
    }

    private func configureButtons() {
        configureAccessibility(fireButton, label: "Close all tabs and clear data", identifier: "Browser.Toolbar.Button.Fire")
        configureAccessibility(duckChatButton, label: UserText.duckAiFeatureName, identifier: "TabSwitcher.Button.DuckChat")
        configureAccessibility(plusButton, label: UserText.keyCommandNewTab)
        configureAccessibility(doneIconButton, label: UserText.navigationTitleDone)
        configureAccessibility(doneTextButton, label: UserText.navigationTitleDone)
        configureAccessibility(editButton, label: UserText.actionGenericEdit)
        configureAccessibility(selectAllButton, label: UserText.selectAllTabs)
        configureAccessibility(deselectAllButton, label: UserText.deselectAllTabs)
        configureAccessibility(menuButton, label: "More Menu")

        setEnabled(editButton, params.totalCount > 1 || params.containsWebPages)
        setEnabled(closeTabsButton, params.selectedCount > 0)
        let doneEnabled = params.canDismissOnEmpty || params.totalCount > 0
        setEnabled(doneIconButton, doneEnabled)
        setEnabled(doneTextButton, doneEnabled)
    }

    private func configureAccessibility(_ item: UIBarButtonItem, label: String, identifier: String? = nil) {
        item.accessibilityLabel = label
        item.customView?.accessibilityLabel = label
        if let identifier {
            item.accessibilityIdentifier = identifier
            item.customView?.accessibilityIdentifier = identifier
        }
    }

    private func setEnabled(_ item: UIBarButtonItem, _ enabled: Bool) {
        item.isEnabled = enabled
        (item.customView as? UIControl)?.isEnabled = enabled
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

        switch params.interfaceMode {

        case .regularSize:
            topBarLeftButtons = [
                doneIconButton,
            ].views()

        case .largeSize:
            topBarLeftButtons = [
                editButton,
                tabSwitcherStyleButton,
            ].views()

        case .editingRegularSize:
            topBarLeftButtons = [
                doneIconButton,
            ].views()

        case .editingLargeSize:
            topBarLeftButtons = [
                doneTextButton,
            ].views()

        }
    }

    func updateTopRightButtons() {

        switch params.interfaceMode {

        case .largeSize:
            topBarRightButtons = ([
                doneTextButton,
                fireButton,
                plusButton,
                params.showAIChat ? duckChatButton : nil,
            ] as [UIBarButtonItem?]).compactMap { $0 }.views()

        case .regularSize:
            topBarRightButtons = ([
                params.showAIChat ? duckChatButton : nil,
            ] as [UIBarButtonItem?]).compactMap { $0 }.views()

        case .editingRegularSize:
            topBarRightButtons = [
                params.selectedCount == params.totalCount ? deselectAllButton : selectAllButton,
            ].views()

        case .editingLargeSize:
            topBarRightButtons = [
                menuButton,
            ].views()

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

private extension Array where Element == UIBarButtonItem {
    func views() -> [UIView] {
        compactMap { $0.customView }
    }
}
