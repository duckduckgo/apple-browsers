//
//  TabSwitcherBarsStateHandlerTests.swift
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
import Core

@testable import DuckDuckGo

class TabSwitcherBarsStateHandlerTests: XCTestCase {

    var stateHandler: TabSwitcherBarsStateHandling!

    override func setUp() {
        super.setUp()
        stateHandler = DefaultTabSwitcherBarsStateHandler()
    }

    override func tearDown() {
        stateHandler = nil
        super.tearDown()
    }

    func testWhenNoPagesThenEditButtonVisibleButDisabled() {
        stateHandler.update(.regularSize(selectedCount: 0, totalCount: 1, containsWebPages: false, showAIChat: true, canDismissOnEmpty: true))

        let items = stateHandler.bottomBarItems
        XCTAssertEqual(items.count, 9)
        XCTAssertEqual(items[0], stateHandler.tabSwitcherStyleButton)
        XCTAssertEqual(items[4], stateHandler.fireButton)
        XCTAssertEqual(items[6], stateHandler.plusButton)
        XCTAssertEqual(items[8], stateHandler.editButton)

        XCTAssertFalse(stateHandler.isBottomBarHidden)
        XCTAssertFalse(stateHandler.editButton.isEnabled)
    }

    func testWhenDuckChatEnabledThenBottomBarItemsAreSetCorrectly() {
        stateHandler.update(.regularSize(selectedCount: 0, totalCount: 2, containsWebPages: true, showAIChat: true, canDismissOnEmpty: true))

        // Check that the expected items are present in the correct order
        let items = stateHandler.bottomBarItems
        XCTAssertEqual(items.count, 9)
        XCTAssertEqual(items[0], stateHandler.tabSwitcherStyleButton)
        XCTAssertEqual(items[4], stateHandler.fireButton)
        XCTAssertEqual(items[6], stateHandler.plusButton)
        XCTAssertEqual(items[8], stateHandler.editButton)

        XCTAssertFalse(stateHandler.isBottomBarHidden)
        XCTAssertTrue(stateHandler.editButton.isEnabled)
    }

    func testWhenInterfaceModeIsEditingRegularSizeThenBottomBarItemsAreSetCorrectly() {
        stateHandler.update(.editingRegularSize(selectedCount: 0, totalCount: 0))

        // Check that the expected items are present
        let items = stateHandler.bottomBarItems
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0], stateHandler.closeTabsButton)
        XCTAssertEqual(items[2], stateHandler.menuButton)

        XCTAssertFalse(stateHandler.isBottomBarHidden)
    }

    func testWhenInterfaceModeIsEditingLargeThenBottomBarIsHidden() {
        stateHandler.update(.editingLargeSize(selectedCount: 0, totalCount: 0))

        XCTAssertTrue(stateHandler.bottomBarItems.isEmpty)
        XCTAssertTrue(stateHandler.isBottomBarHidden)
    }

    func testWhenInterfaceModeIsRegularSizeThenTopRightButtonItemsAreSetCorrectly() {
        stateHandler.update(.regularSize(selectedCount: 0, totalCount: 2, containsWebPages: false, showAIChat: false, canDismissOnEmpty: true))

        XCTAssertEqual(stateHandler.topBarRightButtonItems, [])
    }

    func testWhenInterfaceModeIsEditingRegularSizeThenTopRightButtonItemsAreSetCorrectly() {
        stateHandler.update(.editingRegularSize(selectedCount: 0, totalCount: 2))

        XCTAssertEqual(stateHandler.topBarRightButtonItems, [
            stateHandler.selectAllButton
        ])
    }

    func testWhenShowAIChatButtonIsTrueThenDuckChatButtonIsIncludedInTopRightButtons() {
        stateHandler.update(.regularSize(selectedCount: 0, totalCount: 2, containsWebPages: true, showAIChat: true, canDismissOnEmpty: true))

        XCTAssertTrue(stateHandler.topBarRightButtonItems.contains(stateHandler.duckChatButton))
    }

    func testWhenCanShowEditButtonThenEditButtonIsIncludedInBottomBarItems() {
        stateHandler.update(.regularSize(selectedCount: 0, totalCount: 2, containsWebPages: true, showAIChat: false, canDismissOnEmpty: true))

        XCTAssertTrue(stateHandler.bottomBarItems.contains(stateHandler.editButton))
    }

    func testWhenInterfaceModeIsRegularSizeWithAIChatThenTopRightButtonItemsAreSetCorrectly() {
        stateHandler.update(.regularSize(selectedCount: 0, totalCount: 2, containsWebPages: true, showAIChat: true, canDismissOnEmpty: true))

        XCTAssertEqual(stateHandler.topBarRightButtonItems, [
            stateHandler.duckChatButton
        ])
    }

    func testWhenTotalTabsCountIsGreaterThanOneThenCanShowEditButtonIsTrue() {
        stateHandler.update(.regularSize(selectedCount: 0, totalCount: 2, containsWebPages: false, showAIChat: false, canDismissOnEmpty: true))

        XCTAssertTrue(stateHandler.editButton.isEnabled)
    }

    func testWhenContainsWebPagesIsTrueThenCanShowEditButtonIsTrue() {
        stateHandler.update(.regularSize(selectedCount: 0, totalCount: 0, containsWebPages: true, showAIChat: false, canDismissOnEmpty: true))

        XCTAssertTrue(stateHandler.editButton.isEnabled)
    }

    func testWhenNotEnoughTabsAndNowWebPagesEditButtonIsDisabled() {
        stateHandler.update(.regularSize(selectedCount: 0, totalCount: 0, containsWebPages: false, showAIChat: false, canDismissOnEmpty: true))

        XCTAssertFalse(stateHandler.editButton.isEnabled)
    }

    func testWhenInterfaceModeIsLargeSizeThenBottomBarIsHidden() {
        stateHandler.update(.largeSize(selectedCount: 0, totalCount: 0, containsWebPages: false, showAIChat: false, canDismissOnEmpty: true))

        XCTAssertTrue(stateHandler.bottomBarItems.isEmpty)
        XCTAssertTrue(stateHandler.isBottomBarHidden)
    }

    func testWhenInterfaceModeIsRegularSizeThenTopLeftButtonItemsAreSetCorrectly() {
        stateHandler.update(.regularSize(selectedCount: 0, totalCount: 2, containsWebPages: false, showAIChat: false, canDismissOnEmpty: true))

        XCTAssertEqual(stateHandler.topBarLeftButtonItems, [
            stateHandler.doneButton
        ])
    }

    func testWhenInterfaceModeIsEditingRegularSizeThenTopLeftButtonItemsAreSetCorrectly() {
        stateHandler.update(.editingRegularSize(selectedCount: 0, totalCount: 2))

        XCTAssertEqual(stateHandler.topBarLeftButtonItems, [
            stateHandler.doneButton
        ])
    }

    func testWhenInterfaceModeIsLargeSizeThenTopLeftButtonItemsAreSetCorrectly() {
        stateHandler.update(.largeSize(selectedCount: 0, totalCount: 2, containsWebPages: false, showAIChat: false, canDismissOnEmpty: true))

        XCTAssertEqual(stateHandler.topBarLeftButtonItems, [
            stateHandler.editButton,
            stateHandler.tabSwitcherStyleButton
        ])
    }

    func testWhenInterfaceModeIsLargeSizeAndCannotShowEditButtonThenTopLeftButtonItemsAreSetCorrectly() {
        stateHandler.update(.largeSize(selectedCount: 0, totalCount: 0, containsWebPages: false, showAIChat: false, canDismissOnEmpty: true))

        XCTAssertEqual(stateHandler.topBarLeftButtonItems, [
            stateHandler.editButton,
            stateHandler.tabSwitcherStyleButton,
        ])
    }

    func testWhenInterfaceModeIsLargeSizeThenTopRightButtonItemsAreSetCorrectly() {
        stateHandler.update(.largeSize(selectedCount: 0, totalCount: 0, containsWebPages: false, showAIChat: true, canDismissOnEmpty: true))

        XCTAssertEqual(stateHandler.topBarRightButtonItems, [
            stateHandler.doneButton,
            stateHandler.fireButton,
            stateHandler.plusButton,
            stateHandler.duckChatButton,
        ])
    }

    // MARK: - Done Button (Fire Mode)

    func testWhenCanDismissOnEmptyAndNoTabsThenDoneButtonIsEnabled() {
        stateHandler.update(.regularSize(selectedCount: 0, totalCount: 0, containsWebPages: false, showAIChat: false, canDismissOnEmpty: true))

        XCTAssertTrue(stateHandler.doneButton.isEnabled)
    }

    func testWhenCannotDismissOnEmptyAndNoTabsThenDoneButtonIsDisabled() {
        stateHandler.update(.regularSize(selectedCount: 0, totalCount: 0, containsWebPages: false, showAIChat: false, canDismissOnEmpty: false))

        XCTAssertFalse(stateHandler.doneButton.isEnabled)
    }

    func testWhenCannotDismissOnEmptyButHasTabsThenDoneButtonIsEnabled() {
        stateHandler.update(.regularSize(selectedCount: 0, totalCount: 2, containsWebPages: true, showAIChat: false, canDismissOnEmpty: false))

        XCTAssertTrue(stateHandler.doneButton.isEnabled)
    }

    func testWhenCannotDismissOnEmptyAndNoTabsLargeSizeThenDoneButtonIsDisabled() {
        stateHandler.update(.largeSize(selectedCount: 0, totalCount: 0, containsWebPages: false, showAIChat: false, canDismissOnEmpty: false))

        XCTAssertFalse(stateHandler.doneButton.isEnabled)
    }

}
