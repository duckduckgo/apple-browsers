//
//  FloatingTabSwitcherChromeTests.swift
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

import XCTest
import UIKit
@testable import DuckDuckGo

@MainActor
final class FloatingTabSwitcherChromeTests: XCTestCase {

    private func makeInstalledChrome() -> FloatingTabSwitcherChrome {
        let chrome = FloatingTabSwitcherChrome()
        let host = UIView()
        let content = UIScrollView()
        chrome.install(in: host, contentView: content)
        return chrome
    }

    func testWhenRegularSizeThenTopBarHasStyleMenuAndDone() {
        let chrome = makeInstalledChrome()

        chrome.update(state: .regularSize(selectedCount: 0, totalCount: 3, containsWebPages: true, showAIChat: false, canDismissOnEmpty: true),
                      tabsStyle: .grid,
                      canShowSelectionMenu: false,
                      isEditing: false)

        XCTAssertEqual(chrome.navigationItem.leftBarButtonItems?.count, 1)
        XCTAssertEqual(chrome.navigationItem.rightBarButtonItems?.count, 1)
        XCTAssertNil(chrome.navigationItem.title)
        XCTAssertNotNil(chrome.navigationItem.leftBarButtonItems?.first?.menu)
        if #unavailable(iOS 26.0) {
            XCTAssertEqual(chrome.navigationItem.rightBarButtonItems?.first?.title, UserText.navigationTitleDone)
        }
    }

    func testWhenRegularSizeWithoutAIChatThenBottomBarHasNoDuckChat() {
        let chrome = makeInstalledChrome()

        chrome.update(state: .regularSize(selectedCount: 0, totalCount: 3, containsWebPages: true, showAIChat: false, canDismissOnEmpty: true),
                      tabsStyle: .grid,
                      canShowSelectionMenu: false,
                      isEditing: false)

        if #available(iOS 26.0, *) {
            XCTAssertEqual(chrome.toolbar.items?.count, 5)
        } else {
            XCTAssertEqual(chrome.toolbar.items?.count, 7)
            XCTAssertEqual(chrome.toolbar.items?.first?.width, 20)
            XCTAssertEqual(chrome.toolbar.items?.last?.width, 20)
        }
    }

    func testWhenRegularSizeWithAIChatThenBottomBarHasDuckChat() {
        let chrome = makeInstalledChrome()

        chrome.update(state: .regularSize(selectedCount: 0, totalCount: 3, containsWebPages: true, showAIChat: true, canDismissOnEmpty: true),
                      tabsStyle: .grid,
                      canShowSelectionMenu: false,
                      isEditing: false)

        if #available(iOS 26.0, *) {
            XCTAssertEqual(chrome.toolbar.items?.count, 6)
        } else {
            XCTAssertEqual(chrome.toolbar.items?.count, 9)
            XCTAssertEqual(chrome.toolbar.items?[6].width, 12)
        }
    }

    func testWhenEditingThenTopBarHasLeadingTitleAndSelectAll() {
        let chrome = makeInstalledChrome()
        chrome.setTitle("2 Selected")

        chrome.update(state: .editingRegularSize(selectedCount: 2, totalCount: 4),
                      tabsStyle: .grid,
                      canShowSelectionMenu: true,
                      isEditing: true)

        XCTAssertEqual((chrome.navigationItem.leftBarButtonItems?.first?.customView as? UILabel)?.text, "2 Selected")
        XCTAssertEqual(chrome.navigationItem.leftBarButtonItems?.count, 1)
        XCTAssertNil(chrome.navigationItem.title)
        XCTAssertNil(chrome.navigationItem.titleView)
        XCTAssertEqual(chrome.navigationItem.rightBarButtonItems?.first?.title, UserText.selectAllTabs)
    }

    func testWhenEditingThenBottomBarHasDoneCloseTabsAndMenu() {
        let chrome = makeInstalledChrome()
        chrome.actions.onMultiSelectMenuRequested = { UIMenu(children: []) }

        chrome.update(state: .editingRegularSize(selectedCount: 2, totalCount: 4),
                      tabsStyle: .grid,
                      canShowSelectionMenu: true,
                      isEditing: true)

        let items = chrome.toolbar.items ?? []
        let doneIndex = items.firstIndex { $0.accessibilityLabel == UserText.navigationTitleDone }
        let closeTabsIndex = items.firstIndex { $0.title == UserText.closeTabs(withCount: 2) }
        let menuIndex = items.firstIndex { $0.menu != nil }

        guard let doneIndex, let closeTabsIndex, let menuIndex else {
            XCTFail("Missing selection toolbar items")
            return
        }
        XCTAssertLessThan(doneIndex, closeTabsIndex)
        XCTAssertLessThan(closeTabsIndex, menuIndex)
    }

    func testWhenAllSelectedWhileEditingThenShowsDeselectAll() {
        let chrome = makeInstalledChrome()

        chrome.update(state: .editingRegularSize(selectedCount: 4, totalCount: 4),
                      tabsStyle: .grid,
                      canShowSelectionMenu: true,
                      isEditing: true)

        XCTAssertEqual(chrome.navigationItem.rightBarButtonItems?.first?.title, UserText.deselectAllTabs)
    }

    func testWhenNoTabsSelectedWhileEditingThenCloseTabsDisabled() {
        let chrome = makeInstalledChrome()

        chrome.update(state: .editingRegularSize(selectedCount: 0, totalCount: 4),
                      tabsStyle: .grid,
                      canShowSelectionMenu: false,
                      isEditing: true)

        let closeTabsItem = chrome.toolbar.items?.first { $0.title == UserText.closeTabs(withCount: 0) }
        XCTAssertEqual(closeTabsItem?.isEnabled, false)
    }

    func testWhenTabsSelectedWhileEditingThenCloseTabsEnabled() {
        let chrome = makeInstalledChrome()

        chrome.update(state: .editingRegularSize(selectedCount: 2, totalCount: 4),
                      tabsStyle: .grid,
                      canShowSelectionMenu: true,
                      isEditing: true)

        let closeTabsItem = chrome.toolbar.items?.first { $0.title == UserText.closeTabs(withCount: 2) }
        XCTAssertEqual(closeTabsItem?.isEnabled, true)
    }

    func testWhenStyleMenuBuiltThenItHasGridAndListActions() {
        let chrome = makeInstalledChrome()

        chrome.update(state: .regularSize(selectedCount: 0, totalCount: 3, containsWebPages: true, showAIChat: false, canDismissOnEmpty: true),
                      tabsStyle: .grid,
                      canShowSelectionMenu: false,
                      isEditing: false)

        let menu = chrome.navigationItem.leftBarButtonItems?.first?.menu
        let actions = menu?.children.compactMap { $0 as? UIAction } ?? []
        XCTAssertEqual(actions.count, 2)
        XCTAssertTrue(actions.contains { $0.title == UserText.tabSwitcherGridViewMenuTitle && $0.state == .on })
        XCTAssertTrue(actions.contains { $0.title == UserText.tabSwitcherListViewMenuTitle && $0.state == .off })
    }

    func testWhenLayoutIsAppliedMultipleTimesThenPreviousConstraintsAreDeactivated() {
        let chrome = FloatingTabSwitcherChrome()
        let host = UIView()
        let content = UIScrollView()
        chrome.install(in: host, contentView: content)

        chrome.layout(addressBarPosition: .top, interfaceMode: .regularSize)
        let firstHostConstraintCount = host.constraints.count
        let firstContentConstraints = host.constraints.filter { $0.firstItem === content || $0.secondItem === content }

        chrome.layout(addressBarPosition: .top, interfaceMode: .regularSize)
        let secondHostConstraintCount = host.constraints.count
        let secondContentConstraints = host.constraints.filter { $0.firstItem === content || $0.secondItem === content }

        XCTAssertEqual(firstHostConstraintCount, secondHostConstraintCount)
        XCTAssertEqual(firstContentConstraints.count, 4)
        XCTAssertEqual(secondContentConstraints.count, 4)
        XCTAssertTrue(firstContentConstraints.allSatisfy { !$0.isActive })
        XCTAssertTrue(secondContentConstraints.allSatisfy(\.isActive))
    }
}
