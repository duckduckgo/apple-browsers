//
//  TabNavigationTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import XCTest

class TabNavigationTests: UITestCase {

    override class func setUp() {
        super.setUp()
        UITests.firstRun()
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()
    }

    // MARK: - Link Navigation Tests

    func testCommandClickOpensBackgroundTab() {
        openTestPage("Page #1") {
            "<a href='\(UITests.simpleServedPage(titled: "Opened Tab"))'>Open in new tab</a>"
        }
        let link = app.webViews["Page #1"].links["Open in new tab"]
        XCUIElement.perform(withKeyModifiers: [.command]) {
            link.click()
        }

        XCTAssertTrue(app.tabs["Opened Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Page #1"].exists)
        XCTAssertTrue(app.tabs["Page #1"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testMiddleClickOpensBackgroundTab() {
        openTestPage("Page #2") {
            "<a href='\(UITests.simpleServedPage(titled: "Opened Tab"))'>Open in new tab</a>"
        }
        let link = app.webViews["Page #2"].links["Open in new tab"]
        link.middleClick()

        XCTAssertTrue(app.tabs["Opened Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Page #2"].exists)
        XCTAssertTrue(app.tabs["Page #2"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testCommandShiftClickOpensActiveTab() {
        openTestPage("Page #3") {
            "<a href='\(UITests.simpleServedPage(titled: "Opened Tab"))'>Open in new tab</a>"
        }
        let link = app.webViews["Page #3"].links["Open in new tab"]
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            link.click()
        }

        XCTAssertTrue(app.webViews["Opened Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Page #3"].exists)
        XCTAssertTrue(app.tabs["Opened Tab"].exists)
        XCTAssertTrue(app.tabs["Page #3"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testMiddleShiftClickOpensActiveTab() {
        openTestPage("Page #4") {
            "<a href='\(UITests.simpleServedPage(titled: "Opened Tab"))'>Open in new tab</a>"
        }
        let link = app.webViews["Page #4"].links["Open in new tab"]
        XCUIElement.perform(withKeyModifiers: [.shift]) {
            link.middleClick()
        }
        XCTAssertTrue(app.webViews["Opened Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Page #4"].exists)
        XCTAssertTrue(app.tabs["Opened Tab"].exists)
        XCTAssertTrue(app.tabs["Page #4"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testCommandOptionClickOpensBackgroundWindow() {
        openTestPage("Page #5") {
            "<a href='\(UITests.simpleServedPage(titled: "New Window Page"))'>Open in new window</a>"
        }
        let link = app.webViews["Page #5"].links["Open in new window"]
        XCUIElement.perform(withKeyModifiers: [.command, .option]) {
            link.click()
        }

        let mainWindow = app.windows.firstMatch
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertTrue(backgroundWindow.webViews["New Window Page"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(mainWindow.webViews["New Window Page"].exists)

        XCTAssertTrue(mainWindow.webViews["Page #5"].exists)
        XCTAssertFalse(mainWindow.webViews["New Window Page"].exists)

        XCTAssertTrue(mainWindow.tabs["Page #5"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 1)

        XCTAssertTrue(backgroundWindow.tabs["New Window Page"].exists)
        XCTAssertEqual(backgroundWindow.tabs.count, 1)
    }

    func testMiddleOptionClickOpensBackgroundWindow() {
        openTestPage("Page #6") {
            "<a href='\(UITests.simpleServedPage(titled: "New Window Page"))'>Open in new window</a>"
        }
        let link = app.webViews["Page #6"].links["Open in new window"]
        XCUIElement.perform(withKeyModifiers: [.option]) {
            link.middleClick()
        }

        let mainWindow = app.windows.firstMatch
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertTrue(backgroundWindow.webViews["New Window Page"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(mainWindow.webViews["New Window Page"].exists)

        XCTAssertTrue(mainWindow.webViews["Page #6"].exists)
        XCTAssertFalse(mainWindow.webViews["New Window Page"].exists)

        XCTAssertTrue(mainWindow.tabs["Page #6"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 1)

        XCTAssertTrue(backgroundWindow.tabs["New Window Page"].exists)
        XCTAssertEqual(backgroundWindow.tabs.count, 1)
    }

    func testCommandOptionShiftClickOpensActiveWindow() {
        openTestPage("Page #7") {
            "<a href='\(UITests.simpleServedPage(titled: "New Window Page"))'>Open in new window</a>"
        }
        let link = app.webViews["Page #7"].links["Open in new window"]
        XCUIElement.perform(withKeyModifiers: [.command, .option, .shift]) {
            link.click()
        }

        let activeWindow = app.windows.firstMatch
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertTrue(activeWindow.webViews["New Window Page"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(activeWindow.webViews["Page #7"].exists)

        XCTAssertTrue(activeWindow.tabs["New Window Page"].exists)
        XCTAssertEqual(activeWindow.tabs.count, 1)
    }

    func testMiddleOptionShiftClickOpensActiveWindow() {
        openTestPage("Page #8") {
            "<a href='\(UITests.simpleServedPage(titled: "New Window Page"))'>Open in new window</a>"
        }
        let link = app.webViews["Page #8"].links["Open in new window"]
        XCUIElement.perform(withKeyModifiers: [.option, .shift]) {
            link.middleClick()
        }

        let activeWindow = app.windows.firstMatch
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertTrue(activeWindow.webViews["New Window Page"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(activeWindow.webViews["Page #8"].exists)

        XCTAssertTrue(activeWindow.tabs["New Window Page"].exists)
        XCTAssertEqual(activeWindow.tabs.count, 1)
    }

    func _testOptionClickDownloadsContent() {
        openTestPage("Page #9") {
            "<a href='data:application/zip;base64,UEsDBBQAAAAIAA==' download='file.zip'>Download file</a>"
        }
        let link = app.webViews["Page #9"].links["Download file"]
        XCUIElement.perform(withKeyModifiers: [.option]) {
            link.click()
        }

        XCTAssertTrue(app.downloadsButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.staticTexts["Downloading file.zip"].exists)
        XCTAssertTrue(app.tabs["Page #9"].exists)
        XCTAssertEqual(app.tabs.count, 1)
    }

    // MARK: - Settings and Special Cases Tests

    func testSettingsImpactOnTabBehavior() {
        // Enable "switch to new tab immediately" setting
        navigateToGeneralPreferences()
        let switchToNewTabToggle = app.switchToNewTabWhenOpenedCheckbox
        XCTAssertTrue(switchToNewTabToggle.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        if (switchToNewTabToggle.value as? Bool) != true {
            switchToNewTabToggle.click()
        }
        app.closeCurrentTab()

        // Test inverted behavior
        openTestPage("Page #10") {
            "<a href='\(UITests.simpleServedPage(titled: "Opened Tab"))'>Open in new tab</a>"
        }
        let link = app.webViews["Page #10"].links["Open in new tab"]
        XCUIElement.perform(withKeyModifiers: [.command]) {
            link.click()
        }

        XCTAssertTrue(app.webViews["Opened Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Page #10"].exists)
        XCTAssertTrue(app.tabs["Opened Tab"].exists)
        XCTAssertTrue(app.tabs["Page #10"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func _testPinnedTabsNavigation() {
        // Pin a tab
        openTestPage("Page #11") {
            "<a href='\(UITests.simpleServedPage(titled: "Opened Tab"))'>Open in new tab</a>"
        }
        app.mainMenuPinTabMenuItem.click()

        // Try to navigate in pinned tab
        let link = app.webViews["Page #11"].links["Open in new tab"]
        XCUIElement.perform(withKeyModifiers: [.command]) {
            link.click()
        }

        // Should open in new tab since pinned tabs can't navigate
        XCTAssertTrue(app.tabs["Opened Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Page #11"].exists)
        XCTAssertTrue(app.tabs["Page #11"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func _testPopupWindowsNavigation() {
        // Open a popup window
        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: "<a href='\(UITests.simpleServedPage(titled: "New Tab"))'>Open in new tab</a>")
            .absoluteString.escapedJavaScriptString()
        openTestPage("Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let popupLink = app.webViews["Page #12"].links["Open popup"]
        Thread.sleep(forTimeInterval: 60)
        popupLink.click()

        XCTAssertTrue(app.webViews["Popup Page"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Try to navigate in popup
        let link = app.webViews["Popup Page"].links["Open in new tab"]
        link.click()

        // Should open in new tab since popup windows can't navigate
        XCTAssertTrue(app.webViews["New Tab Page"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)
        XCTAssertTrue(app.webViews["Popup Page"].exists)
        XCTAssertTrue(app.tabs["Page #12"].exists)
        XCTAssertTrue(app.tabs["New Tab"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    // MARK: - Bookmark Navigation Tests

    func testBookmarkCommandClickOpensBackgroundTab() {
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()

        // Navigate to different page
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Other Page")

        // Command click bookmark should open in background tab
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Page #13"]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.command]) {
            bookmarkItem.click()
        }

        XCTAssertTrue(app.tabs["Page #13"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Other Page"].exists)    // Original page still visible
        XCTAssertFalse(app.webViews["Page #13"].exists)     // Bookmark page in background
        XCTAssertTrue(app.tabs["Page #13"].exists)
        XCTAssertTrue(app.tabs["Other Page"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testBookmarkCommandShiftClickOpensActiveTab() {
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()

        // Navigate to different page
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Other Page")

        // Command+Shift click bookmark should open in foreground tab
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Page #13"]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            bookmarkItem.click()
        }

        XCTAssertTrue(app.webViews["Page #13"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Other Page"].exists)   // Original page now in background
        XCTAssertTrue(app.tabs["Page #13"].exists)
        XCTAssertTrue(app.tabs["Other Page"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testBookmarkCommandOptionClickOpensBackgroundWindow() {
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()

        // Navigate to different page
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Other Page")

        // Command+Option click bookmark should open in background window
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Page #13"]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.command, .option]) {
            bookmarkItem.click()
        }

        let mainWindow = app.windows.firstMatch
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(backgroundWindow.webViews["Page #13"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertTrue(mainWindow.webViews["Other Page"].exists)     // Original page still visible in main window
        XCTAssertFalse(mainWindow.webViews["Page #13"].exists)     // Bookmark not in main window
        XCTAssertTrue(mainWindow.tabs["Other Page"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 1)

        XCTAssertTrue(backgroundWindow.tabs["Page #13"].exists)
        XCTAssertEqual(backgroundWindow.tabs.count, 1)
    }

    func testBookmarkCommandOptionShiftClickOpensActiveWindow() {
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()

        // Navigate to different page
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Other Page")

        // Command+Option+Shift click bookmark should open in foreground window
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Page #13"]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.command, .option, .shift]) {
            bookmarkItem.click()
        }

        let activeWindow = app.windows.firstMatch
        XCTAssertTrue(activeWindow.webViews["Page #13"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertFalse(activeWindow.webViews["Other Page"].exists) // Original page now in background window
        XCTAssertTrue(activeWindow.tabs["Page #13"].exists)
        XCTAssertEqual(activeWindow.tabs.count, 1)
    }

    func testBookmarkRegularClickOpensSameTab() {
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()

        // Navigate to different page
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Other Page")

        // Regular click bookmark should replace current tab
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Page #13"]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        bookmarkItem.click()

        XCTAssertTrue(app.webViews["Page #13"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Other Page"].exists)   // Replaced by bookmark
        XCTAssertTrue(app.tabs["Page #13"].exists)
        XCTAssertEqual(app.tabs.count, 1)                   // Only one tab
    }

    func testBookmarkMiddleClickOpensBackgroundTab() {
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()

        // Navigate to different page
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Other Page")

        // Middle click bookmark should open in background tab
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Page #13"]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        bookmarkItem.middleClick()

        XCTAssertTrue(app.tabs["Page #13"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Other Page"].exists)    // Original page still visible
        XCTAssertFalse(app.webViews["Page #13"].exists)     // Bookmark page in background
        XCTAssertTrue(app.tabs["Page #13"].exists)
        XCTAssertTrue(app.tabs["Other Page"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testBookmarkMiddleShiftClickOpensActiveTab() {
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()

        // Navigate to different page
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Other Page")

        // Middle+Shift click bookmark should open in foreground tab
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Page #13"]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.shift]) {
            bookmarkItem.middleClick()
        }

        XCTAssertTrue(app.webViews["Page #13"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Other Page"].exists)   // Original page now in background
        XCTAssertTrue(app.tabs["Page #13"].exists)
        XCTAssertTrue(app.tabs["Other Page"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testBookmarkMiddleOptionClickOpensBackgroundWindow() {
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()

        // Navigate to different page
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Other Page")

        // Middle+Option click bookmark should open in background window
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Page #13"]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.option]) {
            bookmarkItem.middleClick()
        }

        let mainWindow = app.windows.firstMatch
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(backgroundWindow.webViews["Page #13"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertTrue(mainWindow.webViews["Other Page"].exists)     // Original page still visible in main window
        XCTAssertFalse(mainWindow.webViews["Page #13"].exists)     // Bookmark not in main window
        XCTAssertTrue(mainWindow.tabs["Other Page"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 1)

        XCTAssertTrue(backgroundWindow.tabs["Page #13"].exists)
        XCTAssertEqual(backgroundWindow.tabs.count, 1)
    }

    func testBookmarkMiddleOptionShiftClickOpensActiveWindow() {
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()

        // Navigate to different page
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Other Page")

        // Middle+Option+Shift click bookmark should open in foreground window
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Page #13"]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.option, .shift]) {
            bookmarkItem.middleClick()
        }

        let activeWindow = app.windows.firstMatch
        XCTAssertTrue(activeWindow.webViews["Page #13"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertFalse(activeWindow.webViews["Other Page"].exists) // Original page now in background window
        XCTAssertTrue(activeWindow.tabs["Page #13"].exists)
        XCTAssertEqual(activeWindow.tabs.count, 1)
    }

    // MARK: - History Navigation Tests

    func testHistoryCommandClickOpensBackgroundTab() {
        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Other Page")

        // Command click history item should open in background tab
        app.historyMenu.click()
        let historyItem = app.menuItems["Page #14"]
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.command]) {
            historyItem.click()
        }

        XCTAssertTrue(app.tabs["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Other Page"].exists)    // Original page still visible
        XCTAssertFalse(app.webViews["Page #14"].exists)     // History page in background
        XCTAssertTrue(app.tabs["Page #14"].exists)
        XCTAssertTrue(app.tabs["Other Page"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testHistoryCommandShiftClickOpensActiveTab() {
        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Other Page")

        // Command+Shift click history item should open in foreground tab
        app.historyMenu.click()
        let historyItem = app.menuItems["Page #14"]
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            historyItem.click()
        }

        XCTAssertTrue(app.webViews["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Other Page"].exists)   // Original page now in background
        XCTAssertTrue(app.tabs["Page #14"].exists)
        XCTAssertTrue(app.tabs["Other Page"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testHistoryRegularClickOpensSameTab() {
        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Other Page")

        // Regular click history item should replace current tab
        app.historyMenu.click()
        let historyItem = app.menuItems["Page #14"]
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        historyItem.click()

        XCTAssertTrue(app.webViews["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Other Page"].exists)   // Replaced by history item
        XCTAssertTrue(app.tabs["Page #14"].exists)
        XCTAssertEqual(app.tabs.count, 1)                   // Only one tab
    }

    func testHistoryMiddleClickOpensBackgroundTab() {
        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Other Page")

        // Middle click history item should open in background tab
        app.historyMenu.click()
        let historyItem = app.menuItems["Page #14"]
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        historyItem.middleClick()

        XCTAssertTrue(app.tabs["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Other Page"].exists)    // Original page still visible
        XCTAssertFalse(app.webViews["Page #14"].exists)     // History page in background
        XCTAssertTrue(app.tabs["Page #14"].exists)
        XCTAssertTrue(app.tabs["Other Page"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testHistoryMiddleShiftClickOpensActiveTab() {
        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Other Page")

        // Middle+Shift click history item should open in foreground tab
        app.historyMenu.click()
        let historyItem = app.menuItems["Page #14"]
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.shift]) {
            historyItem.middleClick()
        }

        XCTAssertTrue(app.webViews["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Other Page"].exists)   // Original page now in background
        XCTAssertTrue(app.tabs["Page #14"].exists)
        XCTAssertTrue(app.tabs["Other Page"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testHistoryCommandOptionClickOpensBackgroundWindow() {
        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Other Page")

        // Command+Option click history item should open in background window
        app.historyMenu.click()
        let historyItem = app.menuItems["Page #14"]
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.command, .option]) {
            historyItem.click()
        }

        let mainWindow = app.windows.firstMatch
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(backgroundWindow.webViews["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertTrue(mainWindow.webViews["Other Page"].exists)     // Original page still visible in main window
        XCTAssertFalse(mainWindow.webViews["Page #14"].exists)     // History not in main window
        XCTAssertTrue(mainWindow.tabs["Other Page"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 1)

        XCTAssertTrue(backgroundWindow.tabs["Page #14"].exists)
        XCTAssertEqual(backgroundWindow.tabs.count, 1)
    }

    func testHistoryCommandOptionShiftClickOpensActiveWindow() {
        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Other Page")

        // Command+Option+Shift click history item should open in foreground window
        app.historyMenu.click()
        let historyItem = app.menuItems["Page #14"]
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.command, .option, .shift]) {
            historyItem.click()
        }

        let activeWindow = app.windows.firstMatch
        XCTAssertTrue(activeWindow.webViews["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertFalse(activeWindow.webViews["Other Page"].exists) // Original page now in background window
        XCTAssertTrue(activeWindow.tabs["Page #14"].exists)
        XCTAssertEqual(activeWindow.tabs.count, 1)
    }

    func testHistoryMiddleOptionClickOpensBackgroundWindow() {
        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Other Page")

        // Middle+Option click history item should open in background window
        app.historyMenu.click()
        let historyItem = app.menuItems["Page #14"]
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.option]) {
            historyItem.middleClick()
        }

        let mainWindow = app.windows.firstMatch
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(backgroundWindow.webViews["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertTrue(mainWindow.webViews["Other Page"].exists)     // Original page still visible in main window
        XCTAssertFalse(mainWindow.webViews["Page #14"].exists)     // History not in main window
        XCTAssertTrue(mainWindow.tabs["Other Page"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 1)

        XCTAssertTrue(backgroundWindow.tabs["Page #14"].exists)
        XCTAssertEqual(backgroundWindow.tabs.count, 1)
    }

    func testHistoryMiddleOptionShiftClickOpensActiveWindow() {
        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Other Page")

        // Middle+Option+Shift click history item should open in foreground window
        app.historyMenu.click()
        let historyItem = app.menuItems["Page #14"]
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.option, .shift]) {
            historyItem.middleClick()
        }

        let activeWindow = app.windows.firstMatch
        XCTAssertTrue(activeWindow.webViews["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertFalse(activeWindow.webViews["Other Page"].exists) // Original page now in background window
        XCTAssertTrue(activeWindow.tabs["Page #14"].exists)
        XCTAssertEqual(activeWindow.tabs.count, 1)
    }

    // MARK: - Favorites Navigation Tests

    func testFavoritesRegularClickOpensSameTab() {
        app.resetBookmarks()

        // Add to favorites
        openTestPage("Page #15")
        app.mainMenuAddBookmarkMenuItem.click()
        app.bookmarksDialogAddToFavoritesCheckbox.click()
        app.addBookmarkAlertAddButton.click()

        app.closeAllWindows()
        app.openNewWindow()

        // Find the favorite item by its title
        let favoriteItem = app.links["Page #15"]
        XCTAssertTrue(favoriteItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Regular click should open in same tab
        favoriteItem.click()
        XCTAssertTrue(app.webViews["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["New Tab Page"].exists)
        XCTAssertTrue(app.tabs["Page #15"].exists)
        XCTAssertEqual(app.tabs.count, 1)
    }

    func testFavoritesCommandClickOpensBackgroundTab() {
        app.resetBookmarks()

        // Add to favorites
        openTestPage("Page #15")
        app.mainMenuAddBookmarkMenuItem.click()
        app.bookmarksDialogAddToFavoritesCheckbox.click()
        app.addBookmarkAlertAddButton.click()

        app.closeAllWindows()
        app.openNewWindow()

        // Find the favorite item by its title
        let favoriteItem = app.links["Page #15"]
        XCTAssertTrue(favoriteItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Command click should open in background tab
        XCUIElement.perform(withKeyModifiers: [.command]) {
            favoriteItem.click()
        }
        XCTAssertTrue(app.tabs["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["New Tab Page"].exists)
        XCTAssertFalse(app.webViews["Page #15"].exists)      // Favorites in background
        XCTAssertTrue(app.tabs["Page #15"].exists)
        XCTAssertTrue(app.tabs["New Tab"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testFavoritesCommandShiftClickOpensActiveTab() {
        app.resetBookmarks()

        // Add to favorites
        openTestPage("Page #15")
        app.mainMenuAddBookmarkMenuItem.click()
        app.bookmarksDialogAddToFavoritesCheckbox.click()
        app.addBookmarkAlertAddButton.click()

        app.closeAllWindows()
        app.openNewWindow()

        // Find the favorite item by its title
        let favoriteItem = app.links["Page #15"]
        XCTAssertTrue(favoriteItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Command shift click should open in foreground tab
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            favoriteItem.click()
        }
        XCTAssertTrue(app.webViews["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["New Tab Page"].exists) // New Tab now in background
        XCTAssertTrue(app.tabs["Page #15"].exists)
        XCTAssertTrue(app.tabs["New Tab"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testFavoritesCommandOptionClickOpensBackgroundWindow() {
        app.resetBookmarks()

        // Add to favorites
        openTestPage("Page #15")
        app.mainMenuAddBookmarkMenuItem.click()
        app.bookmarksDialogAddToFavoritesCheckbox.click()
        app.addBookmarkAlertAddButton.click()

        app.closeAllWindows()
        app.openNewWindow()

        // Find the favorite item by its title
        let favoriteItem = app.links["Page #15"]
        XCTAssertTrue(favoriteItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Command option click should open in background window
        XCUIElement.perform(withKeyModifiers: [.command, .option]) {
            favoriteItem.click()
        }
        let mainWindow = app.windows.firstMatch
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(backgroundWindow.webViews["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertTrue(mainWindow.webViews["New Tab Page"].exists)
        XCTAssertFalse(mainWindow.webViews["Page #15"].exists)
        XCTAssertTrue(mainWindow.tabs["New Tab"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 1)

        XCTAssertTrue(backgroundWindow.tabs["Page #15"].exists)
        XCTAssertEqual(backgroundWindow.tabs.count, 1)
    }

    func testFavoritesCommandOptionShiftClickOpensActiveWindow() {
        app.resetBookmarks()

        // Add to favorites
        openTestPage("Page #15")
        app.mainMenuAddBookmarkMenuItem.click()
        app.bookmarksDialogAddToFavoritesCheckbox.click()
        app.addBookmarkAlertAddButton.click()

        app.closeAllWindows()
        app.openNewWindow()

        // Find the favorite item by its title
        let favoriteItem = app.links["Page #15"]
        XCTAssertTrue(favoriteItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Command option shift click should open in foreground window
        XCUIElement.perform(withKeyModifiers: [.command, .option, .shift]) {
            favoriteItem.click()
        }
        let activeWindow = app.windows.firstMatch
        XCTAssertTrue(activeWindow.webViews["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertFalse(activeWindow.webViews["New Tab Page"].exists)
        XCTAssertTrue(activeWindow.tabs["Page #15"].exists)
        XCTAssertEqual(activeWindow.tabs.count, 1)
    }

    func testFavoritesMiddleClickOpensBackgroundTab() {
        app.resetBookmarks()

        // Add to favorites
        openTestPage("Page #15")
        app.mainMenuAddBookmarkMenuItem.click()
        app.bookmarksDialogAddToFavoritesCheckbox.click()
        app.addBookmarkAlertAddButton.click()

        app.closeAllWindows()
        app.openNewWindow()

        // Find the favorite item by its title
        let favoriteItem = app.links["Page #15"]
        XCTAssertTrue(favoriteItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Middle click should open in background tab
        favoriteItem.middleClick()

        XCTAssertTrue(app.tabs["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["New Tab Page"].exists)
        XCTAssertFalse(app.webViews["Page #15"].exists)      // Favorite in background
        XCTAssertTrue(app.tabs["Page #15"].exists)
        XCTAssertTrue(app.tabs["New Tab"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testFavoritesMiddleShiftClickOpensActiveTab() {
        app.resetBookmarks()

        // Add to favorites
        openTestPage("Page #15")
        app.mainMenuAddBookmarkMenuItem.click()
        app.bookmarksDialogAddToFavoritesCheckbox.click()
        app.addBookmarkAlertAddButton.click()

        app.closeAllWindows()
        app.openNewWindow()

        // Find the favorite item by its title
        let favoriteItem = app.links["Page #15"]
        XCTAssertTrue(favoriteItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Middle+Shift click should open in foreground tab
        XCUIElement.perform(withKeyModifiers: [.shift]) {
            favoriteItem.middleClick()
        }

        XCTAssertTrue(app.webViews["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["New Tab Page"].exists) // New Tab now in background
        XCTAssertTrue(app.tabs["Page #15"].exists)
        XCTAssertTrue(app.tabs["New Tab"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testFavoritesMiddleOptionClickOpensBackgroundWindow() {
        app.resetBookmarks()

        // Add to favorites
        openTestPage("Page #15")
        app.mainMenuAddBookmarkMenuItem.click()
        app.bookmarksDialogAddToFavoritesCheckbox.click()
        app.addBookmarkAlertAddButton.click()

        app.closeAllWindows()
        app.openNewWindow()

        // Find the favorite item by its title
        let favoriteItem = app.links["Page #15"]
        XCTAssertTrue(favoriteItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Middle+Option click should open in background window
        XCUIElement.perform(withKeyModifiers: [.option]) {
            favoriteItem.middleClick()
        }

        let mainWindow = app.windows.firstMatch
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(backgroundWindow.webViews["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertTrue(mainWindow.webViews["New Tab Page"].exists)
        XCTAssertFalse(mainWindow.webViews["Page #15"].exists)
        XCTAssertTrue(mainWindow.tabs["New Tab"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 1)

        XCTAssertTrue(backgroundWindow.tabs["Page #15"].exists)
        XCTAssertEqual(backgroundWindow.tabs.count, 1)
    }

    func testFavoritesMiddleOptionShiftClickOpensActiveWindow() {
        app.resetBookmarks()

        // Add to favorites
        openTestPage("Page #15")
        app.mainMenuAddBookmarkMenuItem.click()
        app.bookmarksDialogAddToFavoritesCheckbox.click()
        app.addBookmarkAlertAddButton.click()

        app.closeAllWindows()
        app.openNewWindow()

        // Find the favorite item by its title
        let favoriteItem = app.links["Page #15"]
        XCTAssertTrue(favoriteItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Middle+Option+Shift click should open in foreground window
        XCUIElement.perform(withKeyModifiers: [.option, .shift]) {
            favoriteItem.middleClick()
        }

        let activeWindow = app.windows.firstMatch
        XCTAssertTrue(activeWindow.webViews["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertFalse(activeWindow.webViews["New Tab Page"].exists)
        XCTAssertTrue(activeWindow.tabs["Page #15"].exists)
        XCTAssertEqual(activeWindow.tabs.count, 1)
    }

    // MARK: - Other Navigation Tests

    func testBookmarksBarNavigation() {
        // Add to bookmarks bar
        openTestPage("Page #16")
        app.mainMenuAddBookmarkMenuItem.click()
        app.bookmarkDialogBookmarkFolderDropdown.click()
        app.mainMenuToggleBookmarksBarMenuItem.click()
        app.addBookmarkAlertAddButton.click()

        // Open bookmark with different modifiers
        let bookmarkItem = app.bookmarksBar.buttons["Page #16"]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Command click should open in background
        XCUIElement.perform(withKeyModifiers: [.command]) {
            bookmarkItem.click()
        }
        XCTAssertTrue(app.webViews["Page #16"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["New Tab Page"].exists)
        XCTAssertTrue(app.tabs["Page #16"].exists)
        XCTAssertTrue(app.tabs["New Tab"].exists)
        XCTAssertEqual(app.tabs.count, 2)

        // Command shift click should open in foreground
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            bookmarkItem.click()
        }
        XCTAssertTrue(app.webViews["Page #16"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["New Tab Page"].exists)
        XCTAssertTrue(app.tabs["Page #16"].exists)
        XCTAssertTrue(app.tabs["New Tab"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testBackForwardCommandClickOpensBackgroundTab() {
        // Create navigation history
        openTestPage("Page #17")
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Page #18")
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Page #19")

        // Go back to Page #18
        app.backButton.click()
        XCTAssertTrue(app.webViews["Page #18"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertEqual(app.tabs.count, 1)

        // Command click back button should open Page #17 in background tab
        XCUIElement.perform(withKeyModifiers: [.command]) {
            app.backButton.click()
        }

        XCTAssertTrue(app.tabs["Page #17"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Page #18"].exists)       // Original page still visible
        XCTAssertFalse(app.webViews["Page #17"].exists)      // Back page in background
        XCTAssertTrue(app.tabs["Page #17"].exists)
        XCTAssertTrue(app.tabs["Page #18"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testBackForwardCommandShiftClickOpensActiveTab() {
        // Create navigation history
        openTestPage("Page #17")
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Page #18")
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Page #19")

        // Go back to Page #18
        app.backButton.click()
        XCTAssertTrue(app.webViews["Page #18"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertEqual(app.tabs.count, 1)

        // Command+Shift click back button should open Page #17 in foreground tab
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            app.backButton.click()
        }

        XCTAssertTrue(app.webViews["Page #17"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Page #18"].exists)      // Original page now in background
        XCTAssertTrue(app.tabs["Page #17"].exists)
        XCTAssertTrue(app.tabs["Page #18"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testBackForwardMiddleClickOpensBackgroundTab() {
        // Create navigation history
        openTestPage("Page #17")
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Page #18")
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Page #19")

        // Go back to Page #18
        app.backButton.click()
        XCTAssertTrue(app.webViews["Page #18"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertEqual(app.tabs.count, 1)

        // Middle click back button should open Page #17 in background tab
        app.backButton.middleClick()

        XCTAssertTrue(app.tabs["Page #17"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Page #18"].exists)       // Original page still visible
        XCTAssertFalse(app.webViews["Page #17"].exists)      // Back page in background
        XCTAssertTrue(app.tabs["Page #17"].exists)
        XCTAssertTrue(app.tabs["Page #18"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testBackForwardMiddleShiftClickOpensActiveTab() {
        // Create navigation history
        openTestPage("Page #17")
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Page #18")
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Page #19")

        // Go back to Page #18
        app.backButton.click()
        XCTAssertTrue(app.webViews["Page #18"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertEqual(app.tabs.count, 1)

        // Middle+Shift click back button should open Page #17 in foreground tab
        XCUIElement.perform(withKeyModifiers: [.shift]) {
            app.backButton.middleClick()
        }

        XCTAssertTrue(app.webViews["Page #17"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Page #18"].exists)      // Original page now in background
        XCTAssertTrue(app.tabs["Page #17"].exists)
        XCTAssertTrue(app.tabs["Page #18"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testForwardNavigationCommandClickOpensBackgroundTab() {
        // Create navigation history and go back
        openTestPage("Page #17")
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Page #18")
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Page #19")

        // Go back twice to Page #17
        app.backButton.click()
        app.backButton.click()
        XCTAssertTrue(app.webViews["Page #17"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertEqual(app.tabs.count, 1)

        // Command click forward button should open Page #18 in background tab
        XCUIElement.perform(withKeyModifiers: [.command]) {
            app.forwardButton.click()
        }

        XCTAssertTrue(app.tabs["Page #18"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Page #17"].exists)       // Original page still visible
        XCTAssertFalse(app.webViews["Page #18"].exists)      // Forward page in background
        XCTAssertTrue(app.tabs["Page #17"].exists)
        XCTAssertTrue(app.tabs["Page #18"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testForwardNavigationCommandShiftClickOpensActiveTab() {
        // Create navigation history and go back
        openTestPage("Page #17")
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Page #18")
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Page #19")

        // Go back twice to Page #17
        app.backButton.click()
        app.backButton.click()
        XCTAssertTrue(app.webViews["Page #17"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertEqual(app.tabs.count, 1)

        // Command+Shift click forward button should open Page #18 in foreground tab
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            app.forwardButton.click()
        }

        XCTAssertTrue(app.webViews["Page #18"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Page #17"].exists)      // Original page now in background
        XCTAssertTrue(app.tabs["Page #17"].exists)
        XCTAssertTrue(app.tabs["Page #18"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testForwardNavigationMiddleClickOpensBackgroundTab() {
        // Create navigation history and go back
        openTestPage("Page #17")
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Page #18")
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Page #19")

        // Go back twice to Page #17
        app.backButton.click()
        app.backButton.click()
        XCTAssertTrue(app.webViews["Page #17"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertEqual(app.tabs.count, 1)

        // Middle click forward button should open Page #18 in background tab
        app.forwardButton.middleClick()

        XCTAssertTrue(app.tabs["Page #18"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Page #17"].exists)       // Original page still visible
        XCTAssertFalse(app.webViews["Page #18"].exists)      // Forward page in background
        XCTAssertTrue(app.tabs["Page #17"].exists)
        XCTAssertTrue(app.tabs["Page #18"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testForwardNavigationMiddleShiftClickOpensActiveTab() {
        // Create navigation history and go back
        openTestPage("Page #17")
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Page #18")
        app.typeKey("l", modifierFlags: .command)  // Activate address bar
        openTestPage("Page #19")

        // Go back twice to Page #17
        app.backButton.click()
        app.backButton.click()
        XCTAssertTrue(app.webViews["Page #17"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertEqual(app.tabs.count, 1)

        // Middle+Shift click forward button should open Page #18 in foreground tab
        XCUIElement.perform(withKeyModifiers: [.shift]) {
            app.forwardButton.middleClick()
        }

        XCTAssertTrue(app.webViews["Page #18"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Page #17"].exists)      // Original page now in background
        XCTAssertTrue(app.tabs["Page #17"].exists)
        XCTAssertTrue(app.tabs["Page #18"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testAddressBarSuggestionsNavigation() {
        // Type to get suggestions
        app.addressBar.typeText("Page #20")

        // Command click suggestion should open in background
        let suggestion = app.tables["SuggestionViewController.tableView"].cells["Page #20"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command]) {
            suggestion.click()
        }

        XCTAssertTrue(app.webViews["Page #20"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["New Tab Page"].exists)
        XCTAssertTrue(app.tabs["Page #20"].exists)
        XCTAssertTrue(app.tabs["New Tab"].exists)
        XCTAssertEqual(app.tabs.count, 2)

        // Command shift click suggestion should open in foreground
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            suggestion.click()
        }
        XCTAssertTrue(app.webViews["Page #20"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["New Tab Page"].exists)
        XCTAssertTrue(app.tabs["Page #20"].exists)
        XCTAssertTrue(app.tabs["New Tab"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testContextMenuNavigation() {
        openTestPage("Page #21") {
            "<a href='\(UITests.simpleServedPage(titled: "New Tab"))'>Open in new tab</a>"
        }
        let link = app.webViews["Page #21"].links["Open in new tab"]

        // Right click to show context menu
        link.rightClick()

        // Command click menu item should open in background
        let menuItem = app.menuItems["Open in New Tab"]
        XCTAssertTrue(menuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command]) {
            menuItem.click()
        }

        XCTAssertTrue(app.webViews["New Tab Page"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Page #21"].exists)
        XCTAssertTrue(app.tabs["New Tab"].exists)
        XCTAssertTrue(app.tabs["Page #21"].exists)
        XCTAssertEqual(app.tabs.count, 2)

        // Command shift click menu item should open in foreground
        link.rightClick()
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            menuItem.click()
        }

        XCTAssertTrue(app.webViews["New Tab Page"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Page #21"].exists)
        XCTAssertTrue(app.tabs["New Tab"].exists)
        XCTAssertTrue(app.tabs["Page #21"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    // MARK: - Test Utilities

    private func openTestPage(_ title: String, body: (() -> String)? = nil) {
        let url = UITests.simpleServedPage(titled: title, body: body?() ?? "<p>Sample text for \(title)</p>")
        XCTAssertTrue(
            app.addressBar.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The address bar text field didn't become available in a reasonable timeframe."
        )
        app.addressBar.pasteURL(url)
        XCTAssertTrue(
            app.windows.firstMatch.webViews[title].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Visited site didn't load with the expected title in a reasonable timeframe."
        )
    }

    private func navigateToGeneralPreferences() {
        app.openPreferences()
        app.preferencesGeneralButton.click()
    }

}
