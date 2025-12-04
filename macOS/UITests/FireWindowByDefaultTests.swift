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
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        // Assume feature flag is on by default
        app = XCUIApplication.setUp()

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
        app.openPreferencesWindow()
        app.preferencesGoToDataClearingPane()

        // Turn on the 'Open Fire Window by Default' setting
        app.setOpenFireWindowByDefault(enabled: true)

        // Close preferences
        app.closePreferencesWindow()

        // Test CMD+N opens Fire Window
        app.openNewWindow()
        assertFireWindowOpened()

        // Close the Fire Window
        app.closeWindow()

        // Test CMD+SHIFT+N opens Normal Window
        app.typeKey("n", modifierFlags: [.command, .shift])
        assertNormalWindowOpened()
    }

    func testFireWindowByDefaultDisabled() {
        // Navigate to Settings -> Data Clearing
        app.openPreferencesWindow()
        app.preferencesGoToDataClearingPane()

        // Turn off the 'Open Fire Window by Default' setting
        app.setOpenFireWindowByDefault(enabled: false)

        // Close preferences
        app.closePreferencesWindow()

        // Test CMD+N opens Normal Window
        app.openNewWindow()
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

        app.preferencesSetRestorePreviousSession(to: .restoreLastSession)

        // Navigate to Data Clearing preferences
        app.preferencesGoToDataClearingPane()

        // Enable Fire Window by Default
        app.setOpenFireWindowByDefault(enabled: true)

        app.closeWindow()

        // Open Normal Window using (CMD + SHIFT + N)
        app.typeKey("n", modifierFlags: [.command, .shift])
        app.openSite(pageTitle: "Page #1")

        // Quit the application
        app.typeKey("q", modifierFlags: [.command])
        app.launch()

        _ = app.wait(for: .runningForeground, timeout: UITests.Timeouts.elementExistence)

        assertRestoredSession()
    }

    // MARK: - Helper Methods

    private func navigateToGeneralSettings() {
        app.openPreferencesWindow()
        app.preferencesGoToGeneralPane()
    }

    private func resetToDefaultSettings() {
        // Reset Fire Window by Default to disable
        app.openPreferencesWindow()
        app.preferencesGoToDataClearingPane()
        app.setOpenFireWindowByDefault(enabled: false)

        // Reset session restore to disabled (open new window)
        app.preferencesGoToGeneralPane()
        app.preferencesSetRestorePreviousSession(to: .newWindow)
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
