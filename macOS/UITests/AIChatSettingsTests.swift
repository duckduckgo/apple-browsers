//
//  AIChatSettingsTests.swift
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

class AIChatSettingsTests: UITestCase {
    private var addressBarTextField: XCUIElement!

    private enum Identifiers {
        static let searchModeToggleControl = "AddressBarButtonsViewController.searchModeToggleControl"
        static let aiFeaturesToggle = "Preferences.AIChat.aiFeaturesToggle"
        static let showSearchAndDuckAIToggleToggle = "Preferences.AIChat.showSearchAndDuckAIToggleToggle"
        static let showDuckAIButtonInTabBarToggle = "Preferences.AIChat.showDuckAIButtonInTabBarToggle"
        static let showSidebarButtonInTabBarToggle = "Preferences.AIChat.showSidebarButtonInTabBarToggle"
        static let duckAITitleButton = "TabBarViewController.duckAIChromeTitleButton"
        static let sidebarButton = "TabBarViewController.duckAIChromeSidebarButton"
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp(featureFlags: ["aiChatOmnibarToggle": true, "aiChatChromeSidebar": true, "aiChatSidebarFloating": true])

        addressBarTextField = app.addressBar
        app.enforceSingleWindow()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        app.terminate()
    }

    // MARK: - Search and Duck.ai Toggle

    func test_whenShowSearchAndDuckAIToggleIsChanged_thenToggleVisibilityUpdatesOnFocus() {
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)
        let showToggleCheckbox = app.checkBoxes[Identifiers.showSearchAndDuckAIToggleToggle]
        XCTAssertTrue(showToggleCheckbox.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Show Search and Duck.ai toggle setting should be visible")

        // Ensure the toggle setting is ON
        if !showToggleCheckbox.isOn {
            showToggleCheckbox.click()
        }

        // Open new tab and activate address bar to enter editing mode
        app.openNewTab()
        app.activateAddressBar()

        let searchModeToggle = app.radioGroups[Identifiers.searchModeToggleControl]
        XCTAssertTrue(searchModeToggle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Search/Duck.ai toggle should be visible when address bar is focused and setting is on")

        // Go back to settings tab and turn OFF the toggle setting
        app.closeCurrentTab()
        showToggleCheckbox.click()

        // Open new tab, activate address bar, and verify toggle is not visible
        app.openNewTab()
        app.activateAddressBar()
        XCTAssertFalse(searchModeToggle.waitForExistence(timeout: 2),
                       "Search/Duck.ai toggle should not be visible when setting is disabled")

        // Restore: go back to settings and re-enable
        app.closeCurrentTab()
        showToggleCheckbox.click()
    }

    // MARK: - Tab Bar Button Visibility from Settings

    func test_settingsToggleDuckAIButton_hidesAndShowsTitleButton() {
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)

        let duckAIToggle = app.checkBoxes[Identifiers.showDuckAIButtonInTabBarToggle]
        XCTAssertTrue(duckAIToggle.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        let titleButton = app.windows.firstMatch.buttons[Identifiers.duckAITitleButton]
        XCTAssertTrue(titleButton.exists, "Duck.ai title button should be visible by default")

        // Disable via settings
        duckAIToggle.click()
        XCTAssertTrue(titleButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
                      "Duck.ai title button should be hidden after disabling in settings")

        // Re-enable via settings
        duckAIToggle.click()
        XCTAssertTrue(titleButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Duck.ai title button should reappear after re-enabling in settings")
    }

    func test_settingsToggleSidebarButton_hidesAndShowsSidebarButton() {
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)

        let sidebarToggle = app.checkBoxes[Identifiers.showSidebarButtonInTabBarToggle]
        XCTAssertTrue(sidebarToggle.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        let sidebarButton = app.windows.firstMatch.buttons[Identifiers.sidebarButton]
        XCTAssertTrue(sidebarButton.exists, "Sidebar button should be visible by default")

        // Disable via settings
        sidebarToggle.click()
        XCTAssertTrue(sidebarButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
                      "Sidebar button should be hidden after disabling in settings")

        // Re-enable via settings
        sidebarToggle.click()
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Sidebar button should reappear after re-enabling in settings")
    }

    // MARK: - Main Duck.ai Toggle Disables Everything

    func test_whenDuckAIIsDisabled_thenTabBarButtonsAndToggleAreNotVisible() {
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)

        // Ensure sub-settings are ON before disabling the main setting
        let showToggleCheckbox = app.checkBoxes[Identifiers.showSearchAndDuckAIToggleToggle]
        XCTAssertTrue(showToggleCheckbox.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        if !showToggleCheckbox.isOn {
            showToggleCheckbox.click()
        }

        // Disable the main Duck.ai setting
        let disableButton = app.buttons[Identifiers.aiFeaturesToggle]
        XCTAssertTrue(disableButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        disableButton.click()

        // Confirm in the dialog
        let confirmButton = app.buttons["Disable Duck.ai"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        confirmButton.click()

        // Tab bar buttons should be hidden
        let titleButton = app.windows.firstMatch.buttons[Identifiers.duckAITitleButton]
        XCTAssertTrue(titleButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
                      "Duck.ai title button should be hidden when Duck.ai is disabled")
        let sidebarButton = app.windows.firstMatch.buttons[Identifiers.sidebarButton]
        XCTAssertFalse(sidebarButton.exists,
                       "Sidebar button should be hidden when Duck.ai is disabled")

        // Verify toggle is not visible when address bar is focused
        app.openNewTab()
        app.activateAddressBar()
        let searchModeToggle = app.radioGroups[Identifiers.searchModeToggleControl]
        XCTAssertFalse(searchModeToggle.waitForExistence(timeout: 2),
                       "Search/Duck.ai toggle should not be visible when Duck.ai is disabled")

        // Right-click on a tab — Duck.ai context menu items should not appear
        let tab = app.tabGroups.matching(identifier: "Tabs").radioButtons.firstMatch
        tab.rightClick()
        let contextMenu = tab.children(matching: .menu).firstMatch
        if contextMenu.waitForExistence(timeout: UITests.Timeouts.elementExistence) {
            XCTAssertFalse(contextMenu.menuItems["hideDuckAITitleButtonAction"].exists,
                           "Duck.ai context menu items should not appear when Duck.ai is disabled")
            XCTAssertFalse(contextMenu.menuItems["openAISettingsAction"].exists,
                           "Open AI Settings context menu item should not appear when Duck.ai is disabled")
            // Dismiss the context menu
            app.typeKey(.escape, modifierFlags: [])
        }

        // View menu should not show Duck.ai items
        let viewMenu = app.menuBars.menuBarItems["View"]
        viewMenu.click()
        XCTAssertFalse(viewMenu.menuItems["Hide Duck.ai Shortcut"].waitForExistence(timeout: 2),
                       "Hide Duck.ai Shortcut should not be in View menu when Duck.ai is disabled")
        XCTAssertFalse(viewMenu.menuItems["Show Duck.ai Shortcut"].exists,
                       "Show Duck.ai Shortcut should not be in View menu when Duck.ai is disabled")
        XCTAssertFalse(viewMenu.menuItems["Hide Sidebar Button"].exists,
                       "Hide Sidebar Button should not be in View menu when Duck.ai is disabled")
        XCTAssertFalse(viewMenu.menuItems["Show Sidebar Button"].exists,
                       "Show Sidebar Button should not be in View menu when Duck.ai is disabled")
        app.typeKey(.escape, modifierFlags: [])

        // Restore: re-enable Duck.ai
        app.activateAddressBar()
        addressBarTextField = app.addressBar
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)
        let enableButton = app.buttons[Identifiers.aiFeaturesToggle]
        XCTAssertTrue(enableButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        enableButton.click()
    }
}
