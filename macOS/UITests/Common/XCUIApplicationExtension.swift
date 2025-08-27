//
//  XCUIApplicationExtension.swift
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

import XCTest

// Enum to represent bookmark modes
enum BookmarkMode {
    case panel
    case manager
}

extension XCUIApplication {

    private enum AccessibilityIdentifiers {
        static let addressBarTextField = "AddressBarViewController.addressBarTextField"
        static let bookmarksPanelShortcutButton = "NavigationBarViewController.bookmarkListButton"
        static let manageBookmarksMenuItem = "MainMenu.manageBookmarksMenuItem"
        static let resetBookmarksMenuItem = "MainMenu.resetBookmarks"
    }

    static func setUp(environment: [String: String]? = nil, featureFlags: [String: Bool] = ["visualUpdates": true]) -> XCUIApplication {
        let app = XCUIApplication()
        if let environment {
            app.launchEnvironment = app.launchEnvironment.merging(environment, uniquingKeysWith: { $1 })
        } else {
            app.launchEnvironment["UITEST_MODE"] = "1"
        }
        if !featureFlags.isEmpty {
            app.launchEnvironment["FEATURE_FLAGS"] = featureFlags.map { "\($0)=\($1)" }.joined(separator: " ")
        }
        app.launch()
        return app
    }

    @nonobjc var path: String? {
        self.value(forKey: "path") as? String
    }

    /// Dismiss popover with the passed button identifier if exists. If it does not exist it continues the execution without failing.
    /// - Parameter buttonIdentifier: The button identifier we want to tap from the popover
    func dismissPopover(buttonIdentifier: String) {
        let popover = popovers.firstMatch
        guard popover.exists else {
            return
        }

        let button = popover.buttons[buttonIdentifier]
        guard button.exists else {
            return
        }

        button.tap()
    }

    /// Enforces single a single window by:
    ///  1. First, closing all windows
    ///  2. Opening a new window
    func enforceSingleWindow() {
        let window = windows.firstMatch
        while window.exists {
            window.click()
            typeKey("w", modifierFlags: [.command, .option, .shift])
            _=window.waitForNonExistence(timeout: UITests.Timeouts.elementExistence)
        }
        typeKey("n", modifierFlags: .command)
    }

    /// Opens a new tab via keyboard shortcut
    func openNewTab() {
        typeKey("t", modifierFlags: .command)
    }

    /// Opens a Fire window via keyboard shortcut (Cmd+Shift+N)
    func openFireWindow() {
        typeKey("n", modifierFlags: [.command, .shift])
    }

    /// Closes current tab via keyboard shortcut
    func closeCurrentTab() {
        typeKey("w", modifierFlags: .command)
    }

    /// Closes the current window via keyboard shortcut (Cmd+Shift+W)
    func closeWindow() {
        typeKey("w", modifierFlags: [.command, .shift])
    }

    /// Activate address bar for input
    /// On new tab pages, the address bar is already activated by default
    func activateAddressBar() {
        typeKey("l", modifierFlags: [.command])
    }

    /// Address bar text field element
    var addressBar: XCUIElement {
        windows.firstMatch.textFields[AccessibilityIdentifiers.addressBarTextField]
    }

    /// Activates the address bar if needed and returns its current value
    /// - Returns: The current value of the address bar as a string
    func addressBarValueActivatingIfNeeded() -> String? {
        activateAddressBar()
        return addressBar.value as? String
    }

    // MARK: - Bookmarks

    /// Reset the bookmarks so we can rely on a single bookmark's existence
    func resetBookmarks() {
        let resetMenuItem = menuItems[AccessibilityIdentifiers.resetBookmarksMenuItem]
        XCTAssertTrue(
            resetMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Reset bookmarks menu item didn't become available in a reasonable timeframe."
        )
        resetMenuItem.click()
    }

    /// Opens the bookmarks manager via the menu
    func openBookmarksManager() {
        let manageBookmarksMenuItem = menuItems[AccessibilityIdentifiers.manageBookmarksMenuItem]
        XCTAssertTrue(
            manageBookmarksMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Manage bookmarks menu item didn't become available in a reasonable timeframe."
        )
        manageBookmarksMenuItem.click()
    }

    /// Open the initial site to be bookmarked, bookmarking it and/or escaping out of the dialog only if needed
    /// - Parameter url: The URL we will use to load the bookmark
    /// - Parameter pageTitle: The page title that would become the bookmark name
    /// - Parameter bookmarkingViaDialog: open bookmark dialog, adding bookmark
    /// - Parameter escapingDialog: `esc` key to leave dialog
    /// - Parameter folderName: The name of the folder where you want to save the bookmark. If the folder does not exist, it fails.
    func openSiteToBookmark(url: URL,
                            pageTitle: String,
                            bookmarkingViaDialog: Bool,
                            escapingDialog: Bool,
                            folderName: String? = nil) {
        let addressBarTextField = windows.textFields[AccessibilityIdentifiers.addressBarTextField]
        XCTAssertTrue(
            addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The address bar text field didn't become available in a reasonable timeframe."
        )
        addressBarTextField.typeURL(url)
        XCTAssertTrue(
            windows.webViews[pageTitle].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Visited site didn't load with the expected title in a reasonable timeframe."
        )
        if bookmarkingViaDialog {
            typeKey("d", modifierFlags: [.command]) // Add bookmark

            if let folderName = folderName {
                let folderLocationButton = popUpButtons["bookmark.add.folder.dropdown"]
                folderLocationButton.tap()
                let folderOneLocation = folderLocationButton.menuItems[folderName]
                folderOneLocation.tap()
            }

            if escapingDialog {
                typeKey(.escape, modifierFlags: []) // Exit dialog
            }
        }
    }

    /// Shows the bookmarks panel shortcut and taps it. If the bookmarks shortcut is visible, it only taps it.
    func openBookmarksPanel() {
        let bookmarksPanelShortcutButton = buttons[AccessibilityIdentifiers.bookmarksPanelShortcutButton]
        if !bookmarksPanelShortcutButton.exists {
            typeKey("k", modifierFlags: [.command, .shift])
        }

        bookmarksPanelShortcutButton.tap()
    }

    func verifyBookmarkOrder(expectedOrder: [String], mode: BookmarkMode) {
        let rowCount = (mode == .panel ? popovers.firstMatch.outlines.firstMatch : tables.firstMatch).cells.count
        XCTAssertEqual(rowCount, expectedOrder.count, "Row count does not match expected count.")

        for index in 0..<rowCount {
            let cell = (mode == .panel ? popovers.firstMatch.outlines.firstMatch : tables.firstMatch).cells.element(boundBy: index)
            XCTAssertTrue(cell.exists, "Cell at index \(index) does not exist.")

            let cellLabel = cell.staticTexts[expectedOrder[index]]
            XCTAssertTrue(cellLabel.exists, "Cell at index \(index) has unexpected label.")
        }
    }

    // MARK: - Context Menu

    /// Find the coordinates of a context menu item that matches the given predicate
    /// - Parameter matching: A closure that takes an XCUIElementSnapshot and returns Bool to match the desired menu item
    /// - Returns: The CGRect frame of the matching menu item
    /// - Throws: XCTestError if no matching item is found or context menu doesn't exist
    func coordinatesForContextMenuItem(matching: (XCUIElementSnapshot) -> Bool) throws -> CGRect {
        let contextMenu = windows.firstMatch.children(matching: .menu).firstMatch
        XCTAssertTrue(
            contextMenu.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Context menu did not appear in a reasonable timeframe."
        )

        let menuSnapshot = try contextMenu.snapshot()
        for child in menuSnapshot.children where matching(child) {
            return child.frame
        }

        throw XCTestError(.failureWhileWaiting, userInfo: [
            "reason": "No context menu item found matching the specified condition"
        ])
    }

    /// Click a context menu item that matches the given predicate using XCUITest coordinate-based clicking
    /// 
    /// This method uses coordinate-based clicking rather than direct XCUIElement interaction because
    /// context menu item detection tends to fail on macOS 13/14 CI workers. The snapshot-based approach
    /// with coordinate clicking provides more reliable interaction with context menu items across
    /// different macOS versions in CI environments.
    /// 
    /// - Parameter matching: A closure that takes an XCUIElementSnapshot and returns Bool to match the desired menu item
    /// - Throws: XCTestError if no matching item is found or click fails
    func clickContextMenuItem(matching: (XCUIElementSnapshot) -> Bool) throws {
        let contextMenu = windows.firstMatch.children(matching: .menu).firstMatch
        XCTAssertTrue(
            contextMenu.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Context menu did not appear in a reasonable timeframe."
        )

        let itemFrame = try coordinatesForContextMenuItem(matching: matching)

        // Calculate normalized offset within the context menu bounds
        let menuFrame = contextMenu.frame
        let normalizedX = (itemFrame.midX - menuFrame.minX) / menuFrame.width
        let normalizedY = (itemFrame.midY - menuFrame.minY) / menuFrame.height

        // Use XCUITest's coordinate-based clicking
        let coordinate = contextMenu.coordinate(withNormalizedOffset: CGVector(dx: normalizedX, dy: normalizedY))
        coordinate.click()
    }

    // MARK: - Preferences

    /// Opens the Preferences window via Cmd+, and waits for it to appear
    func openPreferencesWindow() {
        typeKey(",", modifierFlags: [.command])
        let prefs = preferencesWindow
        _ = prefs.waitForExistence(timeout: UITests.Timeouts.elementExistence)
    }

    /// Closes the Preferences window if present
    func closePreferencesWindow() {
        let prefs = preferencesWindow
        if prefs.exists {
            let close = prefs.buttons["_XCUI:CloseWindow"].firstMatch
            if close.exists { close.click() }
        }
    }

    /// Returns the Preferences/Settings window element
    var preferencesWindow: XCUIElement {
        windows.containing(\.title, equalTo: "Settings").firstMatch
    }

    /// Selects the General pane in Preferences
    func preferencesGoToGeneralPane() {
        let prefs = preferencesWindow
        let general = prefs.buttons["PreferencesSidebar.generalButton"]
        if general.waitForExistence(timeout: UITests.Timeouts.elementExistence) { general.click() }
    }

    /// Sets startup behavior to reopen all windows from last session (or not)
    func preferencesSetRestorePreviousSession(enabled: Bool) {
        let prefs = preferencesWindow
        preferencesGoToGeneralPane()
        preferencesSetRestorePreviousSession(enabled: enabled, in: prefs)
    }

    func preferencesSetRestorePreviousSession(enabled: Bool, in prefs: XCUIElement) {
        let reopen = prefs.radioButtons["PreferencesGeneralView.stateRestorePicker.reopenAllWindowsFromLastSession"].firstMatch
        let openNew = prefs.radioButtons["PreferencesGeneralView.stateRestorePicker.openANewWindow"].firstMatch
        if enabled {
            XCTAssertTrue(reopen.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Reopen last session radio button should exist")
            if reopen.isSelected == false { reopen.click() }
        } else {
            XCTAssertTrue(openNew.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Open new window radio button should exist")
            if openNew.isSelected == false { openNew.click() }
        }
    }

    /// Sets the "Always ask where to save files" toggle to a specific state
    func setAlwaysAskWhereToSaveFiles(enabled: Bool) {
        let prefs = preferencesWindow

        let toggleIdentifier = "PreferencesGeneralView.alwaysAskWhereToSaveFiles"
        let scrollView = prefs.scrollViews.containing(.checkBox, identifier: toggleIdentifier).firstMatch
        scrollView.swipeUp()
        let checkbox = prefs.checkBoxes.element(matching: .checkBox, identifier: toggleIdentifier)
        XCTAssertTrue(checkbox.exists, "Always ask toggle should exist in Preferences")

        checkbox.toggleCheckboxIfNeeded(to: enabled)
    }

    /// Sets the Tabs behavior: whether to switch to a new tab when opened (true) or keep in background (false)
    func setSwitchToNewTabWhenOpened(enabled: Bool) {
        let prefs = preferencesWindow
        let label = "When opening links, switch to the new tab or window immediately"
        let checkbox = prefs.checkBoxes.element(matching: \.label, equalTo: label)
        XCTAssertTrue(checkbox.exists, "Switch-to-new-tab toggle should exist in Preferences")

        checkbox.toggleCheckboxIfNeeded(to: enabled)
    }

    /// Sets the "Automatically open the Downloads panel when downloads complete" preference
    func setOpenDownloadsPopupOnCompletion(enabled: Bool) {
        let prefs = preferencesWindow
        let label = "Automatically open the Downloads panel when downloads complete"
        let checkbox = prefs.checkBoxes.element(matching: \.label, equalTo: label)
        XCTAssertTrue(checkbox.exists, "Downloads panel toggle should exist in Preferences")

        checkbox.toggleCheckboxIfNeeded(to: enabled)
    }

    // MARK: - Downloads Location

    /// Change the downloads directory using the Preferences UI and the system "Go to Folder" panel
    func setDownloadsLocation(to directoryURL: URL) {
        let prefs = preferencesWindow
        let changeButton = prefs.buttons["Change…"].firstMatch
        XCTAssertTrue(changeButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Change… button should exist in Preferences")
        changeButton.click()

        // Open "Go to the folder" panel
        typeKey("g", modifierFlags: [.command, .shift])
        typeKey("a", modifierFlags: [.command, .shift])

        // Type path and confirm
        typeText(directoryURL.path)
        sleep(1)
        XCTAssertTrue(sheets.firstMatch.sheets.firstMatch.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        typeKey(.return, modifierFlags: [])
        if !sheets.firstMatch.sheets.firstMatch.waitForExistence(timeout: UITests.Timeouts.elementExistence) {
            typeKey(.return, modifierFlags: [])
        }

        // Confirm selection
        typeKey(.return, modifierFlags: [])
    }
}
