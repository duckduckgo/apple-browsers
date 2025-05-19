//
//  ContentScopeExperimentsEndToEndTest.swift
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

final class ContentScopeExperimentsEndToEndTest: XCTestCase {

    func testContentScopeExperiments() throws {
        // Initial set up
        super.setUp()
        UITests.firstRun()
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launch()
        app.openNewTab()

        // Step 1: Load custom remote config
        let menuBarsQuery = app.menuBars
        menuBarsQuery.menuBarItems["Debug"].click()
        menuBarsQuery.menuItems["Remote Configuration"].click()
        menuBarsQuery.menuItems["setCustomConfigurationURL:"].click()

        let configURL = URL(string: "https://privacy-test-pages.site/content-scope-scripts/infra/config/conditional-matching-experiments.json")!
        let textField = app.dialogs["alert"].children(matching: .textField).element
        XCTAssertTrue(textField.waitForExistence(timeout: 3), "Custom config alert did not appear.")
        textField.typeURL(configURL, pressingEnter: false)
        app.buttons["action-button-1"].click()

        // Step 2: Load test page
        let testPageUrl = URL(string: "https://privacy-test-pages.site/content-scope-scripts/infra/pages/conditional-matching-experiments.html")!
        let addressBarTextField = app.windows.textFields["AddressBarViewController.addressBarTextField"]
        XCTAssertTrue(
            addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The Address Bar text field did not exist when it was expected."
        )
        addressBarTextField.typeURL(testPageUrl)

        // Step 3: Wait for web view and table and check test passes
        let tableRow = app.windows["Conditional Matching experiments"]
            .webViews["Conditional Matching experiments"]
            .tables.children(matching: .tableRow).element(boundBy: 2)

        let firstCell = tableRow.children(matching: .cell).element(boundBy: 1).staticTexts.element
        let secondCell = tableRow.children(matching: .cell).element(boundBy: 2).staticTexts.element

        let existsPredicate = NSPredicate(format: "exists == true")

        expectation(for: existsPredicate, evaluatedWith: firstCell, handler: nil)
        expectation(for: existsPredicate, evaluatedWith: secondCell, handler: nil)

        waitForExpectations(timeout: 5, handler: nil)

        XCTAssertEqual(firstCell.label, secondCell.label, "The two numbers do not match.")
    }

}
