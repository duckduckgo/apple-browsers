//
//  FireDialogWindowScopeUITests.swift
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

/// Window Scope Fire Dialog UI tests
final class FireDialogWindowScopeUITests: UITestCase, FireDialogUITests {

    override func setUp() {
        super.setUp()
        setUpFireDialogUITests()
    }

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

}
