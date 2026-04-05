//
//  TabNavigationMenuItemTests.swift
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
import XCTest

final class TabNavigationMenuItemTests: UITestCase, TabNavigationTestHelpers {

    override class func setUp() {
        super.setUp()
        UITests.firstRun()
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp()
    }

    // MARK: - Bookmark Navigation Tests

    func testBookmarkRegularClickOpensInCurrentTab() {
        app.setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add a bookmark target page.
        openTestPage("Bookmark Current Tab Target")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()
        app.dismissBookmarksBarPopover()

        // Move away so menu navigation has a visible source page.
        app.activateAddressBar()
        openTestPage("Bookmark Source Page")

        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Bookmark Current Tab Target"]
        // Bookmark item should be visible in the menu.
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        bookmarkItem.click()

        // Target page should be active in the current tab.
        XCTAssertTrue(app.webViews["Bookmark Current Tab Target"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // No new window should be created.
        XCTAssertEqual(app.windows.count, 1)
        // Source page should no longer be active.
        XCTAssertFalse(app.webViews["Bookmark Source Page"].exists)
        // Target tab should exist.
        XCTAssertTrue(app.tabs["Bookmark Current Tab Target"].exists)
        // Tab count should stay one (current-tab navigation).
        XCTAssertEqual(app.tabs.count, 1)
    }

    func testBookmarkCommandClickOpensBackgroundTab() {
        app.setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()
        app.dismissBookmarksBarPopover()

        // Navigate to different page
        app.activateAddressBar()
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
        app.setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()
        app.dismissBookmarksBarPopover()

        // Navigate to different page
        app.activateAddressBar()
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
        app.setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()
        app.dismissBookmarksBarPopover()

        // Navigate to different page
        app.activateAddressBar()
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
        app.setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()
        app.dismissBookmarksBarPopover()

        // Navigate to different page
        app.activateAddressBar()
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

    func testBookmarkMiddleClickOpensBackgroundTab() {
        app.setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()
        app.dismissBookmarksBarPopover()

        // Navigate to different page
        app.activateAddressBar()
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
        app.setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()
        app.dismissBookmarksBarPopover()

        // Navigate to different page
        app.activateAddressBar()
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
        app.setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()
        app.dismissBookmarksBarPopover()

        // Navigate to different page
        app.activateAddressBar()
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
        app.setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()
        app.dismissBookmarksBarPopover()

        // Navigate to different page
        app.activateAddressBar()
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

    func testHistoryRegularClickOpensInCurrentTab() {
        app.setSwitchToNewTab(enabled: false)

        // Visit target page so it appears in history.
        openTestPage("History Current Tab Target")

        // Move away so opening from history is observable.
        app.activateAddressBar()
        openTestPage("History Source Page")

        app.historyMenu.click()
        let historyItem = app.menuItems["History Current Tab Target"]
        // History item should be visible in the menu.
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        historyItem.click()

        // Target page should be active in the current tab.
        XCTAssertTrue(app.webViews["History Current Tab Target"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // No new window should be created.
        XCTAssertEqual(app.windows.count, 1)
        // Source page should no longer be active.
        XCTAssertFalse(app.webViews["History Source Page"].exists)
        // Target tab should exist.
        XCTAssertTrue(app.tabs["History Current Tab Target"].exists)
        // Tab count should stay one (current-tab navigation).
        XCTAssertEqual(app.tabs.count, 1)
    }

    func testHistoryCommandClickOpensBackgroundTab() {
        app.setSwitchToNewTab(enabled: false)

        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.activateAddressBar()
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
        app.setSwitchToNewTab(enabled: false)

        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.activateAddressBar()
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

    func testHistoryMiddleClickOpensBackgroundTab() {
        app.setSwitchToNewTab(enabled: false)

        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.activateAddressBar()
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
        app.setSwitchToNewTab(enabled: false)

        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.activateAddressBar()
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
        app.setSwitchToNewTab(enabled: false)

        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.activateAddressBar()
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
        app.setSwitchToNewTab(enabled: false)

        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.activateAddressBar()
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
        app.setSwitchToNewTab(enabled: false)

        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.activateAddressBar()
        app.activateAddressBar()
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
        app.setSwitchToNewTab(enabled: false)

        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.activateAddressBar()
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
        app.setSwitchToNewTab(enabled: false)
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
        app.setSwitchToNewTab(enabled: false)
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
        app.setSwitchToNewTab(enabled: false)
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
        app.setSwitchToNewTab(enabled: false)
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
        app.setSwitchToNewTab(enabled: false)
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
        app.setSwitchToNewTab(enabled: false)
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
        app.setSwitchToNewTab(enabled: false)
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
        app.setSwitchToNewTab(enabled: false)
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
        app.setSwitchToNewTab(enabled: false)
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

    // MARK: - Bookmarks Panel and Bar Navigation Tests

    func testBookmarksPanelNavigation() throws {
        app.setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        func panelBookmarkTargetItem(in window: XCUIElement) -> XCUIElement {
            let bookmarksPanelPopover = window.popovers.firstMatch
            if !bookmarksPanelPopover.exists {
                window.openBookmarksPanel()
            }

            XCTAssertTrue(bookmarksPanelPopover.waitForExistence(timeout: UITests.Timeouts.elementExistence))
            let item = bookmarksPanelPopover.outlines.firstMatch.staticTexts["Panel Bookmark Target"].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: UITests.Timeouts.elementExistence))
            return item
        }

        // Open test page and bookmark it.
        openTestPage("Panel Bookmark Target")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()
        app.dismissBookmarksBarPopover()

        // Navigate to another page.
        app.activateAddressBar()
        openTestPage("Panel Bookmark Source")
        let mainWindow = app.windows.containing(.keyPath(\.title, equalTo: "Panel Bookmark Source")).firstMatch

        // Regular click from bookmarks panel should open current tab.
        var panelBookmarkItem = panelBookmarkTargetItem(in: mainWindow)
        panelBookmarkItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        // Target page should be active in the current tab.
        XCTAssertTrue(app.webViews["Panel Bookmark Target"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // No new window should be created.
        XCTAssertEqual(app.windows.count, 1)
        // Source page should no longer be active.
        XCTAssertFalse(app.webViews["Panel Bookmark Source"].exists)
        // Tab count should stay one (current-tab navigation).
        XCTAssertEqual(app.tabs.count, 1)

        // Cmd click from panel should open background tab.
        app.activateAddressBar()
        openTestPage("Panel Bookmark Source")
        panelBookmarkItem = panelBookmarkTargetItem(in: mainWindow)
        let commandPanelBookmarkClick = panelBookmarkItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        XCUIElement.perform(withKeyModifiers: [.command]) {
            commandPanelBookmarkClick.click()
        }
        // Target tab should be created.
        XCTAssertTrue(app.tabs["Panel Bookmark Target"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // No new window should be created.
        XCTAssertEqual(app.windows.count, 1)
        // Source page should remain active (target opens in background).
        XCTAssertTrue(app.webViews["Panel Bookmark Source"].exists)
        // Target page should not be active (background tab check).
        XCTAssertFalse(app.webViews["Panel Bookmark Target"].exists)
        // There should be source + target tabs.
        XCTAssertEqual(app.tabs.count, 2)
        try app.tabs.element(boundBy: 1).closeTab()

        // Cmd+Shift click from panel should open selected tab.
        panelBookmarkItem = panelBookmarkTargetItem(in: mainWindow)
        let commandShiftPanelBookmarkClick = panelBookmarkItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            commandShiftPanelBookmarkClick.click()
        }
        // Target page should be active.
        XCTAssertTrue(app.webViews["Panel Bookmark Target"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // No new window should be created.
        XCTAssertEqual(app.windows.count, 1)
        // Source page should no longer be active.
        XCTAssertFalse(app.webViews["Panel Bookmark Source"].exists)
        // Source tab should still exist.
        XCTAssertTrue(app.tabs["Panel Bookmark Source"].exists)
        // Target tab should exist.
        XCTAssertTrue(app.tabs["Panel Bookmark Target"].exists)
        // There should be source + target tabs.
        XCTAssertEqual(app.tabs.count, 2)
        app.closeCurrentTab()

        // Cmd+Option click from panel should open background window.
        panelBookmarkItem = panelBookmarkTargetItem(in: mainWindow)
        let commandOptionPanelBookmarkClick = panelBookmarkItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        XCUIElement.perform(withKeyModifiers: [.command, .option]) {
            commandOptionPanelBookmarkClick.click()
        }
        let backgroundWindow = app.windows.element(boundBy: 1)
        // Background window should appear.
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Target page should load in that background window.
        XCTAssertTrue(backgroundWindow.webViews["Panel Bookmark Target"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Total windows should be main + background window.
        XCTAssertEqual(app.windows.count, 2)

        // Cmd+Option+Shift click from panel should open selected window.
        panelBookmarkItem = panelBookmarkTargetItem(in: mainWindow)
        let commandOptionShiftPanelBookmarkClick = panelBookmarkItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        XCUIElement.perform(withKeyModifiers: [.command, .option, .shift]) {
            commandOptionShiftPanelBookmarkClick.click()
        }
        let activeWindow = app.windows.firstMatch
        // Target page should load in the active new window.
        XCTAssertTrue(activeWindow.webViews["Panel Bookmark Target"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Total windows should be main + background + foreground window.
        XCTAssertEqual(app.windows.count, 3)
    }

    func testBookmarksBarNavigation() throws {
        app.setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add to bookmarks bar
        openTestPage("Page #16")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()
        app.dismissBookmarksBarPopover(shouldDisplayBar: true, requirePopover: false)
        if !app.bookmarksBar.exists {
            app.mainMenuToggleBookmarksBarMenuItem.click()
        }

        app.activateAddressBar()
        openTestPage("Page #17")

        // Open bookmark with different modifiers
        // Access bookmark item from bookmarks bar (using pattern from BookmarksAndFavoritesTests)
        let bookmarkItem = app.bookmarksBar.groups.firstMatch
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Command click should open in background
        XCUIElement.perform(withKeyModifiers: [.command]) {
            bookmarkItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }
        XCTAssertTrue(app.tabs["Page #16"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(app.tabs["Page #17"].exists)
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Page #17"].exists)
        XCTAssertFalse(app.webViews["Page #16"].exists) // Should open in background
        XCTAssertEqual(app.tabs.count, 2)
        try app.tabs.element(boundBy: 1).closeTab()

        // Command shift click should open in foreground
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            bookmarkItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }
        XCTAssertTrue(app.webViews["Page #16"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Page #17"].exists)
        XCTAssertTrue(app.tabs["Page #16"].exists)
        XCTAssertTrue(app.tabs["Page #17"].exists)
        XCTAssertEqual(app.tabs.count, 2)
        app.closeCurrentTab()

        // Command+Option click should open in background window
        XCUIElement.perform(withKeyModifiers: [.command, .option]) {
            bookmarkItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }

        let mainWindow = app.windows.firstMatch
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(backgroundWindow.webViews["Page #16"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(backgroundWindow.tabs.count, 1)
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertTrue(mainWindow.webViews["Page #17"].exists)     // Original page still visible in main window
        XCTAssertTrue(mainWindow.tabs["Page #17"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 1)

        XCTAssertTrue(backgroundWindow.tabs["Page #16"].exists)
        XCTAssertEqual(backgroundWindow.tabs.count, 1)

        // Command+Option+Shift click should open in foreground window
        XCUIElement.perform(withKeyModifiers: [.command, .option, .shift]) {
            bookmarkItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }

        XCTAssertTrue(mainWindow.webViews["Page #16"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 3)

        XCTAssertTrue(mainWindow.tabs["Page #16"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 1)
    }

}
