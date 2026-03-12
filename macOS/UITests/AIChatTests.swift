//
//  AIChatTests.swift
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

class AIChatTests: UITestCase {
    private var addressBarTextField: XCUIElement!

    private enum Identifiers {
        static let duckAIControlContainer = "TabBarViewController.duckAIChromeControlContainer"
        static let duckAITitleButton = "TabBarViewController.duckAIChromeTitleButton"
        static let sidebarButton = "TabBarViewController.duckAIChromeSidebarButton"
        static let aiChatButton = "AddressBarButtonsViewController.aiChatButton"
        static let showDuckAIButtonInTabBarToggle = "Preferences.AIChat.showDuckAIButtonInTabBarToggle"
        static let showSidebarButtonInTabBarToggle = "Preferences.AIChat.showSidebarButtonInTabBarToggle"
    }

    /// Context menu item identifiers (derived from @objc selector names)
    private enum ContextMenuIdentifiers {
        static let hideDuckAI = "hideDuckAITitleButtonAction"
        static let showDuckAI = "showDuckAITitleButtonAction"
        static let hideSidebar = "hideDuckAISidebarButtonAction"
        static let showSidebar = "showDuckAISidebarButtonAction"
        static let openSettings = "openAISettingsAction"
    }

    /// The sidebar button's accessibility title when the sidebar is open.
    private let sidebarOpenTitle = "Close Duck.ai sidebar"
    /// The sidebar button's accessibility title when the sidebar is closed.
    private let sidebarClosedTitle = "Open Duck.ai sidebar"

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp(featureFlags: ["aiChatChromeSidebar": true])

        addressBarTextField = app.addressBar
        app.enforceSingleWindow()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        app.terminate()
    }

    // MARK: - Helpers

    private var duckAITitleButton: XCUIElement {
        app.windows.firstMatch.buttons[Identifiers.duckAITitleButton]
    }

    private var sidebarButton: XCUIElement {
        app.windows.firstMatch.buttons[Identifiers.sidebarButton]
    }

    /// Waits for the sidebar button's accessibility title to match the expected value.
    /// `setAccessibilityTitle()` maps to AXTitle → XCUIElement's `title` property.
    private func waitForSidebarButtonTitle(_ expectedTitle: String, timeout: TimeInterval = UITests.Timeouts.elementExistence) -> Bool {
        let predicate = NSPredicate(format: "title == %@", expectedTitle)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: sidebarButton)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    // MARK: - Split Button Existence

    func test_duckAISplitButtonExists_byDefault() throws {
        XCTAssertTrue(duckAITitleButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Duck.ai title button should exist")
        XCTAssertTrue(sidebarButton.exists, "Sidebar button should exist")
    }

    // MARK: - Duck.ai Title Button Opens New Tab

    func test_duckAITitleButton_opensNewTab_whenOnWebsite() throws {
        // Navigate to a website so we're not on NTP
        addressBarTextField.typeURL(URL(string: "duck://settings/general")!)

        XCTAssertTrue(duckAITitleButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Count tabs before clicking
        let tabsBefore = app.tabGroups.matching(identifier: "Tabs").radioButtons.count

        duckAITitleButton.click()

        // A new tab should have been opened
        let tabsAfter = app.tabGroups.matching(identifier: "Tabs").radioButtons.count
        XCTAssertEqual(tabsAfter, tabsBefore + 1,
                       "Clicking Duck.ai title button on a website should open a new tab")
    }

    func test_duckAITitleButton_loadsInCurrentTab_whenOnNewTabPage() throws {
        // We start on NTP after enforceSingleWindow
        XCTAssertTrue(duckAITitleButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Count tabs before clicking
        let tabsBefore = app.tabGroups.matching(identifier: "Tabs").radioButtons.count

        duckAITitleButton.click()

        // Should load in the same tab, not open a new one
        let tabsAfter = app.tabGroups.matching(identifier: "Tabs").radioButtons.count
        XCTAssertEqual(tabsAfter, tabsBefore,
                       "Clicking Duck.ai title button on NTP should load in current tab, not open a new one")
    }

    // MARK: - Sidebar Toggle Per Tab

    func test_sidebarButton_togglesSidebarPerTab() throws {
        // Navigate tab A to a website
        addressBarTextField.typeURL(URL(string: "duck://settings/general")!)
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Ensure sidebar starts closed
        XCTAssertTrue(waitForSidebarButtonTitle(sidebarClosedTitle),
                      "Sidebar should start closed on tab A")

        // Open sidebar on tab A
        sidebarButton.click()
        XCTAssertTrue(waitForSidebarButtonTitle(sidebarOpenTitle),
                      "Sidebar button should show 'Close' after opening sidebar on tab A")

        // Open tab B and navigate to a website
        app.openNewTab()
        addressBarTextField = app.addressBar
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Tab B should not have sidebar open
        XCTAssertTrue(waitForSidebarButtonTitle(sidebarClosedTitle),
                      "Sidebar should be closed on tab B initially")

        // Open sidebar on tab B
        sidebarButton.click()
        XCTAssertTrue(waitForSidebarButtonTitle(sidebarOpenTitle),
                      "Sidebar button should show 'Close' after opening sidebar on tab B")

        // Switch to tab A — sidebar should still be open
        let tabA = app.tabGroups.matching(identifier: "Tabs").radioButtons.element(boundBy: 0)
        tabA.click()
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(waitForSidebarButtonTitle(sidebarOpenTitle),
                      "Sidebar should still be open on tab A after switching back")

        // Close sidebar on tab A
        sidebarButton.click()
        XCTAssertTrue(waitForSidebarButtonTitle(sidebarClosedTitle),
                      "Sidebar should be closed on tab A after clicking close")

        // Switch to tab B — sidebar should still be open
        let tabB = app.tabGroups.matching(identifier: "Tabs").radioButtons.element(boundBy: 1)
        tabB.click()
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(waitForSidebarButtonTitle(sidebarOpenTitle),
                      "Sidebar should still be open on tab B")

        // Close sidebar on tab B
        sidebarButton.click()
        XCTAssertTrue(waitForSidebarButtonTitle(sidebarClosedTitle),
                      "Sidebar should be closed on tab B after clicking close")

        // Switch to tab A — should still be closed
        tabA.click()
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(waitForSidebarButtonTitle(sidebarClosedTitle),
                      "Sidebar should still be closed on tab A")
    }

    // MARK: - Tab Bar Context Menu: Hide/Show Buttons

    func test_tabBarContextMenu_hideDuckAIButton() {
        XCTAssertTrue(duckAITitleButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Duck.ai title button should exist before hiding")

        // Right-click on the Duck.ai button to open context menu, then click via identifier
        duckAITitleButton.rightClick()
        let hideItem = app.menuItems[ContextMenuIdentifiers.hideDuckAI].firstMatch
        XCTAssertTrue(hideItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        hideItem.click()

        // Duck.ai title button should now be hidden
        XCTAssertTrue(duckAITitleButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
                      "Duck.ai title button should be hidden after using context menu")

        // Verify in settings
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)
        let duckAIToggle = app.checkBoxes[Identifiers.showDuckAIButtonInTabBarToggle]
        XCTAssertTrue(duckAIToggle.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(duckAIToggle.isOn, "Settings toggle should reflect hidden state")

        // Re-enable via settings
        duckAIToggle.click()
        XCTAssertTrue(duckAITitleButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Duck.ai title button should reappear after re-enabling in settings")
    }

    func test_tabBarContextMenu_hideSidebarButton() {
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Sidebar button should exist before hiding")

        // Right-click on the sidebar button to open context menu, then click via identifier
        sidebarButton.rightClick()
        let hideItem = app.menuItems[ContextMenuIdentifiers.hideSidebar].firstMatch
        XCTAssertTrue(hideItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        hideItem.click()

        // Sidebar button should now be hidden
        XCTAssertTrue(sidebarButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
                      "Sidebar button should be hidden after using context menu")

        // Verify in settings
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)
        let sidebarToggle = app.checkBoxes[Identifiers.showSidebarButtonInTabBarToggle]
        XCTAssertTrue(sidebarToggle.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(sidebarToggle.isOn, "Settings toggle should reflect hidden state")

        // Re-enable via settings
        sidebarToggle.click()
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Sidebar button should reappear after re-enabling in settings")
    }

    func test_tabBarContextMenu_opensSettings() {
        XCTAssertTrue(duckAITitleButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        duckAITitleButton.rightClick()
        let settingsItem = app.menuItems[ContextMenuIdentifiers.openSettings].firstMatch
        XCTAssertTrue(settingsItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        settingsItem.click()

        // AI settings should open
        let duckAIToggle = app.checkBoxes[Identifiers.showDuckAIButtonInTabBarToggle]
        XCTAssertTrue(duckAIToggle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "AI Chat settings should be visible after clicking Open AI Settings")
    }

    // MARK: - View Menu: Hide/Show Buttons

    func test_viewMenu_hideDuckAIButton() throws {
        XCTAssertTrue(duckAITitleButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Use View menu to hide Duck.ai button
        let viewMenu = app.menuBars.menuBarItems["View"]
        viewMenu.click()
        let hideItem = viewMenu.menuItems["Hide Duck.ai Shortcut"]
        XCTAssertTrue(hideItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        hideItem.click()

        XCTAssertTrue(duckAITitleButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
                      "Duck.ai button should be hidden after View menu action")

        // Use View menu to show it back
        viewMenu.click()
        let showItem = viewMenu.menuItems["Show Duck.ai Shortcut"]
        XCTAssertTrue(showItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        showItem.click()

        XCTAssertTrue(duckAITitleButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Duck.ai button should reappear after View menu show action")
    }

    func test_viewMenu_hideSidebarButton() throws {
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Use View menu to hide sidebar button
        let viewMenu = app.menuBars.menuBarItems["View"]
        viewMenu.click()
        let hideItem = viewMenu.menuItems["Hide Sidebar Button"]
        XCTAssertTrue(hideItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        hideItem.click()

        XCTAssertTrue(sidebarButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
                      "Sidebar button should be hidden after View menu action")

        // Use View menu to show it back
        viewMenu.click()
        let showItem = viewMenu.menuItems["Show Sidebar Button"]
        XCTAssertTrue(showItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        showItem.click()

        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Sidebar button should reappear after View menu show action")
    }

}
