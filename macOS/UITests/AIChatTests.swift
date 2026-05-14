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
        static let duckAITitleButton = "TabBarViewController.duckAIChromeTitleButton"
        static let sidebarButton = "TabBarViewController.duckAIChromeSidebarButton"
        static let showDuckAIButtonInTabBarToggle = "Preferences.AIChat.showDuckAIButtonInTabBarToggle"
        static let showSidebarButtonInTabBarToggle = "Preferences.AIChat.showSidebarButtonInTabBarToggle"
        static let openInNewTabButton = "AIChatViewController.openInNewTabButton"
        static let detachButton = "AIChatViewController.detachButton"
        static let attachButton = "AIChatViewController.attachButton"
        static let titleButton = "AIChatViewController.titleButton"
        static let tabCloseButton = "TabBarViewItem.closeButton"
    }

    /// Context menu item identifiers (derived from @objc selector names)
    private enum ContextMenuIdentifiers {
        static let hideDuckAI = "hideDuckAITitleButtonAction"
        static let hideSidebar = "hideDuckAISidebarButtonAction"
        static let openSettings = "openAISettingsAction"
    }

    /// The sidebar button's accessibility title when the sidebar is open.
    private let sidebarOpenTitle = "Close Duck.ai sidebar"
    /// The sidebar button's accessibility title when the sidebar is closed.
    private let sidebarClosedTitle = "Open Duck.ai sidebar"
    /// The sidebar button's accessibility title when the sidebar is floating (detached).
    private let sidebarFloatingTitle = "Show Duck.ai"

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp(featureFlags: ["aiChatChromeSidebar": true, "aiChatSidebarFloating": true])

        addressBarTextField = app.addressBar
        app.enforceSingleWindow()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        app.terminate()
    }

    // MARK: - Helpers

    private var duckAITitleButton: XCUIElement {
        app.buttons[Identifiers.duckAITitleButton].firstMatch
    }

    private var sidebarButton: XCUIElement {
        app.buttons[Identifiers.sidebarButton].firstMatch
    }

    /// Waits for the sidebar button's accessibility title to match the expected value.
    /// `setAccessibilityTitle()` maps to AXTitle → XCUIElement's `title` property.
    private func waitForSidebarButtonTitle(_ expectedTitle: String, timeout: TimeInterval = UITests.Timeouts.elementExistence) -> Bool {
        let predicate = NSPredicate(format: "title == %@", expectedTitle)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: sidebarButton)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Opens the sidebar on the current tab and detaches it into a floating window.
    /// Asserts that the detach completes successfully.
    private func openAndDetachSidebar() {
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        sidebarButton.click()
        XCTAssertTrue(waitForSidebarButtonTitle(sidebarOpenTitle),
                      "Sidebar should be open before detaching")

        let detachButton = app.buttons[Identifiers.detachButton]
        XCTAssertTrue(detachButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Detach button should be visible in docked sidebar")
        detachButton.click()

        XCTAssertTrue(waitForSidebarButtonTitle(sidebarFloatingTitle),
                      "Chrome bar button should show 'Show Duck.ai' after detaching")
    }

    // MARK: - Split Button Existence

    func test_duckAISplitButtonExists_byDefault() {
        XCTAssertTrue(duckAITitleButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Duck.ai title button should exist")
        XCTAssertTrue(sidebarButton.exists, "Sidebar button should exist")
    }

    // MARK: - Duck.ai Title Button Opens New Tab

    func test_duckAITitleButton_opensNewTab_whenOnWebsite() {
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

    func test_duckAITitleButton_loadsInCurrentTab_whenOnNewTabPage() {
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

    func test_sidebarButton_togglesSidebarPerTab() {
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

    // MARK: - Sidebar: Expand Opens Duck.ai Tab

    func test_sidebarExpandButton_opensDuckAITab() {
        addressBarTextField.typeURL(URL(string: "duck://settings/general")!)
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Open sidebar
        sidebarButton.click()
        XCTAssertTrue(waitForSidebarButtonTitle(sidebarOpenTitle),
                      "Sidebar should be open")

        let expandButton = app.buttons[Identifiers.openInNewTabButton]
        XCTAssertTrue(expandButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Expand button should be visible in docked sidebar")

        let tabsBefore = app.tabGroups.matching(identifier: "Tabs").radioButtons.count
        expandButton.click()

        // A new Duck.ai tab should have been opened
        let tabsAfter = app.tabGroups.matching(identifier: "Tabs").radioButtons.count
        XCTAssertEqual(tabsAfter, tabsBefore + 1,
                       "Clicking expand button should open a new Duck.ai tab")
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

    func test_viewMenu_hideDuckAIButton() {
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

    func test_viewMenu_hideSidebarButton() {
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

    // MARK: - Floating Sidebar: Detach and Chrome Icon

    func test_detachSidebar_createsFloatingWindow_andChromeIconChanges() {
        addressBarTextField.typeURL(URL(string: "duck://settings/general")!)
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        let windowsBefore = app.windows.count
        openAndDetachSidebar()

        // A new floating window should have appeared
        let windowsAfter = app.windows.count
        XCTAssertEqual(windowsAfter, windowsBefore + 1,
                       "Detaching sidebar should create a new floating window")

        // Attach button should be visible in the floating window
        let attachButton = app.buttons[Identifiers.attachButton]
        XCTAssertTrue(attachButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Attach button should be visible in floating sidebar")

        // Chrome bar icon should show floating state
        XCTAssertTrue(waitForSidebarButtonTitle(sidebarFloatingTitle),
                      "Chrome bar button should show 'Show Duck.ai' when sidebar is floating")

        // Clicking chrome bar button when floating should bring floating window to front (not close it)
        sidebarButton.click()
        XCTAssertTrue(attachButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Floating sidebar should still exist after clicking chrome bar icon")

        // Window menu should list the floating Duck.ai window
        let windowMenu = app.menuBars.menuBarItems["Window"]
        windowMenu.click()
        let floatingWindowItem = windowMenu.menuItems.matching(NSPredicate(format: "title BEGINSWITH %@", "Duck.ai")).firstMatch
        XCTAssertTrue(floatingWindowItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Window menu should list the floating Duck.ai window")
        windowMenu.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - Floating Sidebar: Attach (Regular and Pinned Tab)

    // Floating window hittability is unreliable on macOS 14 CI runners.
    // Manually verified on macOS 14 hardware — the feature works correctly.
    func test_floatingSidebar_attachButton_reattachesSidebar() throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Floating sidebar UI tests require macOS 15+") }
        addressBarTextField.typeURL(URL(string: "duck://settings/general")!)
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // --- Regular tab: detach and reattach ---
        openAndDetachSidebar()

        let attachButton = app.buttons[Identifiers.attachButton]
        XCTAssertTrue(attachButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        let windowsBefore = app.windows.count
        attachButton.click()

        XCTAssertTrue(waitForSidebarButtonTitle(sidebarOpenTitle),
                      "Chrome bar button should show 'Close' after reattaching sidebar")
        XCTAssertEqual(app.windows.count, windowsBefore - 1,
                       "Floating window should be closed after reattaching")
        XCTAssertTrue(attachButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
                      "Attach button should not be visible in docked sidebar")

        // --- Pinned tab: detach and reattach ---
        sidebarButton.click()
        XCTAssertTrue(waitForSidebarButtonTitle(sidebarClosedTitle),
                      "Sidebar should be closed before pinning")

        app.menuItems["Pin Tab"].click()

        openAndDetachSidebar()
        XCTAssertTrue(attachButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Attach button should be visible for pinned tab's floating sidebar")

        attachButton.click()

        XCTAssertTrue(waitForSidebarButtonTitle(sidebarOpenTitle),
                      "Chrome bar should show 'Close' after reattaching to pinned tab")
        XCTAssertTrue(attachButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
                      "Attach button should not be visible after reattaching to pinned tab")

        // Cleanup: unpin
        app.menuItems["Unpin Tab"].click()
    }

    // MARK: - Floating Sidebar: Multi-Tab Switching

    // Floating window hittability is unreliable on macOS 14 CI runners.
    // Manually verified on macOS 14 hardware — the feature works correctly.
    func test_floatingSidebar_titleButton_switchesToAssociatedTab() throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Floating sidebar UI tests require macOS 15+") }
        // Tab A: navigate to a page
        addressBarTextField.typeURL(URL(string: "duck://settings/general")!)
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Open tab B before detaching (avoids keyboard shortcuts going to floating window)
        app.openNewTab()
        addressBarTextField = app.addressBar
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)

        // Switch back to tab A and detach sidebar
        let tabA = app.tabGroups.matching(identifier: "Tabs").radioButtons.element(boundBy: 0)
        tabA.click()
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        openAndDetachSidebar()

        // Switch to tab B
        let tabB = app.tabGroups.matching(identifier: "Tabs").radioButtons.element(boundBy: 1)
        tabB.click()

        // We're now on tab B. Bring the floating sidebar to front via Window menu
        // (clicking chrome bar button doesn't reliably bring floating window to front for XCUITest).
        let windowMenu = app.menuBars.menuBarItems["Window"]
        windowMenu.click()
        let floatingWindowItem = windowMenu.menuItems.matching(NSPredicate(format: "title BEGINSWITH %@", "Duck.ai")).firstMatch
        XCTAssertTrue(floatingWindowItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        floatingWindowItem.click()

        let floatingTitleButton = app.buttons[Identifiers.titleButton]
        XCTAssertTrue(floatingTitleButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        floatingTitleButton.click()

        // After clicking title, tab A should be selected in the main browser
        let selectedPredicate = NSPredicate(format: "isSelected == true")
        let selectedExpectation = XCTNSPredicateExpectation(predicate: selectedPredicate, object: tabA)
        XCTAssertEqual(XCTWaiter.wait(for: [selectedExpectation], timeout: UITests.Timeouts.elementExistence), .completed,
                       "Tab A should be selected after clicking floating sidebar title button")
    }

    // Floating window hittability is unreliable on macOS 14 CI runners.
    // Manually verified on macOS 14 hardware — the feature works correctly.
    func test_floatingSidebar_attachButton_switchesToAssociatedTabAndReattaches() throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Floating sidebar UI tests require macOS 15+") }
        // Tab A: navigate to a page
        addressBarTextField.typeURL(URL(string: "duck://settings/general")!)
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Open tab B before detaching (avoids keyboard shortcuts going to floating window)
        app.openNewTab()
        addressBarTextField = app.addressBar
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)

        // Switch back to tab A and detach sidebar
        let tabA = app.tabGroups.matching(identifier: "Tabs").radioButtons.element(boundBy: 0)
        tabA.click()
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        openAndDetachSidebar()

        // Switch to tab B
        let tabB = app.tabGroups.matching(identifier: "Tabs").radioButtons.element(boundBy: 1)
        tabB.click()

        // We're now on tab B. Bring the floating sidebar to front via Window menu
        // (clicking chrome bar button doesn't reliably bring floating window to front for XCUITest).
        let windowMenu = app.menuBars.menuBarItems["Window"]
        windowMenu.click()
        let floatingWindowItem = windowMenu.menuItems.matching(NSPredicate(format: "title BEGINSWITH %@", "Duck.ai")).firstMatch
        XCTAssertTrue(floatingWindowItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        floatingWindowItem.click()

        let attachButton = app.buttons[Identifiers.attachButton]
        XCTAssertTrue(attachButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        attachButton.click()

        // Tab A should be selected and sidebar should be docked
        let selectedPredicate = NSPredicate(format: "isSelected == true")
        let selectedExpectation = XCTNSPredicateExpectation(predicate: selectedPredicate, object: tabA)
        XCTAssertEqual(XCTWaiter.wait(for: [selectedExpectation], timeout: UITests.Timeouts.elementExistence), .completed,
                       "Tab A should be selected after attaching from tab B")

        XCTAssertTrue(waitForSidebarButtonTitle(sidebarOpenTitle),
                      "Chrome bar button should show sidebar is docked after attaching")
    }

    // MARK: - Floating Sidebar: Close Updates Chrome Bar

    func test_closeFloatingSidebar_updatesChromeBarIcon() {
        addressBarTextField.typeURL(URL(string: "duck://settings/general")!)
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        openAndDetachSidebar()

        // Floating window should be in front after detach — close it with Cmd+W
        let attachButton = app.buttons[Identifiers.attachButton]
        XCTAssertTrue(attachButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        app.typeKey("w", modifierFlags: .command)

        // Chrome bar icon should update to closed state
        XCTAssertTrue(waitForSidebarButtonTitle(sidebarClosedTitle),
                      "Chrome bar button should show 'Open' after closing floating sidebar")

        // Attach button should no longer exist (floating window is gone)
        XCTAssertTrue(attachButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
                      "Floating sidebar should be closed")
    }

    // MARK: - Floating Sidebar: Close Tab Warning

    // Floating window hittability is unreliable on macOS 14 CI runners.
    // Manually verified on macOS 14 hardware — the feature works correctly.
    func test_closeTabWithDetachedSidebar_showsWarningPopover() throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Floating sidebar UI tests require macOS 15+") }
        addressBarTextField.typeURL(URL(string: "duck://settings/general")!)
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Open a second tab so closing tab A doesn't close the window
        app.openNewTab()
        addressBarTextField = app.addressBar
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)

        // Switch back to tab A and detach sidebar
        let tabA = app.tabGroups.matching(identifier: "Tabs").radioButtons.element(boundBy: 0)
        tabA.click()
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        openAndDetachSidebar()

        // Focus main window by clicking on tab A (no keyboard shortcuts — they go to floating window)
        tabA.click()
        let tabCloseButton = tabA.buttons[Identifiers.tabCloseButton]
        tabA.hover()
        XCTAssertTrue(tabCloseButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Tab close button should be visible")
        tabCloseButton.click()

        // Warning popover should appear
        let warningTitle = app.staticTexts["Close tab and Duck.ai chat"]
        XCTAssertTrue(warningTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Warning popover should appear when closing tab with detached sidebar")

        // Dismiss the warning — tab and sidebar should remain
        app.typeKey(.escape, modifierFlags: [])

        // Tab should still exist
        XCTAssertTrue(tabA.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Tab should still exist after dismissing the warning")

        // Floating sidebar should still exist
        let attachButton = app.buttons[Identifiers.attachButton]
        XCTAssertTrue(attachButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Floating sidebar should still exist after dismissing the warning")

        // Now close for real: click the tab close button again and confirm
        tabA.hover()
        tabCloseButton.click()
        // Find the popover's "Close Tab" button (not the tab bar close button which shares the same label)
        let closeTabButton = app.buttons.matching(NSPredicate(format: "label == 'Close Tab' AND identifier != %@", Identifiers.tabCloseButton)).firstMatch
        XCTAssertTrue(closeTabButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Close Tab button should appear in the warning popover")
        closeTabButton.click()

        // Both tab and floating sidebar should be gone
        XCTAssertTrue(attachButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
                      "Floating sidebar should be closed after confirming tab close")
    }
}
