//
//  FireDialogTabScopeUITests.swift
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

/// Tab Scope Fire Dialog UI tests
final class FireDialogTabScopeUITests: UITestCase, FireDialogUITests {

    override func setUp() {
        super.setUp()
        setUpFireDialogUITests()
    }

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

}
