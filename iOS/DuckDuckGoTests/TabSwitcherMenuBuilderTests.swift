//
//  TabSwitcherMenuBuilderTests.swift
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

import XCTest
@testable import DuckDuckGo

// MARK: - DefaultTabSwitcherMenuBuilder Tests

class DefaultTabSwitcherMenuBuilderTests: XCTestCase {

    var builder: DefaultTabSwitcherMenuBuilder!
    var noopMultiSelectActions: TabSwitcherMultiSelectMenuActions!
    var noopEditActions: TabSwitcherEditMenuActions!
    var noopLongPressActions: TabSwitcherLongPressMenuActions!

    override func setUp() {
        super.setUp()
        builder = DefaultTabSwitcherMenuBuilder()
        noopMultiSelectActions = TabSwitcherMultiSelectMenuActions(
            onDeselectAll: {}, onSelectAll: {}, onShare: {},
            onBookmarkSelected: {}, onCloseOther: {}, onCloseSelected: {}, onBookmarkAll: {}
        )
        noopEditActions = TabSwitcherEditMenuActions(onEnterSelectMode: {}, onCloseAll: {})
        noopLongPressActions = TabSwitcherLongPressMenuActions(
            onShare: {}, onBookmark: {}, onSelect: {}, onClose: {}, onCloseOther: {}
        )
    }

    override func tearDown() {
        builder = nil
        super.tearDown()
    }

    // MARK: - Multi-Select Menu

    func testMultiSelectMenu_whenNothingSelected_showsOnlySelectAll() {
        let state = TabSwitcherMultiSelectMenuState(
            selectedCount: 0, totalCount: 3,
            selectedContainsWebPages: false, allContainsWebPages: false
        )
        let items = builder.multiSelectionMenuItems(state: state, actions: noopMultiSelectActions)
        let actions = flatActions(items)

        XCTAssertTrue(actions.contains(title: UserText.selectAllTabs))
        XCTAssertFalse(actions.contains(title: UserText.deselectAllTabs))
        XCTAssertFalse(actions.contains(title: UserText.tabSwitcherBookmarkAllTabs))
    }

    func testMultiSelectMenu_whenAllSelected_showsDeselectAllAndClose() {
        let state = TabSwitcherMultiSelectMenuState(
            selectedCount: 3, totalCount: 3,
            selectedContainsWebPages: false, allContainsWebPages: false
        )
        let items = builder.multiSelectionMenuItems(state: state, actions: noopMultiSelectActions)
        let actions = flatActions(items)

        XCTAssertTrue(actions.contains(title: UserText.deselectAllTabs))
        XCTAssertFalse(actions.contains(title: UserText.selectAllTabs))
        XCTAssertTrue(actions.contains(title: UserText.closeTabs(withCount: 3)))
    }

    func testMultiSelectMenu_whenSelectedTabsHaveWebPages_showsShareAndBookmark() {
        let state = TabSwitcherMultiSelectMenuState(
            selectedCount: 2, totalCount: 3,
            selectedContainsWebPages: true, allContainsWebPages: true
        )
        let items = builder.multiSelectionMenuItems(state: state, actions: noopMultiSelectActions)
        let actions = flatActions(items)

        XCTAssertTrue(actions.contains(title: UserText.shareLinks(withCount: 2)))
        XCTAssertTrue(actions.contains(title: UserText.bookmarkSelectedTabs(withCount: 2)))
    }

    func testMultiSelectMenu_whenNoWebPages_hidesShareAndBookmark() {
        let state = TabSwitcherMultiSelectMenuState(
            selectedCount: 2, totalCount: 3,
            selectedContainsWebPages: false, allContainsWebPages: false
        )
        let items = builder.multiSelectionMenuItems(state: state, actions: noopMultiSelectActions)
        let actions = flatActions(items)

        XCTAssertFalse(actions.contains(title: UserText.shareLinks(withCount: 2)))
        XCTAssertFalse(actions.contains(title: UserText.bookmarkSelectedTabs(withCount: 2)))
    }

    func testMultiSelectMenu_whenSomeSelectedWithOthersRemaining_showsCloseOther() {
        let state = TabSwitcherMultiSelectMenuState(
            selectedCount: 1, totalCount: 3,
            selectedContainsWebPages: false, allContainsWebPages: false
        )
        let items = builder.multiSelectionMenuItems(state: state, actions: noopMultiSelectActions)
        let actions = flatActions(items)

        XCTAssertTrue(actions.contains(title: UserText.tabSwitcherCloseOtherTabs(withCount: 2)))
    }

    func testMultiSelectMenu_whenAllSelected_hidesCloseOther() {
        let state = TabSwitcherMultiSelectMenuState(
            selectedCount: 3, totalCount: 3,
            selectedContainsWebPages: false, allContainsWebPages: false
        )
        let items = builder.multiSelectionMenuItems(state: state, actions: noopMultiSelectActions)
        let actions = flatActions(items)

        XCTAssertFalse(actions.contains(title: UserText.tabSwitcherCloseOtherTabs(withCount: 2)))
    }

    func testMultiSelectMenu_whenNoneSelectedAndAllHaveWebPages_showsBookmarkAll() {
        let state = TabSwitcherMultiSelectMenuState(
            selectedCount: 0, totalCount: 3,
            selectedContainsWebPages: false, allContainsWebPages: true
        )
        let items = builder.multiSelectionMenuItems(state: state, actions: noopMultiSelectActions)
        let actions = flatActions(items)

        XCTAssertTrue(actions.contains(title: UserText.tabSwitcherBookmarkAllTabs))
    }

    func testMultiSelectMenu_closeUsesCorrectDestructiveAttribute() {
        let state = TabSwitcherMultiSelectMenuState(
            selectedCount: 2, totalCount: 3,
            selectedContainsWebPages: false, allContainsWebPages: false
        )
        let items = builder.multiSelectionMenuItems(state: state, actions: noopMultiSelectActions)
        let closeAction = flatActions(items).first(withTitle: UserText.closeTabs(withCount: 2))

        XCTAssertNotNil(closeAction)
        XCTAssertTrue(closeAction!.attributes.contains(.destructive))
    }

    // MARK: - Edit Menu

    func testEditMenu_alwaysContainsSelectTabsAndCloseAll() {
        let items = builder.editMenuItems(actions: noopEditActions)
        let actions = flatActions(items)

        XCTAssertTrue(actions.contains(title: UserText.tabSwitcherSelectTabs(withCount: 2)))
        XCTAssertTrue(actions.contains(title: UserText.closeAllTabs))
    }

    func testEditMenu_closeAllIsDestructive() {
        let items = builder.editMenuItems(actions: noopEditActions)
        let closeAllAction = flatActions(items).first(withTitle: UserText.closeAllTabs)

        XCTAssertNotNil(closeAllAction)
        XCTAssertTrue(closeAllAction!.attributes.contains(.destructive))
    }

    // MARK: - Long Press Menu

    func testLongPressMenu_singleWebPageTab_showsAllItems() {
        let state = TabSwitcherLongPressMenuState(
            pressedCount: 1, totalCount: 3,
            pressedContainsWebPages: true, isEditing: false, title: "example.com"
        )
        let items = builder.longPressMenuItems(state: state, actions: noopLongPressActions)
        let actions = flatActions(items)

        XCTAssertTrue(actions.contains(title: UserText.shareLinks(withCount: 1)))
        XCTAssertTrue(actions.contains(title: UserText.bookmarkSelectedTabs(withCount: 1)))
        XCTAssertTrue(actions.contains(title: UserText.tabSwitcherSelectTabs(withCount: 1)))
        XCTAssertTrue(actions.contains(title: UserText.closeTabs(withCount: 1)))
        XCTAssertTrue(actions.contains(title: UserText.tabSwitcherCloseOtherTabs(withCount: 2)))
    }

    func testLongPressMenu_homePageTab_hidesShareAndBookmarkButShowsSelect() {
        let state = TabSwitcherLongPressMenuState(
            pressedCount: 1, totalCount: 3,
            pressedContainsWebPages: false, isEditing: false, title: ""
        )
        let items = builder.longPressMenuItems(state: state, actions: noopLongPressActions)
        let actions = flatActions(items)

        XCTAssertFalse(actions.contains(title: UserText.shareLinks(withCount: 1)))
        XCTAssertFalse(actions.contains(title: UserText.bookmarkSelectedTabs(withCount: 1)))
        // Select is available for home page tabs too — long-press is valid to enter selection mode
        XCTAssertTrue(actions.contains(title: UserText.tabSwitcherSelectTabs(withCount: 1)))
        XCTAssertTrue(actions.contains(title: UserText.closeTabs(withCount: 1)))
    }

    func testLongPressMenu_inEditingMode_hidesSelectOption() {
        let state = TabSwitcherLongPressMenuState(
            pressedCount: 1, totalCount: 3,
            pressedContainsWebPages: true, isEditing: true, title: "example.com"
        )
        let items = builder.longPressMenuItems(state: state, actions: noopLongPressActions)
        let actions = flatActions(items)

        XCTAssertFalse(actions.contains(title: UserText.tabSwitcherSelectTabs(withCount: 1)))
    }

    func testLongPressMenu_multipleTabsPressed_hidesSelectOption() {
        let state = TabSwitcherLongPressMenuState(
            pressedCount: 2, totalCount: 3,
            pressedContainsWebPages: true, isEditing: false, title: "2 tabs"
        )
        let items = builder.longPressMenuItems(state: state, actions: noopLongPressActions)
        let actions = flatActions(items)

        XCTAssertFalse(actions.contains(title: UserText.tabSwitcherSelectTabs(withCount: 1)))
    }

    func testLongPressMenu_whenAllTabsPressed_hidesCloseOther() {
        let state = TabSwitcherLongPressMenuState(
            pressedCount: 3, totalCount: 3,
            pressedContainsWebPages: true, isEditing: false, title: "3 tabs"
        )
        let items = builder.longPressMenuItems(state: state, actions: noopLongPressActions)
        let actions = flatActions(items)

        XCTAssertFalse(actions.contains(title: UserText.tabSwitcherCloseOtherTabs(withCount: 2)))
    }

    func testLongPressMenu_closeIsDestructive() {
        let state = TabSwitcherLongPressMenuState(
            pressedCount: 1, totalCount: 3,
            pressedContainsWebPages: false, isEditing: false, title: ""
        )
        let items = builder.longPressMenuItems(state: state, actions: noopLongPressActions)
        let closeAction = flatActions(items).first(withTitle: UserText.closeTabs(withCount: 1))

        XCTAssertNotNil(closeAction)
        XCTAssertTrue(closeAction!.attributes.contains(.destructive))
    }

    // MARK: - Action wiring

    @available(iOS 16, *)
    func testMultiSelectMenu_onDeselectAllCalled() {
        var called = false
        let actions = TabSwitcherMultiSelectMenuActions(
            onDeselectAll: { called = true }, onSelectAll: {}, onShare: {},
            onBookmarkSelected: {}, onCloseOther: {}, onCloseSelected: {}, onBookmarkAll: {}
        )
        let state = TabSwitcherMultiSelectMenuState(
            selectedCount: 3, totalCount: 3,
            selectedContainsWebPages: false, allContainsWebPages: false
        )
        let items = builder.multiSelectionMenuItems(state: state, actions: actions)
        let deselectAction = flatActions(items).first(withTitle: UserText.deselectAllTabs)!
        deselectAction.performWithSender(nil, target: nil)

        XCTAssertTrue(called)
    }

    @available(iOS 16, *)
    func testLongPressMenu_onShareCalled() {
        var called = false
        let actions = TabSwitcherLongPressMenuActions(
            onShare: { called = true }, onBookmark: {}, onSelect: {}, onClose: {}, onCloseOther: {}
        )
        let state = TabSwitcherLongPressMenuState(
            pressedCount: 1, totalCount: 3,
            pressedContainsWebPages: true, isEditing: false, title: ""
        )
        let items = builder.longPressMenuItems(state: state, actions: actions)
        let shareAction = flatActions(items).first(withTitle: UserText.shareLinks(withCount: 1))!
        shareAction.performWithSender(nil, target: nil)

        XCTAssertTrue(called)
    }

    // MARK: - Helpers

    /// Recursively collects all UIActions from a menu element tree.
    private func flatActions(_ elements: [UIMenuElement]) -> [UIAction] {
        elements.flatMap { element -> [UIAction] in
            if let action = element as? UIAction {
                return [action]
            } else if let menu = element as? UIMenu {
                return flatActions(menu.children)
            }
            return []
        }
    }
}

private extension Array where Element == UIAction {
    func contains(title: String) -> Bool {
        contains(where: { $0.title == title })
    }

    func first(withTitle title: String) -> UIAction? {
        first(where: { $0.title == title })
    }
}

// MARK: - TabSwitcherMultiSelectMenuState Tests

class TabSwitcherMultiSelectMenuStateTests: XCTestCase {

    // MARK: canShowDeselectAll

    func testWhenAllTabsSelectedThenCanShowDeselectAll() {
        let state = makeState(selectedCount: 3, totalCount: 3)
        XCTAssertTrue(state.canShowDeselectAll)
    }

    func testWhenNotAllTabsSelectedThenCannotShowDeselectAll() {
        let state = makeState(selectedCount: 2, totalCount: 3)
        XCTAssertFalse(state.canShowDeselectAll)
    }

    func testWhenNoTabsSelectedThenCannotShowDeselectAll() {
        let state = makeState(selectedCount: 0, totalCount: 3)
        XCTAssertFalse(state.canShowDeselectAll)
    }

    // MARK: canShowSelectAll

    func testWhenFewerThanAllSelectedThenCanShowSelectAll() {
        let state = makeState(selectedCount: 2, totalCount: 3)
        XCTAssertTrue(state.canShowSelectAll)
    }

    func testWhenNoTabsSelectedThenCanShowSelectAll() {
        let state = makeState(selectedCount: 0, totalCount: 3)
        XCTAssertTrue(state.canShowSelectAll)
    }

    func testWhenAllTabsSelectedThenCannotShowSelectAll() {
        let state = makeState(selectedCount: 3, totalCount: 3)
        XCTAssertFalse(state.canShowSelectAll)
    }

    // MARK: canShare / canAddBookmarks

    func testWhenSelectedContainsWebPagesThenCanShare() {
        let state = makeState(selectedContainsWebPages: true)
        XCTAssertTrue(state.canShare)
        XCTAssertTrue(state.canAddBookmarks)
    }

    func testWhenSelectedHasNoWebPagesThenCannotShare() {
        let state = makeState(selectedContainsWebPages: false)
        XCTAssertFalse(state.canShare)
        XCTAssertFalse(state.canAddBookmarks)
    }

    // MARK: canCloseOther

    func testWhenSomeSelectedAndOthersExistThenCanCloseOther() {
        let state = makeState(selectedCount: 2, totalCount: 3)
        XCTAssertTrue(state.canCloseOther)
    }

    func testWhenNoneSelectedThenCannotCloseOther() {
        let state = makeState(selectedCount: 0, totalCount: 3)
        XCTAssertFalse(state.canCloseOther)
    }

    func testWhenAllSelectedThenCannotCloseOther() {
        let state = makeState(selectedCount: 3, totalCount: 3)
        XCTAssertFalse(state.canCloseOther)
    }

    func testWhenOnlyOneTabAndItIsSelectedThenCannotCloseOther() {
        let state = makeState(selectedCount: 1, totalCount: 1)
        XCTAssertFalse(state.canCloseOther)
    }

    // MARK: canBookmarkAll

    func testWhenNoneSelectedAndAllHaveWebPagesThenCanBookmarkAll() {
        let state = makeState(selectedCount: 0, allContainsWebPages: true)
        XCTAssertTrue(state.canBookmarkAll)
    }

    func testWhenNoneSelectedButNoWebPagesThenCannotBookmarkAll() {
        let state = makeState(selectedCount: 0, allContainsWebPages: false)
        XCTAssertFalse(state.canBookmarkAll)
    }

    func testWhenSomeSelectedThenCannotBookmarkAll() {
        let state = makeState(selectedCount: 1, allContainsWebPages: true)
        XCTAssertFalse(state.canBookmarkAll)
    }

    // MARK: canClose

    func testWhenTabsSelectedThenCanClose() {
        let state = makeState(selectedCount: 1)
        XCTAssertTrue(state.canClose)
    }

    func testWhenNoneSelectedThenCannotClose() {
        let state = makeState(selectedCount: 0)
        XCTAssertFalse(state.canClose)
    }

    // MARK: hasAnyItems

    func testWhenNoTabsAndNothingSelectedThenHasNoItems() {
        let state = makeState(selectedCount: 0, totalCount: 0,
                              selectedContainsWebPages: false, allContainsWebPages: false)
        XCTAssertFalse(state.canShowSelectionMenu)
    }

    func testWhenTabsExistAndNothingSelectedThenHasItems() {
        // canShowSelectAll = true (0 < 3), canBookmarkAll depends on allContainsWebPages
        let state = makeState(selectedCount: 0, totalCount: 3,
                              selectedContainsWebPages: false, allContainsWebPages: false)
        XCTAssertTrue(state.canShowSelectionMenu) // canShowSelectAll is true
    }

    func testWhenAllTabsSelectedThenHasItems() {
        let state = makeState(selectedCount: 3, totalCount: 3,
                              selectedContainsWebPages: false, allContainsWebPages: false)
        XCTAssertTrue(state.canShowSelectionMenu) // canShowDeselectAll + canClose are true
    }

    // MARK: - Helpers

    private func makeState(selectedCount: Int = 0,
                           totalCount: Int = 5,
                           selectedContainsWebPages: Bool = false,
                           allContainsWebPages: Bool = false) -> TabSwitcherMultiSelectMenuState {
        TabSwitcherMultiSelectMenuState(
            selectedCount: selectedCount,
            totalCount: totalCount,
            selectedContainsWebPages: selectedContainsWebPages,
            allContainsWebPages: allContainsWebPages
        )
    }

}

// MARK: - TabSwitcherLongPressMenuState Tests

class TabSwitcherLongPressMenuStateTests: XCTestCase {

    // MARK: canShare / canAddBookmarks

    func testWhenPressedTabsContainWebPagesThenCanShare() {
        let state = makeState(pressedContainsWebPages: true)
        XCTAssertTrue(state.canShare)
        XCTAssertTrue(state.canAddBookmarks)
    }

    func testWhenPressedTabsHaveNoWebPagesThenCannotShare() {
        let state = makeState(pressedContainsWebPages: false)
        XCTAssertFalse(state.canShare)
        XCTAssertFalse(state.canAddBookmarks)
    }

    // MARK: canSelect

    func testWhenNotEditingAndSingleTabThenCanSelect() {
        let state = makeState(pressedCount: 1, isEditing: false)
        XCTAssertTrue(state.canSelect)
    }

    func testWhenNotEditingAndSingleHomePageTabThenCanSelect() {
        // Home page tabs can also enter selection mode via long-press
        let state = makeState(pressedCount: 1, pressedContainsWebPages: false, isEditing: false)
        XCTAssertTrue(state.canSelect)
    }

    func testWhenEditingThenCannotSelect() {
        let state = makeState(pressedCount: 1, isEditing: true)
        XCTAssertFalse(state.canSelect)
    }

    func testWhenMultipleTabsPressedThenCannotSelect() {
        let state = makeState(pressedCount: 2, isEditing: false)
        XCTAssertFalse(state.canSelect)
    }

    func testWhenEditingAndMultipleTabsThenCannotSelect() {
        let state = makeState(pressedCount: 2, isEditing: true)
        XCTAssertFalse(state.canSelect)
    }

    // MARK: canCloseOthers

    func testWhenFewerTabsPressedThanTotalThenCanCloseOthers() {
        let state = makeState(pressedCount: 1, totalCount: 3)
        XCTAssertTrue(state.canCloseOthers)
    }

    func testWhenAllTabsPressedThenCannotCloseOthers() {
        let state = makeState(pressedCount: 3, totalCount: 3)
        XCTAssertFalse(state.canCloseOthers)
    }

    // MARK: - Helpers

    private func makeState(pressedCount: Int = 1,
                           totalCount: Int = 5,
                           pressedContainsWebPages: Bool = false,
                           isEditing: Bool = false) -> TabSwitcherLongPressMenuState {
        TabSwitcherLongPressMenuState(
            pressedCount: pressedCount,
            totalCount: totalCount,
            pressedContainsWebPages: pressedContainsWebPages,
            isEditing: isEditing,
            title: ""
        )
    }

}
