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
import Utilities

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
    // System-level verification (e.g. checking if the app is added to the dock,
    // or if the app is set as default browser) is out of scope for UI tests.
    func testInactiveUserPrompt_ConfirmButtonDismissesPrompt() throws {
        app.showInactiveUserModal()

        // Confirm the prompt
        app.confirmButton.click()
        XCTAssertTrue(app.inactiveUserPrompt.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Inactive user prompt should be dismissed after clicking confirm button")

        // Dismiss the default browser dialog, if needed, to prevent interference with other tests
        let coreServicesUIAgent = XCUIApplication(bundleIdentifier: "com.apple.coreservices.uiagent")
        let defaultBrowserDialog = coreServicesUIAgent.dialogs.firstMatch
        if defaultBrowserDialog.waitForExistence(timeout: UITests.Timeouts.elementExistence) {
            defaultBrowserDialog.buttons.element(boundBy: 1).click()
        }
    }

    // Note that this test only covers the behavior in the app under test, not the system behavior.
    // System-level verification (e.g. checking or interacting with the feedback notification) is out of scope for UI tests.
    func testInactiveUserPrompt_CancelButtonDismissesPrompt() throws {
        app.showInactiveUserModal()

        // Dismiss the prompt
        app.dismissButton.click()
        XCTAssertTrue(app.inactiveUserPrompt.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Inactive user prompt should be dismissed after clicking dismiss button")
    }
}

// MARK: - Helper Identifiers

private extension XCUIApplication {
    private typealias Identifiers = Utilities.AccessibilityIdentifiers

    var inactiveUserPrompt: XCUIElement {
        sheets[Identifiers.DefaultBrowserAndDockPrompts.inactiveUserPrompt]
    }

    var confirmButton: XCUIElement {
        inactiveUserPrompt.buttons[Identifiers.DefaultBrowserAndDockPrompts.confirmButton]
    }

    var dismissButton: XCUIElement {
        inactiveUserPrompt.buttons[Identifiers.DefaultBrowserAndDockPrompts.dismissButton]
    }

    var reportAProblemForm: XCUIElement {
        sheets[Identifiers.Feedback.reportAProblem]
    }

    var inactiveUserPromptDebugMenuItem: XCUIElement {
        promoQueueMenu
            .menuItems[Utilities.AccessibilityIdentifiers.PromoQueue.promoMenuItem("default-browser-and-dock-inactive-modal")]
    }
}

// MARK: - Helper Methods

private extension XCUIApplication {

    func showInactiveUserModal() {
        debugMenu.click()
        inactiveUserPromptDebugMenuItem.menuItems[Utilities.AccessibilityIdentifiers.PromoQueue.forceShowPromo].click()
    }

}
