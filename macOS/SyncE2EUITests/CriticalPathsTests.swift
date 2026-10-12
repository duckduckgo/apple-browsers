//
//  CriticalPathsTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import JavaScriptCore

extension XCUIElement {
    /// Timeout constants for different test requirements
    enum Timeouts {
        /// Mostly, we use timeouts to wait for element existence. This is about 3x longer than needed, for CI resilience
        static let elementExistence: Double = 5.0
    }

    @discardableResult
    func assertExists(with timeout: TimeInterval = Timeouts.elementExistence, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(waitForExistence(timeout: timeout), "\(self) didn't become available in a reasonable timeframe.", file: file, line: line)
        return self
    }

    func waitAndClick(timeout: TimeInterval = Timeouts.elementExistence, file: StaticString = #filePath, line: UInt = #line) {
        assertExists(with: timeout, file: file, line: line).click()
    }
}

final class CriticalPathsTests: XCTestCase {

    var isCI: Bool {
        !(ProcessInfo.processInfo.environment["CI"]?.isEmpty ?? true)
    }

    var app: XCUIApplication!
    var debugMenuBarItem: XCUIElement!
    var internaluserstateMenuItem: XCUIElement!

    override func setUp() {
        // Launch App
        app = XCUIApplication(bundleIdentifier: "com.duckduckgo.macos.browser.review")
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchEnvironment["FEATURE_FLAGS"] = "simplifiedSyncSetupV2=false"
        app.launch()
        ensureMainWindowOpen()
        selectDevelopmentEnvironment()
        cleanupAndResetData()
    }

    override func tearDown() {
        cleanupAndResetData()
        app.typeKey(",", modifierFlags: [.command, .option, .shift])
    }

    private func ensureMainWindowOpen() {
        if app.windows.firstMatch.exists {
            return
        }

        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: XCUIElement.Timeouts.elementExistence), "Main browser window is not visible")
    }

    private func syncSettingsWindow() -> XCUIElement {
        let settingsWindow = app.windows.containing(.button, identifier: "Sync & Backup").firstMatch
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: XCUIElement.Timeouts.elementExistence), "Settings window is not visible")
        return settingsWindow
    }

    private func bookmarkManagerWindow() -> XCUIElement {
        let bookmarksWindow = app.windows.containing(.button, identifier: "BookmarkManagementDetailViewController.newBookmarkButton").firstMatch
        XCTAssertTrue(bookmarksWindow.waitForExistence(timeout: XCUIElement.Timeouts.elementExistence), "Bookmarks window is not visible")
        return bookmarksWindow
    }

    private func ensureSyncSettingsWindowOpen() {
        let settingsWindow = app.windows.containing(.button, identifier: "Sync & Backup").firstMatch
        guard !settingsWindow.exists else { return }
        app.typeKey(",", modifierFlags: [.command])
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: XCUIElement.Timeouts.elementExistence), "Settings window is not visible")
    }

    private func accessSettings() {
        app.menuItems["MainMenu.preferencesMenuItem"].waitAndClick()
        _ = syncSettingsWindow()
    }

    private func selectDevelopmentEnvironment() {
        let menuBarsQuery = app.menuBars
        debugMenuBarItem = menuBarsQuery.menuBarItems["Debug"]
        debugMenuBarItem.click()

        let currentEnvironmentMenuItem = app.menuItems["SyncDebugMenu.currentEnvironment"]
        currentEnvironmentMenuItem.assertExists()
        if !currentEnvironmentMenuItem.title.contains("Development") {
            let switchEnvironmentMenuItem = app.menuItems["SyncDebugMenu.switchEnvironment"]
            switchEnvironmentMenuItem.assertExists()
            guard switchEnvironmentMenuItem.title == "Switch to Development" else {
                XCTFail("Failed to switch to Development Sync environment")
                return
            }
            switchEnvironmentMenuItem.click()
        }
    }

    private func cleanupAndResetData() {
        app.menuItems["SyncDebugMenu.turnOffSync"].click()
        app.menuItems["MainMenu.resetBookmarks"].click()
        app.menuItems["MainMenu.resetSecureVaultData"].click()
    }

    func testCanCreateSyncAccount() throws {
        // Go to Sync Set up
        accessSettings()
        let settingsWindow = syncSettingsWindow()
        settingsWindow.buttons["Sync & Backup"].waitAndClick()

        // Create Account
        let sheetsQuery = settingsWindow.sheets
        settingsWindow.buttons["Sync and Back Up This Device"].waitAndClick()
        sheetsQuery.buttons["Turn On Sync & Backup"].waitAndClick()
        sheetsQuery.buttons["Next"].waitAndClick()
        sheetsQuery.buttons["Done"].waitAndClick()
        settingsWindow.staticTexts["Sync Enabled"].assertExists()

        // Clean Up
        settingsWindow.swipeUp()
        settingsWindow.buttons["Turn Off and Delete Server Data…"].waitAndClick()
        sheetsQuery.buttons["Delete Data"].waitAndClick()
        settingsWindow.staticTexts["Begin Syncing"].waitAndClick()
    }

    func testCanRecoverSyncAccount() throws {
        // Go to Sync Set up
        accessSettings()
        let settingsWindow = syncSettingsWindow()
        settingsWindow.buttons["Sync & Backup"].waitAndClick()

        // Create Account
        let sheetsQuery = settingsWindow.sheets
        settingsWindow.buttons["Sync and Back Up This Device"].waitAndClick()
        sheetsQuery.buttons["Turn On Sync & Backup"].waitAndClick()
        sheetsQuery.buttons["Copy Code"].waitAndClick()
        sheetsQuery.buttons["Next"].waitAndClick()
        sheetsQuery.buttons["Done"].waitAndClick()
        let syncEnabledElement = settingsWindow.staticTexts["Sync Enabled"]
        syncEnabledElement.assertExists()

        // Log out
        settingsWindow.buttons["Turn Off Sync…"].waitAndClick()
        sheetsQuery.buttons["Turn Off"].waitAndClick()

        // Recover Account
        settingsWindow.buttons["Recover Synced Data"].waitAndClick()
        sheetsQuery.buttons["Get Started"].waitAndClick()
        sheetsQuery.buttons["Paste"].waitAndClick()
        sheetsQuery.buttons["Next"].waitAndClick()
        sheetsQuery.buttons["Done"].waitAndClick()
        syncEnabledElement.assertExists()

        // Clean Up
        settingsWindow.swipeUp()
        settingsWindow.buttons["Turn Off and Delete Server Data…"].waitAndClick()
        sheetsQuery.buttons["Delete Data"].waitAndClick()
        settingsWindow.staticTexts["Begin Syncing"].waitAndClick()
    }

    func testCanRemoveData() {

        // Go to Sync Set up
        accessSettings()

        let settingsWindow = syncSettingsWindow()
        settingsWindow.buttons["Sync & Backup"].waitAndClick()

        // Create Account
        let sheetsQuery = settingsWindow.sheets
        settingsWindow.buttons["Sync and Back Up This Device"].waitAndClick()
        sheetsQuery.buttons["Turn On Sync & Backup"].waitAndClick()
        sheetsQuery.buttons["Copy Code"].waitAndClick()
        sheetsQuery.buttons["Next"].waitAndClick()
        sheetsQuery.buttons["Done"].waitAndClick()
        settingsWindow.staticTexts["Sync Enabled"].assertExists()

        // Delete Data
        settingsWindow.swipeUp()
        settingsWindow.buttons["Turn Off and Delete Server Data…"].waitAndClick()
        sheetsQuery.buttons["Delete Data"].waitAndClick()
        settingsWindow.staticTexts["Begin Syncing"].waitAndClick()

        // Log In and check error
        settingsWindow.buttons["Sync With Another Device"].waitAndClick()
        sheetsQuery.buttons["Enter Code"].waitAndClick()
        sheetsQuery.buttons["Paste"].waitAndClick()
        let alertSheet = sheetsQuery.sheets["alert"]
        alertSheet.staticTexts["Sync failed."].assertExists()
        alertSheet.buttons["Got It"].waitAndClick()

    }

    func testCanLoginToExistingSyncAccount() {
        guard let code = ProcessInfo.processInfo.environment["CODE"] else {
            XCTFail("CODE not set")
            return
        }

        // Go to Sync Set up
        accessSettings()
        let settingsWindow = syncSettingsWindow()
        settingsWindow.buttons["Sync & Backup"].waitAndClick()

        // Copy code to clipboard
        copyToClipboard(code: code)

        // Log In
        logIn()

        // Clean Up
        logOut()
    }

    func testCanSyncData() {
        guard let code = ProcessInfo.processInfo.environment["CODE"] else {
            XCTFail("CODE not set")
            return
        }

        // Add Bookmarks and Favorite
        addBookmarksAndFavorites()

        // Add Login
        addLogin()

        // Add Credit Card
        addCreditCard()

        // Add Identity
        addIdentity()

        // Copy code to clipboard
        copyToClipboard(code: code)

        // Log In
        let bookmarksWindow = bookmarkManagerWindow()
        bookmarksWindow.splitGroups.children(matching: .popUpButton).element.click()
        bookmarksWindow.menuItems["Settings"].click()
        logIn()

        // Ensure Unify Favorites not checked
        let settingsWindow = syncSettingsWindow()
        XCTAssertFalse(settingsWindow.checkBoxes["Unify Favorites Across Devices"].value as! Bool)

        // Log Out
        logOut()

        // Check Favorites not unified
        checkFavoriteNonUnified()

        // Remove Bookmarks
        ensureSyncSettingsWindowOpen()
        settingsWindow.popUpButtons["Settings"].click()
        settingsWindow.menuItems["Bookmarks"].click()
        bookmarksWindow.staticTexts["www.spreadprivacy.com"].rightClick()
        bookmarksWindow.menus.menuItems["ContextualMenu.deleteBookmark"].click()
        bookmarksWindow.staticTexts["www.duckduckgo.com"].rightClick()
        bookmarksWindow.menus.menuItems["ContextualMenu.deleteBookmark"].click()

        // Log In
        bookmarksWindow.splitGroups.children(matching: .popUpButton).element.click()
        bookmarksWindow.menuItems["Settings"].click()
        logIn()

        // Toggle Unified Favorite
        settingsWindow.checkBoxes["Unify Favorites Across Devices"].click()
        XCTAssertTrue(settingsWindow.checkBoxes["Unify Favorites Across Devices"].value as! Bool)

        // Check Bookmarks
        checkBookmarks()

        // Check Unified favorites
        checkUnifiedFavorites()

        // Check Logins
        checkLogins()

        // Check Credit Cards
        checkCreditCards()

        // Check Identities
        checkIdentities()

        // Switch Unified Favorite back off
        app.typeKey(",", modifierFlags: [.command])
        XCTAssertTrue(settingsWindow.checkBoxes["Unify Favorites Across Devices"].value as! Bool)
        settingsWindow.checkBoxes["Unify Favorites Across Devices"].click()
    }

    private func logIn() {
        let settingsWindow = syncSettingsWindow()
        settingsWindow.buttons["Sync & Backup"].waitAndClick()
        settingsWindow.buttons["Sync With Another Device"].waitAndClick()
        let settingsSheetsQuery = settingsWindow.sheets
        settingsSheetsQuery.buttons["Enter Code"].waitAndClick()
        settingsSheetsQuery.buttons["Paste"].waitAndClick()
        settingsSheetsQuery.buttons["Next"].waitAndClick()
        settingsSheetsQuery.buttons["Done"].waitAndClick()
        settingsWindow.images["SyncSettings.syncedDevice.mobile"].assertExists()
    }

    private func logOut() {
        let settingsWindow = syncSettingsWindow()
        let settingsSheetsQuery = settingsWindow.sheets
        settingsWindow.buttons["Turn Off Sync…"].waitAndClick()
        settingsSheetsQuery.buttons["Turn Off"].waitAndClick()
        settingsWindow.staticTexts["Begin Syncing"].waitAndClick()
    }

    private func copyToClipboard(code: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(code, forType: .string)
    }

    private func addBookmarksAndFavorites() {
        app.menuItems["MainMenu.manageBookmarksMenuItem"].click()
        let bookmarksWindow = bookmarkManagerWindow()
        let newBookmarkButton = bookmarksWindow.buttons["BookmarkManagementDetailViewController.newBookmarkButton"].assertExists()

        newBookmarkButton.click()

        let sheetsQuery = bookmarksWindow.sheets
        let titleTextField = sheetsQuery.textFields["bookmark.add.name.textfield"].assertExists()
        let urlTextField = sheetsQuery.textFields["bookmark.add.url.textfield"].assertExists()
        let addButton = sheetsQuery.buttons["BookmarkDialogButtonsView.defaultButton"].assertExists()
        let favoriteCheckBox = sheetsQuery.checkBoxes["bookmark.add.add.to.favorites.button"].assertExists()

        titleTextField.click()
        titleTextField.typeText("www.duckduckgo.com")
        urlTextField.click()
        urlTextField.typeText("www.duckduckgo.com")
        addButton.click()

        newBookmarkButton.click()
        titleTextField.click()
        titleTextField.typeText("www.spreadprivacy.com")
        urlTextField.click()
        urlTextField.typeText("www.spreadprivacy.com")
        favoriteCheckBox.click()
        addButton.click()
    }

    private func addLogin() {
        let bookmarksWindow = bookmarkManagerWindow()
        bookmarksWindow.buttons["NavigationBarViewController.optionsButton"].waitAndClick()
        bookmarksWindow.menuItems["MoreOptionsMenu.autofill"].waitAndClick()
        bookmarksWindow.popovers.buttons["add item"].waitAndClick()
        bookmarksWindow.popovers.menuItems["createNewLogin"].waitAndClick()
        let usernameTextField = bookmarksWindow.popovers.textFields["Username TextField"]
        usernameTextField.waitAndClick()
        usernameTextField.typeText("mywebsite")
        let websiteTextField = bookmarksWindow.popovers.textFields["Website TextField"]
        websiteTextField.waitAndClick()
        websiteTextField.typeText("mywebsite.com")
        bookmarksWindow.popovers.buttons["Save"].waitAndClick()
    }

    private func addCreditCard() {
        let bookmarksWindow = bookmarkManagerWindow()
        bookmarksWindow.buttons["NavigationBarViewController.optionsButton"].waitAndClick()
        bookmarksWindow.menuItems["MoreOptionsMenu.autofill"].waitAndClick()
        let autofillPopover = bookmarksWindow.popovers
        autofillPopover.buttons["add item"].waitAndClick()
        autofillPopover.menuItems["createNewCreditCard"].waitAndClick()

        let titleField = bookmarksWindow.popovers.textFields["Title TextField"]
        titleField.waitAndClick()
        titleField.typeText("Test Credit Card")

        let cardNumberField = bookmarksWindow.popovers.textFields["Card Number TextField"]
        cardNumberField.waitAndClick()
        cardNumberField.typeText("4111111111111111")

        let cardholderField = bookmarksWindow.popovers.textFields["Cardholder Name TextField"]
        cardholderField.waitAndClick()
        cardholderField.typeText("Dax Duck")

        let securityCodeField = bookmarksWindow.popovers.textFields["Security Code TextField"]
        securityCodeField.waitAndClick()
        securityCodeField.typeText("123")

        autofillPopover.buttons["Save"].waitAndClick()
    }

    private func addIdentity() {
        let bookmarksWindow = bookmarkManagerWindow()
        bookmarksWindow.buttons["NavigationBarViewController.optionsButton"].waitAndClick()
        bookmarksWindow.menuItems["MoreOptionsMenu.autofill"].waitAndClick()
        let autofillPopover = bookmarksWindow.popovers
        autofillPopover.buttons["add item"].waitAndClick()
        autofillPopover.menuItems["createNewIdentity"].waitAndClick()

        let titleField = bookmarksWindow.popovers.textFields["Title TextField"]
        titleField.waitAndClick()
        titleField.typeText("Home Address")

        let firstNameField = bookmarksWindow.popovers.textFields["FirstName TextField"]
        firstNameField.waitAndClick()
        firstNameField.typeText("Dax")

        let lastNameField = bookmarksWindow.popovers.textFields["LastName TextField"]
        lastNameField.waitAndClick()
        lastNameField.typeText("Ducky")

        autofillPopover.buttons["Save"].waitAndClick()
    }

    private func checkFavoriteNonUnified() {
        app.typeKey("t", modifierFlags: [.command])
        let newTabPage = app.windows["New Tab"]
        let gitHub = newTabPage.staticTexts["DuckDuckGo · GitHub"]
        let spreadPrivacy = newTabPage.staticTexts["www.spreadprivacy.com"]
        spreadPrivacy.assertExists()
        XCTAssertFalse(gitHub.exists)
        newTabPage.typeKey("w", modifierFlags: [.command])
    }

    private func checkBookmarks() {
        let settingsWindow = syncSettingsWindow()
        settingsWindow.popUpButtons["Settings"].click()
        settingsWindow.menuItems["Bookmarks"].click()
        let bookmarksWindow = bookmarkManagerWindow()
        if bookmarksWindow.sheets.buttons["Not Now"].exists {
            bookmarksWindow.sheets.buttons["Not Now"].click()
        }
        let duckduckgoBookmark =  bookmarksWindow.staticTexts["www.duckduckgo.com"]
        let stackOverflow =  bookmarksWindow.staticTexts["Stack Overflow - Where Developers Learn, Share, & Build Careers"]
        let privacySimplified = bookmarksWindow.staticTexts["DuckDuckGo — Privacy, simplified."]
        let wolfram = bookmarksWindow.staticTexts["Wolfram|Alpha: Computational Intelligence"]
        let news = bookmarksWindow.staticTexts["news"]
        let codes = bookmarksWindow.staticTexts["code"]
        let sports = bookmarksWindow.staticTexts["sports"]
        let gitHub = bookmarksWindow.staticTexts["DuckDuckGo · GitHub"]
        let spreadPrivacy = bookmarksWindow.staticTexts["www.spreadprivacy.com"]
        XCTAssertTrue(duckduckgoBookmark.exists)
        XCTAssertTrue(spreadPrivacy.exists)
        XCTAssertTrue(stackOverflow.exists)
        XCTAssertTrue(privacySimplified.exists)
        XCTAssertTrue(gitHub.exists)
        XCTAssertTrue(wolfram.exists)
        XCTAssertTrue(news.exists)
        XCTAssertTrue(codes.exists)
        XCTAssertTrue(sports.exists)
    }

    private func checkUnifiedFavorites() {
        app.typeKey("t", modifierFlags: [.command])
        let newTabPage = app.windows["New Tab"]
        let gitHub = newTabPage.staticTexts["DuckDuckGo · GitHub"]
        let spreadPrivacy = newTabPage.staticTexts["www.spreadprivacy.com"]
        gitHub.assertExists()
        spreadPrivacy.assertExists()
        newTabPage.typeKey("w", modifierFlags: [.command])
    }

    private func checkLogins() {
        let currentWindow = app.windows.firstMatch
        app.buttons["NavigationBarViewController.optionsButton"].waitAndClick()
        let passwordsItem = app.menuItems["LoginsSubMenu.passwords"]
        XCTAssertTrue(passwordsItem.waitForExistence(timeout: 5))
        passwordsItem.click()
        let elementsQuery = currentWindow.popovers.scrollViews.otherElements
        elementsQuery.buttons["Dax Login, daxthetest"].waitAndClick()
        elementsQuery.buttons["Github, githubusername"].waitAndClick()
        elementsQuery.buttons["mywebsite.com, mywebsite"].waitAndClick()
        elementsQuery.buttons["StackOverflow, stacker"].waitAndClick()
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
    }

    private func checkCreditCards() {
        let currentWindow = app.windows.firstMatch
        app.buttons["NavigationBarViewController.optionsButton"].waitAndClick()
        let creditCardsItem = app.menuItems["LoginsSubMenu.creditCards"]
        XCTAssertTrue(creditCardsItem.waitForExistence(timeout: 5))
        creditCardsItem.click()
        let elementsQuery = currentWindow.popovers.scrollViews.otherElements
        elementsQuery.buttons["Test Credit Card, •••• 1111"].waitAndClick()
        elementsQuery.buttons["Credit card, •••• 1308 Expires: 07/2032"].waitAndClick()
        elementsQuery.buttons["Debit card, •••• 4242 Expires: 10/2030"].waitAndClick()
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
    }

    private func checkIdentities() {
        let currentWindow = app.windows.firstMatch
        app.buttons["NavigationBarViewController.optionsButton"].waitAndClick()
        let identitiesMenuItem = app.menuItems["LoginsSubMenu.identities"]
        XCTAssertTrue(identitiesMenuItem.waitForExistence(timeout: 5))
        identitiesMenuItem.click()

        let elementsQuery = currentWindow.popovers.scrollViews.otherElements
        elementsQuery.buttons["Company, Wile Coyote"].waitAndClick()
        elementsQuery.buttons["Junior, Ben Coyote"].waitAndClick()
        elementsQuery.buttons["Personal, Wile Coyote"].waitAndClick()
        elementsQuery.buttons["Home Address, Dax Ducky"].waitAndClick()
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
    }
}
