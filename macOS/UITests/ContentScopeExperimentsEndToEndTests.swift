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

    func testContentScopeExperiments() throws {
        let app = XCUIApplication.setUp()
        app.openNewTab()

        // Step 1: Load custom remote config
        let menuBarsQuery = app.menuBars
        let internalUserMenuItem = menuBarsQuery.menuItems["Set Internal User State"]
        if internalUserMenuItem.exists {
            internalUserMenuItem.click()
        }
        menuBarsQuery.menuBarItems["Debug"].click()
        menuBarsQuery.menuItems["Remote Configuration"].click()
        menuBarsQuery.menuItems["Set custom configuration URL…"].click()

        let configURL = URL(string: "https://privacy-test-pages.site/content-scope-scripts/infra/config/conditional-matching-experiments.json")!
        let textField = app.dialogs["alert"].children(matching: .textField).element
        XCTAssertTrue(textField.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Custom config alert did not appear.")
        textField.typeURL(configURL, pressingEnter: false)
        app.typeKey(.return, modifierFlags: [])

        // Step 2: Load test page
        let testPageUrl = URL(string: "https://privacy-test-pages.site/content-scope-scripts/infra/pages/conditional-matching-experiments.html")!
        XCTAssertTrue(
            app.addressBar.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The address bar text field didn't become available in a reasonable timeframe."
        )
        app.typeURL(testPageUrl)
        XCTAssertTrue(
            app.windows.firstMatch.webViews["Conditional Matching experiments"].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Test page didn't load with the expected title in a reasonable timeframe."
        )

        // Step 3: Check test passes
        let suiteStatusLabel = app.staticTexts["Test suite status: "]
        let suiteStatusValue = app.staticTexts["pass"]
        XCTAssertTrue(suiteStatusLabel.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Test Suite Status Label not found")
        XCTAssertTrue(suiteStatusValue.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Test Suite Status Value not pass")
    }

}
