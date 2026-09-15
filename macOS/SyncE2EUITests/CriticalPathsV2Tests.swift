//
//  CriticalPathsV2Tests.swift
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

final class CriticalPathsV2Tests: XCTestCase {

    private enum Timeouts {
        static let syncOperation: Double = 30.0
    }

    private enum Identifiers {
        static let syncThisDeviceToggle = "SyncSettings.syncThisDeviceToggle"
        static let currentDeviceRow = "SyncSettings.deviceRow.current"
        static let mobileDeviceRow = "SyncSettings.deviceRow.mobile"
        static let successCopyCodeButton = "SyncSuccessCopyCodeButton"
        static let successDoneButton = "SyncSuccessDoneButton"
    }

    private enum Titles {
        static let syncAndBackupPane = "Sync & Backup"
        static let beginSync = "Keep DuckDuckGo in sync!"
        static let myDevices = "My Devices"
        static let syncWithAnotherDevice = "Sync With Another Device"
        static let syncThisDeviceOnly = "Sync This Device Only"
        static let recoveryCode = "I Have a Recovery Code"
        static let getStarted = "Get Started"
        static let enterCodeTab = "Enter Code"
        static let pasteCode = "Paste Code"
        static let paste = "Paste"
        static let deviceDetails = "Details..."
        static let turnOffSync = "Turn Off Sync & Backup"
        static let removeDevice = "Remove Device"
        static let turnOffAndDeleteServerData = "Turn Off and Delete Server Data"
        static let deleteServerData = "Delete Server Data"
        static let shareFavorites = "Share Favorites Across Devices"
        static let syncFailed = "Sync failed."
        static let gotIt = "Got It"
    }

    var app: XCUIApplication!
    var debugMenuBarItem: XCUIElement!

    override func setUp() {
        app = XCUIApplication(bundleIdentifier: "com.duckduckgo.macos.browser.review")
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchEnvironment["FEATURE_FLAGS"] = "simplifiedSyncSetupV2=true"
        app.launch()
        ensureMainWindowOpen()
        selectDevelopmentEnvironment()
        cleanupAndResetData()
    }

    override func tearDown() {
        cleanupAndResetData()
        app.typeKey(",", modifierFlags: [.command, .option, .shift])
    }

    // MARK: - Tests

    func testCanCreateSyncAccount() throws {
        openSyncSettings()

        createAccountForThisDeviceOnly()
        assertSyncIsEnabled()

        deleteServerData()
        assertSyncIsDisabled()
    }

    func testCanRecoverSyncAccount() throws {
        openSyncSettings()

        createAccountForThisDeviceOnly(copyingRecoveryCode: true)
        assertSyncIsEnabled()

        turnOffSync()
        assertSyncIsDisabled()

        recoverSyncedData()
        assertSyncIsEnabled()

        deleteServerData()
        assertSyncIsDisabled()
    }

    func testCanRemoveData() {
        openSyncSettings()

        createAccountForThisDeviceOnly(copyingRecoveryCode: true)
        assertSyncIsEnabled()

        deleteServerData()
        assertSyncIsDisabled()

        pasteCodeOnConnectScreen()

        let settingsWindow = syncSettingsWindow()
        let alertSheet = settingsWindow.sheets.sheets["alert"]
        alertSheet.staticTexts[Titles.syncFailed].assertExists(with: Timeouts.syncOperation)
        alertSheet.buttons[Titles.gotIt].assertExists().click()
    }

    func testCanLoginToExistingSyncAccount() {
        guard let code = ProcessInfo.processInfo.environment["CODE"] else {
            XCTFail("CODE not set")
            return
        }

        openSyncSettings()
        copyToClipboard(code: code)

        logIn()

        logOut()
    }

    func testCanSyncData() {
        guard let code = ProcessInfo.processInfo.environment["CODE"] else {
            XCTFail("CODE not set")
            return
        }

        addBookmarksAndFavorites()
        addLogin()
        addCreditCard()
        addIdentity()

        copyToClipboard(code: code)

        let bookmarksWindow = bookmarkManagerWindow()
        bookmarksWindow.splitGroups.children(matching: .popUpButton).element.click()
        bookmarksWindow.menuItems["Settings"].click()
        logIn()

        let settingsWindow = syncSettingsWindow()
        XCTAssertFalse(settingsWindow.checkBoxes[Titles.shareFavorites].value as! Bool)

        logOut()

        checkFavoriteNonUnified()

        ensureSyncSettingsWindowOpen()
        settingsWindow.popUpButtons["Settings"].click()
        settingsWindow.menuItems["Bookmarks"].click()
        bookmarksWindow.staticTexts["www.spreadprivacy.com"].rightClick()
        bookmarksWindow.menus.menuItems["ContextualMenu.deleteBookmark"].click()
        bookmarksWindow.staticTexts["www.duckduckgo.com"].rightClick()
        bookmarksWindow.menus.menuItems["ContextualMenu.deleteBookmark"].click()

        bookmarksWindow.splitGroups.children(matching: .popUpButton).element.click()
        bookmarksWindow.menuItems["Settings"].click()
        logIn()

        settingsWindow.checkBoxes[Titles.shareFavorites].click()
        XCTAssertTrue(settingsWindow.checkBoxes[Titles.shareFavorites].value as! Bool)

        checkBookmarks()
        checkUnifiedFavorites()
        checkLogins()
        checkCreditCards()
        checkIdentities()

        app.typeKey(",", modifierFlags: [.command])
        XCTAssertTrue(settingsWindow.checkBoxes[Titles.shareFavorites].value as! Bool)
        settingsWindow.checkBoxes[Titles.shareFavorites].click()
    }

    // MARK: - App and window helpers

    private func ensureMainWindowOpen() {
        if app.windows.firstMatch.exists {
            return
        }

        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: XCUIElement.Timeouts.elementExistence), "Main browser window is not visible")
    }

    private func syncSettingsWindow() -> XCUIElement {
        let settingsWindow = app.windows.containing(.button, identifier: Titles.syncAndBackupPane).firstMatch
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: XCUIElement.Timeouts.elementExistence), "Settings window is not visible")
        return settingsWindow
    }

    private func bookmarkManagerWindow() -> XCUIElement {
        let bookmarksWindow = app.windows.containing(.button, identifier: "BookmarkManagementDetailViewController.newBookmarkButton").firstMatch
        XCTAssertTrue(bookmarksWindow.waitForExistence(timeout: XCUIElement.Timeouts.elementExistence), "Bookmarks window is not visible")
        return bookmarksWindow
    }

    private func ensureSyncSettingsWindowOpen() {
        let settingsWindow = app.windows.containing(.button, identifier: Titles.syncAndBackupPane).firstMatch
        guard !settingsWindow.exists else { return }
        app.typeKey(",", modifierFlags: [.command])
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: XCUIElement.Timeouts.elementExistence), "Settings window is not visible")
    }

    private func accessSettings() {
        app.menuItems["MainMenu.preferencesMenuItem"].assertExists().click()
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

    // MARK: - Sync setup helpers

    private func element(_ identifier: String, in container: XCUIElement) -> XCUIElement {
        container.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func openSyncSettings() {
        accessSettings()
        let settingsWindow = syncSettingsWindow()
        settingsWindow.buttons[Titles.syncAndBackupPane].click()
    }

    private func createAccountForThisDeviceOnly(copyingRecoveryCode: Bool = false) {
        let settingsWindow = syncSettingsWindow()
        let sheetsQuery = settingsWindow.sheets

        element(Identifiers.syncThisDeviceToggle, in: settingsWindow).assertExists().click()
        sheetsQuery.buttons[Titles.syncThisDeviceOnly].assertExists().click()

        let doneButton = sheetsQuery.buttons[Identifiers.successDoneButton]
        doneButton.assertExists(with: Timeouts.syncOperation)
        if copyingRecoveryCode {
            sheetsQuery.buttons[Identifiers.successCopyCodeButton].assertExists().click()
        }
        doneButton.click()
    }

    private func recoverSyncedData() {
        let settingsWindow = syncSettingsWindow()
        let sheetsQuery = settingsWindow.sheets

        settingsWindow.buttons[Titles.recoveryCode].assertExists().click()
        sheetsQuery.buttons[Titles.getStarted].assertExists().click()
        sheetsQuery.buttons[Titles.paste].assertExists(with: Timeouts.syncOperation).click()

        sheetsQuery.buttons[Identifiers.successDoneButton].assertExists(with: Timeouts.syncOperation).click()
    }

    private func pasteCodeOnConnectScreen() {
        let settingsWindow = syncSettingsWindow()
        let sheetsQuery = settingsWindow.sheets

        settingsWindow.buttons[Titles.syncWithAnotherDevice].assertExists().click()
        sheetsQuery.buttons[Titles.enterCodeTab].assertExists(with: Timeouts.syncOperation).click()
        sheetsQuery.buttons[Titles.pasteCode].assertExists().click()
    }

    private func logIn() {
        let settingsWindow = syncSettingsWindow()
        settingsWindow.buttons[Titles.syncAndBackupPane].click()

        pasteCodeOnConnectScreen()

        settingsWindow.sheets.buttons[Identifiers.successDoneButton].assertExists(with: Timeouts.syncOperation).click()

        element(Identifiers.mobileDeviceRow, in: settingsWindow).assertExists(with: Timeouts.syncOperation)
    }

    private func logOut() {
        turnOffSync()
        assertSyncIsDisabled()
    }

    private func turnOffSync() {
        let settingsWindow = syncSettingsWindow()
        let sheetsQuery = settingsWindow.sheets

        openCurrentDeviceDetails()
        sheetsQuery.buttons[Titles.turnOffSync].assertExists().click()
        sheetsQuery.buttons[Titles.removeDevice].assertExists().click()
    }

    private func deleteServerData() {
        let settingsWindow = syncSettingsWindow()
        let sheetsQuery = settingsWindow.sheets

        settingsWindow.swipeUp()
        settingsWindow.buttons[Titles.turnOffAndDeleteServerData].assertExists().click()
        sheetsQuery.buttons[Titles.deleteServerData].assertExists().click()
    }

    private func openCurrentDeviceDetails() {
        let settingsWindow = syncSettingsWindow()
        let deviceRow = element(Identifiers.currentDeviceRow, in: settingsWindow)
        deviceRow.assertExists(with: Timeouts.syncOperation)
        deviceRow.hover()

        let detailsButton = settingsWindow.buttons[Titles.deviceDetails]
        if detailsButton.waitForExistence(timeout: 1.0) {
            detailsButton.click()
        } else {
            deviceRow.coordinate(withNormalizedOffset: CGVector(dx: 1.0, dy: 0.5))
                .withOffset(CGVector(dx: -45.0, dy: 0.0))
                .click()
        }

        settingsWindow.sheets.buttons[Titles.turnOffSync].assertExists()
    }

    private func assertSyncIsEnabled() {
        syncSettingsWindow().staticTexts[Titles.myDevices].assertExists(with: Timeouts.syncOperation)
    }

    private func assertSyncIsDisabled() {
        syncSettingsWindow().staticTexts[Titles.beginSync].assertExists(with: Timeouts.syncOperation)
    }

    private func copyToClipboard(code: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(code, forType: .string)
    }

    // MARK: - Data helpers

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
        bookmarksWindow.buttons["NavigationBarViewController.optionsButton"].click()
        bookmarksWindow.menuItems["MoreOptionsMenu.autofill"].click()
        bookmarksWindow.popovers.buttons["add item"].click()
        bookmarksWindow.popovers.menuItems["createNewLogin"].click()
        let usernameTextField = bookmarksWindow.popovers.textFields["Username TextField"]
        usernameTextField.click()
        usernameTextField.typeText("mywebsite")
        let websiteTextField = bookmarksWindow.popovers.textFields["Website TextField"]
        websiteTextField.click()
        websiteTextField.typeText("mywebsite.com")
        bookmarksWindow.popovers.buttons["Save"].click()
    }

    private func addCreditCard() {
        let bookmarksWindow = bookmarkManagerWindow()
        bookmarksWindow.buttons["NavigationBarViewController.optionsButton"].click()
        bookmarksWindow.menuItems["MoreOptionsMenu.autofill"].click()
        let autofillPopover = bookmarksWindow.popovers
        autofillPopover.buttons["add item"].click()
        autofillPopover.menuItems["createNewCreditCard"].click()

        let titleField = bookmarksWindow.popovers.textFields["Title TextField"]
        titleField.click()
        titleField.typeText("Test Credit Card")

        let cardNumberField = bookmarksWindow.popovers.textFields["Card Number TextField"]
        cardNumberField.click()
        cardNumberField.typeText("4111111111111111")

        let cardholderField = bookmarksWindow.popovers.textFields["Cardholder Name TextField"]
        cardholderField.click()
        cardholderField.typeText("Dax Duck")

        let securityCodeField = bookmarksWindow.popovers.textFields["Security Code TextField"]
        securityCodeField.click()
        securityCodeField.typeText("123")

        autofillPopover.buttons["Save"].click()
    }

    private func addIdentity() {
        let bookmarksWindow = bookmarkManagerWindow()
        bookmarksWindow.buttons["NavigationBarViewController.optionsButton"].click()
        bookmarksWindow.menuItems["MoreOptionsMenu.autofill"].click()
        let autofillPopover = bookmarksWindow.popovers
        autofillPopover.buttons["add item"].click()
        autofillPopover.menuItems["createNewIdentity"].click()

        let titleField = bookmarksWindow.popovers.textFields["Title TextField"]
        titleField.click()
        titleField.typeText("Home Address")

        let firstNameField = bookmarksWindow.popovers.textFields["FirstName TextField"]
        firstNameField.click()
        firstNameField.typeText("Dax")

        let lastNameField = bookmarksWindow.popovers.textFields["LastName TextField"]
        lastNameField.click()
        lastNameField.typeText("Ducky")

        autofillPopover.buttons["Save"].click()
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
        let duckduckgoBookmark = bookmarksWindow.staticTexts["www.duckduckgo.com"]
        let stackOverflow = bookmarksWindow.staticTexts["Stack Overflow - Where Developers Learn, Share, & Build Careers"]
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
        app.buttons["NavigationBarViewController.optionsButton"].click()
        let passwordsItem = app.menuItems["LoginsSubMenu.passwords"]
        XCTAssertTrue(passwordsItem.waitForExistence(timeout: 5))
        passwordsItem.click()
        let elementsQuery = currentWindow.popovers.scrollViews.otherElements
        elementsQuery.buttons["Dax Login, daxthetest"].click()
        elementsQuery.buttons["Github, githubusername"].click()
        elementsQuery.buttons["mywebsite.com, mywebsite"].click()
        elementsQuery.buttons["StackOverflow, stacker"].click()
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
    }

    private func checkCreditCards() {
        let currentWindow = app.windows.firstMatch
        app.buttons["NavigationBarViewController.optionsButton"].click()
        let creditCardsItem = app.menuItems["LoginsSubMenu.creditCards"]
        XCTAssertTrue(creditCardsItem.waitForExistence(timeout: 5))
        creditCardsItem.click()
        let elementsQuery = currentWindow.popovers.scrollViews.otherElements
        elementsQuery.buttons["Test Credit Card, •••• 1111"].click()
        elementsQuery.buttons["Credit card, •••• 1308 Expires: 07/2032"].click()
        elementsQuery.buttons["Debit card, •••• 4242 Expires: 10/2030"].click()
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
    }

    private func checkIdentities() {
        let currentWindow = app.windows.firstMatch
        app.buttons["NavigationBarViewController.optionsButton"].click()
        let identitiesMenuItem = app.menuItems["LoginsSubMenu.identities"]
        XCTAssertTrue(identitiesMenuItem.waitForExistence(timeout: 5))
        identitiesMenuItem.click()

        let elementsQuery = currentWindow.popovers.scrollViews.otherElements
        elementsQuery.buttons["Company, Wile Coyote"].click()
        elementsQuery.buttons["Junior, Ben Coyote"].click()
        elementsQuery.buttons["Personal, Wile Coyote"].click()
        elementsQuery.buttons["Home Address, Dax Ducky"].click()
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
    }
}
