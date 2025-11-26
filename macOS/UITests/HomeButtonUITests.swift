//
//  HomeButtonUITests.swift
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
import Foundation

class HomeButtonUITests: UITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp()

        app.openNewWindow()
    }

    func testWhenHomeButtonIsPressedAndNoURLIsSet_thenNewTabPageIsOpened() {
        app.showHomeButtonInToolbar()
        app.openSettings()

        /// Close the first opened new tab
        app.typeKey("[", modifierFlags: [.command, .shift])
        app.typeKey("w", modifierFlags: [.command])

        app.preferencesGoToGeneralPane()
        app.radioButtons["PreferencesGeneralView.homePage.newTab"].click()
        app.openNewTab()
        app.openSite(pageTitle: "Some Site")

        /// Close the first opened new tab
        app.typeKey("[", modifierFlags: [.command, .shift])
        app.typeKey("w", modifierFlags: [.command])

        app.homeButton.click()

        // We test the tapping the home button replaces the current site and opens a new tab
        assertNewTabPageIsShown()

        // Now we check that tapping back goes back to the first opened site
        app.backButton.click()
        let someSiteText = app.staticTexts["Some Site"].firstMatch
        XCTAssertTrue(
            someSiteText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The site didn't become available in a reasonable timeframe."
        )
    }

    func testAfterSettingCustomURLForHome_thenWhenTappingHomeButtonCustomURLIsOpened() {
        app.showHomeButtonInToolbar()
        app.openSettings()

        /// Close the first opened new tab
        app.typeKey("[", modifierFlags: [.command, .shift])
        app.typeKey("w", modifierFlags: [.command])

        app.preferencesGoToGeneralPane()
        app.radioButtons["PreferencesGeneralView.homePage.specificPage"].click()
        app.openNewTab()
        app.homeButton.click()
        assertSpecificPageIsShown()
    }

    // MARK: - Helper functions

    private func assertNewTabPageIsShown() {
        // Validate via address bar - more precise than menu item existence
        let addressBarValue = app.addressBarValueActivatingIfNeeded()
        XCTAssertTrue(
            addressBarValue?.isEmpty == true || addressBarValue?.contains("newtab") == true,
            "Should show new tab page in address bar, got: \(addressBarValue ?? "nil")"
        )
    }

    private func assertSpecificPageIsShown() {
        let duckduckGoText = app.staticTexts["duckduckgo.com"].firstMatch
        XCTAssertTrue(
            duckduckGoText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "DuckDuckGo site New Tab didn't become available in a reasonable timeframe."
        )

        // Also validate address bar shows expected URL
        let addressBarValue = app.addressBarValueActivatingIfNeeded()
        XCTAssertTrue(
            addressBarValue?.contains("duckduckgo.com") == true,
            "Address bar should show duckduckgo.com, got: \(addressBarValue ?? "nil")"
        )
    }
}
