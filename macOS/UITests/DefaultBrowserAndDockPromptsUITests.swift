//
//  DefaultBrowserAndDockPromptsUITests.swift
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

final class DefaultBrowserAndDockPromptsUITests: UITestCase {

    private var webView: XCUIElement!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()
        webView = app.webViews.firstMatch
    }

    override func tearDown() {
        webView = nil
        app = nil
        super.tearDown()
    }

    // Note that this test only covers the behavior in the app under test, not the system behavior.
    // System-level verification (e.g. checking if the system alert is shown for setting the default browser,
    // if the app is added to the dock, or if the app is set as default browser) is out of scope for UI tests.
    func testInactiveUserPrompt_ConfirmButtonDismissesPrompt() throws {
        // Simulate conditions for user eligibility for the prompt:
        // 28 days after app install and 7 days of user inactivity
        app.simulateFreshAppInstall()
        let promptEligibilityDate = Date().advanced(by: .days(28))
        app.overrideCurrentDate(with: promptEligibilityDate)

        // Trigger the prompt
        triggerPrompt(app.inactiveUserPrompt)

        // Confirm the prompt
        app.confirmButton.click()
        XCTAssertTrue(app.inactiveUserPrompt.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Inactive user prompt should be dismissed after confirming")
    }

    // Note that this test only covers the behavior in the app under test, not the system behavior.
    // System-level verification (e.g. checking or interacting with the feedback notification) is out of scope for UI tests.
    func testInactiveUserPrompt_CancelButtonDismissesPrompt() throws {
        // Simulate conditions for user eligibility for the prompt:
        // 28 days after app install and 7 days of user inactivity
        app.simulateFreshAppInstall()
        let promptEligibilityDate = Date().advanced(by: .days(28))
        app.overrideCurrentDate(with: promptEligibilityDate)

        // Trigger the prompt
        triggerPrompt(app.inactiveUserPrompt)

        // Dismiss the prompt
        app.dismissButton.click()
        XCTAssertTrue(app.inactiveUserPrompt.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Inactive user prompt should be dismissed after confirming")
    }
}

// MARK: - Test helpers

private extension DefaultBrowserAndDockPromptsUITests {

    /// Trigger the provided prompt by simulating window focus changes, and check its existence before and after.
    func triggerPrompt(_ prompt: XCUIElement) {
        XCTAssertTrue(prompt.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Inactive user prompt should not be shown until window regains focus")

        app.closeWindow()
        app.openNewWindow()

        XCTAssertTrue(prompt.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Inactive user prompt should be shown when window regains focus after inactive period and installation period have passed")
    }
}

// MARK: - Helper Identifiers

private extension XCUIApplication {
    enum AccessibilityIdentifiers {
        static let simulateFreshAppInstallMenuItem = "DefaultBrowserAndDockPromptDebugMenu.simulateFreshInstall"
        static let overrideCurrentDateMenuItem = "DefaultBrowserAndDockPromptDebugMenu.simulateCurrentDate"
        static let inactiveUserPrompt = "DefaultBrowserAndDockPrompts.inactiveUser"
        static let confirmButton = "DefaultBrowserAndDockPrompts.inactiveUser.confirmButton"
        static let dismissButton = "DefaultBrowserAndDockPrompts.inactiveUser.dismissButton"
    }

    var simulateFreshAppInstallMenuItem: XCUIElement {
        menuItems[AccessibilityIdentifiers.simulateFreshAppInstallMenuItem]
    }

    var overrideCurrentDateMenuItem: XCUIElement {
        menuItems[AccessibilityIdentifiers.overrideCurrentDateMenuItem]
    }

    var inactiveUserPrompt: XCUIElement {
        sheets[AccessibilityIdentifiers.inactiveUserPrompt]
    }

    var confirmButton: XCUIElement {
        inactiveUserPrompt.buttons[AccessibilityIdentifiers.confirmButton]
    }

    var dismissButton: XCUIElement {
        inactiveUserPrompt.buttons[AccessibilityIdentifiers.dismissButton]
    }
}

// MARK: - Helper Methods

private extension XCUIApplication {

    /// Open Debug menu -> Default Browser and Dock Prompt submenu -> Simulate Fresh App Install
    func simulateFreshAppInstall() {
        let debugMenu = menuBars.menuBarItems["Debug"]
        debugMenu.click()

        let defaultBrowserAndDockPromptSubmenu = menuItems["SAD/ATT Prompts"]
        XCTAssertTrue(defaultBrowserAndDockPromptSubmenu.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Default Browser and Dock Prompt submenu should exist")
        defaultBrowserAndDockPromptSubmenu.hover()

        XCTAssertTrue(simulateFreshAppInstallMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Simulate Fresh App Install menu item should exist")
        simulateFreshAppInstallMenuItem.click()
    }

    /// Open Debug menu -> Default Browser and Dock Prompt submenu -> Override Current Date
    func overrideCurrentDate(with newDate: Date) {
        let debugMenu = menuBars.menuBarItems["Debug"]
        debugMenu.click()

        let defaultBrowserAndDockPromptSubmenu = menuItems["SAD/ATT Prompts"]
        XCTAssertTrue(defaultBrowserAndDockPromptSubmenu.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Default Browser and Dock Prompt submenu should exist")
        defaultBrowserAndDockPromptSubmenu.hover()

        XCTAssertTrue(overrideCurrentDateMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Override Current Date menu item should exist")
        overrideCurrentDateMenuItem.click()

        let datePicker = datePickers.firstMatch
        XCTAssertTrue(datePicker.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Date picker should exist")
        let dateComponents = Calendar.current.dateComponents([.day, .month, .year], from: newDate)
        guard let day = dateComponents.day,
              let month = dateComponents.month,
              let year = dateComponents.year else {
            XCTFail("Failed to extract date components from \(newDate)")
            return
        }

        let dateString = String(format: "%02d/%02d/%04d", day, month, year)
        datePicker.typeText(dateString)
        datePicker.typeText("\r") // Enter to confirm
    }

}
