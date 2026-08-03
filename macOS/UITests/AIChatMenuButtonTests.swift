//
//  AIChatMenuButtonTests.swift
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

/// Coverage for the single "Ask Duck.ai" pill layout (aiChatChromeMenuButton ON, the shipping default).
/// The split-button layout is covered by `AIChatTests` with the flag forced off.
class AIChatMenuButtonTests: UITestCase {
    private var addressBarTextField: XCUIElement!

    private enum Identifiers {
        /// The pill reuses the split-button title-button identifier; clicking it opens the dropdown.
        static let pillButton = "TabBarViewController.duckAIChromeTitleButton"
        /// The split sidebar sub-button, force-hidden in menu-button layout.
        static let sidebarButton = "TabBarViewController.duckAIChromeSidebarButton"
        static let showDuckAIButtonInTabBarToggle = "Preferences.AIChat.showDuckAIButtonInTabBarToggle"
        static let detachButton = "AIChatViewController.detachButton"
    }

    /// Dropdown / context-menu item identifiers (AppKit derives these from the @objc action selector names).
    private enum MenuItemIdentifiers {
        static let newChat = "duckAIMenuNewChatAction"
        static let sidebar = "duckAIMenuSidebarAction"
        static let hideDuckAI = "hideDuckAITitleButtonAction"
    }

    /// Menu-item titles (from UserText); the sidebar item's title is state-dependent.
    private enum MenuTitles {
        static let newChat = "New Chat"
        static let askAboutPage = "Ask About Page"
        static let openSidebar = "Open Sidebar"
        static let closeSidebar = "Close Sidebar"
        static let hideAskDuckAI = "Hide Ask Duck.ai Button"
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp(featureFlags: [
            "aiChatChromeSidebar": true,
            "aiChatSidebarFloating": true,
            "aiChatChromeMenuButton": true // the layout under test
        ])

        addressBarTextField = app.addressBar
        app.enforceSingleWindow()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        app.terminate()
    }

    // MARK: - Helpers

    private var pillButton: XCUIElement {
        app.buttons[Identifiers.pillButton].firstMatch
    }

    private var newChatMenuItem: XCUIElement {
        app.menuItems[MenuItemIdentifiers.newChat].firstMatch
    }

    private var sidebarMenuItem: XCUIElement {
        app.menuItems[MenuItemIdentifiers.sidebar].firstMatch
    }

    private var detachButton: XCUIElement {
        app.buttons[Identifiers.detachButton]
    }

    /// Clicks the pill to present its dropdown and waits for the items to appear.
    private func openDropdown() {
        XCTAssertTrue(pillButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Ask Duck.ai pill should exist in menu-button layout")
        pillButton.click()
        XCTAssertTrue(newChatMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Clicking the pill should present the dropdown")
    }

    private func dismissMenu() {
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - Layout

    func test_menuButtonLayout_showsPill_andHidesSidebarSubButton() {
        XCTAssertTrue(pillButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Ask Duck.ai pill should exist")
        // The split sidebar sub-button is force-hidden in this layout.
        XCTAssertFalse(app.buttons[Identifiers.sidebarButton].isHittable,
                       "The split sidebar sub-button should not be shown in menu-button layout")
    }

    // MARK: - Dropdown

    func test_pillClick_opensDropdown_withNewChatAndSidebarItems() {
        openDropdown()
        XCTAssertTrue(newChatMenuItem.exists, "Dropdown should contain a New Chat item")
        XCTAssertTrue(sidebarMenuItem.exists, "Dropdown should contain the sidebar item")
        dismissMenu()
    }

    /// On the new-tab page there's nothing to attach, so the sidebar item reads "Open Sidebar".
    func test_menu_onNewTabPage_showsOpenSidebar_andOpensSidebar() {
        // We start on NTP after enforceSingleWindow.
        openDropdown()
        XCTAssertEqual(sidebarMenuItem.label, MenuTitles.openSidebar,
                       "On the new-tab page the sidebar item should read 'Open Sidebar'")
        sidebarMenuItem.click()

        XCTAssertTrue(detachButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Clicking 'Open Sidebar' should open the docked sidebar")
    }

    /// On a real web page the sidebar item reads "Ask About Page" and opens the sidebar.
    /// (The page-content attachment itself is covered by unit tests.)
    func test_menu_onWebsite_showsAskAboutPage_andOpensSidebar() {
        addressBarTextField.typeURL(UITests.simpleServedPage(titled: "Ask About Page Test"))

        openDropdown()
        XCTAssertEqual(sidebarMenuItem.label, MenuTitles.askAboutPage,
                       "On a web page the sidebar item should read 'Ask About Page'")
        sidebarMenuItem.click()

        XCTAssertTrue(detachButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Clicking 'Ask About Page' should open the docked sidebar")
    }

    // MARK: - New Chat

    func test_menu_newChat_opensNewTab() {
        addressBarTextField.typeURL(UITests.simpleServedPage(titled: "New Chat Test"))

        let tabsBefore = app.tabGroups.matching(identifier: "Tabs").radioButtons.count

        openDropdown()
        XCTAssertEqual(newChatMenuItem.label, MenuTitles.newChat)
        newChatMenuItem.click()

        let tabsAfter = app.tabGroups.matching(identifier: "Tabs").radioButtons.count
        XCTAssertEqual(tabsAfter, tabsBefore + 1,
                       "Clicking 'New Chat' should open a new Duck.ai tab")
    }

    // MARK: - Close Sidebar

    /// With a chat already presented the sidebar item becomes "Close Sidebar" and closes it.
    func test_menu_whenChatOpen_showsCloseSidebar_andCloses() {
        // Open the sidebar first (NTP → "Open Sidebar").
        openDropdown()
        XCTAssertEqual(sidebarMenuItem.label, MenuTitles.openSidebar)
        sidebarMenuItem.click()
        XCTAssertTrue(detachButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Sidebar should be open before testing close")

        // Re-open the dropdown: the item should now offer to close the sidebar.
        openDropdown()
        XCTAssertEqual(sidebarMenuItem.label, MenuTitles.closeSidebar,
                       "With a chat open the sidebar item should read 'Close Sidebar'")
        sidebarMenuItem.click()

        XCTAssertTrue(detachButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
                      "Clicking 'Close Sidebar' should close the sidebar")
    }

    // MARK: - Context Menu

    func test_contextMenu_hideAskDuckAIButton() {
        XCTAssertTrue(pillButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        pillButton.rightClick()
        let hideItem = app.menuItems[MenuItemIdentifiers.hideDuckAI].firstMatch
        XCTAssertTrue(hideItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Context menu should offer to hide the Ask Duck.ai button")
        XCTAssertEqual(hideItem.label, MenuTitles.hideAskDuckAI,
                       "The hide item should use the 'Ask Duck.ai' wording in menu-button layout")
        hideItem.click()

        XCTAssertTrue(pillButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
                      "Pill should be hidden after using the context menu")

        // Re-enable via settings and confirm it returns.
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)
        let toggle = app.checkBoxes[Identifiers.showDuckAIButtonInTabBarToggle]
        XCTAssertTrue(toggle.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(toggle.isOn, "Settings toggle should reflect the hidden state")
        toggle.click()
        XCTAssertTrue(pillButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Pill should reappear after re-enabling in settings")
    }
}
