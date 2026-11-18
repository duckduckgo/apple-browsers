//
//  ContentScopeExperimentsEndToEndTests.swift
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

final class ContentScopeExperimentsEndToEndTests: UITestCase {

    private typealias Identifiers = XCUIApplication.AccessibilityIdentifiers

    private var didSetCustomConfiguration = false

    override func tearDownWithError() throws {
        if didSetCustomConfiguration, let app {
            app.revealDebugMenuItem(Identifiers.debugMenuResetPrivacyConfigurationToDefault, in: Identifiers.debugMenuRemoteConfiguration)
                .clickAfterExistenceTestSucceeds()

            let configUpdateComplete = app.staticTexts["Configuration Update Complete"]
            XCTAssertTrue(configUpdateComplete.waitForExistence(timeout: UITests.Timeouts.navigation), "Default configuration was not restored")
            app.typeKey(.return, modifierFlags: [])
        }

        try super.tearDownWithError()
    }

    func testContentScopeExperiments() throws {
        app = XCUIApplication.setUp()
        app.openNewTab()

        // Step 1: Enable internal user if needed
        let internalUserMenuItem = app.revealDebugMenuItem(Identifiers.debugMenuInternalUserState)
        guard internalUserMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence) else {
            XCTFail("Internal user menu item did not appear")
            return
        }
        if internalUserMenuItem.title == "Set Internal User State" {
            internalUserMenuItem.click()
        } else {
            app.typeKey(.escape, modifierFlags: [])
        }

        // Step 2: Load custom remote config
        app.revealDebugMenuItem(Identifiers.debugMenuSetCustomPrivacyConfigurationURL, in: Identifiers.debugMenuRemoteConfiguration)
            .clickAfterExistenceTestSucceeds()

        let configURL = URL(string: "https://privacy-test-pages.site/content-scope-scripts/infra/config/conditional-matching-experiments.json")!
        let textField = app.dialogs["alert"].children(matching: .textField).element
        XCTAssertTrue(textField.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Custom config alert did not appear.")
        textField.typeURL(configURL, pressingEnter: false)
        app.typeKey(.return, modifierFlags: [])
        didSetCustomConfiguration = true
        let configUpdateComplete = app.staticTexts["Configuration Update Complete"]
        XCTAssertTrue(configUpdateComplete.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Custom config alert did not appear.")
        app.typeKey(.return, modifierFlags: [])

        // Step 3: Load test page
        let testPageUrl = URL(string: "https://privacy-test-pages.site/content-scope-scripts/infra/pages/conditional-matching-experiments.html")!
        XCTAssertTrue(
            app.addressBar.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The address bar text field didn't become available in a reasonable timeframe."
        )
        app.typeURL(testPageUrl)
        XCTAssertTrue(
            app.windows.firstMatch.webViews["Conditional Matching experiments"].waitForExistence(timeout: UITests.Timeouts.navigation),
            "Test page didn't load with the expected title in a reasonable timeframe."
        )

        // Step 4: Check test passes
        let webView = app.windows.firstMatch.webViews["Conditional Matching experiments"]
        let suiteStatusValue = webView.descendants(matching: .any)["pass"]
        XCTAssertTrue(suiteStatusValue.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Test suite status should be pass")
    }

}
