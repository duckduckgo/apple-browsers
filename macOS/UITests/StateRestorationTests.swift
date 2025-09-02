//
//  StateRestorationTests.swift
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

class StateRestorationTests: UITestCase {

    private var firstPageTitle: String!
    private var secondPageTitle: String!
    private var firstURLForBookmarksBar: URL!
    private var secondURLForBookmarksBar: URL!
    private let titleStringLength = 12
    private var addressBarTextField: XCUIElement!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        firstPageTitle = UITests.randomPageTitle(length: titleStringLength)
        secondPageTitle = UITests.randomPageTitle(length: titleStringLength)
        firstURLForBookmarksBar = UITests.simpleServedPage(titled: firstPageTitle)
        secondURLForBookmarksBar = UITests.simpleServedPage(titled: secondPageTitle)
        addressBarTextField = app.addressBar

        app.enforceSingleWindow()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        app.terminate()
    }

    func test_tabStateAtRelaunch_shouldContainTwoSitesVisitedInPreviousSession_whenReopenAllWindowsFromLastSessionIsSet() {
        // Open settings and enable session restore using helper
        app.openPreferencesWindow()
        app.preferencesSetRestorePreviousSession(to: .restoreLastSession)
        app.closePreferencesWindow()
        app.enforceSingleWindow()
        XCTAssertTrue(
            addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The address bar text field didn't become available in a reasonable timeframe."
        )
        addressBarTextField.pasteURL(firstURLForBookmarksBar)
        XCTAssertTrue(
            app.windows.webViews[firstPageTitle].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Site didn't load with the expected title in a reasonable timeframe."
        )
        app.openNewTab()
        addressBarTextField.pasteURL(secondURLForBookmarksBar)
        XCTAssertTrue(
            app.windows.webViews[secondPageTitle].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Site didn't load with the expected title in a reasonable timeframe."
        )

        app.typeKey("q", modifierFlags: [.command])
        app.launch()

        XCTAssertTrue(
            app.windows.webViews[secondPageTitle].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Second visited site wasn't found in a webview with the expected title in a reasonable timeframe."
        )
        app.closeCurrentTab()
        XCTAssertTrue(
            app.windows.webViews[firstPageTitle].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "First visited site wasn't found in a webview with the expected title in a reasonable timeframe."
        )
    }

    func test_tabStateAtRelaunch_shouldContainNoSitesVisitedInPreviousSession_whenReopenAllWindowsFromLastSessionIsUnset() {
        // Open settings and disable session restore using helper
        app.openPreferencesWindow()
        app.preferencesSetRestorePreviousSession(to: .newWindow)
        app.closePreferencesWindow()
        app.enforceSingleWindow()
        XCTAssertTrue(
            addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The address bar text field didn't become available in a reasonable timeframe."
        )
        addressBarTextField.pasteURL(firstURLForBookmarksBar)
        XCTAssertTrue(
            app.windows.webViews[firstPageTitle].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Site didn't load with the expected title in a reasonable timeframe."
        )
        app.openNewTab()
        addressBarTextField.pasteURL(secondURLForBookmarksBar)
        XCTAssertTrue(
            app.windows.webViews[secondPageTitle].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Site didn't load with the expected title in a reasonable timeframe."
        )

        app.terminate()
        app.launch()

        XCTAssertTrue(
            app.windows.webViews[secondPageTitle].waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "Second visited site from previous session should not be in any webview."
        )
        XCTAssertTrue(
            app.windows.webViews[firstPageTitle].waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "First visited site from previous session should not be in any webview."
        )
        app.closeCurrentTab()
        XCTAssertTrue(
            app.windows.webViews[firstPageTitle].waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "First visited site from previous session should not be in any webview."
        )
        XCTAssertTrue(
            app.windows.webViews[secondPageTitle].waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "Second visited site from previous session should not be in any webview."
        )
    }
}
