//
//  FireDialogHistoryMultiSelectDeletionUITests.swift
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

/// History View Multi-select Deletion Fire Dialog UI tests
final class FireDialogHistoryMultiSelectDeletionUITests: UITestCase, FireDialogUITests {

    override func setUp() {
        super.setUp()
        setUpFireDialogUITests()
    }

    func test_historyView_deleteMultipleRecords_viaRightClick_onlyHistory() throws {
        let site1Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.openSite(pageTitle: site1Title)

        let site2Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: site2Title)

        let site3Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: site3Title)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Verify all sites exist
        let site1Link = historyWebView.links[site1Title]
        XCTAssertTrue(site1Link.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Site 1 should be in history")
        let site2Link = historyWebView.links[site2Title]
        XCTAssertTrue(site2Link.exists, "Site 2 should be in history")
        let site3Link = historyWebView.links[site3Title]
        XCTAssertTrue(site3Link.exists, "Site 3 should be in history")

        // Multi-select: Cmd-click site 1 and site 2
        site1Link.click()
        XCUIElement.perform(withKeyModifiers: [.command]) {
            site2Link.click()
        }

        // Right-click on selected items and select Delete from context menu
        site1Link.rightClick()
        try app.clickContextMenuItem { $0.title == "Delete" }

        // Verify Fire dialog DOES appear for multi-select
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should appear for multi-select deletion")

        // Verify no scope pill appears
        XCTAssertFalse(app.fireDialogSegmentedControl.exists, "Scope pill should not appear for multi-select deletion")

        // Configure toggles: only history
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })

        // Burn
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify sites 1 and 2 deleted, site 3 preserved
        XCTAssertFalse(site1Link.exists, "Site 1 should be deleted")
        XCTAssertFalse(site2Link.exists, "Site 2 should be deleted")
        XCTAssertTrue(site3Link.exists, "Site 3 should still be in history")
    }

    func test_historyView_deleteMultipleRecords_viaDeleteKey_historyAndCookies() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!

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

        // Verify all sites exist
        let site1Link = historyWebView.links[site1Title]
        XCTAssertTrue(site1Link.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Site 1 should be in history")
        let site2Link = historyWebView.links[site2Title]
        XCTAssertTrue(site2Link.exists, "Site 2 should be in history")

        // Multi-select: Cmd-click site 1 and site 2
        site1Link.click()
        XCUIElement.perform(withKeyModifiers: [.command]) {
            site2Link.click()
        }

        // Press Delete key
        app.typeKey(.delete, modifierFlags: [])

        // Verify Fire dialog appears
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should appear for multi-select deletion")

        // Verify no scope pill appears
        XCTAssertFalse(app.fireDialogSegmentedControl.exists, "Scope pill should not appear for multi-select deletion")

        // Configure toggles: history + cookies
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })

        // Burn
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify sites deleted
        XCTAssertFalse(site1Link.exists, "Site 1 should be deleted")
        XCTAssertFalse(site2Link.exists, "Site 2 should be deleted")

        // Verify storage was cleared (cookies toggle was on)
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyInitialCountersSet()
    }

    func test_historyView_deleteMultipleRecords_viaDeleteButton_allToggles() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!

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

        // Verify all sites exist
        let site1Link = historyWebView.links[site1Title]
        XCTAssertTrue(site1Link.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Site 1 should be in history")
        let site2Link = historyWebView.links[site2Title]
        XCTAssertTrue(site2Link.exists, "Site 2 should be in history")

        // Multi-select: Cmd-click site 1 and site 2
        site1Link.click()
        XCUIElement.perform(withKeyModifiers: [.command]) {
            site2Link.click()
        }

        // Click Delete button
        let deleteButton = historyWebView.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Delete button should appear when items are selected")
        deleteButton.click()

        // Verify Fire dialog appears
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should appear for multi-select deletion")

        // Verify no scope pill appears
        XCTAssertFalse(app.fireDialogSegmentedControl.exists, "Scope pill should not appear for multi-select deletion")

        // Verify tabs toggle exists for multi-select (since it can close windows with history)
        XCTAssertFalse(fireDialogTabsToggle.exists, "Tabs toggle should not exist for multi-select deletion")

        // Configure toggles: all active
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })

        // Burn
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // verify sites deleted
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should reopen")
        XCTAssertFalse(historyWebView.links[site1Title].exists, "Site 1 should be deleted")
        XCTAssertFalse(historyWebView.links[site2Title].exists, "Site 2 should be deleted")
        XCTAssertTrue(historyWebView.links["Local Storage & Cookies storing"].exists, "Storage Site should still be in history")

        // Refresh history (Cmd+R)
        app.typeKey("r", modifierFlags: [.command])
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should still exist after refresh")

        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should reopen")
        XCTAssertFalse(historyWebView.links[site1Title].exists, "Site 1 should be deleted")
        XCTAssertFalse(historyWebView.links[site2Title].exists, "Site 2 should be deleted")
        XCTAssertTrue(historyWebView.links["Local Storage & Cookies storing"].exists, "Storage Site should still be in history")

        // Verify storage was cleared
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyInitialCountersSet()
    }

    func test_historyView_deleteMultipleRecords_viaHoverGroupButton() throws {
        let site1Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.openSite(pageTitle: site1Title)

        let site2Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: site2Title)

        let site3Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: site3Title)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Verify all sites exist
        let site1Link = historyWebView.links[site1Title]
        XCTAssertTrue(site1Link.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Site 1 should be in history")
        let site2Link = historyWebView.links[site2Title]
        XCTAssertTrue(site2Link.exists, "Site 2 should be in history")
        let site3Link = historyWebView.links[site3Title]
        XCTAssertTrue(site3Link.exists, "Site 3 should be in history")

        // Multi-select: Cmd-click site 1 and site 2
        site1Link.click()
        XCUIElement.perform(withKeyModifiers: [.command]) {
            site2Link.click()
        }

        // Find the parent group containing site1Link
        let site1Group = historyWebView.groups.containing(.link, identifier: site1Title).firstMatch
        XCTAssertTrue(site1Group.exists, "Site 1 group should exist")

        // Hover the link to reveal the context menu button
        site1Link.hover()

        // Find the button that appears on hover and click using coordinates
        let groupButton = site1Group.buttons.firstMatch
        XCTAssertTrue(groupButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Group button should appear on hover")

        // Use button's x coordinate and link's y coordinate to click the correct button
        let buttonFrame = groupButton.frame
        let linkFrame = site1Link.frame
        let webViewFrame = historyWebView.frame

        // Calculate normalized coordinates relative to the web view
        let normalizedX = (buttonFrame.midX - webViewFrame.minX) / webViewFrame.width
        let normalizedY = (linkFrame.midY - webViewFrame.minY) / webViewFrame.height

        let coordinate = historyWebView.coordinate(withNormalizedOffset: CGVector(dx: normalizedX, dy: normalizedY))
        coordinate.click()

        // Click Delete from context menu
        try app.clickContextMenuItem { $0.title == "Delete" }

        // Verify Fire dialog appears
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should appear for multi-select deletion")

        // Verify no scope pill appears
        XCTAssertFalse(app.fireDialogSegmentedControl.exists, "Scope pill should not appear for multi-select deletion")

        // Configure toggles: only history
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })

        // Burn
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify sites 1 and 2 deleted, site 3 preserved
        XCTAssertFalse(site1Link.exists, "Site 1 should be deleted")
        XCTAssertFalse(site2Link.exists, "Site 2 should be deleted")
        XCTAssertTrue(site3Link.exists, "Site 3 should still be in history")
    }

}
