//
//  FireDialogGeneralUITests.swift
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

/// General Fire Dialog UI tests covering basic functionality
final class FireDialogGeneralUITests: UITestCase, FireDialogUITests {

    override func setUp() {
        super.setUp()
        setUpFireDialogUITests()
    }

    func test_fireDialog_clearsHistoryWhenBurnButtonPressed() throws {
        let pageTitle = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.openSite(pageTitle: pageTitle)

        // Open History window to verify site appears there
        app.openHistory()
        let historyTab = app.tabs["History"]
        XCTAssertTrue(historyTab.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History tab should be open")

        // Verify site appears in History window
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History webView should exist")
        let siteInHistoryView = historyWebView.staticTexts[pageTitle]
        XCTAssertTrue(
            siteInHistoryView.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Site should appear in History view"
        )

        // Open Fire dialog via history menu and verify site appears in history menu
        app.historyMenu.click()
        let siteMenuItemInHistory = app.menuItems[pageTitle]
        XCTAssertTrue(
            siteMenuItemInHistory.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Site should appear in history menu"
        )
        app.clearAllHistoryMenuItem.click()
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Select "Everything" scope (All data)
        app.fireDialogSegmentedControl.buttons["Everything"].click()

        // Disable tabs toggle (to not close windows), enable history and cookies
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify History window is still open
        XCTAssertTrue(historyTab.exists, "History tab should still be open after burning")
        XCTAssertTrue(historyWebView.exists, "History webView should still exist after burning")

        // Verify history is now empty
        let emptyHistoryText = historyWebView.staticTexts["No browsing history yet."]
        XCTAssertTrue(emptyHistoryText.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Empty history message should appear")

        // Verify site is no longer in history menu
        app.historyMenu.click()
        XCTAssertFalse(siteMenuItemInHistory.exists, "Site should not appear in history menu after burning")
    }

    func test_fireDialog_clearsCookieBasedLogin() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        app.openURL(storageURL)

        setStorageAndCookies()
        verifyCountersSet()

        // Navigate away
        let tempPageTitle = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: tempPageTitle)

        // Open Fire dialog via keyboard shortcut (Cmd+Shift+Backspace)
        app.typeKey(.delete, modifierFlags: [.command, .shift])
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Select "Everything" scope (All data)
        app.fireDialogSegmentedControl.buttons["Everything"].click()

        // Burn with all toggles enabled
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Navigate back to storage test page and verify storage was cleared (window reopened after burn)
        app.openURL(storageURL)
        verifyCountersCleared()
    }

    func test_fireDialog_preservesFireproofedSiteCookies() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        app.openURL(storageURL)

        setStorageAndCookies()
        verifyCountersSet()

        // Open Fire dialog via keyboard shortcut and fireproof current site
        app.typeKey(.delete, modifierFlags: [.command, .shift])
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Select "Everything" scope (All data)
        app.fireDialogSegmentedControl.buttons["Everything"].click()

        // Burn with all toggles enabled
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireproofCurrentSite()

        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify storage preserved for fireproofed site
        app.openURL(storageURL)
        verifyInitialCountersSet()
    }

    func test_fireDialog_preservesCookiesWhenToggleDisabled() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        app.openURL(storageURL)

        setStorageAndCookies()
        verifyCountersSet()

        // Burn with cookies toggle DISABLED (tabs and history enabled)
        // Open Fire dialog via Fire button
        app.fireButton.click()
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Select "Everything" scope (All data)
        app.fireDialogSegmentedControl.buttons["Everything"].click()

        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify storage preserved (toggle was disabled, window reopened after burn)
        app.openURL(storageURL)
        verifyInitialCountersSet()
    }

    func test_fireDialog_closesWindowWhenTabsToggleEnabled() throws {
        // Open multiple tabs in the window
        let page1Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.openSite(pageTitle: page1Title)

        app.openNewTab()
        let page2Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.openSite(pageTitle: page2Title)

        // Record initial window state
        let initialTabCount = app.tabs.count
        XCTAssertEqual(initialTabCount, 2, "Should have 2 tabs before burning")

        // Open Fire dialog via Fire button
        app.fireButton.click()
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Select "Everything" scope (All data)
        app.fireDialogSegmentedControl.buttons["Everything"].click()

        // Enable all toggles
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })

        fireDialogBurnButton.click()

        // Wait for Fire animation
        waitForFireAnimationToComplete()

        // Verify window stayed open but tabs were cleared and replaced with new tab
        let finalWindowCount = app.windows.count
        XCTAssertEqual(finalWindowCount, 1, "Should have exactly 1 window")

        // Should have 1 new tab (the replacement tab)
        let finalTabCount = app.tabs.count
        XCTAssertEqual(finalTabCount, 1, "Should have 1 new tab after burning")

        // Verify New Tab is open
        XCTAssertTrue(app.tabs["New Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence), "New Tab should be open")
        XCTAssertTrue(app.webViews["New Tab Page"].exists, "New Tab Page webView should be visible")

        // Verify old tabs are gone
        XCTAssertFalse(app.tabs[page1Title].exists, "Old tab 1 should not exist")
        XCTAssertFalse(app.tabs[page2Title].exists, "Old tab 2 should not exist")
    }

    func test_fireDialog_keepsHistoryWhenToggleDisabled() throws {
        // Visit storage test site to generate history and set cookies/storage
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        app.openURL(storageURL)

        setStorageAndCookies()
        verifyCountersSet()

        // Open History window to verify site appears there
        app.openHistory()
        let historyTab = app.tabs["History"]
        XCTAssertTrue(historyTab.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History tab should be open")

        // Verify site appears in History window
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History webView should exist")
        let siteInHistoryView = historyWebView.staticTexts["Local Storage & Cookies storing"]
        XCTAssertTrue(
            siteInHistoryView.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Site should appear in History view"
        )

        // Open Fire dialog via history menu and verify site appears in history menu
        app.historyMenu.click()
        let siteMenuItemInHistory = app.menuItems["Local Storage & Cookies storing"]
        XCTAssertTrue(
            siteMenuItemInHistory.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Site should appear in history menu"
        )
        app.clearAllHistoryMenuItem.click()
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Select "Everything" scope (All data)
        app.fireDialogSegmentedControl.buttons["Everything"].click()

        // Enable tabs/cookies, disable history toggle
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })

        // Burn with history toggle off
        fireDialogBurnButton.click()

        // Wait for Fire animation
        waitForFireAnimationToComplete()

        // Verify window stayed open with New Tab
        XCTAssertEqual(app.windows.count, 1, "Should have exactly 1 window")
        XCTAssertEqual(app.tabs.count, 1, "Should have 1 new tab after burning")
        XCTAssertTrue(app.tabs["New Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence), "New Tab should be open")
        XCTAssertTrue(app.webViews["New Tab Page"].exists, "New Tab Page webView should be visible")

        // Reopen History window to verify site is still in it (windows were closed by tabs toggle)
        app.openHistory()
        XCTAssertTrue(historyTab.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History tab should be reopenable")
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History webView should exist after reopening")
        XCTAssertTrue(siteInHistoryView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Site should still appear in History view when history toggle is off")

        // Verify site is STILL in history menu (not cleared)
        app.historyMenu.click()
        XCTAssertTrue(
            siteMenuItemInHistory.exists,
            "Site should still appear in history menu when history toggle is off"
        )
        app.historyMenu.typeKey(.escape, modifierFlags: [])

        // Verify site data (cookies/storage) WAS cleared despite history being kept
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyCountersCleared()
    }

    func test_fireDialog_clearsOnlyHistory() throws {
        // Visit storage test site to generate history and set cookies/storage
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        app.openURL(storageURL)

        setStorageAndCookies()
        verifyCountersSet()

        // Open History window to verify site appears there
        app.openHistory()
        let historyTab = app.tabs["History"]
        XCTAssertTrue(historyTab.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History tab should be open")

        // Verify site appears in History window
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History webView should exist")
        let siteInHistoryView = historyWebView.staticTexts["Local Storage & Cookies storing"]
        XCTAssertTrue(
            siteInHistoryView.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Site should appear in History view"
        )

        // Open Fire dialog via history menu and verify site appears in history menu
        app.historyMenu.click()
        let siteMenuItemInHistory = app.menuItems["Local Storage & Cookies storing"]
        XCTAssertTrue(
            siteMenuItemInHistory.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Site should appear in history menu"
        )
        app.clearAllHistoryMenuItem.click()
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Select "Everything" scope (All data)
        app.fireDialogSegmentedControl.buttons["Everything"].click()

        // Disable tabs and cookies, enable history only
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify tabs were NOT closed (tabs toggle was disabled)
        XCTAssertEqual(app.windows.count, 1, "Should have exactly 1 window")
        XCTAssertTrue(historyTab.exists, "History tab should still be open after burning (tabs toggle was off)")
        XCTAssertTrue(historyWebView.exists, "History webView should still exist after burning")

        // Verify site is no longer in History view
        XCTAssertTrue(siteInHistoryView.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Site should not appear in History view after burning")

        // Verify site is no longer in history menu
        app.historyMenu.click()
        XCTAssertFalse(siteMenuItemInHistory.exists, "Site should not appear in history menu after burning")
        app.historyMenu.typeKey(.escape, modifierFlags: [])

        // Verify site data (cookies/storage) WAS preserved (toggle was disabled)
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyInitialCountersSet()
    }

    func test_fireDialog_clearsOnlyCookies() throws {
        // Visit storage test site to generate history and set cookies/storage
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        app.openURL(storageURL)

        setStorageAndCookies()
        verifyCountersSet()

        // Open History window to verify site appears there
        app.openHistory()
        let historyTab = app.tabs["History"]
        XCTAssertTrue(historyTab.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History tab should be open")

        // Verify site appears in History window
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History webView should exist")
        let siteInHistoryView = historyWebView.staticTexts["Local Storage & Cookies storing"]
        XCTAssertTrue(
            siteInHistoryView.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Site should appear in History view"
        )

        // Open Fire dialog via keyboard shortcut
        app.typeKey(.delete, modifierFlags: [.command, .shift])
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Select "Everything" scope (All data)
        app.fireDialogSegmentedControl.buttons["Everything"].click()

        // Disable tabs and history, enable cookies only
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify tabs were NOT closed (tabs toggle was disabled)
        XCTAssertEqual(app.windows.count, 1, "Should have exactly 1 window")
        XCTAssertTrue(historyTab.exists, "History tab should still be open after burning (tabs toggle was off)")
        XCTAssertTrue(historyWebView.exists, "History webView should still exist after burning")

        // Verify site is still in History view
        XCTAssertTrue(siteInHistoryView.exists, "Site should still appear in History view when history toggle is off")

        // Verify site is still in history menu
        app.historyMenu.click()
        let siteMenuItemInHistory = app.menuItems["Local Storage & Cookies storing"]
        XCTAssertTrue(
            siteMenuItemInHistory.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Site should still appear in history menu when history toggle is off"
        )
        app.historyMenu.typeKey(.escape, modifierFlags: [])

        // Verify site data (cookies/storage) WAS cleared
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyCountersCleared()
    }

    func test_fireDialog_closesOnlyTabsAndWindows() throws {
        // Visit storage test site to generate history and set cookies/storage
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        app.openURL(storageURL)

        setStorageAndCookies()
        verifyCountersSet()

        // Open History window to verify site appears there
        app.openHistory()
        let historyTab = app.tabs["History"]
        XCTAssertTrue(historyTab.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History tab should be open")

        // Verify site appears in History window
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History webView should exist")
        let siteInHistoryView = historyWebView.staticTexts["Local Storage & Cookies storing"]
        XCTAssertTrue(
            siteInHistoryView.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Site should appear in History view"
        )

        // Open Fire dialog via Fire button
        app.fireButton.click()
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Select "Everything" scope (All data)
        app.fireDialogSegmentedControl.buttons["Everything"].click()

        // Enable tabs only, disable history and cookies
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify window stayed open with New Tab
        XCTAssertEqual(app.windows.count, 1, "Should have exactly 1 window")
        XCTAssertEqual(app.tabs.count, 1, "Should have 1 new tab after burning")
        XCTAssertTrue(app.tabs["New Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence), "New Tab should be open")
        XCTAssertTrue(app.webViews["New Tab Page"].exists, "New Tab Page webView should be visible")

        // Reopen History window to verify site is still in it
        app.openHistory()
        XCTAssertTrue(historyTab.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History tab should be reopenable")
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History webView should exist after reopening")
        XCTAssertTrue(siteInHistoryView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Site should still appear in History view when history toggle is off")

        // Verify site is still in history menu
        app.historyMenu.click()
        let siteMenuItemInHistory = app.menuItems["Local Storage & Cookies storing"]
        XCTAssertTrue(
            siteMenuItemInHistory.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Site should still appear in history menu when history toggle is off"
        )
        app.historyMenu.typeKey(.escape, modifierFlags: [])

        // Verify site data (cookies/storage) WAS preserved (toggle was disabled)
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyInitialCountersSet()
    }

    func test_fireDialog_burnButtonDisabledWhenAllTogglesOff() throws {
        // Visit a site to have data available
        let pageTitle = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.openSite(pageTitle: pageTitle)

        // Open Fire dialog via history menu
        app.historyMenu.click()
        app.clearAllHistoryMenuItem.click()
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Test "Tab" scope with tabs toggle
        app.fireDialogSegmentedControl.buttons["Tab"].click()

        // Disable all toggles
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })

        // Verify burn button is disabled
        XCTAssertFalse(fireDialogBurnButton.isEnabled, "Burn button should be disabled when all toggles are off in Tab scope")

        // Test tabs toggle (1st toggle)
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        XCTAssertTrue(fireDialogBurnButton.isEnabled, "Burn button should be enabled when tabs toggle is on in Tab scope")
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        XCTAssertFalse(fireDialogBurnButton.isEnabled, "Burn button should be disabled when tabs toggle is off in Tab scope")

        // Test "Window" scope with history toggle
        app.fireDialogSegmentedControl.buttons["Window"].click()

        // Disable all toggles
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })

        // Verify burn button is still disabled (all toggles off)
        XCTAssertFalse(fireDialogBurnButton.isEnabled, "Burn button should be disabled when all toggles are off in Window scope")

        // Test history toggle (2nd toggle)
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        XCTAssertTrue(fireDialogBurnButton.isEnabled, "Burn button should be enabled when history toggle is on in Window scope")
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        XCTAssertFalse(fireDialogBurnButton.isEnabled, "Burn button should be disabled when history toggle is off in Window scope")

        // Test "Everything" scope with cookies toggle
        app.fireDialogSegmentedControl.buttons["Everything"].click()

        // Disable all toggles
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })

        // Verify burn button is still disabled (all toggles off)
        XCTAssertFalse(fireDialogBurnButton.isEnabled, "Burn button should be disabled when all toggles are off in Everything scope")

        // Test cookies toggle (3rd toggle)
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        XCTAssertTrue(fireDialogBurnButton.isEnabled, "Burn button should be enabled when cookies toggle is on in Everything scope")
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        XCTAssertFalse(fireDialogBurnButton.isEnabled, "Burn button should be disabled when cookies toggle is off in Everything scope")

        // Cancel the dialog
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(fireDialogTitle.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should close")
    }
}
