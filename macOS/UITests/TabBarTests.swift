//
//  TabBarTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

class TabBarTests: UITestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launch()
    }

    override class func setUp() {
        super.setUp()
        UITests.firstRun()
    }

    func testTabGetsToRecentlyClosedTabWhenCurrentTabIsClosed() {
        openThreeSitesOnSameWindow()
        pinsPageOne()
        moveToRightEndTab()
        /// Closes last tab
        app.typeKey("W", modifierFlags: [.command])

        /// Asserts that the pinned tab
        XCTAssertTrue(app.staticTexts["Sample text for Page #1"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    // MARK: - Utilities

    private func moveToRightEndTab() {
        let toolbar = app.toolbars.firstMatch
        let toolbarCoordinate = toolbar.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let startPoint = toolbarCoordinate.withOffset(CGVector(dx: 160, dy: 0))
        startPoint.press(forDuration: 0.1)

        sleep(1)
    }

    private func openThreeSitesOnSameWindow() {
        openSite(pageTitle: "Page #1")
        app.openNewTab()
        openSite(pageTitle: "Page #2")
        app.openNewTab()
        openSite(pageTitle: "Page #3")
        app.openNewTab()
        openSite(pageTitle: "Page #4")
    }

    private func pinsPageOne() {
        app.typeKey("[", modifierFlags: [.command, .shift])
        app.typeKey("[", modifierFlags: [.command, .shift])
        app.typeKey("[", modifierFlags: [.command, .shift])
        app.menuItems["Pin Tab"].tap()
    }

    private func openSite(pageTitle: String) {
        let url = UITests.simpleServedPage(titled: pageTitle)
        let addressBarTextField = app.windows.firstMatch.textFields["AddressBarViewController.addressBarTextField"]
        XCTAssertTrue(
            addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The address bar text field didn't become available in a reasonable timeframe."
        )
        addressBarTextField.typeURL(url)
        XCTAssertTrue(
            app.windows.firstMatch.webViews[pageTitle].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Visited site didn't load with the expected title in a reasonable timeframe."
        )
    }
}
