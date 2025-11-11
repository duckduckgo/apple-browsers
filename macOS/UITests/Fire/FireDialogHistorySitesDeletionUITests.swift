//
//  FireDialogHistorySitesDeletionUITests.swift
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

import SharedTestUtilities
import XCTest

/// History View Sites Section Deletion Fire Dialog UI tests
final class FireDialogHistorySitesDeletionUITests: UITestCase, FireDialogUITests {

    override func setUp() {
        super.setUp()
        setUpFireDialogUITests()
    }

    func test_historyView_deleteSingleSite_fromSitesSection() throws {
        throw XCTSkip("Enable when C-S-S Sites is merged")
        let storageURL1 = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        let storageURL2 = URL(string: "https://example.com")!

        // Visit first site with storage
        app.openURL(storageURL1)
        setStorageAndCookies()
        verifyCountersSet()

        // Visit second site
        app.activateAddressBar()
        app.openURL(storageURL2)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Click Sites section button to activate it
        let sitesButton = historyWebView.buttons["Show history for sites"]
        XCTAssertTrue(sitesButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Sites button should exist")
        sitesButton.click()

        // Verify both sites appear in Sites section
        let site1 = historyWebView.staticTexts["privacy-test-pages.site"]
        XCTAssertTrue(site1.waitForExistence(timeout: UITests.Timeouts.elementExistence), "privacy-test-pages.site should be in Sites section")
        let site2 = historyWebView.staticTexts["example.com"]
        XCTAssertTrue(site2.exists, "example.com should be in Sites section")

        // Click on privacy-test-pages.site to select it
        site1.click()

        // Click Delete button
        let deleteButton = historyWebView.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Delete button should appear")
        deleteButton.click()

        // Verify Fire dialog appears (even single site shows dialog for site data deletion)
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should appear for site deletion")

        // Verify no scope pill appears
        XCTAssertFalse(app.fireDialogSegmentedControl.exists, "Scope pill should not appear for sites deletion")

        // Verify no Close windows toggle (sites deletion doesn't close tabs)
        XCTAssertFalse(fireDialogTabsToggle.exists, "Close windows toggle should not appear for sites deletion")

        // Configure toggles: history + cookies
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })

        // Burn
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify privacy-test-pages.site deleted from Sites section, example.com preserved
        XCTAssertFalse(site1.exists, "privacy-test-pages.site should be deleted from Sites section")
        XCTAssertTrue(site2.exists, "example.com should still be in Sites section")

        // Switch back to history view to verify all history for the site is gone
        let showAllHistoryButton = historyWebView.buttons["Show all history"]
        XCTAssertTrue(showAllHistoryButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Show all history button should exist")
        showAllHistoryButton.click()

        XCTAssertFalse(historyWebView.links.element(matching: .keyPath(\.title, contains: "Local Storage")).exists,
                       "privacy-test-pages.site history should be deleted")

        // Verify site is gone from history menu
        app.historyMenu.click()
        XCTAssertFalse(app.menuItems.element(matching: .keyPath(\.title, contains: "Local Storage")).exists,
                       "privacy-test-pages.site should not be in history menu")
        app.historyMenu.typeKey(.escape, modifierFlags: [])

        // Verify storage for privacy-test-pages.site was cleared
        app.activateAddressBar()
        app.openURL(storageURL1)
        verifyCountersCleared()

        // Verify example.com history is preserved
        app.openHistory()
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should reopen")
        XCTAssertTrue(historyWebView.links["Example Domain"].exists, "example.com history should be preserved")
    }

    func test_historyView_deleteMultipleSites_fromSitesSection() throws {
        throw XCTSkip("Enable when C-S-S Sites is merged")
        let storageURL1 = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        let storageURL2 = URL(string: "https://example.com")!
        let storageURL3 = URL(string: "https://duckduckgo.com")!

        // Visit first site with storage
        app.openURL(storageURL1)
        setStorageAndCookies()
        verifyCountersSet()

        // Visit second site
        app.activateAddressBar()
        app.openURL(storageURL2)

        // Visit third site
        app.activateAddressBar()
        app.openURL(storageURL3)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Click Sites section button to activate it
        let sitesButton = historyWebView.buttons["Show history for sites"]
        XCTAssertTrue(sitesButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Sites button should exist")
        sitesButton.click()

        // Verify all sites appear in Sites section
        let site1 = historyWebView.staticTexts["privacy-test-pages.site"]
        XCTAssertTrue(site1.waitForExistence(timeout: UITests.Timeouts.elementExistence), "privacy-test-pages.site should be in Sites section")
        let site2 = historyWebView.staticTexts["example.com"]
        XCTAssertTrue(site2.exists, "example.com should be in Sites section")
        let site3 = historyWebView.staticTexts["duckduckgo.com"]
        XCTAssertTrue(site3.exists, "duckduckgo.com should be in Sites section")

        // Multi-select: Cmd-click site 1 and site 2
        site1.click()
        XCUIElement.perform(withKeyModifiers: [.command]) {
            site2.click()
        }

        // Click Delete button
        let deleteButton = historyWebView.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Delete button should appear")
        deleteButton.click()

        // Verify Fire dialog appears
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should appear for sites deletion")

        // Verify no scope pill appears
        XCTAssertFalse(app.fireDialogSegmentedControl.exists, "Scope pill should not appear for sites deletion")

        // Verify no Close windows toggle
        XCTAssertFalse(fireDialogTabsToggle.exists, "Close windows toggle should not appear for sites deletion")

        // Configure toggles: only history (preserve cookies to test)
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })

        // Burn
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify sites 1 and 2 deleted from Sites section, site 3 preserved
        XCTAssertFalse(site1.exists, "privacy-test-pages.site should be deleted from Sites section")
        XCTAssertFalse(site2.exists, "example.com should be deleted from Sites section")
        XCTAssertTrue(site3.exists, "duckduckgo.com should still be in Sites section")

        // Switch back to history view to verify deleted sites' history is gone
        let showAllHistoryButton = historyWebView.buttons["Show all history"]
        XCTAssertTrue(showAllHistoryButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Show all history button should exist")
        showAllHistoryButton.click()

        XCTAssertFalse(historyWebView.links.element(matching: .keyPath(\.title, contains: "Local Storage")).exists,
                       "privacy-test-pages.site history should be deleted")
        XCTAssertFalse(historyWebView.links["Example Domain"].exists,
                       "example.com history should be deleted")

        // Verify duckduckgo.com history is preserved
        XCTAssertTrue(historyWebView.links.element(matching: .keyPath(\.title, contains: "DuckDuckGo")).exists,
                      "duckduckgo.com history should be preserved")

        // Verify sites are gone from history menu
        app.historyMenu.click()
        XCTAssertFalse(app.menuItems.element(matching: .keyPath(\.title, contains: "Local Storage")).exists,
                       "privacy-test-pages.site should not be in history menu")
        XCTAssertFalse(app.menuItems["Example Domain"].exists,
                       "example.com should not be in history menu")
        XCTAssertTrue(app.menuItems.element(matching: .keyPath(\.title, contains: "DuckDuckGo")).exists,
                      "duckduckgo.com should still be in history menu")
        app.historyMenu.typeKey(.escape, modifierFlags: [])

        // Verify storage for privacy-test-pages.site was preserved (cookies toggle was off)
        app.activateAddressBar()
        app.openURL(storageURL1)
        verifyInitialCountersSet()
    }

    func test_historyView_deleteSingleSite_verifiesOtherSiteDataPreserved() throws {
        throw XCTSkip("Enable when C-S-S Sites is merged")
        let storageURL1 = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        let storageURL2 = URL.testsServer.appendingPathComponent("test.html")

        // Visit first site with storage
        app.openURL(storageURL1)
        setStorageAndCookies()
        verifyCountersSet()

        // Visit second site (would need local server for actual storage, but we verify the flow)
        app.activateAddressBar()
        app.openURL(storageURL2)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Click Sites section button to activate it
        let sitesButton = historyWebView.buttons["Show history for sites"]
        XCTAssertTrue(sitesButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Sites button should exist")
        sitesButton.click()

        // Find and select localhost site
        let localhostSite = historyWebView.staticTexts["localhost"]
        XCTAssertTrue(localhostSite.waitForExistence(timeout: UITests.Timeouts.elementExistence), "localhost should be in Sites section")

        // Click on localhost to select it
        localhostSite.click()

        // Click Delete button
        let deleteButton = historyWebView.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Delete button should appear")
        deleteButton.click()

        // Verify Fire dialog appears
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should appear")

        // Verify no scope pill and no Close windows toggle
        XCTAssertFalse(app.fireDialogSegmentedControl.exists, "Scope pill should not appear")
        XCTAssertFalse(fireDialogTabsToggle.exists, "Close windows toggle should not appear")

        // Configure toggles: history + cookies
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })

        // Burn
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify localhost deleted from Sites section
        XCTAssertFalse(localhostSite.exists, "localhost should be deleted from Sites section")

        // Verify privacy-test-pages.site still exists
        let privacyTestSite = historyWebView.staticTexts["privacy-test-pages.site"]
        XCTAssertTrue(privacyTestSite.exists, "privacy-test-pages.site should still be in Sites section")

        // Verify privacy-test-pages.site storage is preserved (not deleted)
        app.activateAddressBar()
        app.openURL(storageURL1)
        verifyInitialCountersSet()
    }

    func test_historyView_deleteAllHistory_viaSitesSection_deleteAllButton() throws {
        throw XCTSkip("Enable when C-S-S Sites is merged")
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

        // Click Sites section button to activate it
        let sitesButton = historyWebView.buttons["Show history for sites"]
        XCTAssertTrue(sitesButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Sites button should exist")
        sitesButton.click()

        // Click "Delete All" button in Sites section
        let deleteAllButton = historyWebView.buttons["Delete history for sites"]
        XCTAssertTrue(deleteAllButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Delete All button should exist in Sites section")
        deleteAllButton.click()

        // Verify Fire dialog opens
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Verify no scope pill appears
        XCTAssertFalse(app.fireDialogSegmentedControl.exists, "Scope pill should not appear for Delete All")

        // Configure toggles: history + cookies
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })

        // Burn
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify History view still open and now empty
        XCTAssertTrue(historyWebView.exists, "History view should still be open")

        let emptyHistoryText = historyWebView.staticTexts["No browsing history yet."]
        XCTAssertTrue(emptyHistoryText.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Empty history message should appear after deleting all history")

        // Verify storage was cleared
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyCountersCleared()
    }

    func test_historyView_deleteAllHistory_viaSitesSection_hoverAndDelete() throws {
        throw XCTSkip("Enable when C-S-S Sites is merged")
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

        // Click Sites section button to activate it
        let sitesButton = historyWebView.buttons["Show history for sites"]
        XCTAssertTrue(sitesButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Sites button should exist")
        sitesButton.click()

        // Hover Sites button to reveal "Delete all history" button
        sitesButton.hover()

        // Click "Delete all history" button
        let deleteAllHistoryButton = historyWebView.buttons["Delete history for sites"]
        XCTAssertTrue(deleteAllHistoryButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Delete all history button should appear on hover")
        deleteAllHistoryButton.click()

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

}
