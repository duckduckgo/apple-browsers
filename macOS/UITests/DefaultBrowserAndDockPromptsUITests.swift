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
        XCTAssertTrue(app.inactiveUserPrompt.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Inactive user prompt should be dismissed after clicking confirm button")
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
        XCTAssertTrue(app.inactiveUserPrompt.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Inactive user prompt should be dismissed after clicking dismiss button")
    }
}

// MARK: - Test helpers

private extension DefaultBrowserAndDockPromptsUITests {

    /// Trigger the provided prompt by simulating window focus changes, and check its existence before and after.
    func triggerPrompt(_ prompt: XCUIElement) {
        XCTAssertTrue(prompt.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Prompt \(prompt.identifier) should not be shown until window regains focus")

        app.closeWindow()
        app.openNewWindow()

        XCTAssertTrue(prompt.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Prompt \(prompt.identifier) should be shown when window regains focus")
    }
}

// MARK: - Helper Identifiers

private extension XCUIApplication {
    enum AccessibilityIdentifiers {
        static let promptsDebugMenu = "DebugMenu.defaultBrowserAndDockPrompts"
        static let simulateFreshAppInstallMenuItem = "DefaultBrowserAndDockPromptDebugMenu.simulateFreshInstall"
        static let overrideCurrentDateMenuItem = "DefaultBrowserAndDockPromptDebugMenu.simulateCurrentDate"
        static let inactiveUserPrompt = "DefaultBrowserAndDockPrompts.inactiveUser"
        static let confirmButton = "DefaultBrowserAndDockPrompts.inactiveUser.confirmButton"
        static let dismissButton = "DefaultBrowserAndDockPrompts.inactiveUser.dismissButton"
    }

    var promptsDebugMenu: XCUIElement {
        debugMenu.menuItems[AccessibilityIdentifiers.promptsDebugMenu]
    }

    var simulateFreshAppInstallMenuItem: XCUIElement {
        promptsDebugMenu.menuItems[AccessibilityIdentifiers.simulateFreshAppInstallMenuItem]
    }

    var overrideCurrentDateMenuItem: XCUIElement {
        promptsDebugMenu.menuItems[AccessibilityIdentifiers.overrideCurrentDateMenuItem]
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
        selectMenuItem(simulateFreshAppInstallMenuItem)
    }

    /// Open Debug menu -> Default Browser and Dock Prompt submenu -> Override Current Date
    func overrideCurrentDate(with newDate: Date) {
        selectMenuItem(overrideCurrentDateMenuItem)

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

    private func selectMenuItem(_ menuItem: XCUIElement) {
        XCTAssertTrue(menuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Menu item \(menuItem.identifier) should exist")
        menuItem.click()
    }

}
