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
import UIKit
import Core
import DesignResourcesKit

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

@MainActor
final class TabViewCellSelectionAppearanceTests: XCTestCase {

    func testSelectionAccentIsShockingGreenInLightAndDarkMode() {
        let color = UIColor(singleUseColor: .tabSwitcherSelectionAccent)

        assertShockingGreen(color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)))
        assertShockingGreen(color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)))
    }

    func testSelectedNormalTabUsesSelectionAccent() {
        let tab = Tab(fireTab: false)
        let cell = makeCell(tab: tab, isSelectionModeEnabled: true, isSelected: true)

        assertSelectionAccent(on: cell)
    }

    func testSelectedFireTabUsesSelectionAccent() {
        let tab = Tab(fireTab: true)
        let cell = makeCell(tab: tab, isSelectionModeEnabled: true, isSelected: true)

        assertSelectionAccent(on: cell)
    }

    func testDeselectedTabHasNoBorder() {
        let tab = Tab(fireTab: false)
        let cell = makeCell(tab: tab, isSelectionModeEnabled: true, isSelected: false)

        XCTAssertEqual(cell.border.layer.borderWidth, TabViewCell.Constants.unselectedBorderWidth)
    }

    func testCurrentNormalTabOutsideSelectionModeKeepsCurrentTabAccent() {
        let tab = Tab(fireTab: false)
        let cell = makeCell(tab: tab, isSelectionModeEnabled: false, isSelected: false, isCurrent: true)

        assertBorderColor(UIColor(designSystemColor: .decorationTertiary), on: cell)
    }

    func testCurrentFireTabOutsideSelectionModeKeepsFireAccent() {
        let tab = Tab(fireTab: true)
        let cell = makeCell(tab: tab, isSelectionModeEnabled: false, isSelected: false, isCurrent: true)

        assertBorderColor(UIColor(singleUseColor: .fireModeAccent), on: cell)
    }

    private func makeCell(tab: Tab,
                          isSelectionModeEnabled: Bool,
                          isSelected: Bool,
                          isCurrent: Bool = false) -> TabViewCell {
        let cell = TabViewCell(frame: .zero)
        cell.tab = tab
        cell.isSelectionModeEnabled = isSelectionModeEnabled
        cell.isSelected = isSelected
        cell.isCurrent = isCurrent
        cell.refreshSelectionAppearance()
        return cell
    }

    private func assertSelectionAccent(on cell: TabViewCell, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(cell.border.layer.borderWidth, TabViewCell.Constants.selectedBorderWidth, file: file, line: line)
        assertBorderColor(UIColor(singleUseColor: .tabSwitcherSelectionAccent), on: cell, file: file, line: line)
        XCTAssertNotNil(cell.selectionIndicator.image, file: file, line: line)
        assertShockingGreen(cell.selectionAccentColor, file: file, line: line)
    }

    private func assertBorderColor(_ expectedColor: UIColor,
                                   on cell: TabViewCell,
                                   file: StaticString = #filePath,
                                   line: UInt = #line) {
        guard let borderColor = cell.border.layer.borderColor else {
            XCTFail("Missing border color", file: file, line: line)
            return
        }
        assertColor(UIColor(cgColor: borderColor), matches: expectedColor.resolvedColor(with: cell.traitCollection), file: file, line: line)
    }

    private func assertShockingGreen(_ color: UIColor, file: StaticString = #filePath, line: UInt = #line) {
        assertColor(color,
                    matches: UIColor(red: 57.0 / 255.0, green: 1, blue: 20.0 / 255.0, alpha: 1),
                    file: file,
                    line: line)
    }

    private func assertColor(_ color: UIColor,
                             matches expectedColor: UIColor,
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        var expectedRed: CGFloat = 0
        var expectedGreen: CGFloat = 0
        var expectedBlue: CGFloat = 0
        var expectedAlpha: CGFloat = 0

        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha), file: file, line: line)
        XCTAssertTrue(expectedColor.getRed(&expectedRed,
                                           green: &expectedGreen,
                                           blue: &expectedBlue,
                                           alpha: &expectedAlpha), file: file, line: line)
        XCTAssertEqual(red, expectedRed, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(green, expectedGreen, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(blue, expectedBlue, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(alpha, expectedAlpha, accuracy: 0.001, file: file, line: line)
    }
}
