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
        app = XCUIApplication.setUp()

        app.typeKey("n", modifierFlags: .command)
        resetPinnedTabs()
    }

    override class func setUp() {
        super.setUp()
        UITests.firstRun()
    }

    func testClosesChildTabIsSelected_whenSibilingTabIsClosed() {
        openPrivacyTestPagesSite()

        /// Opens the first link with CMD pressed so we open it on a new tab
        let tab1Link = app.webViews.firstMatch.links["Downloads"]
        tab1Link.rightClick()
        app.menuItems["Open Link in New Tab"].firstMatch.tap()

        let tab2Link = app.webViews.firstMatch.links["Print"]
        tab2Link.rightClick()
        app.menuItems["Open Link in New Tab"].firstMatch.tap()

        /// Move to the next tab and closes it
        app.typeKey("]", modifierFlags: [.command, .shift])
        app.typeKey("w", modifierFlags: [.command])

        /// Asserts that the next child tab is shown
        XCTAssertTrue(app.staticTexts["Print"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    func testClosesChildTabIsSelected_whenParentTabIsClosed() {
        /// We open three empty tabs and then we load the parent privacy site
        app.typeKey("t", modifierFlags: [.command])
        app.typeKey("t", modifierFlags: [.command])
        app.typeKey("t", modifierFlags: [.command])
        openPrivacyTestPagesSite()

        /// Opens two child sites (downloads and print)
        let downloadsChildSiteLink = app.webViews.firstMatch.links["Downloads"]
        downloadsChildSiteLink.rightClick()
        app.menuItems["Open Link in New Tab"].firstMatch.tap()

        let printChildSiteLink = app.webViews.firstMatch.links["Print"]
        printChildSiteLink.rightClick()
        app.menuItems["Open Link in New Tab"].firstMatch.tap()

        /// We pin the privacy site and we close it. We do this to position the parent child first in the tab collection
        /// The reason why we unpin it, is because we do not want for it to be pinned for other tests.
        app.menuItems["Pin Tab"].tap()
        app.menuItems["Unpin Tab"].tap()
        app.menuItems["Close Tab"].tap()

        /// Asserts that the first child next to the closed parent tab is shown. In this case si the Downloads site
        XCTAssertTrue(app.staticTexts["Download PDF"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    func testParentTabIsSelected_whenChildTabIsClosedAndNoOtherChildTabsAreOpened() {
        /// We open three empty tabs and then we load the parent privacy site
        app.typeKey("t", modifierFlags: [.command])
        app.typeKey("t", modifierFlags: [.command])
        app.typeKey("t", modifierFlags: [.command])
        openPrivacyTestPagesSite()

        /// Opens one child sites (downloads and print)
        let downloadsChildSiteLink = app.webViews.firstMatch.links["Downloads"]
        downloadsChildSiteLink.rightClick()
        app.menuItems["Open Link in New Tab"].firstMatch.tap()

        /// We pin the privacy site and we close it. We do this to position the parent child first in the tab collection
        /// The reason why we unpin it, is because we do not want for it to be pinned for other tests.
        app.menuItems["Pin Tab"].tap()
        app.menuItems["Unpin Tab"].tap()

        /// We move through tabs until we are in the child position tab and we close it
        app.typeKey("]", modifierFlags: [.command, .shift])
        app.typeKey("]", modifierFlags: [.command, .shift])
        app.typeKey("]", modifierFlags: [.command, .shift])
        app.typeKey("]", modifierFlags: [.command, .shift])

        app.menuItems["Close Tab"].tap()

        /// Asserts that the first child next to the closed parent tab is shown. In this case si the Downloads site
        XCTAssertTrue(app.staticTexts["Privacy Test Pages"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    func testRecentlyActiveTabIsSelected_whenNewTabIsClosedAndNoOtherTabWasSelected() {
        /// We open three sites  and then we select the first tab
        openFourSitesOnSameWindow()
        app.typeKey("1", modifierFlags: [.command])

        /// We open a new tab and we close it
        app.typeKey("t", modifierFlags: [.command])
        app.menuItems["Close Tab"].tap()

        /// Asserts that the recently active tab is visible
        XCTAssertTrue(app.staticTexts["Sample text for Page #1"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    func testRecentlyActiveTabIsNotSelected_ifAnotherTabWasSelectedBeforeTheTabWasClosed() {
        /// We open three sites  and then we select the first tab
        openFourSitesOnSameWindow()
        app.typeKey("1", modifierFlags: [.command])

        /// We open a new tab
        app.typeKey("t", modifierFlags: [.command])
        /// We move to the third tab
        app.typeKey("3", modifierFlags: [.command])
        /// We move to the last tab and we close it
        app.typeKey("5", modifierFlags: [.command])
        app.menuItems["Close Tab"].tap()

        /// Asserts that the tab to the right is shown
        XCTAssertTrue(app.staticTexts["Sample text for Page #4"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    // MARK: - Utilities

    private func resetPinnedTabs() {
        app.menuItems["Reset Pinned Tabs"].tap()
    }

    private func moveToRightEndTab() {
        let toolbar = app.toolbars.firstMatch
        let toolbarCoordinate = toolbar.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let startPoint = toolbarCoordinate.withOffset(CGVector(dx: 160, dy: 0))
        startPoint.press(forDuration: 0.1)

        sleep(1)
    }

    private func openFourSitesOnSameWindow() {
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

    private func openPrivacyTestPagesSite() {
        let url = URL(string: "http://privacy-test-pages.site/index.html")!
        let addressBarTextField = app.windows.firstMatch.textFields["AddressBarViewController.addressBarTextField"]
        XCTAssertTrue(
            addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The address bar text field didn't become available in a reasonable timeframe."
        )
        addressBarTextField.typeURL(url)
        XCTAssertTrue(
            app.windows.firstMatch.webViews["Privacy Test Pages - Home"].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Visited site didn't load with the expected title in a reasonable timeframe."
        )
    }
}
