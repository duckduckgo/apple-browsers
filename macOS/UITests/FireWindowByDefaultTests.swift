//
//  FireWindowByDefaultTests.swift
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

class FireWindowByDefaultTests: UITestCase {

    private var dataClearingButton: XCUIElement!
    private var generalButton: XCUIElement!
    private var openFireWindowByDefaultToggle: XCUIElement!
    private var reopenAllWindowsFromLastSessionRadio: XCUIElement!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        // Assume feature flag is on by default
        app = XCUIApplication.setUp(featureFlags: ["openFireWindowByDefault": true])

        dataClearingButton = app.buttons["PreferencesSidebar.dataClearingButton"]
        generalButton = app.buttons["PreferencesSidebar.generalButton"]
        openFireWindowByDefaultToggle = app.checkBoxes["PreferencesDataClearingView.openFireWindowByDefault"]
        reopenAllWindowsFromLastSessionRadio = app.radioButtons["PreferencesGeneralView.stateRestorePicker.reopenAllWindowsFromLastSession"]

        app.enforceSingleWindow()
    }

    override func tearDownWithError() throws {
        // Reset both settings to default after each test
        resetToDefaultSettings()
        try super.tearDownWithError()
    }

    // MARK: - Test Cases

    func testFireWindowByDefaultEnabled() {
        // Navigate to Settings -> Data Clearing
        navigateToDataClearingSettings()

        // Turn on the 'Open Fire Window by Default' setting
        if openFireWindowByDefaultToggle.value as? Bool == false {
            openFireWindowByDefaultToggle.click()
        }

        // Verify the setting is enabled
        XCTAssertTrue(openFireWindowByDefaultToggle.value as? Bool == true,
                     "Open Fire Window by Default should be enabled")

        // Close preferences
        app.closePreferencesWindow()

        // Test CMD+N opens Fire Window
        app.typeKey("n", modifierFlags: .command)
        assertFireWindowOpened()

        // Close the Fire Window
        app.closeWindow()

        // Test CMD+SHIFT+N opens Normal Window
        app.typeKey("n", modifierFlags: [.command, .shift])
        assertNormalWindowOpened()
    }

    func testFireWindowByDefaultDisabled() {
        // Navigate to Settings -> Data Clearing
        navigateToDataClearingSettings()

        // Turn off the 'Open Fire Window by Default' setting
        if openFireWindowByDefaultToggle.value as? Bool == true {
            openFireWindowByDefaultToggle.click()
        }

        // Verify the setting is disabled
        XCTAssertTrue(openFireWindowByDefaultToggle.value as? Bool == false,
                     "Open Fire Window by Default should be disabled")

        // Close preferences
        app.closePreferencesWindow()

        // Test CMD+N opens Normal Window
        app.typeKey("n", modifierFlags: .command)
        assertNormalWindowOpened()

        // Close the Normal Window
        app.closeWindow()

        // Test CMD+SHIFT+N opens Fire Window
        app.typeKey("n", modifierFlags: [.command, .shift])
        assertFireWindowOpened()
    }

    func testFireWindowByDefaultSessionRestoreInteraction() {
        // First, enable session restore in General preferences
        navigateToGeneralSettings()

        if reopenAllWindowsFromLastSessionRadio.isSelected == false {
            reopenAllWindowsFromLastSessionRadio.click()
        }

        // Verify session restore is enabled
        XCTAssertTrue(reopenAllWindowsFromLastSessionRadio.isSelected,
                     "Session restore should be enabled")

        // Navigate to Data Clearing preferences
        navigateToDataClearingSettings()

        // Enable Fire Window by Default
        if openFireWindowByDefaultToggle.value as? Bool == false {
            openFireWindowByDefaultToggle.click()
        }

        app.closeWindow()

        // Open Normal Window
        app.typeKey("n", modifierFlags: [.command, .shift])
        openSite(pageTitle: "Page #1")

        // Quit the application
        app.typeKey("q", modifierFlags: [.command])
        app.launch()

        assertRestoredSession()
    }

    // MARK: - Helper Methods

    private func openSite(pageTitle: String) {
        let url = UITests.simpleServedPage(titled: pageTitle)
        let addressBar = app.addressBar
        XCTAssertTrue(
            addressBar.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The address bar text field didn't become available in a reasonable timeframe."
        )
        addressBar.typeURL(url)
        XCTAssertTrue(
            app.windows.firstMatch.webViews[pageTitle].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Visited site didn't load with the expected title in a reasonable timeframe."
        )
    }

    private func navigateToDataClearingSettings() {
        app.openPreferencesWindow()

        XCTAssertTrue(
            dataClearingButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Data Clearing button should be available in preferences sidebar"
        )

        dataClearingButton.click()

        XCTAssertTrue(
            openFireWindowByDefaultToggle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Open Fire Window by Default toggle should be available in Data Clearing preferences"
        )
    }

    private func navigateToGeneralSettings() {
        app.openPreferencesWindow()

        XCTAssertTrue(
            generalButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "General button should be available in preferences sidebar"
        )

        generalButton.click()

        XCTAssertTrue(
            reopenAllWindowsFromLastSessionRadio.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Session restore radio button should be available in General preferences"
        )
    }

    private func resetToDefaultSettings() {
        // Reset Fire Window by Default to disabled
        navigateToDataClearingSettings()
        if openFireWindowByDefaultToggle.value as? Bool == true {
            openFireWindowByDefaultToggle.click()
        }

        // Reset session restore to disabled (open new window)
        navigateToGeneralSettings()
        let openNewWindowRadio = app.radioButtons["PreferencesGeneralView.stateRestorePicker.openANewWindow"]
        if openNewWindowRadio.exists && !openNewWindowRadio.isSelected {
            openNewWindowRadio.click()
        }

        // Reset startup window type to default (normal window)
        let startupWindowTypePicker = app.popUpButtons.firstMatch
        if startupWindowTypePicker.exists {
            startupWindowTypePicker.click()
            let windowOption = app.menuItems["Window"]
            if windowOption.exists {
                windowOption.click()
            }
        }

        app.closePreferencesWindow()
    }

    private func assertFireWindowOpened() {
        let fireWindowIndicator = app.staticTexts["Fire Window"]
        XCTAssertTrue(
            fireWindowIndicator.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Fire Window should be opened (indicated by 'Fire Window' text)"
        )
    }

    private func assertNormalWindowOpened() {
        // Verify that no "Fire Window" indicator exists in the new window
        let fireWindowIndicator = app.staticTexts["Fire Window"]
        XCTAssertFalse(
            fireWindowIndicator.exists,
            "Normal Window should not have 'Fire Window' indicator"
        )
    }

    private func assertRestoredSession() {
        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "App window didn't become available in a reasonable timeframe."
        )

        XCTAssertTrue(app.staticTexts["Sample text for Page #1"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }
}
