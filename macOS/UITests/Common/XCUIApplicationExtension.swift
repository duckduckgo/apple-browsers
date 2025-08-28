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
        static let okButton = "OKButton"
        static let addressBarTextField = "AddressBarViewController.addressBarTextField"
        static let bookmarksPanelShortcutButton = "NavigationBarViewController.bookmarkListButton"
        static let manageBookmarksMenuItem = "MainMenu.manageBookmarksMenuItem"
        static let resetBookmarksMenuItem = "MainMenu.resetBookmarks"
        static let backButton = "NavigationBarViewController.BackButton"
        static let forwardButton = "NavigationBarViewController.ForwardButton"
        static let downloadsButton = "NavigationBarViewController.downloadsButton"
        static let bookmarksBar = "BookmarksBarViewController.bookmarksBarCollectionView"
        static let mainMenuAddBookmarkMenuItem = "MainMenu.addBookmark"
        static let mainMenuToggleBookmarksBarMenuItem = "MainMenu.toggleBookmarksBar"
        static let historyMenu = "History"
        static let bookmarksMenu = "Bookmarks"
        static let mainMenuPinTabMenuItem = "Pin Tab"
        static let mainMenuUnpinTabMenuItem = "Unpin Tab"
        static let preferencesMenuItem = "MainMenu.preferencesMenuItem"

        static let preferencesGeneralButton = "PreferencesSidebar.generalButton"
        static let switchToNewTabWhenOpenedCheckbox = "PreferencesGeneralView.switchToNewTabWhenOpened"
        static let alwaysAskWhereToSaveFilesCheckbox = "PreferencesGeneralView.alwaysAskWhereToSaveFiles"
        static let openPopupOnDownloadCompletionCheckbox = "PreferencesGeneralView.openPopupOnDownloadCompletion"
        static let addBookmarkAddToFavoritesCheckbox = "bookmark.add.add.to.favorites.button"
        static let bookmarkDialogAddButton = "BookmarkDialogButtonsView.defaultButton"

        static let addBookmarkFolderDropdown = "bookmark.add.folder.dropdown"

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

    /// Closes current tab via keyboard shortcut
    func closeCurrentTab() {
        typeKey("w", modifierFlags: .command)
    }

    /// Activate address bar for input
    /// On new tab pages, the address bar is already activated by default
    func activateAddressBar() {
        typeKey("l", modifierFlags: [.command])
    }

    /// Address bar text field element
    var addressBar: XCUIElement {
        windows.firstMatch.textFields[XCUIApplication.AccessibilityIdentifiers.addressBarTextField]
    }

    /// Activates the address bar if needed and returns its current value
    /// - Returns: The current value of the address bar as a string
    func addressBarValueActivatingIfNeeded() -> String? {
        activateAddressBar()
        return addressBar.value as? String
    }

    /// Opens a new window
    func openNewWindow() {
        typeKey("n", modifierFlags: .command)
    }

    /// Opens a Fire window via keyboard shortcut (Cmd+Shift+N)
    func openFireWindow() {
        typeKey("n", modifierFlags: [.command, .shift])
    }

    /// Closes the current window via keyboard shortcut (Cmd+Shift+W)
    func closeWindow() {
        typeKey("w", modifierFlags: [.command, .shift])
    }

    /// Closes all windows
    func closeAllWindows() {
        typeKey("w", modifierFlags: [.command, .option, .shift])
    }

    /// Opens downloads
    func openDownloads() {
        typeKey("j", modifierFlags: .command)
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
            let close = prefs.buttons[XCUIIdentifierCloseWindow].firstMatch
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
        let general = prefs.buttons[AccessibilityIdentifiers.preferencesGeneralButton]
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
            ensureHittable(reopen)
            XCTAssertTrue(reopen.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Reopen last session radio button should exist")
            if reopen.isSelected == false { reopen.click() }
        } else {
            ensureHittable(openNew)
            XCTAssertTrue(openNew.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Open new window radio button should exist")
            if openNew.isSelected == false { openNew.click() }
        }
    }

    /// Sets the "Always ask where to save files" toggle to a specific state
    func setAlwaysAskWhereToSaveFiles(enabled: Bool) {
        let checkbox = preferencesWindow.checkBoxes[AccessibilityIdentifiers.alwaysAskWhereToSaveFilesCheckbox]
        checkbox.toggleCheckboxIfNeeded(to: enabled, ensureHittable: self.ensureHittable)
    }

    /// Sets the Tabs behavior: whether to switch to a new tab when opened (true) or keep in background (false)
    func setSwitchToNewTabWhenOpened(enabled: Bool) {
        let checkbox = preferencesWindow.checkBoxes[AccessibilityIdentifiers.switchToNewTabWhenOpenedCheckbox]
        checkbox.toggleCheckboxIfNeeded(to: enabled, ensureHittable: self.ensureHittable)
    }

    /// Sets the "Automatically open the Downloads panel when downloads complete" preference
    func setOpenDownloadsPopupOnCompletion(enabled: Bool) {
        let checkbox = preferencesWindow.checkBoxes[AccessibilityIdentifiers.openPopupOnDownloadCompletionCheckbox]
        checkbox.toggleCheckboxIfNeeded(to: enabled, ensureHittable: self.ensureHittable)
    }

    func ensureHittable(_ element: XCUIElement) {
        let scrollView = preferencesWindow.scrollViews.containing(.checkBox, where: NSPredicate(value: true)).firstMatch

        if !element.isHittable {
            // Get the element's frame and scroll view's frame
            let elementFrame = element.frame
            let scrollViewFrame = scrollView.frame

            // Calculate how much we need to scroll to make the element visible
            // Add some padding to ensure the element is fully visible
            let padding: CGFloat = 20
            let delta = elementFrame.maxY - scrollViewFrame.maxY + padding
            // Create a normalized vector for the scroll amount
            scrollView.scroll(byDeltaX: 0, deltaY: -delta)
        }
        XCTAssertTrue(element.exists, "\(element) should exist in Preferences")
        XCTAssertTrue(element.isHittable, "\(element) should be hittable after scrolling up")
    }

    func setSaveDialogLocation(to location: URL, in sheet: XCUIElement? = nil) {
        let saveSheet: XCUIElement
        if let sheet {
            saveSheet = sheet
            XCTAssertTrue(saveSheet.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        } else {
            saveSheet = getOpenSaveSheet()
        }

        // Open Go To Folder (Cmd+Shift+G)
        typeKey("g", modifierFlags: [.command, .shift])
        // Wait for the Location Chooser to appear
        let chooseFolderSheet = saveSheet.sheets.firstMatch
        XCTAssertTrue(chooseFolderSheet.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Select All
        typeKey("a", modifierFlags: [.command])

        // Enter path
        typeText(location.path)

        // Wait for the path to appear in the Location Chooser
        Logger.log("Waiting for cell with \"\(location.path)\"")
        let standardizedPath = location.standardizedFileURL.path
        let pathCell = chooseFolderSheet.tables.cells.containing(NSPredicate { element, _ in
            guard let id = (element as? NSObject)?.value(forKey: #keyPath(XCUIElement.identifier)) as? String,
                  id.hasPrefix("/"),
                  URL(fileURLWithPath: id).standardizedFileURL.path == standardizedPath else { return false }

            return true
        }).firstMatch
        XCTAssertTrue(pathCell.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Confirm Location selection
        typeKey(.return, modifierFlags: [])
        XCTAssertTrue(chooseFolderSheet.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Location Chooser should disappear")
    }

    private func getOpenSaveSheet() -> XCUIElement {
        var saveSheet: XCUIElement!
        wait(for: NSPredicate { _, _ in
            let sheet = self.sheets.containing(.button, identifier: AccessibilityIdentifiers.okButton).firstMatch
            let dialog = self.dialogs.containing(.button, identifier: AccessibilityIdentifiers.okButton).firstMatch
            if dialog.exists {
                saveSheet = dialog
                return true
            } else if sheet.exists {
                saveSheet = sheet
                return true
            }
            return false
        }, timeout: UITests.Timeouts.elementExistence)

        guard let saveSheet else {
            XCTFail("Save dialog not found")
            fatalError("Save dialog not found")
        }
        return saveSheet
    }

    func enterSaveDialogFileNameAndConfirm(_ fileName: String, in sheet: XCUIElement? = nil) {
        let saveSheet: XCUIElement
        if let sheet {
            saveSheet = sheet
            XCTAssertTrue(saveSheet.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        } else {
            saveSheet = getOpenSaveSheet()
        }

        // Select All
        typeKey("a", modifierFlags: [.command])
        // Enter filename
        typeText(fileName)

        // Click Save
        let saveButton = saveSheet.buttons[AccessibilityIdentifiers.okButton].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(saveButton.isHittable)
        saveButton.click()

        let replaceDialog = sheets.containing(.button, identifier: "Replace").firstMatch
        if replaceDialog.waitForExistence(timeout: 0.5) {
            replaceDialog.buttons["Replace"].click()
        }
    }

    // MARK: - Downloads Location

    /// Change the downloads directory using the Preferences UI and the system "Go to Folder" panel
    func setDownloadsLocation(to directoryURL: URL) {
        let prefs = preferencesWindow
        let changeButton = prefs.buttons["Change…"].firstMatch
        ensureHittable(changeButton)
        changeButton.click()

        self.setSaveDialogLocation(to: directoryURL)

        // Confirm selection
        typeKey(.return, modifierFlags: [])
    }

    var mainMenuPinTabMenuItem: XCUIElement {
        menuItems[AccessibilityIdentifiers.mainMenuPinTabMenuItem]
    }

    var mainMenuUnpinTabMenuItem: XCUIElement {
        menuItems[AccessibilityIdentifiers.mainMenuUnpinTabMenuItem]
    }

    var mainMenuAddBookmarkMenuItem: XCUIElement {
        menuItems[AccessibilityIdentifiers.mainMenuAddBookmarkMenuItem]
    }

    var mainMenuToggleBookmarksBarMenuItem: XCUIElement {
        menuItems[AccessibilityIdentifiers.mainMenuToggleBookmarksBarMenuItem]
    }

    var preferencesMenuItem: XCUIElement {
        menuItems[AccessibilityIdentifiers.preferencesMenuItem]
    }

    var bookmarksBar: XCUIElement {
        collectionViews[AccessibilityIdentifiers.bookmarksBar]
    }

    var backButton: XCUIElement {
        buttons[AccessibilityIdentifiers.backButton]
    }

    var forwardButton: XCUIElement {
        buttons[AccessibilityIdentifiers.forwardButton]
    }

    var downloadsButton: XCUIElement {
        buttons[AccessibilityIdentifiers.downloadsButton]
    }

    var historyMenu: XCUIElement {
        menuBarItems[AccessibilityIdentifiers.historyMenu]
    }

    var bookmarksMenu: XCUIElement {
        menuBarItems[AccessibilityIdentifiers.bookmarksMenu]
    }

    var preferencesGeneralButton: XCUIElement {
        buttons[AccessibilityIdentifiers.preferencesGeneralButton]
    }

    var bookmarksDialogAddToFavoritesCheckbox: XCUIElement {
        checkBoxes[XCUIApplication.AccessibilityIdentifiers.addBookmarkAddToFavoritesCheckbox]
    }

    var addBookmarkAlertAddButton: XCUIElement {
        buttons[XCUIApplication.AccessibilityIdentifiers.bookmarkDialogAddButton]
    }

    var bookmarkDialogBookmarkFolderDropdown: XCUIElement {
        popUpButtons[XCUIApplication.AccessibilityIdentifiers.addBookmarkFolderDropdown]
    }

}
