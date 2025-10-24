//
//  FireDialogHistoryDeleteAllUITests.swift
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

/// History View Delete All Fire Dialog UI tests
final class FireDialogHistoryDeleteAllUITests: UITestCase, FireDialogUITests {

    override func setUp() {
        super.setUp()
        setUpFireDialogUITests()
    }

    func test_historyView_deleteAllHistory_viaShowAllHistoryHover() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!

        // Visit sites and set storage
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        let site1Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: site1Title)

        let site2Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: site2Title)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Verify sites appear in history
        XCTAssertTrue(historyWebView.links[site1Title].waitForExistence(timeout: UITests.Timeouts.elementExistence), "Site 1 should be in history")
        XCTAssertTrue(historyWebView.links[site2Title].exists, "Site 2 should be in history")

        // Hover "Show all history" button to reveal "Delete all history" button
        let showAllHistoryButton = historyWebView.buttons["Show all history"]
        XCTAssertTrue(showAllHistoryButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Show all history button should exist")
        showAllHistoryButton.hover()

        // Click "Delete all history" button
        let deleteAllHistoryButton = historyWebView.buttons["Delete all history"]
        XCTAssertTrue(deleteAllHistoryButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Delete all history button should appear on hover")
        deleteAllHistoryButton.click()

        // Verify Fire dialog opens
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Verify no scope pill appears (Everything scope should be selected by default for Delete All)
        XCTAssertFalse(app.fireDialogSegmentedControl.exists, "Scope pill should not appear for Delete All")

        // Configure toggles: only history
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })

        // Burn
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify history was cleared and now shows empty state
        XCTAssertTrue(historyWebView.exists, "History view should still be open")

        let emptyHistoryText = historyWebView.staticTexts["No browsing history yet."]
        XCTAssertTrue(emptyHistoryText.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Empty history message should appear after deleting all history")

        // Verify storage was preserved (cookies toggle was off)
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyInitialCountersSet()
    }

    func test_historyView_deleteAllHistory_viaDeleteAllButton_onlyTabsToggle() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!

        // Visit sites and set storage
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        let site1Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: site1Title)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Click "Delete All" button directly
        let deleteAllButton = historyWebView.buttons["Delete All"]
        XCTAssertTrue(deleteAllButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Delete All button should exist")
        deleteAllButton.click()

        // Verify Fire dialog opens
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Verify no scope pill appears
        XCTAssertFalse(app.fireDialogSegmentedControl.exists, "Scope pill should not appear for Delete All")

        // Configure toggles: only tabs (close windows)
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })

        // Burn
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify window closed and new tab opened
        XCTAssertEqual(app.windows.count, 1, "Should have 1 window")
        XCTAssertTrue(app.tabs["New Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence), "New Tab should be open")

        // Verify history was preserved (history toggle was off)
        app.openHistory()
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should reopen")
        XCTAssertTrue(historyWebView.links[site1Title].waitForExistence(timeout: UITests.Timeouts.elementExistence), "Site 1 should still be in history")
        XCTAssertTrue(historyWebView.links.element(matching: .keyPath(\.title, contains: "Local Storage")).exists, "Storage site should still be in history")

        // Verify storage was preserved (cookies toggle was off)
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyInitialCountersSet()
    }

    func test_historyView_deleteAllHistory_viaDeleteAllButton_onlyCookiesToggle() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!

        // Visit sites and set storage
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        let site1Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: site1Title)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Click "Delete All" button directly
        let deleteAllButton = historyWebView.buttons["Delete All"]
        XCTAssertTrue(deleteAllButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Delete All button should exist")
        deleteAllButton.click()

        // Verify Fire dialog opens
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Verify no scope pill appears
        XCTAssertFalse(app.fireDialogSegmentedControl.exists, "Scope pill should not appear for Delete All")

        // Configure toggles: only cookies
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })

        // Burn
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify History view still open
        XCTAssertTrue(historyWebView.exists, "History view should still be open")

        // Verify history was preserved (history toggle was off)
        XCTAssertTrue(historyWebView.links[site1Title].exists, "Site 1 should still be in history")
        XCTAssertTrue(historyWebView.links.element(matching: .keyPath(\.title, contains: "Local Storage")).exists, "Storage site should still be in history")

        // Verify storage was cleared (cookies toggle was on)
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyCountersCleared()
    }

    func test_historyView_deleteAllHistory_viaDeleteAllButton_allTogglesActive() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!

        // Visit sites and set storage
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        let site1Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: site1Title)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Click "Delete All" button directly
        let deleteAllButton = historyWebView.buttons["Delete All"]
        XCTAssertTrue(deleteAllButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Delete All button should exist")
        deleteAllButton.click()

        // Verify Fire dialog opens
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Verify no scope pill appears
        XCTAssertFalse(app.fireDialogSegmentedControl.exists, "Scope pill should not appear for Delete All")

        // Configure toggles: all active
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })

        // Burn
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify window closed and new tab opened
        XCTAssertEqual(app.windows.count, 1, "Should have 1 window")
        XCTAssertTrue(app.tabs["New Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence), "New Tab should be open")

        // Verify history was cleared
        app.openHistory()
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should reopen")

        let emptyHistoryText = historyWebView.staticTexts["No browsing history yet."]
        XCTAssertTrue(emptyHistoryText.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Empty history message should appear after deleting all history")

        // Verify storage was cleared
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyCountersCleared()
    }

}
