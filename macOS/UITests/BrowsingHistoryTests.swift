//
//  BrowsingHistoryTests.swift
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

class BrowsingHistoryTests: UITestCase {

    private let lengthForRandomPageTitle = 8

    // Fire Dialog Element Accessors
    private var fireDialog: XCUIElement { app.sheets.firstMatch }
    private var fireDialogTitle: XCUIElement { app.fireDialogTitle }
    private var fireDialogHistoryToggle: XCUIElement { app.fireDialogHistoryToggle }
    private var fireDialogCookiesToggle: XCUIElement { app.fireDialogCookiesToggle }
    private var fireDialogTabsToggle: XCUIElement { app.fireDialogTabsToggle }
    private var fireDialogBurnButton: XCUIElement { app.fireDialogBurnButton }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()

        XCTAssertTrue(
            app.historyMenu.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "History menu bar item didn't appear in a reasonable timeframe."
        )
        app.historyMenu.click()

        XCTAssertTrue(
            app.clearAllHistoryMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Clear all history item didn't appear in a reasonable timeframe."
        )
        app.clearAllHistoryMenuItem.click()

        XCTAssertTrue(
            app.clearAllHistoryAlertClearButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Clear all history item didn't appear in a reasonable timeframe."
        )
        app.clearAllHistoryAlertClearButton.click() // Manually remove the history
    }

    func test_recentlyVisited_showsLastVisitedSite() throws {
        let historyPageTitleExpectedToBeFirstInRecentlyVisited = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.openSite(pageTitle: historyPageTitleExpectedToBeFirstInRecentlyVisited)

        let firstSiteInRecentlyVisitedSection = app.recentlyVisitedMenuItem(at: 0)
        XCTAssertTrue(
            app.historyMenu.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "History menu bar item didn't appear in a reasonable timeframe."
        )
        app.historyMenu.click() // The visited sites identifiers will not be available until after the History menu has been accessed.
        XCTAssertTrue(
            firstSiteInRecentlyVisitedSection.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The first site in the recently visited section didn't appear in a reasonable timeframe."
        )

        XCTAssertEqual(historyPageTitleExpectedToBeFirstInRecentlyVisited, firstSiteInRecentlyVisitedSection.title)
    }

    func test_history_showsVisitedSiteAfterClosingAndReopeningWindow() throws {
        let historyPageTitleExpectedToBeFirstInTodayHistory = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.openSite(pageTitle: historyPageTitleExpectedToBeFirstInTodayHistory)

        let siteInRecentlyVisitedSection = app.menuItems[historyPageTitleExpectedToBeFirstInTodayHistory]
        app.enforceSingleWindow()
        XCTAssertTrue(
            app.historyMenu.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "History menu bar item didn't appear in a reasonable timeframe."
        )
        app.historyMenu.click() // The visited sites identifiers will not be available until after the History menu has been accessed.
        XCTAssertTrue(
            siteInRecentlyVisitedSection.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The first site in the recently visited section didn't appear in a reasonable timeframe."
        )
    }

    func test_reopenLastClosedWindowMenuItem_canReopenTabsOfLastClosedWindow() throws {
        let titleOfFirstTabWhichShouldRestore = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let titleOfSecondTabWhichShouldRestore = UITests.randomPageTitle(length: lengthForRandomPageTitle)

        app.openSite(pageTitle: titleOfFirstTabWhichShouldRestore)
        app.openNewTab()
        app.openSite(pageTitle: titleOfSecondTabWhichShouldRestore)

        app.enforceSingleWindow()
        XCTAssertTrue(
            app.historyMenu.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "History menu bar item didn't appear in a reasonable timeframe."
        )
        app.historyMenu.click() // The visited sites identifiers will not be available until after the History menu has been accessed.

        XCTAssertTrue(
            app.reopenLastClosedWindowMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The \"Reopen Last Closed Window\" menu item didn't appear in a reasonable timeframe."
        )
        app.reopenLastClosedWindowMenuItem.click()

        XCTAssertTrue(
            app.windows.webViews[titleOfFirstTabWhichShouldRestore].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Restored visited tab 1 wasn't available with the expected title in a reasonable timeframe."
        )
        app.closeCurrentTab()
        XCTAssertTrue(
            app.windows.webViews[titleOfSecondTabWhichShouldRestore].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Restored visited tab 2 wasn't available with the expected title in a reasonable timeframe."
        )
    }
}
