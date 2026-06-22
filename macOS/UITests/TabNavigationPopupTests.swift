//
//  TabNavigationPopupTests.swift
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

import Common
import FoundationExtensions
import XCTest

final class TabNavigationPopupTests: UITestCase, TabNavigationTestHelpers {

    override class func setUp() {
        super.setUp()
        UITests.firstRun()
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp()
    }

    // MARK: - Popup Window Navigation Tests

    func testPopupWindowsNavigation() {
        app.setSwitchToNewTab(enabled: false)

        // Open a popup window
        let popupHTML = """
        <a href='\(UITests.simpleServedPage(titled: "New Tab"))' target='_blank'>Open in new tab</a>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let mainWindow = app.windows.containing(.keyPath(\.title, equalTo: "Page #12")).firstMatch
        let popupLink = mainWindow.webViews["Page #12"].links["Open popup"]
        popupLink.click()

        // Try to navigate in popup
        let popupWindow = app.windows.containing(.keyPath(\.title, equalTo: "Popup Page")).firstMatch
        let link = popupWindow.webViews["Popup Page"].links["Open in new tab"]
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        link.click()

        // Should open in new tab of the original window
        XCTAssertEqual(app.windows.count, 2)
        XCTAssertTrue(mainWindow.webViews["New Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(mainWindow.tabs["Page #12"].exists)
        XCTAssertTrue(mainWindow.tabs["New Tab"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 2)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify main window is frontmost
        XCTAssertEqual(app.windows.firstMatch.title, mainWindow.title, "Main window should be frontmost after popup navigation")
        XCTAssertNotEqual(app.windows.firstMatch.title, popupWindow.title, "Main window should be frontmost after popup navigation")
    }

    func testPopupRegularBookmarkClickOpensNewTabInMainWindow() {
        app.setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Open test page and bookmark it.
        openTestPage("Popup Bookmark Target")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()
        app.dismissBookmarksBarPopover()

        // Navigate to another page that can open a popup.
        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Menu Page", body: "<p>Popup menu actions</p>")
            .absoluteString.escapedJavaScriptString()
        app.activateAddressBar()
        openTestPage("Popup Bookmark Source") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }

        // Open pop-up window.
        let mainWindow = app.windows.containing(.keyPath(\.title, equalTo: "Popup Bookmark Source")).firstMatch
        let popupLink = mainWindow.webViews["Popup Bookmark Source"].links["Open popup"]
        popupLink.click()

        let popupWindow = app.windows.containing(.staticText, identifier: "Popup menu actions").firstMatch
        // Popup window should be open.
        XCTAssertTrue(popupWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Open bookmarked page from app main menu when the popup window is active.
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Popup Bookmark Target"]
        // Bookmark item should be visible in the menu.
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        bookmarkItem.click()

        // Target tab should be created in the main window.
        XCTAssertTrue(mainWindow.tabs["Popup Bookmark Target"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Window count should stay main + popup.
        XCTAssertEqual(app.windows.count, 2)
        // Target page should be active in the main window.
        XCTAssertTrue(mainWindow.webViews["Popup Bookmark Target"].exists)
        // Source page should no longer be active.
        XCTAssertFalse(mainWindow.webViews["Popup Bookmark Source"].exists)
        // Source tab should still exist.
        XCTAssertTrue(mainWindow.tabs["Popup Bookmark Source"].exists)
        // Main window should have source + target tabs.
        XCTAssertEqual(mainWindow.tabs.count, 2)
        // Popup window should still be open.
        XCTAssertTrue(popupWindow.webViews["Popup Menu Page"].exists)
    }

    func testPopupRegularHistoryClickOpensNewTabInMainWindow() {
        app.setSwitchToNewTab(enabled: false)

        // Open test page to create a history item.
        openTestPage("Popup History Target")

        // Navigate to another page that can open a popup.
        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Menu Page", body: "<p>Popup menu actions</p>")
            .absoluteString.escapedJavaScriptString()
        app.activateAddressBar()
        openTestPage("Popup History Source") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }

        // Open pop-up window.
        let mainWindow = app.windows.containing(.keyPath(\.title, equalTo: "Popup History Source")).firstMatch
        let popupLink = mainWindow.webViews["Popup History Source"].links["Open popup"]
        popupLink.click()

        let popupWindow = app.windows.containing(.staticText, identifier: "Popup menu actions").firstMatch
        // Popup window should be open.
        XCTAssertTrue(popupWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Open history page from app main menu when the popup window is active.
        app.historyMenu.click()
        let historyItem = app.menuItems["Popup History Target"]
        // History item should be visible in the menu.
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        historyItem.click()

        // Target tab should be created in the main window.
        XCTAssertTrue(mainWindow.tabs["Popup History Target"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Window count should stay main + popup.
        XCTAssertEqual(app.windows.count, 2)
        // Target page should be active in the main window.
        XCTAssertTrue(mainWindow.webViews["Popup History Target"].exists)
        // Source page should no longer be active.
        XCTAssertFalse(mainWindow.webViews["Popup History Source"].exists)
        // Source tab should still exist.
        XCTAssertTrue(mainWindow.tabs["Popup History Source"].exists)
        // Main window should have source + target tabs.
        XCTAssertEqual(mainWindow.tabs.count, 2)
        // Popup window should still be open.
        XCTAssertTrue(popupWindow.webViews["Popup Menu Page"].exists)
    }

    func testPopupBookmarkMainMenuCommandClickOpensBackgroundTabInMainWindow() {
        app.setSwitchToNewTab(enabled: false)
        // Setup: bookmark target + source page + popup window.
        let (mainWindow, popupWindow) = setupPopupWindowForBookmarkMainMenu(targetTitle: "Popup Bookmark Target", sourceTitle: "Popup Bookmark Source")

        // Open bookmarked page from app main menu with Cmd when the popup window is active.
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Popup Bookmark Target"]
        // Bookmark item should be visible in the menu.
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command]) {
            bookmarkItem.click()
        }

        // Target tab should be created in the main window.
        XCTAssertTrue(mainWindow.tabs["Popup Bookmark Target"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Window count should stay main + popup.
        XCTAssertEqual(app.windows.count, 2)
        // Source page should remain active in the main window.
        XCTAssertTrue(mainWindow.webViews["Popup Bookmark Source"].exists)
        // Target page should not be active (background tab check).
        XCTAssertFalse(mainWindow.webViews["Popup Bookmark Target"].exists)
        // Source tab should still exist.
        XCTAssertTrue(mainWindow.tabs["Popup Bookmark Source"].exists)
        // Main window should have source + target tabs.
        XCTAssertEqual(mainWindow.tabs.count, 2)
        // Popup window should still be open.
        XCTAssertTrue(popupWindow.webViews["Popup Menu Page"].exists)
    }

    func testPopupBookmarkMainMenuCommandShiftClickOpensForegroundTabInMainWindow() {
        app.setSwitchToNewTab(enabled: false)
        // Setup: bookmark target + source page + popup window.
        let (mainWindow, popupWindow) = setupPopupWindowForBookmarkMainMenu(targetTitle: "Popup Bookmark Target", sourceTitle: "Popup Bookmark Source")

        // Open bookmarked page from app main menu with Cmd+Shift when the popup window is active.
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Popup Bookmark Target"]
        // Bookmark item should be visible in the menu.
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            bookmarkItem.click()
        }

        // Target page should be active in the main window.
        XCTAssertTrue(mainWindow.webViews["Popup Bookmark Target"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Window count should stay main + popup.
        XCTAssertEqual(app.windows.count, 2)
        // Source page should not remain active.
        XCTAssertFalse(mainWindow.webViews["Popup Bookmark Source"].exists)
        // Source tab should still exist.
        XCTAssertTrue(mainWindow.tabs["Popup Bookmark Source"].exists)
        // Target tab should exist.
        XCTAssertTrue(mainWindow.tabs["Popup Bookmark Target"].exists)
        // Main window should have source + target tabs.
        XCTAssertEqual(mainWindow.tabs.count, 2)
        // Popup window should still be open.
        XCTAssertTrue(popupWindow.webViews["Popup Menu Page"].exists)
    }

    func testPopupBookmarkMainMenuCommandOptionClickOpensBackgroundWindow() {
        app.setSwitchToNewTab(enabled: false)
        // Setup: bookmark target + source page + popup window.
        let (mainWindow, popupWindow) = setupPopupWindowForBookmarkMainMenu(targetTitle: "Popup Bookmark Target", sourceTitle: "Popup Bookmark Source")

        // Open bookmarked page from app main menu with Cmd+Option when the popup window is active.
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Popup Bookmark Target"]
        // Bookmark item should be visible in the menu.
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command, .option]) {
            bookmarkItem.click()
        }

        // Ensure it opens in background window and popup stays active.
        let backgroundWindow = app.windows.element(boundBy: 2)
        // Background window should appear.
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Target page should load in that background window.
        XCTAssertTrue(backgroundWindow.webViews["Popup Bookmark Target"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Window count should be main + popup + background window.
        XCTAssertEqual(app.windows.count, 3)
        // Main window should stay on source page.
        XCTAssertTrue(mainWindow.webViews["Popup Bookmark Source"].exists)
        // Main window should keep a single tab.
        XCTAssertEqual(mainWindow.tabs.count, 1)
        // Popup window should still be open.
        XCTAssertTrue(popupWindow.webViews["Popup Menu Page"].exists)
        // Popup window should remain frontmost.
        XCTAssertEqual(app.windows.firstMatch.title, popupWindow.title)
    }

    func testPopupBookmarkMainMenuCommandOptionShiftClickOpensForegroundWindow() {
        app.setSwitchToNewTab(enabled: false)
        // Setup: bookmark target + source page + popup window.
        let (_, popupWindow) = setupPopupWindowForBookmarkMainMenu(targetTitle: "Popup Bookmark Target", sourceTitle: "Popup Bookmark Source")

        // Open bookmarked page from app main menu with Cmd+Option+Shift when the popup window is active.
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Popup Bookmark Target"]
        // Bookmark item should be visible in the menu.
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command, .option, .shift]) {
            bookmarkItem.click()
        }

        // Ensure it opens in selected new window, never in popup.
        let activeWindow = app.windows.firstMatch
        // Target page should load in the active new window.
        XCTAssertTrue(activeWindow.webViews["Popup Bookmark Target"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Window count should be main + popup + foreground window.
        XCTAssertEqual(app.windows.count, 3)
        // Popup window should still be open.
        XCTAssertTrue(popupWindow.webViews["Popup Menu Page"].exists)
    }

    func testPopupHistoryMainMenuCommandClickOpensBackgroundTabInMainWindow() {
        app.setSwitchToNewTab(enabled: false)
        // Setup: history target + source page + popup window.
        let (mainWindow, popupWindow) = setupPopupWindowForHistoryMainMenu(targetTitle: "Popup History Target", sourceTitle: "Popup History Source")

        // Open history item from app main menu with Cmd when the popup window is active.
        app.historyMenu.click()
        let historyItem = app.menuItems["Popup History Target"]
        // History item should be visible in the menu.
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command]) {
            historyItem.click()
        }

        // Target tab should be created in the main window.
        XCTAssertTrue(mainWindow.tabs["Popup History Target"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Window count should stay main + popup.
        XCTAssertEqual(app.windows.count, 2)
        // Source page should remain active in the main window.
        XCTAssertTrue(mainWindow.webViews["Popup History Source"].exists)
        // Target page should not be active (background tab check).
        XCTAssertFalse(mainWindow.webViews["Popup History Target"].exists)
        // Source tab should still exist.
        XCTAssertTrue(mainWindow.tabs["Popup History Source"].exists)
        // Main window should have source + target tabs.
        XCTAssertEqual(mainWindow.tabs.count, 2)
        // Popup window should still be open.
        XCTAssertTrue(popupWindow.webViews["Popup Menu Page"].exists)
    }

    func testPopupHistoryMainMenuCommandShiftClickOpensForegroundTabInMainWindow() {
        app.setSwitchToNewTab(enabled: false)
        // Setup: history target + source page + popup window.
        let (mainWindow, popupWindow) = setupPopupWindowForHistoryMainMenu(targetTitle: "Popup History Target", sourceTitle: "Popup History Source")

        // Open history item from app main menu with Cmd+Shift when the popup window is active.
        app.historyMenu.click()
        let historyItem = app.menuItems["Popup History Target"]
        // History item should be visible in the menu.
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            historyItem.click()
        }

        // Target page should be active in the main window.
        XCTAssertTrue(mainWindow.webViews["Popup History Target"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Window count should stay main + popup.
        XCTAssertEqual(app.windows.count, 2)
        // Source page should not remain active.
        XCTAssertFalse(mainWindow.webViews["Popup History Source"].exists)
        // Source tab should still exist.
        XCTAssertTrue(mainWindow.tabs["Popup History Source"].exists)
        // Target tab should exist.
        XCTAssertTrue(mainWindow.tabs["Popup History Target"].exists)
        // Main window should have source + target tabs.
        XCTAssertEqual(mainWindow.tabs.count, 2)
        // Popup window should still be open.
        XCTAssertTrue(popupWindow.webViews["Popup Menu Page"].exists)
    }

    func testPopupHistoryMainMenuCommandOptionClickOpensBackgroundWindow() {
        app.setSwitchToNewTab(enabled: false)
        // Setup: history target + source page + popup window.
        let (mainWindow, popupWindow) = setupPopupWindowForHistoryMainMenu(targetTitle: "Popup History Target", sourceTitle: "Popup History Source")

        // Open history item from app main menu with Cmd+Option when the popup window is active.
        app.historyMenu.click()
        let historyItem = app.menuItems["Popup History Target"]
        // History item should be visible in the menu.
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command, .option]) {
            historyItem.click()
        }

        // Ensure it opens in background window and popup stays active.
        let backgroundWindow = app.windows.element(boundBy: 2)
        // Background window should appear.
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Target page should load in that background window.
        XCTAssertTrue(backgroundWindow.webViews["Popup History Target"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Window count should be main + popup + background window.
        XCTAssertEqual(app.windows.count, 3)
        // Main window should stay on source page.
        XCTAssertTrue(mainWindow.webViews["Popup History Source"].exists)
        // Main window should keep a single tab.
        XCTAssertEqual(mainWindow.tabs.count, 1)
        // Popup window should still be open.
        XCTAssertTrue(popupWindow.webViews["Popup Menu Page"].exists)
        // Popup window should remain frontmost.
        XCTAssertEqual(app.windows.firstMatch.title, popupWindow.title)
    }

    func testPopupHistoryMainMenuCommandOptionShiftClickOpensForegroundWindow() {
        app.setSwitchToNewTab(enabled: false)
        // Setup: history target + source page + popup window.
        let (_, popupWindow) = setupPopupWindowForHistoryMainMenu(targetTitle: "Popup History Target", sourceTitle: "Popup History Source")

        // Open history item from app main menu with Cmd+Option+Shift when the popup window is active.
        app.historyMenu.click()
        let historyItem = app.menuItems["Popup History Target"]
        // History item should be visible in the menu.
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command, .option, .shift]) {
            historyItem.click()
        }

        // Ensure it opens in selected new window, never in popup.
        let activeWindow = app.windows.firstMatch
        // Target page should load in the active new window.
        XCTAssertTrue(activeWindow.webViews["Popup History Target"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Window count should be main + popup + foreground window.
        XCTAssertEqual(app.windows.count, 3)
        // Popup window should still be open.
        XCTAssertTrue(popupWindow.webViews["Popup Menu Page"].exists)
    }

    func testPopupCommandClickOpensBackgroundTab() {
        app.setSwitchToNewTab(enabled: false)

        // Open a popup window
        let popupHTML = """
        <a href='\(UITests.simpleServedPage(titled: "Page #13"))'>Open Page #13</a>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let mainWindow = app.windows.containing(.keyPath(\.title, equalTo: "Page #12")).firstMatch
        let popupLink = mainWindow.webViews["Page #12"].links["Open popup"]
        popupLink.click()

        // Command click in popup - should open in background tab in main window
        let popupWindow = app.windows.containing(.keyPath(\.title, equalTo: "Popup Page")).firstMatch
        let link = popupWindow.webViews["Popup Page"].links["Open Page #13"]
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command]) {
            link.click()
        }

        // Should open in background tab in main window, popup remains frontmost
        XCTAssertTrue(mainWindow.tabs["Page #13"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)
        XCTAssertTrue(mainWindow.webViews["Page #12"].exists)
        XCTAssertFalse(mainWindow.webViews["Page #13"].exists) // Original page still in foreground
        XCTAssertTrue(mainWindow.tabs["Page #12"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 2)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify popup window remains frontmost (background operation)
        XCTAssertEqual(app.windows.firstMatch.title, popupWindow.title, "Popup window should remain frontmost for background operations")
    }

    func testPopupCommandShiftClickOpensForegroundTab() {
        app.setSwitchToNewTab(enabled: false)

        // Open a popup window
        let popupHTML = """
        <a href='\(UITests.simpleServedPage(titled: "Page #14"))'>Open Page #14</a>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let mainWindow = app.windows.containing(.keyPath(\.title, equalTo: "Page #12")).firstMatch
        let popupLink = mainWindow.webViews["Page #12"].links["Open popup"]
        popupLink.click()

        // Command shift click in popup - should open in foreground tab in main window
        let popupWindow = app.windows.containing(.keyPath(\.title, equalTo: "Popup Page")).firstMatch
        let link = popupWindow.webViews["Popup Page"].links["Open Page #14"]
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            link.click()
        }

        // Should open in foreground tab in main window
        XCTAssertEqual(app.windows.count, 2) // Main window + popup window
        XCTAssertTrue(mainWindow.webViews["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(mainWindow.webViews["Page #12"].exists) // Original page now in background
        XCTAssertTrue(mainWindow.tabs["Page #12"].exists)
        XCTAssertTrue(mainWindow.tabs["Page #14"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 2)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify main window is frontmost
        XCTAssertEqual(app.windows.firstMatch.title, mainWindow.title, "Main window should be frontmost after popup navigation")
    }

    func testPopupCommandOptionClickOpensBackgroundWindow() {
        app.setSwitchToNewTab(enabled: false)

        // Open a popup window
        let popupHTML = """
        <a href='\(UITests.simpleServedPage(titled: "Page #15"))'>Open Page #15</a>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let mainWindow = app.windows.containing(.keyPath(\.title, equalTo: "Page #12")).firstMatch
        let popupLink = mainWindow.webViews["Page #12"].links["Open popup"]
        popupLink.click()

        // Command option click in popup - should open in background window
        let popupWindow = app.windows.containing(.keyPath(\.title, equalTo: "Popup Page")).firstMatch
        let link = popupWindow.webViews["Popup Page"].links["Open Page #15"]
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command, .option]) {
            link.click()
        }

        // Should open in background window, popup remains frontmost
        let backgroundWindow = app.windows.element(boundBy: 2) // Now third window (main, popup, background)
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(backgroundWindow.webViews["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 3)

        XCTAssertTrue(mainWindow.webViews["Page #12"].exists)
        XCTAssertFalse(mainWindow.webViews["Page #15"].exists)
        XCTAssertTrue(mainWindow.tabs["Page #12"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 1)

        XCTAssertTrue(backgroundWindow.tabs["Page #15"].exists)
        XCTAssertEqual(backgroundWindow.tabs.count, 1)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify popup window remains frontmost (background window operation)
        XCTAssertEqual(app.windows.firstMatch.title, popupWindow.title, "Popup window should remain frontmost for background operations")
    }

    func testPopupCommandOptionShiftClickOpensForegroundWindow() {
        app.setSwitchToNewTab(enabled: false)

        // Open a popup window
        let popupHTML = """
        <a href='\(UITests.simpleServedPage(titled: "Page #16"))'>Open Page #16</a>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let mainWindow = app.windows.containing(.keyPath(\.title, equalTo: "Page #12")).firstMatch
        let popupLink = mainWindow.webViews["Page #12"].links["Open popup"]
        popupLink.click()

        // Command option shift click in popup - should open in foreground window
        let popupWindow = app.windows.containing(.keyPath(\.title, equalTo: "Popup Page")).firstMatch
        let link = popupWindow.webViews["Popup Page"].links["Open Page #16"]
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command, .option, .shift]) {
            link.click()
        }

        // Should open in foreground window
        let activeWindow = app.windows.firstMatch
        XCTAssertTrue(activeWindow.webViews["Page #16"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 3) // Main window + popup window + new foreground window

        XCTAssertFalse(activeWindow.webViews["Page #12"].exists)
        XCTAssertTrue(activeWindow.tabs["Page #16"].exists)
        XCTAssertEqual(activeWindow.tabs.count, 1)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify new window is frontmost (foreground window operation)
        let foregroundWindow = app.windows.containing(.keyPath(\.title, equalTo: "Page #16")).firstMatch
        XCTAssertEqual(app.windows.firstMatch.title, foregroundWindow.title, "New window should be frontmost when opened in foreground")
    }

    // MARK: - Fire Window Popup Navigation Tests

    func testFireWindowPopupCommandClickOpensBackgroundTab() {
        app.setSwitchToNewTab(enabled: false)

        app.closeWindow()
        // Open Fire window
        app.openFireWindow()

        // Open a popup window from Fire window
        let popupHTML = """
        <a href='\(UITests.simpleServedPage(titled: "Page #13"))'>Open Page #13</a>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Fire Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let fireWindow = app.windows.containing(.keyPath(\.title, equalTo: "Fire Page #12")).firstMatch
        let popupLink = fireWindow.webViews["Fire Page #12"].links["Open popup"]
        popupLink.click()

        // Command click in popup - should open in background tab in Fire window
        let popupWindow = app.windows.containing(.link, identifier: "Open Page #13").firstMatch
        let link = popupWindow.links["Open Page #13"]
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command]) {
            link.click()
        }

        // Should open in background tab in Fire window, popup remains frontmost
        XCTAssertEqual(app.windows.count, 2)
        XCTAssertTrue(fireWindow.tabs["Page #13"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(fireWindow.tabs["Fire Page #12"].exists)
        XCTAssertTrue(fireWindow.webViews["Fire Page #12"].exists) // Original Fire page still in foreground
        XCTAssertEqual(fireWindow.tabs.count, 2)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify popup link still available
        XCTAssertTrue(link.exists, "Popup link should still be available after navigation")

        // Verify popup window remains frontmost (background operation)
        XCTAssertEqual(app.windows.firstMatch.title, popupWindow.title, "Popup window should remain frontmost for background operations")
    }

    func testFireWindowPopupBackgroundAndForegroundTab() {
        app.setSwitchToNewTab(enabled: false)

        app.closeWindow()
        // Open Fire window
        app.openFireWindow()

        // Open a popup window from Fire window
        let popupHTML = """
        <a href='\(UITests.simpleServedPage(titled: "Page #14"))' id='link14'>Open Page #14</a>
        <a href='\(UITests.simpleServedPage(titled: "Page #15"))' id='link15'>Open Page #15</a>
        <a href='\(UITests.simpleServedPage(titled: "Page #16"))' id='link16'>Open Page #16</a>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Fire Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let fireWindow = app.windows.containing(.keyPath(\.title, equalTo: "Fire Page #12")).firstMatch
        let popupLink = fireWindow.webViews["Fire Page #12"].links["Open popup"]
        popupLink.click()

        let popupWindow = app.windows.containing(.link, identifier: "Open Page #15").firstMatch
        XCTAssertTrue(popupWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Test 1: Command+Option click - should open in background Fire window
        let link15 = popupWindow.links["Open Page #15"]
        XCTAssertTrue(link15.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command, .option]) {
            link15.click()
        }

        // Should open in background Fire window
        let backgroundFireWindow = app.windows.element(boundBy: 2) // Main Fire, popup, background Fire
        XCTAssertTrue(backgroundFireWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(backgroundFireWindow.tabs["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(backgroundFireWindow.webViews["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 3)

        XCTAssertEqual(backgroundFireWindow.tabs.count, 1)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify popup link still available
        XCTAssertTrue(link15.exists, "Popup link should still be available after navigation")

        // Verify popup window remains frontmost (background Fire window operation)
        XCTAssertEqual(app.windows.firstMatch.title, popupWindow.title, "Popup window should remain frontmost for background Fire window operations")

        // Test 2: Command+Shift click - should open in foreground tab in Fire window (end test after this)
        let link14 = popupWindow.links["Open Page #14"]
        XCTAssertTrue(link14.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            link14.click()
        }

        // Should open in foreground tab in Fire window
        XCTAssertEqual(app.windows.count, 3) // Main Fire + popup + background Fire
        XCTAssertTrue(fireWindow.tabs["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(fireWindow.webViews["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(fireWindow.webViews["Fire Page #12"].exists) // Original page now in background
        XCTAssertTrue(fireWindow.tabs["Fire Page #12"].exists)
        XCTAssertEqual(fireWindow.tabs.count, 2)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify Fire window is frontmost (foreground tab operation ends test)
        XCTAssertEqual(app.windows.firstMatch.title, fireWindow.title, "Fire window should be frontmost after popup navigation")
    }

    func testFireWindowPopupForegroundWindow() {
        app.setSwitchToNewTab(enabled: false)

        app.closeWindow()
        // Open Fire window
        app.openFireWindow()

        // Open a popup window from Fire window
        let popupHTML = """
        <a href='\(UITests.simpleServedPage(titled: "Page #16"))' id='link16'>Open Page #16</a>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Fire Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let fireWindow = app.windows.containing(.keyPath(\.title, equalTo: "Fire Page #12")).firstMatch
        let popupLink = fireWindow.webViews["Fire Page #12"].links["Open popup"]
        popupLink.click()

        let popupWindow = app.windows.containing(.link, identifier: "Open Page #16").firstMatch
        XCTAssertTrue(popupWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Command+Option+Shift click - should open in foreground Fire window
        let link16 = popupWindow.links["Open Page #16"]
        XCTAssertTrue(link16.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command, .option, .shift]) {
            link16.click()
        }

        // Should open in foreground Fire window
        let foregroundFireWindow = app.windows.firstMatch
        XCTAssertTrue(foregroundFireWindow.tabs["Page #16"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(foregroundFireWindow.webViews["Page #16"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 3) // Original Fire + popup + foreground Fire

        XCTAssertEqual(foregroundFireWindow.tabs.count, 1)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify new Fire window is frontmost (foreground Fire window operation)
        let newFireWindow = app.windows.containing(.keyPath(\.title, equalTo: "Page #16")).firstMatch
        XCTAssertEqual(app.windows.firstMatch.title, newFireWindow.title, "New Fire window should be frontmost when opened in foreground")
    }

    func testFireWindowPopupAfterOriginalFireWindowClosed() {
        app.setSwitchToNewTab(enabled: false)

        app.closeWindow()
        // Open Fire window
        app.openFireWindow()

        // Open a popup window from Fire window
        let popupHTML = """
        <a href='\(UITests.simpleServedPage(titled: "Page #17"))' id='link17'>Open Page #17</a>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Fire Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let fireWindow = app.windows.containing(.keyPath(\.title, equalTo: "Fire Page #12")).firstMatch
        let popupLink = fireWindow.webViews["Fire Page #12"].links["Open popup"]
        popupLink.click()

        // Close the original Fire window
        fireWindow.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(fireWindow.webViews["Fire Page #12"].waitForNonExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1) // Only popup window remains

        // Click link in popup - should open new Fire window
        let popupWindow = app.windows.containing(.link, identifier: "Open Page #17").firstMatch
        XCTAssertTrue(popupWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let link17 = popupWindow.links["Open Page #17"]
        XCTAssertTrue(link17.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            link17.click()
        }

        // Should open new Fire window
        XCTAssertEqual(app.windows.count, 2) // Popup + new Fire window
        let newFireWindow = app.windows.containing(.keyPath(\.title, equalTo: "Page #17")).firstMatch
        XCTAssertTrue(newFireWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(newFireWindow.tabs["Page #17"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(newFireWindow.webViews["Page #17"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(newFireWindow.tabs.count, 1)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify popup link still available
        XCTAssertTrue(link17.exists, "Popup link should still be available after navigation")

        // Verify new Fire window is frontmost
        XCTAssertEqual(app.windows.firstMatch.title, newFireWindow.title, "New Fire window should be frontmost after popup navigation")
    }

    func testFireWindowPopupBookmarkCommandClick() {
        app.setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add a bookmark for Page #18
        openTestPage("Page #18")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()

        app.closeWindow()
        // Open Fire window
        app.openFireWindow()

        // Open a popup window from Fire window
        let popupHTML = """
        <p>Popup content with bookmarks access</p>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Fire Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let fireWindow = app.windows.containing(.keyPath(\.title, equalTo: "Fire Page #12")).firstMatch
        let popupLink = fireWindow.webViews["Fire Page #12"].links["Open popup"]
        popupLink.click()

        let popupWindow = app.windows.containing(.staticText, identifier: "Popup content with bookmarks access").firstMatch
        XCTAssertTrue(popupWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Command click bookmark from popup - should open in background tab in Fire window
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Page #18"]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.command]) {
            bookmarkItem.click()
        }

        // Should open in background tab in Fire window, popup remains frontmost
        XCTAssertEqual(app.windows.count, 2)
        XCTAssertTrue(fireWindow.tabs["Page #18"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(fireWindow.webViews["Fire Page #12"].exists) // Original Fire page still in foreground
        XCTAssertFalse(fireWindow.webViews["Page #18"].exists) // Bookmark page in background
        XCTAssertTrue(fireWindow.tabs["Fire Page #12"].exists)
        XCTAssertEqual(fireWindow.tabs.count, 2)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify popup window remains frontmost (background operation)
        XCTAssertEqual(app.windows.firstMatch.title, popupWindow.title, "Popup window should remain frontmost for background operations")
    }

    func testFireWindowPopupBookmarkCommandShiftClick() {
        app.setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add a bookmark for Page #19
        openTestPage("Page #19")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()

        app.closeWindow()
        // Open Fire window
        app.openFireWindow()

        // Open a popup window from Fire window
        let popupHTML = """
        <p>Popup content with bookmarks access</p>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Fire Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let fireWindow = app.windows.containing(.keyPath(\.title, equalTo: "Fire Page #12")).firstMatch
        let popupLink = fireWindow.webViews["Fire Page #12"].links["Open popup"]
        popupLink.click()

        let popupWindow = app.windows.containing(.staticText, identifier: "Popup content with bookmarks access").firstMatch
        XCTAssertTrue(popupWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Command+Shift click bookmark from popup - should open in foreground tab in Fire window
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Page #19"]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            bookmarkItem.click()
        }

        // Should open in foreground tab in Fire window
        XCTAssertEqual(app.windows.count, 2)
        XCTAssertTrue(fireWindow.tabs["Page #19"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(fireWindow.webViews["Page #19"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(fireWindow.webViews["Fire Page #12"].exists) // Original Fire page now in background
        XCTAssertTrue(fireWindow.tabs["Fire Page #12"].exists)
        XCTAssertEqual(fireWindow.tabs.count, 2)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify Fire window is frontmost (foreground tab operation)
        XCTAssertEqual(app.windows.firstMatch.title, fireWindow.title, "Fire window should be frontmost after popup bookmark navigation")
    }

    func testFireWindowPopupNavigation() {
        app.setSwitchToNewTab(enabled: false)

        app.closeWindow()
        // Open Fire window
        app.openFireWindow()

        // Open a popup window from Fire window
        let popupHTML = """
        <a href='\(UITests.simpleServedPage(titled: "New Tab"))' target='_blank'>Open in new tab</a>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Fire Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let fireWindow = app.windows.containing(.keyPath(\.title, equalTo: "Fire Page #12")).firstMatch
        let popupLink = fireWindow.webViews["Fire Page #12"].links["Open popup"]
        popupLink.click()

        // Try to navigate in popup
        let popupWindow = app.windows.containing(.link, identifier: "Open in new tab").firstMatch
        let link = popupWindow.links["Open in new tab"]
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        link.click()

        // Should open in new tab of the Fire window
        XCTAssertEqual(app.windows.count, 2)
        XCTAssertTrue(fireWindow.tabs["New Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(fireWindow.webViews["New Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(fireWindow.tabs["Fire Page #12"].exists)
        XCTAssertEqual(fireWindow.tabs.count, 2)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify popup link still available
        XCTAssertTrue(link.exists, "Popup link should still be available after navigation")

        // Verify Fire window is frontmost
        XCTAssertEqual(app.windows.firstMatch.title, fireWindow.title, "Fire window should be frontmost after popup navigation")
    }

}
