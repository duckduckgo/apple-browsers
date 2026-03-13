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

    private enum AccessibilityIdentifiers {
        static let aiChatButton = "AddressBarButtonsViewController.aiChatButton"
        static let searchModeToggleControl = "AddressBarButtonsViewController.searchModeToggleControl"
        static let aiFeaturesToggle = "Preferences.AIChat.aiFeaturesToggle"
        static let showInAddressBarToggle = "Preferences.AIChat.showInAddressBarToggle"
        static let showSearchAndDuckAIToggleToggle = "Preferences.AIChat.showSearchAndDuckAIToggleToggle"
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp(featureFlags: ["aiChatOmnibarToggle": true, "aiChatChromeSidebar": false])

        addressBarTextField = app.addressBar
        app.enforceSingleWindow()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        app.terminate()
    }

    // MARK: - Test 1: Show Duck.ai shortcut in address bar

    func test_whenShowDuckAIShortcutInAddressBarIsToggled_thenDuckAIButtonVisibilityUpdates() throws {
        // Navigate to AI Chat settings first; this unfocuses the address bar so
        // the AI chat button becomes visible (it is hidden while the address bar
        // is focused when the omnibar toggle feature flag is on).
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)
        let showInAddressBarToggle = app.checkBoxes[AccessibilityIdentifiers.showInAddressBarToggle]
        XCTAssertTrue(showInAddressBarToggle.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        let aiChatButton = app.windows.buttons[AccessibilityIdentifiers.aiChatButton]
        XCTAssertTrue(aiChatButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "AIChat button should be visible by default")

        // Disable the shortcut in address bar
        showInAddressBarToggle.click()
        XCTAssertFalse(aiChatButton.exists,
                       "AIChat button should not be visible when show in address bar is disabled")

        // Re-enable the shortcut in address bar
        showInAddressBarToggle.click()
        XCTAssertTrue(aiChatButton.exists,
                      "AIChat button should be visible after re-enabling show in address bar")
    }

    // MARK: - Test 2: Show Search and Duck.ai toggle when address bar is focused

    func test_whenShowSearchAndDuckAIToggleIsChanged_thenToggleVisibilityUpdatesOnFocus() throws {
        // Navigate to AI Chat settings
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)
        let showToggleCheckbox = app.checkBoxes[AccessibilityIdentifiers.showSearchAndDuckAIToggleToggle]
        XCTAssertTrue(showToggleCheckbox.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Show Search and Duck.ai toggle setting should be visible")

        // Ensure the toggle setting is ON
        if !showToggleCheckbox.isOn {
            showToggleCheckbox.click()
        }

        // Open new tab and activate address bar to enter editing mode
        app.openNewTab()
        app.activateAddressBar()

        let searchModeToggle = app.radioGroups[AccessibilityIdentifiers.searchModeToggleControl]
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

    // MARK: - Test 3: Main Duck.ai setting disables all features

    func test_whenDuckAIIsDisabled_thenAddressBarButtonAndToggleAreNotVisible() throws {
        // Navigate to AI Chat settings
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)

        // Ensure sub-settings are ON before disabling the main setting
        let showToggleCheckbox = app.checkBoxes[AccessibilityIdentifiers.showSearchAndDuckAIToggleToggle]
        XCTAssertTrue(showToggleCheckbox.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        if !showToggleCheckbox.isOn {
            showToggleCheckbox.click()
        }

        let showInAddressBarToggle = app.checkBoxes[AccessibilityIdentifiers.showInAddressBarToggle]
        if !showInAddressBarToggle.isOn {
            showInAddressBarToggle.click()
        }

        // Disable the main Duck.ai setting
        let disableButton = app.buttons[AccessibilityIdentifiers.aiFeaturesToggle]
        XCTAssertTrue(disableButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        disableButton.click()

        // Confirm in the dialog
        let confirmButton = app.buttons["Disable Duck.ai"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        confirmButton.click()

        // Verify AI chat button is not visible
        let aiChatButton = app.windows.buttons[AccessibilityIdentifiers.aiChatButton]
        XCTAssertFalse(aiChatButton.waitForExistence(timeout: 2),
                       "AIChat button should not be visible when Duck.ai is disabled")

        // Verify toggle is not visible when address bar is focused
        app.openNewTab()
        app.activateAddressBar()
        let searchModeToggle = app.radioGroups[AccessibilityIdentifiers.searchModeToggleControl]
        XCTAssertFalse(searchModeToggle.waitForExistence(timeout: 2),
                       "Search/Duck.ai toggle should not be visible when Duck.ai is disabled")

        // Restore: re-enable Duck.ai
        app.activateAddressBar()
        addressBarTextField = app.addressBar
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)
        let enableButton = app.buttons[AccessibilityIdentifiers.aiFeaturesToggle]
        XCTAssertTrue(enableButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        enableButton.click()
    }
}
