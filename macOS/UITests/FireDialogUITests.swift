//
//  FireDialogUITests.swift
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

class FireDialogUITests: UITestCase {

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
        // Enable feature flags for new Fire dialog, History view, and History view Sites section
        // TO DO: Enable Sites Section when C-S-S implementation is merged in
        app = XCUIApplication.setUp(featureFlags: ["historyView": true, "fireDialog": true, /*"historyViewSitesSection": true*/])
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

    // MARK: - Tests

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

    // MARK: - Tab Scope Tests

    func test_fireDialog_tabScope_closesOnlyCurrentTab() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        let currentTabSite1URL = URL(string: "https://duckduckgo.com")!
        let currentTabSite2URL = URL(string: "https://wikipedia.org")!
        let backgroundTab1URL = URL(string: "https://github.com")!
        let backgroundTab2URL = URL(string: "https://stackoverflow.com/questions")!
        let tab2Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let tab3Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)

        // Setup first window with multiple tabs (will become background)
        app.openURL(backgroundTab1URL)
        app.openNewTab()
        app.openURL(backgroundTab2URL)

        // Open new window (becomes foreground - the one to burn)
        app.typeKey("n", modifierFlags: [.command])

        // Setup current tab with multiple sites visited
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        // Visit more sites in the same tab (different domains)
        app.activateAddressBar()
        app.openURL(currentTabSite1URL)

        app.activateAddressBar()
        app.openURL(currentTabSite2URL)

        // Open additional tabs in the same window (localhost with different titles)
        app.openNewTab()
        app.openSite(pageTitle: tab2Title)
        app.openNewTab()
        app.openSite(pageTitle: tab3Title)

        // Switch back to first tab (the one with multiple sites visited)
        let firstTab = app.tabs.element(boundBy: 0) // First tab in current window
        firstTab.click()

        // Verify we have 2 windows and 3 tabs in current window
        XCTAssertEqual(app.windows.count, 2, "Should have 2 windows")
        let initialTabCount = app.tabs.count
        XCTAssertEqual(initialTabCount, 3, "Should have 3 tabs before burning")

        // Open Fire dialog via Fire button
        app.fireButton.click()
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Select "Tab" scope
        app.fireDialogSegmentedControl.buttons["Tab"].click()

        // Enable cookies toggle to verify Sites overlay
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })

        // Click the info button to open sites overlay and verify only current tab's domains
        app.fireDialogCookiesInfoButton.click()

        let sitesOverlay = fireDialog.groups.containing(.button, identifier: "FireDialogView.sitesOverlayCloseButton").firstMatch
        XCTAssertTrue(sitesOverlay.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Sites overlay should be open")

        let overlayList = sitesOverlay.scrollViews.firstMatch
        XCTAssertTrue(overlayList.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Sites list should exist")

        // Verify current tab's domains appear
        let privacyTestDomain = overlayList.staticTexts["privacy-test-pages.site"]
        XCTAssertTrue(privacyTestDomain.exists, "privacy-test-pages.site domain should appear in sites overlay")

        let duckDuckGoDomain = overlayList.staticTexts["duckduckgo.com"]
        XCTAssertTrue(duckDuckGoDomain.exists, "duckduckgo.com domain should appear in sites overlay")

        let wikipediaDomain = overlayList.staticTexts["wikipedia.org"]
        XCTAssertTrue(wikipediaDomain.exists, "wikipedia.org domain should appear in sites overlay")

        // Verify background window and other tabs' domains do NOT appear
        XCTAssertFalse(overlayList.staticTexts["github.com"].exists, "github.com (from background window) should NOT appear")
        XCTAssertFalse(overlayList.staticTexts["stackoverflow.com"].exists, "stackoverflow.com (from background window) should NOT appear")
        XCTAssertFalse(overlayList.staticTexts["localhost"].exists, "localhost (from other tabs in current window) should NOT appear")

        // Close the sites overlay
        app.fireDialogSitesOverlayCloseButton.click()
        XCTAssertTrue(sitesOverlay.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Sites overlay should close")

        // Enable all toggles
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify only current tab was closed, other tabs in current window remain
        XCTAssertEqual(app.windows.count, 2, "Should still have 2 windows")
        XCTAssertEqual(app.tabs.count, 2, "Should have 2 tabs after burning (first tab was closed)")
        // Verify the other two tabs still exist (proving the first tab was the one closed)
        XCTAssertTrue(app.tabs[tab2Title].exists, "Tab 2 should still exist")
        XCTAssertTrue(app.tabs[tab3Title].exists, "Tab 3 should still exist")

        // Verify background window was not affected (still has 2 tabs)
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertEqual(backgroundWindow.tabs.count, 2, "Background window should still have 2 tabs")

        // Verify history for burnt tab was removed
        app.openHistory()
        let historyWebView = app.webViews["History"]

        // Verify background window's domains ARE still in history (check for github.com or stackoverflow.com in page titles)
        XCTAssertTrue(historyWebView.links.element(matching: .keyPath(\.title, contains: "GitHub")).waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Background window's GitHub site should still be in history")
        XCTAssertTrue(historyWebView.links.element(matching: .keyPath(\.title, contains: "Stack Overflow")).exists,
                      "Background window's Stack Overflow site should still be in history")
        XCTAssertTrue(historyWebView.links[tab2Title].exists, "tab2 in current window should still be in history")
        XCTAssertTrue(historyWebView.links[tab3Title].exists, "tab3 in current window should still be in history")

        // Verify current tab's sites (privacy-test-pages.site, duckduckgo.com, wikipedia.org) are NOT in history
        XCTAssertFalse(historyWebView.links.element(matching: .keyPath(\.title, contains: "Local Storage")).exists, "Current tab's privacy-test-pages site should not be in history")
        XCTAssertFalse(historyWebView.links.element(matching: .keyPath(\.title, contains: "DuckDuckGo")).exists, "Current tab's DuckDuckGo site should not be in history")
        XCTAssertFalse(historyWebView.links.element(matching: .keyPath(\.title, contains: "Wikipedia")).exists, "Current tab's Wikipedia site should not be in history")

        // Verify site data was cleared
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyCountersCleared()
    }

    func test_fireDialog_tabScope_clearsOnlyCurrentTabHistory() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        let currentTabSite1 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let currentTabSite2 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let currentTabSite3 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let backgroundTab1URL = URL(string: "https://github.com")!
        let backgroundTab2URL = URL(string: "https://stackoverflow.com/questions")!
        let tab2Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let tab3Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)

        // Setup first window with multiple tabs (will become background)
        app.openURL(backgroundTab1URL)
        app.openNewTab()
        app.openURL(backgroundTab2URL)

        // Open new window (becomes foreground - the one to burn)
        app.typeKey("n", modifierFlags: [.command])

        // Visit storage page and set cookies/storage
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        // Visit multiple sites in current tab
        app.activateAddressBar()
        app.openSite(pageTitle: currentTabSite1)
        app.activateAddressBar()
        app.openSite(pageTitle: currentTabSite2)
        app.activateAddressBar()
        app.openSite(pageTitle: currentTabSite3)

        // Go back once to enable both back and forward buttons
        app.typeKey("[", modifierFlags: [.command])

        // Verify back/forward buttons are enabled
        let backButton = app.windows.firstMatch.buttons["NavigationBarViewController.BackButton"].firstMatch
        let forwardButton = app.buttons["NavigationBarViewController.ForwardButton"].firstMatch
        XCTAssertTrue(backButton.isEnabled, "Back button should be enabled before burning")
        XCTAssertTrue(forwardButton.isEnabled, "Forward button should be enabled before burning")

        // Open additional tabs in the same window
        app.openNewTab()
        app.openSite(pageTitle: tab2Title)
        app.openNewTab()
        app.openSite(pageTitle: tab3Title)

        // Switch back to first tab
        app.tabs[currentTabSite2].click()

        // Open Fire dialog via keyboard shortcut
        app.typeKey(.delete, modifierFlags: [.command, .shift])
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Select "Tab" scope
        app.fireDialogSegmentedControl.buttons["Tab"].click()

        // Enable only history toggle (tabs and cookies off)
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify tabs were not closed (all 3 tabs should still exist)
        XCTAssertEqual(app.tabs.count, 3, "Should still have 3 tabs (tabs toggle was off)")
        XCTAssertTrue(app.tabs[currentTabSite2].exists, "First tab should still be open")
        XCTAssertTrue(app.tabs[tab2Title].exists, "Second tab should still exist")
        XCTAssertTrue(app.tabs[tab3Title].exists, "Third tab should still exist")

        // Open History to verify history was cleared
        app.openHistory()
        let historyWebView = app.webViews["History"]

        // Verify background window's history was preserved
        XCTAssertTrue(historyWebView.links.element(matching: .keyPath(\.title, contains: "GitHub")).waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Background window's GitHub site should still be in history")

        // Verify other tabs in current window still have their history
        XCTAssertTrue(historyWebView.links[tab2Title].exists,
                      "Tab 2 site '\(tab2Title)' should still be in history")
        XCTAssertTrue(historyWebView.links[tab3Title].exists,
                      "Tab 3 site '\(tab3Title)' should still be in history")

        // Verify current tab's history was cleared (all 3 sites)
        XCTAssertFalse(historyWebView.links[currentTabSite1].exists,
                       "Current tab site 1 '\(currentTabSite1)' should not be in history")
        XCTAssertFalse(historyWebView.links[currentTabSite2].exists,
                       "Current tab site 2 '\(currentTabSite2)' should not be in history")
        XCTAssertFalse(historyWebView.links[currentTabSite3].exists,
                       "Current tab site 3 '\(currentTabSite3)' should not be in history")

        // Switch back to the burnt tab to verify back/forward buttons are disabled
        app.tabs[currentTabSite2].click()

        // Verify back/forward buttons are now disabled (history was cleared)
        XCTAssertFalse(backButton.isEnabled, "Back button should be disabled after burning history")
        XCTAssertFalse(forwardButton.isEnabled, "Forward button should be disabled after burning history")

        // Verify site data preserved (cookies toggle was off)
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyInitialCountersSet()
    }

    func test_fireDialog_tabScope_allTogglesEnabled() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        let currentTabSite1 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let currentTabSite2 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let backgroundTab1URL = URL(string: "https://github.com")!
        let backgroundTab2URL = URL(string: "https://stackoverflow.com/questions")!
        let tab2Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let tab3Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)

        // Setup first window with multiple tabs (will become background)
        app.openURL(backgroundTab1URL)
        app.openNewTab()
        app.openURL(backgroundTab2URL)

        // Open new window (becomes foreground - the one to burn)
        app.typeKey("n", modifierFlags: [.command])

        // Setup current tab with storage and multiple sites
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        // Visit more sites in the same tab
        app.activateAddressBar()
        app.openSite(pageTitle: currentTabSite1)
        app.activateAddressBar()
        app.openSite(pageTitle: currentTabSite2)

        // Open additional tabs in the same window
        app.openNewTab()
        app.openSite(pageTitle: tab2Title)
        app.openNewTab()
        app.openSite(pageTitle: tab3Title)

        // Switch back to first tab
        let firstTab = app.tabs.element(boundBy: 0)
        firstTab.click()

        // Verify we have 3 tabs before burning
        let initialTabCount = app.tabs.count
        XCTAssertEqual(initialTabCount, 3, "Should have 3 tabs before burning")

        // Open Fire dialog
        openFireDialog()

        // Select "Tab" scope
        app.fireDialogSegmentedControl.buttons["Tab"].click()

        // Enable cookies toggle to verify Sites overlay
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })

        // Click the info button to open sites overlay and verify only current tab's domains
        app.fireDialogCookiesInfoButton.click()

        let sitesOverlay = fireDialog.groups.containing(.button, identifier: "FireDialogView.sitesOverlayCloseButton").firstMatch
        XCTAssertTrue(sitesOverlay.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Sites overlay should be open")

        let overlayList = sitesOverlay.scrollViews.firstMatch
        XCTAssertTrue(overlayList.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Sites list should exist")

        // Verify current tab's domains appear (privacy-test-pages.site and localhost)
        let privacyTestDomain = overlayList.staticTexts["privacy-test-pages.site"]
        XCTAssertTrue(privacyTestDomain.exists, "privacy-test-pages.site should appear in sites overlay")

        let localhostDomain = overlayList.staticTexts["localhost"]
        XCTAssertTrue(localhostDomain.exists, "localhost should appear in sites overlay")

        // Verify background window's domains do NOT appear
        XCTAssertFalse(overlayList.staticTexts["github.com"].exists, "github.com (from background window) should NOT appear")
        XCTAssertFalse(overlayList.staticTexts["stackoverflow.com"].exists, "stackoverflow.com (from background window) should NOT appear")

        // Close the sites overlay
        app.fireDialogSitesOverlayCloseButton.click()
        XCTAssertTrue(sitesOverlay.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Sites overlay should close")

        // Enable all toggles
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify only current tab was closed, other tabs remain
        XCTAssertEqual(app.windows.count, 2, "Should still have 2 windows")
        XCTAssertEqual(app.tabs.count, 2, "Should have 2 tabs after burning (first tab was closed)")
        // Verify the other two tabs still exist (proving the first tab was the one closed)
        XCTAssertTrue(app.tabs[tab2Title].exists, "Tab 2 should still exist")
        XCTAssertTrue(app.tabs[tab3Title].exists, "Tab 3 should still exist")

        // Verify background window still exists (still has 2 tabs)
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertEqual(backgroundWindow.tabs.count, 2, "Background window should still have 2 tabs")

        // Verify history for burnt tab was removed
        app.openHistory()
        let historyWebView = app.webViews["History"]

        // Verify background window's sites ARE still in history
        XCTAssertTrue(historyWebView.links.element(matching: .keyPath(\.title, contains: "GitHub")).waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Background window's GitHub site should still be in history")

        // Verify other tabs' sites in current window ARE still in history
        XCTAssertTrue(historyWebView.links[tab2Title].exists,
                      "Other tab in current window should still be in history")

        // Verify current tab's sites (privacy-test-pages.site and localhost) are NOT in history
        XCTAssertFalse(historyWebView.links.element(matching: .keyPath(\.title, contains: "Local Storage")).exists,
                       "Current tab's privacy-test-pages site should not be in history")
        XCTAssertFalse(historyWebView.links[currentTabSite1].exists,
                       "Current tab localhost site 1 should not be in history")
        XCTAssertFalse(historyWebView.links[currentTabSite2].exists,
                       "Current tab localhost site 2 should not be in history")

        // Verify site data cleared
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyCountersCleared()
    }

    func test_fireDialog_tabScope_onlyHistoryAndCookies() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        let currentTabTitle = "Local Storage & Cookies storing"
        let backgroundTab1URL = URL(string: "https://github.com")!
        let backgroundTab2URL = URL(string: "https://stackoverflow.com/questions")!
        let tab2Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let tab3Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)

        // Setup first window with multiple tabs (will become background)
        app.openURL(backgroundTab1URL)
        app.openNewTab()
        app.openURL(backgroundTab2URL)

        // Open new window (becomes foreground - the one to burn)
        app.typeKey("n", modifierFlags: [.command])

        // Setup current window
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        app.openNewTab()
        app.openSite(pageTitle: tab2Title)
        app.openNewTab()
        app.openSite(pageTitle: tab3Title)

        // Switch back to first tab (storage tab)
        app.tabs[currentTabTitle].click()

        // Open Fire dialog from the tab with sites (NOT from History tab)
        app.typeKey(.delete, modifierFlags: [.command, .shift])
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Select "Tab" scope
        app.fireDialogSegmentedControl.buttons["Tab"].click()

        // Enable cookies toggle to verify Sites overlay
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })

        // Click the info button to open sites overlay and verify only current tab's domains
        app.fireDialogCookiesInfoButton.click()

        let sitesOverlay = fireDialog.groups.containing(.button, identifier: "FireDialogView.sitesOverlayCloseButton").firstMatch
        XCTAssertTrue(sitesOverlay.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Sites overlay should be open")

        let overlayList = sitesOverlay.scrollViews.firstMatch
        XCTAssertTrue(overlayList.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Sites list should exist")

        // Verify current tab's domain appears
        XCTAssertTrue(overlayList.staticTexts.element(matching: .keyPath(\.value, contains: "privacy-test-pages.site")).exists,
                      "Current tab domain should appear in sites overlay")

        // Close the sites overlay
        app.fireDialogSitesOverlayCloseButton.click()
        XCTAssertTrue(sitesOverlay.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Sites overlay should close")

        // Disable tabs, enable history and cookies
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify tabs not closed (all 3 tabs should still exist)
        XCTAssertEqual(app.tabs.count, 3, "Should still have 3 tabs (tabs toggle was off)")
        XCTAssertTrue(app.tabs[currentTabTitle].exists, "Storage tab should still be open")
        XCTAssertTrue(app.tabs[tab2Title].exists, "Second tab should still exist")
        XCTAssertTrue(app.tabs[tab3Title].exists, "Third tab should still exist")

        // Open History to verify current tab's history was cleared
        app.openHistory()
        let historyWebView = app.webViews["History"]

        // Verify background window's sites ARE still in history
        XCTAssertTrue(historyWebView.links.element(matching: .keyPath(\.title, contains: "GitHub")).waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Background window's GitHub site should still be in history")

        // Verify other tabs' sites in current window ARE still in history
        XCTAssertTrue(historyWebView.links[tab2Title].exists,
                      "Other tab in current window should still be in history")

        // Verify current tab's history was cleared
        XCTAssertFalse(historyWebView.links[currentTabTitle].exists,
                       "Current tab site should not be in history")

        // Verify background window preserved (still has 2 tabs)
        XCTAssertEqual(app.windows.count, 2, "Should still have 2 windows")
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertEqual(backgroundWindow.tabs.count, 2, "Background window should still have 2 tabs")

        // Verify site data cleared
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyCountersCleared()
    }

    func test_fireDialog_tabScope_onlyTabsAndCookies() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        let currentTabTitle = "Local Storage & Cookies storing"
        let backgroundTab1URL = URL(string: "https://github.com")!
        let backgroundTab2URL = URL(string: "https://stackoverflow.com/questions")!
        let tab2Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let tab3Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)

        // Setup first window with multiple tabs (will become background)
        app.openURL(backgroundTab1URL)
        app.openNewTab()
        app.openURL(backgroundTab2URL)

        // Open new window (becomes foreground - the one to burn)
        app.typeKey("n", modifierFlags: [.command])

        // Setup current window
        app.openURL(storageURL)
        setStorageAndCookies()

        app.openNewTab()
        app.openSite(pageTitle: tab2Title)
        app.openNewTab()
        app.openSite(pageTitle: tab3Title)

        // Switch back to first tab (storage tab)
        app.tabs[currentTabTitle].click()

        // Open Fire dialog from the tab with sites (NOT from History tab)
        app.fireButton.click()
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Select "Tab" scope
        app.fireDialogSegmentedControl.buttons["Tab"].click()

        // Enable cookies toggle to verify Sites overlay
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })

        // Click the info button to open sites overlay and verify only current tab's domains
        app.fireDialogCookiesInfoButton.click()

        let sitesOverlay = fireDialog.groups.containing(.button, identifier: "FireDialogView.sitesOverlayCloseButton").firstMatch
        XCTAssertTrue(sitesOverlay.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Sites overlay should be open")

        let overlayList = sitesOverlay.scrollViews.firstMatch
        XCTAssertTrue(overlayList.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Sites list should exist")

        // Verify current tab's domain appears
        XCTAssertTrue(overlayList.staticTexts.element(matching: .keyPath(\.value, contains: "privacy-test-pages.site")).exists,
                      "Current tab domain should appear in sites overlay")

        // Close the sites overlay
        app.fireDialogSitesOverlayCloseButton.click()
        XCTAssertTrue(sitesOverlay.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Sites overlay should close")

        // Enable tabs and cookies, disable history
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify current tab closed and replaced, other tabs remain
        XCTAssertEqual(app.tabs.count, 2, "Should have 2 tabs after burning (first tab was closed)")
        XCTAssertTrue(app.tabs[tab2Title].exists, "Second tab should still exist")
        XCTAssertTrue(app.tabs[tab3Title].exists, "Third tab should still exist")

        // Verify history preserved - open History
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History should be reopenable")

        // Verify history preserved (all sites should still be in history)
        XCTAssertTrue(historyWebView.links.element(matching: .keyPath(\.title, contains: "GitHub")).waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Background window's GitHub site should still be in history")
        XCTAssertTrue(historyWebView.links[currentTabTitle].exists,
                      "Current tab site should still be in history (history toggle was off)")
        XCTAssertTrue(historyWebView.links[tab2Title].exists,
                      "Other tab in current window should still be in history")

        // Verify background window preserved (still has 2 tabs)
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertEqual(backgroundWindow.tabs.count, 2, "Background window should still have 2 tabs")

        // Verify site data cleared
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyCountersCleared()
    }

    func test_fireDialog_tabScope_onlyTabsAndHistory() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        let currentTabTitle = "Local Storage & Cookies storing"
        let backgroundTab1URL = URL(string: "https://github.com")!
        let backgroundTab2URL = URL(string: "https://stackoverflow.com/questions")!
        let tab2Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let tab3Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)

        // Setup first window with multiple tabs (will become background)
        app.openURL(backgroundTab1URL)
        app.openNewTab()
        app.openURL(backgroundTab2URL)

        // Open new window (becomes foreground - the one to burn)
        app.typeKey("n", modifierFlags: [.command])

        // Setup current window
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        app.openNewTab()
        app.openSite(pageTitle: tab2Title)
        app.openNewTab()
        app.openSite(pageTitle: tab3Title)

        // Switch back to first tab (storage tab)
        app.tabs[currentTabTitle].click()

        // Open Fire dialog
        openFireDialog()

        // Select "Tab" scope
        app.fireDialogSegmentedControl.buttons["Tab"].click()

        // Enable tabs and history, disable cookies
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify current tab closed and replaced, other tabs remain
        XCTAssertEqual(app.tabs.count, 2, "Should have 2 tabs after burning (first tab was closed)")
        XCTAssertTrue(app.tabs[tab2Title].exists, "Second tab should still exist")
        XCTAssertTrue(app.tabs[tab3Title].exists, "Third tab should still exist")

        // Verify history cleared - open History
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History should be reopenable")
        XCTAssertFalse(historyWebView.links[currentTabTitle].exists,
                       "Current tab site should not be in history")

        // Verify background window preserved (still has 2 tabs)
        XCTAssertEqual(app.windows.count, 2, "Should still have 2 windows")
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertEqual(backgroundWindow.tabs.count, 2, "Background window should still have 2 tabs")

        // Verify site data preserved (cookies toggle was off)
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyInitialCountersSet()
    }

    func test_fireDialog_tabScope_onlyCookies() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        let currentTabSite1 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let currentTabSite2 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let currentTabSite3 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let backgroundTab1URL = URL(string: "https://github.com")!
        let backgroundTab2URL = URL(string: "https://stackoverflow.com/questions")!
        let tab2Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let tab3Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)

        // Setup first window with multiple tabs (will become background)
        app.openURL(backgroundTab1URL)
        app.openNewTab()
        app.openURL(backgroundTab2URL)

        // Open new window (becomes foreground - the one to burn)
        app.typeKey("n", modifierFlags: [.command])

        // Setup current tab with multiple sites and storage
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        // Visit more sites in the same tab
        app.activateAddressBar()
        app.openSite(pageTitle: currentTabSite1)
        app.activateAddressBar()
        app.openSite(pageTitle: currentTabSite2)
        app.activateAddressBar()
        app.openSite(pageTitle: currentTabSite3)

        // Go back once to enable both back and forward buttons
        app.typeKey("[", modifierFlags: [.command])

        // Verify back/forward buttons are enabled
        let backButton = app.buttons["NavigationBarViewController.BackButton"].firstMatch
        let forwardButton = app.buttons["NavigationBarViewController.ForwardButton"].firstMatch
        XCTAssertTrue(backButton.isEnabled, "Back button should be enabled before burning")
        XCTAssertTrue(forwardButton.isEnabled, "Forward button should be enabled before burning")

        // Open additional tabs in the same window
        app.openNewTab()
        app.openSite(pageTitle: tab2Title)
        app.openNewTab()
        app.openSite(pageTitle: tab3Title)

        // Switch back to first tab (the one with navigation history)
        app.tabs[currentTabSite2].click()

        // Open Fire dialog from this tab (NOT from History tab)
        app.typeKey(.delete, modifierFlags: [.command, .shift])
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Select "Tab" scope
        app.fireDialogSegmentedControl.buttons["Tab"].click()

        // Disable tabs and history, enable cookies only
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify tabs not closed (all 3 tabs should still exist)
        XCTAssertEqual(app.tabs.count, 3, "Should still have 3 tabs (tabs toggle was off)")
        XCTAssertTrue(app.tabs[currentTabSite2].exists, "First tab should still be open")
        XCTAssertTrue(app.tabs[tab2Title].exists, "Second tab should still exist")
        XCTAssertTrue(app.tabs[tab3Title].exists, "Third tab should still exist")

        // Verify back/forward buttons remain enabled (history was NOT cleared)
        XCTAssertTrue(backButton.isEnabled, "Back button should remain enabled when history toggle is off")
        XCTAssertTrue(forwardButton.isEnabled, "Forward button should remain enabled when history toggle is off")

        // Verify history menu shows tab's history by long-pressing back button
        backButton.press(forDuration: 1.0)
        let backHistoryMenu = app.menus.firstMatch
        XCTAssertTrue(backHistoryMenu.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Back history menu should appear")

        // Verify at least one history item appears in the menu
        let historyMenuItem = backHistoryMenu.menuItems.firstMatch
        XCTAssertTrue(historyMenuItem.exists, "Back history menu should contain at least one item")

        // Dismiss the menu
        app.typeKey(.escape, modifierFlags: [])

        // Now open History window to verify global history is preserved
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.links[currentTabSite1].waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Current tab site 1 should be in history")
        XCTAssertTrue(historyWebView.links[currentTabSite2].exists,
                      "Current tab site 2 should be in history")
        XCTAssertTrue(historyWebView.links[currentTabSite3].exists,
                      "Current tab site 3 should be in history")

        // Verify background window preserved (still has 2 tabs)
        XCTAssertEqual(app.windows.count, 2, "Should still have 2 windows")
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertEqual(backgroundWindow.tabs.count, 2, "Background window should still have 2 tabs")

        // Verify site data cleared
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyCountersCleared()
    }

    func test_fireDialog_tabScope_onlyTabs() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        let currentTabTitle = "Local Storage & Cookies storing"
        let backgroundTab1URL = URL(string: "https://github.com")!
        let backgroundTab2URL = URL(string: "https://stackoverflow.com/questions")!
        let tab2Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let tab3Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)

        // Setup first window with multiple tabs (will become background)
        app.openURL(backgroundTab1URL)
        app.openNewTab()
        app.openURL(backgroundTab2URL)

        // Open new window (becomes foreground - the one to burn)
        app.typeKey("n", modifierFlags: [.command])

        // Setup current window
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        app.openNewTab()
        app.openSite(pageTitle: tab2Title)
        app.openNewTab()
        app.openSite(pageTitle: tab3Title)

        // Switch back to first tab (storage tab)
        app.tabs[currentTabTitle].click()

        // Open Fire dialog
        app.fireButton.click()
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Select "Tab" scope
        app.fireDialogSegmentedControl.buttons["Tab"].click()

        // Enable tabs only, disable history and cookies
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify current tab closed and replaced, other tabs remain
        XCTAssertEqual(app.tabs.count, 2, "Should have 2 tabs after burning (first tab was closed)")
        XCTAssertTrue(app.tabs[tab2Title].exists, "Second tab should still exist")
        XCTAssertTrue(app.tabs[tab3Title].exists, "Third tab should still exist")

        // Verify history preserved - open History
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History should be reopenable")
        XCTAssertTrue(historyWebView.links[currentTabTitle].exists,
                      "Current tab site should still be in history (history toggle was off)")

        // Verify background window preserved (still has 2 tabs)
        XCTAssertEqual(app.windows.count, 2, "Should still have 2 windows")
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertEqual(backgroundWindow.tabs.count, 2, "Background window should still have 2 tabs")

        // Verify site data preserved (cookies toggle was off)
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyInitialCountersSet()
    }

    func test_fireDialog_tabScope_closingOnlyTabClosesWindow() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        let backgroundTab1URL = URL(string: "https://github.com")!
        let backgroundTab2URL = URL(string: "https://stackoverflow.com/questions")!

        // Setup first window with multiple tabs (will become background)
        app.openURL(backgroundTab1URL)
        app.openNewTab()
        app.openURL(backgroundTab2URL)

        // Open new window (becomes foreground - the one to burn, with only 1 tab)
        app.typeKey("n", modifierFlags: [.command])

        // Setup current window with storage (single tab)
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        // Verify we have 2 windows
        XCTAssertEqual(app.windows.count, 2, "Should have 2 windows")

        // Open Fire dialog
        app.fireButton.click()
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Select "Tab" scope
        app.fireDialogSegmentedControl.buttons["Tab"].click()

        // Enable tabs toggle (close tabs)
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify current window was closed entirely (as it had only 1 tab)
        XCTAssertEqual(app.windows.count, 1, "Should have only 1 window remaining (the background window)")

        // Verify only background window remains with its 2 tabs (now frontmost)
        XCTAssertEqual(app.windows.count, 1, "Should have only 1 window (background window)")
        XCTAssertEqual(app.tabs.count, 2, "Background window should still have 2 tabs")

        // Verify site data was cleared
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyCountersCleared()
    }

    // MARK: - Window Scope Tests

    func test_fireDialog_windowScope_closesAllTabsInWindow() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        let windowTab1Site1 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let windowTab1Site2 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let windowTab2Site1 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let windowTab3Site1 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let backgroundTab1URL = URL(string: "https://github.com")!
        let backgroundTab2URL = URL(string: "https://stackoverflow.com/questions")!

        // Setup first window with multiple tabs (will become background)
        app.openURL(backgroundTab1URL)
        app.openNewTab()
        app.openURL(backgroundTab2URL)

        // Open new window (becomes foreground - the one to burn)
        app.typeKey("n", modifierFlags: [.command])

        // Setup first tab in window with storage and multiple sites
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        app.activateAddressBar()
        app.openSite(pageTitle: windowTab1Site1)
        app.activateAddressBar()
        app.openSite(pageTitle: windowTab1Site2)

        // Open second tab in window
        app.openNewTab()
        app.openSite(pageTitle: windowTab2Site1)

        // Open third tab in window
        app.openNewTab()
        app.openSite(pageTitle: windowTab3Site1)

        // Verify we have 2 windows and 3 tabs in current window
        XCTAssertEqual(app.windows.count, 2, "Should have 2 windows")
        XCTAssertEqual(app.tabs.count, 3, "Should have 3 tabs in current window before burning")

        // Open Fire dialog via Fire button
        app.fireButton.click()
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Select "Window" scope
        app.fireDialogSegmentedControl.buttons["Window"].click()

        // Enable cookies toggle to verify Sites overlay
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })

        // Click the info button to open sites overlay and verify all window's domains
        app.fireDialogCookiesInfoButton.click()

        let sitesOverlay = fireDialog.groups.containing(.button, identifier: "FireDialogView.sitesOverlayCloseButton").firstMatch
        XCTAssertTrue(sitesOverlay.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Sites overlay should be open")

        let overlayList = sitesOverlay.scrollViews.firstMatch
        XCTAssertTrue(overlayList.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Sites list should exist")

        // Verify all tabs' domains from current window appear
        XCTAssertTrue(overlayList.staticTexts.element(matching: .keyPath(\.value, contains: "privacy-test-pages.site")).exists,
                      "privacy-test-pages.site domain should appear in sites overlay")
        XCTAssertTrue(overlayList.staticTexts.element(matching: .keyPath(\.value, contains: "localhost")).exists,
                      "localhost domain should appear in sites overlay")

        // Verify background window's domains do NOT appear
        XCTAssertFalse(overlayList.staticTexts["github.com"].exists, "github.com (from background window) should NOT appear")
        XCTAssertFalse(overlayList.staticTexts["stackoverflow.com"].exists, "stackoverflow.com (from background window) should NOT appear")

        // Close the sites overlay
        app.fireDialogSitesOverlayCloseButton.click()
        XCTAssertTrue(sitesOverlay.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Sites overlay should close")

        // Enable all toggles
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify current window was closed entirely (all 3 tabs)
        XCTAssertEqual(app.windows.count, 1, "Should have only 1 window remaining (the background window)")
        XCTAssertEqual(app.tabs.count, 2, "Background window should still have 2 tabs")

        // Verify history for all burnt window's tabs was removed
        app.openHistory()
        let historyWebView = app.webViews["History"]

        // Verify background window's domains ARE still in history
        XCTAssertTrue(historyWebView.links.element(matching: .keyPath(\.title, contains: "GitHub")).waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Background window's GitHub site should still be in history")

        // Verify all current window's tabs' sites are NOT in history
        XCTAssertFalse(historyWebView.links.element(matching: .keyPath(\.title, contains: "Local Storage")).exists,
                       "Window tab 1's privacy-test-pages site should not be in history")
        XCTAssertFalse(historyWebView.links[windowTab1Site1].exists,
                       "Window tab 1 site 1 should not be in history")
        XCTAssertFalse(historyWebView.links[windowTab1Site2].exists,
                       "Window tab 1 site 2 should not be in history")
        XCTAssertFalse(historyWebView.links[windowTab2Site1].exists,
                       "Window tab 2 site should not be in history")
        XCTAssertFalse(historyWebView.links[windowTab3Site1].exists,
                       "Window tab 3 site should not be in history")

        // Verify site data was cleared
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyCountersCleared()
    }

    func test_fireDialog_windowScope_clearsAllTabsHistory() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        let windowTab1Site1 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let windowTab1Site2 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let windowTab2Site1 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let windowTab3Site1 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let backgroundTab1URL = URL(string: "https://github.com")!
        let backgroundTab2URL = URL(string: "https://stackoverflow.com/questions")!

        // Setup first window with multiple tabs (will become background)
        app.openURL(backgroundTab1URL)
        app.openNewTab()
        app.openURL(backgroundTab2URL)

        // Open new window (becomes foreground - the one to burn)
        app.typeKey("n", modifierFlags: [.command])

        // Setup first tab in window with storage and multiple sites
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        app.activateAddressBar()
        app.openSite(pageTitle: windowTab1Site1)
        app.activateAddressBar()
        app.openSite(pageTitle: windowTab1Site2)

        // Open second tab in window
        app.openNewTab()
        app.openSite(pageTitle: windowTab2Site1)

        // Open third tab in window
        app.openNewTab()
        app.openSite(pageTitle: windowTab3Site1)

        // Verify we have 2 windows and 3 tabs in current window
        XCTAssertEqual(app.windows.count, 2, "Should have 2 windows")
        XCTAssertEqual(app.tabs.count, 3, "Should have 3 tabs in current window before burning")

        // Open Fire dialog via keyboard shortcut
        app.typeKey(.delete, modifierFlags: [.command, .shift])
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Select "Window" scope
        app.fireDialogSegmentedControl.buttons["Window"].click()

        // Enable only history toggle (tabs and cookies off)
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify tabs were not closed (all 3 tabs should still exist)
        XCTAssertEqual(app.tabs.count, 3, "Should still have 3 tabs (tabs toggle was off)")
        XCTAssertTrue(app.tabs.element(boundBy: 0).exists, "First tab should still be open")
        XCTAssertTrue(app.tabs.element(boundBy: 1).exists, "Second tab should still exist")
        XCTAssertTrue(app.tabs.element(boundBy: 2).exists, "Third tab should still exist")

        // Open History to verify history was cleared
        app.openHistory()
        let historyWebView = app.webViews["History"]

        // Verify background window's history was preserved
        XCTAssertTrue(historyWebView.links.element(matching: .keyPath(\.title, contains: "GitHub")).waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Background window's GitHub site should still be in history")

        // Verify all current window's tabs' history was cleared
        XCTAssertFalse(historyWebView.links.element(matching: .keyPath(\.title, contains: "Local Storage")).exists,
                       "Window tab 1's privacy-test-pages site should not be in history")
        XCTAssertFalse(historyWebView.links[windowTab1Site1].exists,
                       "Window tab 1 site 1 should not be in history")
        XCTAssertFalse(historyWebView.links[windowTab1Site2].exists,
                       "Window tab 1 site 2 should not be in history")
        XCTAssertFalse(historyWebView.links[windowTab2Site1].exists,
                       "Window tab 2 site should not be in history")
        XCTAssertFalse(historyWebView.links[windowTab3Site1].exists,
                       "Window tab 3 site should not be in history")

        // Verify site data preserved (cookies toggle was off)
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyInitialCountersSet()
    }

    func test_fireDialog_windowScope_onlyHistoryAndCookies() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        let windowTab1Site1 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let windowTab2Site1 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let windowTab3Site1 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let backgroundTab1URL = URL(string: "https://github.com")!
        let backgroundTab2URL = URL(string: "https://stackoverflow.com/questions")!

        // Setup first window with multiple tabs (will become background)
        app.openURL(backgroundTab1URL)
        app.openNewTab()
        app.openURL(backgroundTab2URL)

        // Open new window (becomes foreground - the one to burn)
        app.typeKey("n", modifierFlags: [.command])

        // Setup first tab in window with storage
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        app.activateAddressBar()
        app.openSite(pageTitle: windowTab1Site1)

        // Open second tab in window
        app.openNewTab()
        app.openSite(pageTitle: windowTab2Site1)

        // Open third tab in window
        app.openNewTab()
        app.openSite(pageTitle: windowTab3Site1)

        // Verify we have 2 windows and 3 tabs in current window
        XCTAssertEqual(app.windows.count, 2, "Should have 2 windows")
        XCTAssertEqual(app.tabs.count, 3, "Should have 3 tabs in current window")

        // Open Fire dialog
        openFireDialog()

        // Select "Window" scope
        app.fireDialogSegmentedControl.buttons["Window"].click()

        // Enable cookies toggle to verify Sites overlay
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })

        // Click the info button to open sites overlay
        app.fireDialogCookiesInfoButton.click()

        let sitesOverlay = fireDialog.groups.containing(.button, identifier: "FireDialogView.sitesOverlayCloseButton").firstMatch
        XCTAssertTrue(sitesOverlay.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Sites overlay should be open")

        let overlayList = sitesOverlay.scrollViews.firstMatch
        XCTAssertTrue(overlayList.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Sites list should exist")

        // Verify current window's domains appear
        XCTAssertTrue(overlayList.staticTexts.element(matching: .keyPath(\.value, contains: "privacy-test-pages.site")).exists,
                      "Current window's domain should appear in sites overlay")

        // Close the sites overlay
        app.fireDialogSitesOverlayCloseButton.click()
        XCTAssertTrue(sitesOverlay.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Sites overlay should close")

        // Disable tabs, enable history and cookies
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify tabs not closed (all 3 tabs should still exist)
        XCTAssertEqual(app.tabs.count, 3, "Should still have 3 tabs (tabs toggle was off)")

        // Open History to verify current window's history was cleared
        app.openHistory()
        let historyWebView = app.webViews["History"]

        // Verify background window's sites ARE still in history
        XCTAssertTrue(historyWebView.links.element(matching: .keyPath(\.title, contains: "GitHub")).waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Background window's GitHub site should still be in history")

        // Verify all current window's tabs' sites are NOT in history
        XCTAssertFalse(historyWebView.links.element(matching: .keyPath(\.title, contains: "Local Storage")).exists,
                       "Current window's sites should not be in history")
        XCTAssertFalse(historyWebView.links[windowTab1Site1].exists,
                       "Window tab 1 site should not be in history")
        XCTAssertFalse(historyWebView.links[windowTab2Site1].exists,
                       "Window tab 2 site should not be in history")
        XCTAssertFalse(historyWebView.links[windowTab3Site1].exists,
                       "Window tab 3 site should not be in history")

        // Verify background window preserved (still has 2 tabs)
        XCTAssertEqual(app.windows.count, 2, "Should still have 2 windows")
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertEqual(backgroundWindow.tabs.count, 2, "Background window should still have 2 tabs")

        // Verify site data cleared
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyCountersCleared()
    }

    func test_fireDialog_windowScope_onlyTabsAndCookies() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        let windowTab1Site1 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let windowTab2Site1 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let windowTab3Site1 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let backgroundTab1URL = URL(string: "https://github.com")!
        let backgroundTab2URL = URL(string: "https://stackoverflow.com/questions")!

        // Setup first window with multiple tabs (will become background)
        app.openURL(backgroundTab1URL)
        app.openNewTab()
        app.openURL(backgroundTab2URL)

        // Open new window (becomes foreground - the one to burn)
        app.typeKey("n", modifierFlags: [.command])

        // Setup first tab in window with storage
        app.openURL(storageURL)
        setStorageAndCookies()

        app.activateAddressBar()
        app.openSite(pageTitle: windowTab1Site1)

        // Open second tab in window
        app.openNewTab()
        app.openSite(pageTitle: windowTab2Site1)

        // Open third tab in window
        app.openNewTab()
        app.openSite(pageTitle: windowTab3Site1)

        // Open Fire dialog
        app.fireButton.click()
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Select "Window" scope
        app.fireDialogSegmentedControl.buttons["Window"].click()

        // Enable cookies toggle to verify Sites overlay
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })

        // Click the info button to open sites overlay
        app.fireDialogCookiesInfoButton.click()

        let sitesOverlay = fireDialog.groups.containing(.button, identifier: "FireDialogView.sitesOverlayCloseButton").firstMatch
        XCTAssertTrue(sitesOverlay.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Sites overlay should be open")

        let overlayList = sitesOverlay.scrollViews.firstMatch
        XCTAssertTrue(overlayList.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Sites list should exist")

        // Verify current window's domain appears
        XCTAssertTrue(overlayList.staticTexts.element(matching: .keyPath(\.value, contains: "privacy-test-pages.site")).exists,
                      "Current window's domain should appear in sites overlay")

        // Close the sites overlay
        app.fireDialogSitesOverlayCloseButton.click()
        XCTAssertTrue(sitesOverlay.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Sites overlay should close")

        // Enable tabs and cookies, disable history
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify current window was closed entirely
        XCTAssertEqual(app.windows.count, 1, "Should have only 1 window remaining (the background window)")
        XCTAssertEqual(app.tabs.count, 2, "Background window should still have 2 tabs")

        // Verify history preserved - open History
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History should be reopenable")

        // Verify history preserved (all sites should still be in history)
        XCTAssertTrue(historyWebView.links.element(matching: .keyPath(\.title, contains: "GitHub")).waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Background window's GitHub site should still be in history")
        XCTAssertTrue(historyWebView.links.element(matching: .keyPath(\.title, contains: "Local Storage")).exists,
                      "Window's storage site should still be in history (history toggle was off)")
        XCTAssertTrue(historyWebView.links[windowTab1Site1].exists,
                      "Window tab 1 site should still be in history")
        XCTAssertTrue(historyWebView.links[windowTab2Site1].exists,
                      "Window tab 2 site should still be in history")

        // Verify site data cleared
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyCountersCleared()
    }

    func test_fireDialog_windowScope_onlyTabsAndHistory() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        let windowTab1Site1 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let windowTab2Site1 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let backgroundTab1URL = URL(string: "https://github.com")!
        let backgroundTab2URL = URL(string: "https://stackoverflow.com/questions")!

        // Setup first window with multiple tabs (will become background)
        app.openURL(backgroundTab1URL)
        app.openNewTab()
        app.openURL(backgroundTab2URL)

        // Open new window (becomes foreground - the one to burn)
        app.typeKey("n", modifierFlags: [.command])

        // Setup window with storage
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        app.activateAddressBar()
        app.openSite(pageTitle: windowTab1Site1)

        app.openNewTab()
        app.openSite(pageTitle: windowTab2Site1)

        // Open Fire dialog
        openFireDialog()

        // Select "Window" scope
        app.fireDialogSegmentedControl.buttons["Window"].click()

        // Enable tabs and history, disable cookies
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify current window was closed entirely
        XCTAssertEqual(app.windows.count, 1, "Should have only 1 window remaining")
        XCTAssertEqual(app.tabs.count, 2, "Background window should still have 2 tabs")

        // Verify history cleared - open History
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History should be reopenable")
        XCTAssertFalse(historyWebView.links.element(matching: .keyPath(\.title, contains: "Local Storage")).exists,
                       "Window's sites should not be in history")

        // Verify site data preserved (cookies toggle was off)
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyInitialCountersSet()
    }

    func test_fireDialog_windowScope_onlyCookies() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        let windowTab1Site1 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let windowTab2Site1 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let backgroundTab1URL = URL(string: "https://github.com")!
        let backgroundTab2URL = URL(string: "https://stackoverflow.com/questions")!

        // Setup first window with multiple tabs (will become background)
        app.openURL(backgroundTab1URL)
        app.openNewTab()
        app.openURL(backgroundTab2URL)

        // Open new window (becomes foreground - the one to burn)
        app.typeKey("n", modifierFlags: [.command])

        // Setup window with storage
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        app.activateAddressBar()
        app.openSite(pageTitle: windowTab1Site1)

        app.openNewTab()
        app.openSite(pageTitle: windowTab2Site1)

        // Open Fire dialog via keyboard shortcut
        app.typeKey(.delete, modifierFlags: [.command, .shift])
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Select "Window" scope
        app.fireDialogSegmentedControl.buttons["Window"].click()

        // Disable tabs and history, enable cookies only
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify tabs not closed (all tabs should still exist)
        XCTAssertEqual(app.tabs.count, 2, "Should still have 2 tabs (tabs toggle was off)")

        // Open History window to verify global history is preserved
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.links.element(matching: .keyPath(\.title, contains: "Local Storage")).waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Window's site should still be in history")
        XCTAssertTrue(historyWebView.links[windowTab1Site1].exists,
                      "Window tab 1 site should be in history")
        XCTAssertTrue(historyWebView.links[windowTab2Site1].exists,
                      "Window tab 2 site should be in history")

        // Verify background window preserved (still has 2 tabs)
        XCTAssertEqual(app.windows.count, 2, "Should still have 2 windows")
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertEqual(backgroundWindow.tabs.count, 2, "Background window should still have 2 tabs")

        // Verify site data cleared
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyCountersCleared()
    }

    func test_fireDialog_windowScope_onlyTabs() throws {
        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!
        let windowTab1Site1 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let windowTab2Site1 = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let backgroundTab1URL = URL(string: "https://github.com")!
        let backgroundTab2URL = URL(string: "https://stackoverflow.com/questions")!

        // Setup first window with multiple tabs (will become background)
        app.openURL(backgroundTab1URL)
        app.openNewTab()
        app.openURL(backgroundTab2URL)

        // Open new window (becomes foreground - the one to burn)
        app.typeKey("n", modifierFlags: [.command])

        // Setup window with storage
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        app.activateAddressBar()
        app.openSite(pageTitle: windowTab1Site1)

        app.openNewTab()
        app.openSite(pageTitle: windowTab2Site1)

        // Open Fire dialog
        app.fireButton.click()
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Select "Window" scope
        app.fireDialogSegmentedControl.buttons["Window"].click()

        // Enable tabs only, disable history and cookies
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify current window was closed entirely
        XCTAssertEqual(app.windows.count, 1, "Should have only 1 window remaining")
        XCTAssertEqual(app.tabs.count, 2, "Background window should still have 2 tabs")

        // Verify history preserved - open History
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History should be reopenable")
        XCTAssertTrue(historyWebView.links.element(matching: .keyPath(\.title, contains: "Local Storage")).exists,
                      "Window's site should still be in history (history toggle was off)")

        // Verify site data preserved (cookies toggle was off)
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyInitialCountersSet()
    }

    // MARK: - History View Delete All Tests

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

    // MARK: - History View Date-based Deletion Tests

    func test_historyView_deleteToday_historyAndCookies() throws {
        // First, populate fake history from debug menu to have yesterday/older history
        populateFakeHistoryFromDebugMenu()

        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!

        // Visit sites and set storage TODAY
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        let todaySite1Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: todaySite1Title)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Verify today's sites exist
        XCTAssertTrue(historyWebView.links[todaySite1Title].waitForExistence(timeout: UITests.Timeouts.elementExistence), "Today's site should be in history")
        XCTAssertTrue(historyWebView.links.element(matching: .keyPath(\.title, contains: "Local Storage")).exists, "Storage site should be in today's history")

        // Verify yesterday section exists (from fake history)
        let yesterdayButton = historyWebView.buttons["Show history for yesterday"]
        XCTAssertTrue(yesterdayButton.exists, "Yesterday button should exist from fake history")

        // Hover "today" section button to reveal delete button
        let todayButton = historyWebView.buttons["Show history for today"]
        XCTAssertTrue(todayButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Today button should exist")
        todayButton.hover()

        // Click delete button for today
        let deleteTodayButton = historyWebView.buttons["Delete history for today"]
        XCTAssertTrue(deleteTodayButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Delete today button should appear on hover")
        deleteTodayButton.click()

        // Verify Fire dialog opens
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Verify no scope pill appears
        XCTAssertFalse(app.fireDialogSegmentedControl.exists, "Scope pill should not appear for date deletion")

        // Configure toggles: history + cookies
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })

        // Burn
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify History view still open
        XCTAssertTrue(historyWebView.exists, "History view should still be open")

        // Navigate to "today" section to verify it's now empty
        todayButton.click()

        let emptyHistoryText = historyWebView.staticTexts["No browsing history yet."]
        XCTAssertTrue(emptyHistoryText.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Today section should show empty message after deletion")

        // Navigate to yesterday section to verify it still has history
        yesterdayButton.click()
        XCTAssertFalse(emptyHistoryText.exists, "Yesterday section should not be empty")

        // Refresh history (Cmd+R)
        app.typeKey("r", modifierFlags: [.command])
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should still exist after refresh")

        // Verify today still shows empty state after refresh
        todayButton.click()
        XCTAssertTrue(emptyHistoryText.exists, "Today section should still show empty message after refresh")

        // Verify yesterday still has history after refresh
        yesterdayButton.click()
        XCTAssertFalse(emptyHistoryText.exists, "Yesterday section should still have history after refresh")

        // Verify storage was cleared
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyCountersCleared()
    }

    func test_historyView_deleteYesterday_onlyHistory() throws {
        // Populate fake history from debug menu to ensure we have yesterday's history
        populateFakeHistoryFromDebugMenu()

        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!

        // Visit sites and set storage today
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        let todaySiteTitle = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: todaySiteTitle)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Verify yesterday section exists
        let yesterdayButton = historyWebView.buttons["Show history for yesterday"]
        XCTAssertTrue(yesterdayButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Yesterday button should exist")

        // Hover "yesterday" section button to reveal delete button
        yesterdayButton.hover()

        // Click delete button for yesterday
        let deleteYesterdayButton = historyWebView.buttons["Delete history for yesterday"]
        XCTAssertTrue(deleteYesterdayButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Delete yesterday button should appear on hover")
        deleteYesterdayButton.click()

        // Verify Fire dialog opens
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Verify no scope pill appears
        XCTAssertFalse(app.fireDialogSegmentedControl.exists, "Scope pill should not appear for date deletion")

        // Verify no Close tabs toggle
        XCTAssertFalse(fireDialogTabsToggle.exists, "Tabs toggle should not appear for date-based deletion")

        // Configure toggles: only history
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })

        // Burn
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify History view still open
        XCTAssertTrue(historyWebView.exists, "History view should still be open")

        // Navigate to "today" section to verify it still has history
        let todayButton = historyWebView.buttons["Show history for today"]
        todayButton.click()
        XCTAssertTrue(historyWebView.links[todaySiteTitle].exists, "Today's site should still be in history")

        // Navigate to "yesterday" section to verify it's now empty
        yesterdayButton.click()

        let emptyHistoryText = historyWebView.staticTexts["No browsing history yet."]
        XCTAssertTrue(emptyHistoryText.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Yesterday section should show empty message after deletion")

        // Refresh history (Cmd+R)
        app.typeKey("r", modifierFlags: [.command])
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should still exist after refresh")

        // Verify today's site still preserved after refresh
        todayButton.click()
        XCTAssertTrue(historyWebView.links[todaySiteTitle].exists, "Today's site should still be in history after refresh")

        // Verify yesterday still shows empty state after refresh
        yesterdayButton.click()
        XCTAssertTrue(emptyHistoryText.exists, "Yesterday section should still show empty message after refresh")

        // Verify storage was preserved (cookies toggle was off)
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyInitialCountersSet()
    }

    func test_historyView_deleteWeekDay_onlyCookies() throws {
        // Populate fake history from debug menu to ensure we have week day history
        populateFakeHistoryFromDebugMenu()

        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!

        // Visit sites and set storage
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        let todaySiteTitle = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: todaySiteTitle)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Find any week day button (Monday through Sunday)
        let weekDays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        var foundWeekDayButton: XCUIElement?
        var foundDay = ""
        for day in weekDays {
            let button = historyWebView.buttons["Show history for \(day)"]
            if button.exists {
                foundWeekDayButton = button
                foundDay = day
                break
            }
        }

        XCTAssertNotNil(foundWeekDayButton, "At least one week day section should exist")

        // Hover week day section button to reveal delete button
        foundWeekDayButton!.hover()

        // Click delete button for week day
        let deleteWeekDayButton = historyWebView.buttons["Delete history for \(foundDay)"]
        XCTAssertTrue(deleteWeekDayButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Delete week day button should appear on hover")
        deleteWeekDayButton.click()

        // Verify Fire dialog opens
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Verify no scope pill appears
        XCTAssertFalse(app.fireDialogSegmentedControl.exists, "Scope pill should not appear for date deletion")

        // Verify no Close tabs toggle
        XCTAssertFalse(fireDialogTabsToggle.exists, "Tabs toggle should not appear for date-based deletion")

        // Configure toggles: only cookies
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })

        // Burn
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify History view still open
        XCTAssertTrue(historyWebView.exists, "History view should still be open")

        // Navigate to "today" section to verify it still has history
        let todayButton = historyWebView.buttons["Show history for today"]
        todayButton.click()
        XCTAssertTrue(historyWebView.links[todaySiteTitle].exists, "Today's site should still be in history (history toggle was off)")

        // Navigate to the week day section to verify it still has history (history toggle was off)
        foundWeekDayButton!.click()

        let emptyHistoryText = historyWebView.staticTexts["No browsing history yet."]
        XCTAssertFalse(emptyHistoryText.exists, "\(foundDay) section should NOT be empty when history toggle was off")

        // Refresh history (Cmd+R)
        app.typeKey("r", modifierFlags: [.command])
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should still exist after refresh")

        // Verify today's site still preserved after refresh
        todayButton.click()
        XCTAssertTrue(historyWebView.links[todaySiteTitle].exists, "Today's site should still be in history after refresh")

        // Verify week day still has history after refresh (history toggle was off)
        foundWeekDayButton!.click()
        XCTAssertFalse(emptyHistoryText.exists, "\(foundDay) section should still NOT be empty after refresh when history toggle was off")

        // Verify storage was cleared (cookies toggle was on)
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyInitialCountersSet()
    }

    func test_historyView_deleteOlder_historyAndCookies() throws {
        // Populate fake history from debug menu to ensure we have older history
        populateFakeHistoryFromDebugMenu()

        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!

        // Visit sites and set storage today
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        let todaySiteTitle = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: todaySiteTitle)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Verify older section exists
        let olderButton = historyWebView.buttons["Show older history"]
        XCTAssertTrue(olderButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Older button should exist")

        // Hover "Older" section button to reveal delete button
        olderButton.hover()

        // Click delete button for older
        let deleteOlderButton = historyWebView.buttons["Delete older history"]
        XCTAssertTrue(deleteOlderButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Delete older button should appear on hover")
        deleteOlderButton.click()

        // Verify Fire dialog opens
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Verify no scope pill appears
        XCTAssertFalse(app.fireDialogSegmentedControl.exists, "Scope pill should not appear for date deletion")

        // Verify no Close tabs toggle
        XCTAssertFalse(fireDialogTabsToggle.exists, "Tabs toggle should not appear for date-based deletion")

        // Configure toggles: history + cookies
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })

        // Burn
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify History view still open
        XCTAssertTrue(historyWebView.exists, "History view should still be open")

        // Navigate to "today" section to verify it still has history
        let todayButton = historyWebView.buttons["Show history for today"]
        todayButton.click()
        XCTAssertTrue(historyWebView.links[todaySiteTitle].exists, "Today's site should still be in history")

        // Verify "older" section no longer exists (it disappears when empty)
        XCTAssertFalse(olderButton.exists, "Older section should not exist after deletion")

        // Refresh history (Cmd+R)
        app.typeKey("r", modifierFlags: [.command])
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should still exist after refresh")

        // Verify today's site still preserved after refresh
        todayButton.click()
        XCTAssertTrue(historyWebView.links[todaySiteTitle].exists, "Today's site should still be in history after refresh")

        // Verify older section still doesn't exist after refresh
        XCTAssertFalse(olderButton.exists, "Older section should still not exist after refresh")

        // Storage cleared for older history, but today's storage is new so we verify it was cleared
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyInitialCountersSet()
    }

    // MARK: - History View Individual Record Deletion Tests (No Dialog)

    func test_historyView_deleteSingleRecord_viaRightClick() throws {
        let site1Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.openSite(pageTitle: site1Title)

        let site2Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: site2Title)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Verify both sites exist
        let site1Link = historyWebView.links[site1Title]
        XCTAssertTrue(site1Link.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Site 1 should be in history")
        let site2Link = historyWebView.links[site2Title]
        XCTAssertTrue(site2Link.exists, "Site 2 should be in history")

        // Right-click site 1 and select Delete from context menu
        site1Link.rightClick()
        try app.clickContextMenuItem { $0.title == "Delete" }

        // Verify Fire dialog does NOT appear (single record deletion is direct)
        XCTAssertFalse(fireDialogTitle.exists, "Fire dialog should not appear for single record deletion")

        // Verify site 1 deleted, site 2 preserved
        XCTAssertFalse(site1Link.exists, "Site 1 should be deleted")
        XCTAssertTrue(site2Link.exists, "Site 2 should still be in history")

        // Refresh history (Cmd+R)
        app.typeKey("r", modifierFlags: [.command])
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should still exist after refresh")

        // Verify site 1 still deleted after refresh
        XCTAssertFalse(historyWebView.links[site1Title].exists, "Site 1 should not reappear after refresh")
        XCTAssertTrue(historyWebView.links[site2Title].exists, "Site 2 should still be in history after refresh")
    }

    func test_historyView_deleteSingleRecord_viaDeleteKey() throws {
        let site1Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.openSite(pageTitle: site1Title)

        let site2Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: site2Title)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Verify both sites exist
        let site1Link = historyWebView.links[site1Title]
        XCTAssertTrue(site1Link.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Site 1 should be in history")
        let site2Link = historyWebView.links[site2Title]
        XCTAssertTrue(site2Link.exists, "Site 2 should be in history")

        // Click to select site 1
        site1Link.click()

        // Press Delete key
        app.typeKey(.delete, modifierFlags: [])

        // Verify Fire dialog does NOT appear (single record deletion is direct)
        XCTAssertFalse(fireDialogTitle.exists, "Fire dialog should not appear for single record deletion")

        // Verify site 1 deleted, site 2 preserved
        XCTAssertFalse(site1Link.exists, "Site 1 should be deleted")
        XCTAssertTrue(site2Link.exists, "Site 2 should still be in history")

        // Refresh history (Cmd+R)
        app.typeKey("r", modifierFlags: [.command])
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should still exist after refresh")

        // Verify site 1 still deleted after refresh
        XCTAssertFalse(historyWebView.links[site1Title].exists, "Site 1 should not reappear after refresh")
        XCTAssertTrue(historyWebView.links[site2Title].exists, "Site 2 should still be in history after refresh")
    }

    func test_historyView_deleteSingleRecord_viaDeleteButton() throws {
        let site1Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.openSite(pageTitle: site1Title)

        let site2Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: site2Title)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Verify both sites exist
        let site1Link = historyWebView.links[site1Title]
        XCTAssertTrue(site1Link.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Site 1 should be in history")
        let site2Link = historyWebView.links[site2Title]
        XCTAssertTrue(site2Link.exists, "Site 2 should be in history")

        // Click to select site 1
        site1Link.click()

        // Click Delete button in toolbar
        let deleteButton = historyWebView.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Delete button should appear when item is selected")
        deleteButton.click()

        // Verify Fire dialog does NOT appear (single record deletion is direct)
        XCTAssertFalse(fireDialogTitle.exists, "Fire dialog should not appear for single record deletion")

        // Verify site 1 deleted, site 2 preserved
        XCTAssertFalse(site1Link.exists, "Site 1 should be deleted")
        XCTAssertTrue(site2Link.exists, "Site 2 should still be in history")

        // Refresh history (Cmd+R)
        app.typeKey("r", modifierFlags: [.command])
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should still exist after refresh")

        // Verify site 1 still deleted after refresh
        XCTAssertFalse(historyWebView.links[site1Title].exists, "Site 1 should not reappear after refresh")
        XCTAssertTrue(historyWebView.links[site2Title].exists, "Site 2 should still be in history after refresh")
    }

    func test_historyView_deleteSingleRecord_viaHoverGroupButton() throws {
        let site1Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.openSite(pageTitle: site1Title)

        let site2Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: site2Title)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Verify both sites exist
        let site1Link = historyWebView.links[site1Title]
        XCTAssertTrue(site1Link.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Site 1 should be in history")
        let site2Link = historyWebView.links[site2Title]
        XCTAssertTrue(site2Link.exists, "Site 2 should be in history")

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

        // Verify Fire dialog does NOT appear (single record deletion is direct)
        XCTAssertFalse(fireDialogTitle.exists, "Fire dialog should not appear for single record deletion")

        // Verify site 1 deleted, site 2 preserved
        XCTAssertFalse(site1Link.exists, "Site 1 should be deleted")
        XCTAssertTrue(site2Link.exists, "Site 2 should still be in history")

        // Refresh history (Cmd+R)
        app.typeKey("r", modifierFlags: [.command])
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should still exist after refresh")

        // Verify site 1 still deleted after refresh
        XCTAssertFalse(historyWebView.links[site1Title].exists, "Site 1 should not reappear after refresh")
        XCTAssertTrue(historyWebView.links[site2Title].exists, "Site 2 should still be in history after refresh")
    }

    // MARK: - History View Multi-select Deletion Tests (With Dialog)

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

    // MARK: - History View Sites Section Deletion Tests

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

    // MARK: - Helper Methods

    private func populateFakeHistoryFromDebugMenu(file: StaticString = #file, line: UInt = #line) {
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

    private func openFireDialog(file: StaticString = #file, line: UInt = #line) {
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

    private func setStorageAndCookies(file: StaticString = #file, line: UInt = #line) {
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

    private func verifyInitialCountersSet(file: StaticString = #file, line: UInt = #line) {
        verifyCounterSet("Cookie", at: 0, file: file, line: line)
    }

    private func verifyCountersSet(file: StaticString = #file, line: UInt = #line) {
        verifyCounterSet("Storage", at: 1, file: file, line: line)
        verifyCounterSet("Cookie", at: 1, file: file, line: line)
    }

    private func verifyCounterSet(_ counterName: String, at offset: Int, file: StaticString = #file, line: UInt = #line) {
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

    private func verifyCounterCleared(_ counterName: String, file: StaticString = #file, line: UInt = #line) {
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

    private func verifyCountersCleared(file: StaticString = #file, line: UInt = #line) {
        verifyCounterCleared("Storage", file: file, line: line)
        verifyCounterCleared("Cookie", file: file, line: line)
    }

    private func fireproofCurrentSite(file: StaticString = #file, line: UInt = #line) {
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

    private func waitForFireAnimationToComplete() {
        RunLoop.main.run(until: Date().addingTimeInterval(2.0))
        XCTAssertTrue( // Let any ongoing fire animation or data processes complete
            app.fakeFireButton.waitForNonExistence(timeout: UITests.Timeouts.fireAnimation),
            "Fire animation didn't finish and cease existing in a reasonable timeframe."
        )
    }
}
