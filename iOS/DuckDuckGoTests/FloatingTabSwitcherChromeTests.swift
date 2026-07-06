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
    }

    func testWhenRegularSizeWithoutAIChatThenBottomBarHasNoDuckChat() {
        let chrome = makeInstalledChrome()

        chrome.update(state: .regularSize(selectedCount: 0, totalCount: 3, containsWebPages: true, showAIChat: false, canDismissOnEmpty: true),
                      tabsStyle: .grid,
                      canShowSelectionMenu: false,
                      isEditing: false)

        // editMenu, flex, fire, flex, plus
        XCTAssertEqual(chrome.toolbar.items?.count, 5)
    }

    func testWhenRegularSizeWithAIChatThenBottomBarHasDuckChat() {
        let chrome = makeInstalledChrome()

        chrome.update(state: .regularSize(selectedCount: 0, totalCount: 3, containsWebPages: true, showAIChat: true, canDismissOnEmpty: true),
                      tabsStyle: .grid,
                      canShowSelectionMenu: false,
                      isEditing: false)

        // editMenu, flex, fire, flex, plus, duckChat
        XCTAssertEqual(chrome.toolbar.items?.count, 6)
    }

    func testWhenEditingThenTopBarHasCloseAndSelectAll() {
        let chrome = makeInstalledChrome()
        chrome.setTitle("2 Selected")

        chrome.update(state: .editingRegularSize(selectedCount: 2, totalCount: 4),
                      tabsStyle: .grid,
                      canShowSelectionMenu: true,
                      isEditing: true)

        XCTAssertEqual(chrome.navigationItem.title, "2 Selected")
        XCTAssertNil(chrome.navigationItem.titleView)
        XCTAssertEqual(chrome.navigationItem.rightBarButtonItems?.first?.title, UserText.selectAllTabs)
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

        XCTAssertEqual(chrome.toolbar.items?.last?.isEnabled, false)
    }

    func testWhenTabsSelectedWhileEditingThenCloseTabsEnabled() {
        let chrome = makeInstalledChrome()

        chrome.update(state: .editingRegularSize(selectedCount: 2, totalCount: 4),
                      tabsStyle: .grid,
                      canShowSelectionMenu: true,
                      isEditing: true)

        XCTAssertEqual(chrome.toolbar.items?.last?.isEnabled, true)
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
