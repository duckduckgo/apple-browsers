//
//  FireDialogUITestsBase.swift
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

protocol FireDialogUITests: UITestCase {}
/// Base class for Fire Dialog UI tests with shared setup and helper methods
extension FireDialogUITests {

    var lengthForRandomPageTitle: Int { 8 }

    // Fire Dialog Element Accessors
    var fireDialog: XCUIElement { app.sheets.firstMatch }
    var fireDialogTitle: XCUIElement { app.fireDialogTitle }
    var fireDialogHistoryToggle: XCUIElement { app.fireDialogHistoryToggle }
    var fireDialogCookiesToggle: XCUIElement { app.fireDialogCookiesToggle }
    var fireDialogTabsToggle: XCUIElement { app.fireDialogTabsToggle }
    var fireDialogBurnButton: XCUIElement { app.fireDialogBurnButton }

    func setUpFireDialogUITests() {
        continueAfterFailure = false
        // Enable feature flags for new Fire dialog, History view, and History view Sites section
        // TO DO: Enable Sites Section when C-S-S implementation is merged in
        app = XCUIApplication.setUp(featureFlags: ["fireDialog": true, /*"historyViewSitesSection": true*/])
        app.enforceSingleWindow()

        // Reset fireproof sites
        let menuBarsQuery = app.menuBars
        menuBarsQuery.menuBarItems["Debug"].click()
        menuBarsQuery.menuItems["Reset Fireproof Sites"].click()

        // Clear state
        app.fireButton.click()
        app.fireDialogSegmentedControl.buttons["Everything"].click()
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()
    }

    // MARK: - Helper Methods

    func populateFakeHistoryFromDebugMenu(file: StaticString = #file, line: UInt = #line) {
        // Open Debug menu -> History submenu -> Populate fake history
        let debugMenu = app.menuBars.menuBarItems["Debug"]
        debugMenu.click()

        let historySubmenu = app.menuItems["History"]
        XCTAssertTrue(historySubmenu.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History submenu should exist", file: file, line: line)
        historySubmenu.hover()

        // Click the first populate option (10 visits per day)
        XCTAssertTrue(app.populateFakeHistory10MenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Populate fake history menu item should exist", file: file, line: line)
        app.populateFakeHistory10MenuItem.click()

        // Wait a moment for history to be populated (async operation)
        Thread.sleep(forTimeInterval: 3.0)
    }

    func openFireDialog(file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(
            app.historyMenu.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "History menu bar item didn't appear",
            file: file,
            line: line
        )
        app.historyMenu.click()

        XCTAssertTrue(
            app.clearAllHistoryMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Clear all history menu item didn't appear",
            file: file,
            line: line
        )
        app.clearAllHistoryMenuItem.click()

        XCTAssertTrue(
            fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Fire dialog didn't appear",
            file: file,
            line: line
        )
    }

    func setStorageAndCookies(file: StaticString = #file, line: UInt = #line) {
        let webView = app.webViews.firstMatch
        let manualIncrementButton = webView.buttons["Manual Increment"]
        XCTAssertTrue(
            manualIncrementButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Manual Increment button didn't appear",
            file: file,
            line: line
        )
        manualIncrementButton.click()
    }

    func verifyInitialCountersSet(file: StaticString = #file, line: UInt = #line) {
        verifyCounterSet("Cookie", at: 0, file: file, line: line)
    }

    func verifyCountersSet(file: StaticString = #file, line: UInt = #line) {
        verifyCounterSet("Storage", at: 1, file: file, line: line)
        verifyCounterSet("Cookie", at: 1, file: file, line: line)
    }

    func verifyCounterSet(_ counterName: String, at offset: Int, file: StaticString = #file, line: UInt = #line) {
        let webView = app.webViews.firstMatch
        let counter = webView.staticTexts.containing(\.value, containing: "\(counterName) Counter:").element(boundBy: offset)
        XCTAssertTrue(
            counter.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "\(counterName) counter element didn't appear",
            file: file,
            line: line
        )

        let counterValue = counter.value as? String ?? ""
        // Extract number from "Storage Counter: 1" or similar
        let components = counterValue.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
        if let numberString = components.last, let number = Int(numberString), number >= 1 {
            // Counter is set to a valid value
            return
        }

        XCTFail("\(counterName) counter should be set (>= 1), but got: '\(counterValue)'", file: file, line: line)
    }

    func verifyCounterCleared(_ counterName: String, file: StaticString = #file, line: UInt = #line) {
        let webView = app.webViews.firstMatch
        let counter = webView.staticTexts.containing(\.value, containing: "\(counterName) Counter:").firstMatch
        XCTAssertTrue(
            counter.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "\(counterName) counter should be cleared (undefined)",
            file: file,
            line: line
        )

        let counterValue = counter.value as? String ?? ""
        // Extract number from "Storage Counter: 1" or similar
        let components = counterValue.components(separatedBy: ":").map { $0.trimmingCharacters(in: .whitespaces) }
        if let last = components.last, last.isEmpty || last == "undefined" {
            // Counter is not set to a numeric value
            return
        }

        XCTFail("\(counterName) counter should not be set, but got: '\(components.last ?? "<nil>")'", file: file, line: line)
    }

    func verifyCountersCleared(file: StaticString = #file, line: UInt = #line) {
        verifyCounterCleared("Storage", file: file, line: line)
        verifyCounterCleared("Cookie", file: file, line: line)
    }

    func fireproofCurrentSite(file: StaticString = #file, line: UInt = #line) {
        app.fireDialogManageFireproofButton.click()

        let fireproofDialog = app.sheets.containing(.staticText, where: .keyPath(\.value, equalTo: "Fireproof Sites")).firstMatch
        XCTAssertTrue(
            fireproofDialog.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Fireproof dialog didn't appear",
            file: file,
            line: line
        )

        XCTAssertTrue(
            app.fireproofDomainsAddCurrentButton.isEnabled,
            "Add Current button should be enabled",
            file: file,
            line: line
        )
        app.fireproofDomainsAddCurrentButton.click()

        let tableView = fireproofDialog.tables.firstMatch
        XCTAssertTrue(
            tableView.tableRows.firstMatch.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Should have at least one fireproofed domain",
            file: file,
            line: line
        )

        app.fireproofDomainsDoneButton.click()
        XCTAssertTrue(
            fireproofDialog.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "Fireproof dialog should close",
            file: file,
            line: line
        )
    }

    func waitForFireAnimationToComplete() {
        RunLoop.main.run(until: Date().addingTimeInterval(2.0))
        XCTAssertTrue( // Let any ongoing fire animation or data processes complete
            app.fakeFireButton.waitForNonExistence(timeout: UITests.Timeouts.fireAnimation),
            "Fire animation didn't finish and cease existing in a reasonable timeframe."
        )
    }
}
