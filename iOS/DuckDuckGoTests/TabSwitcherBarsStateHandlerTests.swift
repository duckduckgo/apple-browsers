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

    func testWhenInterfaceModeIsRegularSizeThenTopRightButtonsAreSetCorrectly() {
        stateHandler.update(.regularSize(selectedCount: 0, totalCount: 2, containsWebPages: false, showAIChat: false, canDismissOnEmpty: true))

        XCTAssertTrue(stateHandler.topBarRightButtons.isEmpty)
    }

    func testWhenInterfaceModeIsEditingRegularSizeThenTopRightButtonsAreSetCorrectly() {
        stateHandler.update(.editingRegularSize(selectedCount: 0, totalCount: 2))

        XCTAssertEqual(stateHandler.topBarRightButtons.count, 1)
        XCTAssertTrue(stateHandler.topBarRightButtons.contains(stateHandler.selectAllButton.customView!))
    }

    func testWhenShowAIChatButtonIsTrueThenDuckChatButtonIsIncludedInTopRightButtons() {
        stateHandler.update(.regularSize(selectedCount: 0, totalCount: 2, containsWebPages: true, showAIChat: true, canDismissOnEmpty: true))

        XCTAssertTrue(stateHandler.topBarRightButtons.contains(stateHandler.duckChatButton.customView!))
    }

    func testWhenCanShowEditButtonThenEditButtonIsIncludedInBottomBarItems() {
        stateHandler.update(.regularSize(selectedCount: 0, totalCount: 2, containsWebPages: true, showAIChat: false, canDismissOnEmpty: true))

        XCTAssertTrue(stateHandler.bottomBarItems.contains(stateHandler.editButton))
    }

    func testWhenInterfaceModeIsRegularSizeWithAIChatThenTopRightButtonsAreSetCorrectly() {
        stateHandler.update(.regularSize(selectedCount: 0, totalCount: 2, containsWebPages: true, showAIChat: true, canDismissOnEmpty: true))

        XCTAssertEqual(stateHandler.topBarRightButtons.count, 1)
        XCTAssertTrue(stateHandler.topBarRightButtons.contains(stateHandler.duckChatButton.customView!))
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

    func testWhenInterfaceModeIsRegularSizeThenTopLeftButtonsAreSetCorrectly() {
        stateHandler.update(.regularSize(selectedCount: 0, totalCount: 2, containsWebPages: false, showAIChat: false, canDismissOnEmpty: true))

        XCTAssertEqual(stateHandler.topBarLeftButtons.count, 1)
        XCTAssertTrue(stateHandler.topBarLeftButtons.contains(stateHandler.doneIconButton.customView!))
    }

    func testWhenInterfaceModeIsEditingRegularSizeThenTopLeftButtonsAreSetCorrectly() {
        stateHandler.update(.editingRegularSize(selectedCount: 0, totalCount: 2))

        XCTAssertEqual(stateHandler.topBarLeftButtons.count, 1)
        XCTAssertTrue(stateHandler.topBarLeftButtons.contains(stateHandler.doneIconButton.customView!))
    }

    func testWhenInterfaceModeIsLargeSizeThenTopLeftButtonsAreSetCorrectly() {
        stateHandler.update(.largeSize(selectedCount: 0, totalCount: 2, containsWebPages: false, showAIChat: false, canDismissOnEmpty: true))

        XCTAssertEqual(stateHandler.topBarLeftButtons.count, 2)
        XCTAssertTrue(stateHandler.topBarLeftButtons.contains(stateHandler.editButton.customView!))
        XCTAssertTrue(stateHandler.topBarLeftButtons.contains(stateHandler.tabSwitcherStyleButton.customView!))
    }

    func testWhenInterfaceModeIsLargeSizeAndCannotShowEditButtonThenTopLeftButtonsAreSetCorrectly() {
        stateHandler.update(.largeSize(selectedCount: 0, totalCount: 0, containsWebPages: false, showAIChat: false, canDismissOnEmpty: true))

        XCTAssertEqual(stateHandler.topBarLeftButtons.count, 2)
        XCTAssertTrue(stateHandler.topBarLeftButtons.contains(stateHandler.editButton.customView!))
        XCTAssertTrue(stateHandler.topBarLeftButtons.contains(stateHandler.tabSwitcherStyleButton.customView!))
    }

    func testWhenInterfaceModeIsLargeSizeThenTopRightButtonsAreSetCorrectly() {
        stateHandler.update(.largeSize(selectedCount: 0, totalCount: 0, containsWebPages: false, showAIChat: true, canDismissOnEmpty: true))

        XCTAssertEqual(stateHandler.topBarRightButtons.count, 4)
        XCTAssertTrue(stateHandler.topBarRightButtons.contains(stateHandler.doneTextButton.customView!))
        XCTAssertTrue(stateHandler.topBarRightButtons.contains(stateHandler.fireButton.customView!))
        XCTAssertTrue(stateHandler.topBarRightButtons.contains(stateHandler.plusButton.customView!))
        XCTAssertTrue(stateHandler.topBarRightButtons.contains(stateHandler.duckChatButton.customView!))
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
