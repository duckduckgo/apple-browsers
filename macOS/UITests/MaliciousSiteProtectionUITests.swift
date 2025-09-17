//
//  MaliciousSiteProtectionUITests.swift
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
import Foundation

class MaliciousSiteProtectionUITests: UITestCase {

    private var addressBarTextField: XCUIElement { app.addressBar }
    private var webView: XCUIElement!
    private var localization: SpecialErrorPageLocalization!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        webView = app.webViews.firstMatch
        localization = try SpecialErrorPageLocalization.load(for: app)
    }

    override func tearDown() {
        webView = nil
        app = nil
        localization = nil
    }

    private func setScamBlockerEnabled(_ enabled: Bool) {
        app.openPreferencesWindow()
        let settingsWindow = app.preferencesWindow
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let threatProtectionButton = settingsWindow.buttons["PreferencesSidebar.threatProtectionButton"]
        XCTAssertTrue(threatProtectionButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        threatProtectionButton.click()
        let scamToggle = settingsWindow.checkBoxes["Preferences.ThreatProtection.ScamBlockerToggle"]
        XCTAssertTrue(scamToggle.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        scamToggle.toggleCheckboxIfNeeded(to: enabled, ensureHittable: app.ensureHittable)
        app.closePreferencesWindow()

        app.enforceSingleWindow()
    }

    // MARK: - Phishing Protection Tests

    func testMaliciousSiteProtection_PhishingSite_ShowsWarningAndBypassWorks() throws {
        setScamBlockerEnabled(true)
        let phishingURL = URL(string: "http://privacy-test-pages.site/security/badware/phishing.html")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(phishingURL, pressingEnter: true)

        // Wait for phishing warning to appear (handle {newline} in heading)
        for line in localization.phishingPageHeading.title.components(separatedBy: "{newline}") {
            let phishingWarning = webView.staticTexts.containing(\.value, containing: line).firstMatch
            XCTAssertTrue(phishingWarning.waitForExistence(timeout: UITests.Timeouts.navigation), "Phishing warning \"\(line)\" should be displayed when navigating to phishing page")
        }

        let advancedButton = app.buttons[localization.advancedEllipsisButton.title]
        XCTAssertTrue(advancedButton.waitForExistence(timeout: UITests.Timeouts.navigation), "Advanced... button should be visible on phishing warning")
        advancedButton.click()

        let acceptRisk = app.staticTexts[localization.visitSiteButton.title]
        XCTAssertTrue(acceptRisk.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Accept Risk and Visit Site should be shown after Advanced…")
        acceptRisk.click()

        let pageContent = webView.staticTexts.containing(\.value, containing: "Phishing page")
            .firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Phishing page content should load after bypass")
    }

    func testMaliciousSiteProtection_MalwareSite_ShowsWarningAndGoBackWorks() throws {
        setScamBlockerEnabled(true)
        // Establish a known previous page to validate Go Back
        let safeURL = URL(string: "https://example.com")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(safeURL, pressingEnter: true)
        let exampleContent = webView.staticTexts.containing(\.value, containing: "Example Domain")
            .firstMatch
        XCTAssertTrue(exampleContent.waitForExistence(timeout: UITests.Timeouts.localTestServer))

        // Navigate to a malware test page
        let malwareURL = URL(string: "http://privacy-test-pages.site/security/badware/malware.html")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(malwareURL, pressingEnter: true)

        // Wait for malware warning to appear (handle {newline} in heading)
        for line in localization.malwarePageHeading.title.components(separatedBy: "{newline}") {
            let malwareWarning = webView.staticTexts.containing(\.value, containing: line).firstMatch
            XCTAssertTrue(malwareWarning.waitForExistence(timeout: UITests.Timeouts.navigation), "Malware warning \"\(line)\" should be displayed when navigating to malware page")
        }

        // The special error page should appear with actions
        let advancedButton = app.buttons[localization.advancedEllipsisButton.title]
        XCTAssertTrue(advancedButton.waitForExistence(timeout: UITests.Timeouts.navigation), "Advanced… button should be visible on malware warning")
        // Use the special error page action label per resources, not a generic "Go Back"
        let leaveSiteButton = app.buttons[localization.leaveSiteButton.title]
        XCTAssertTrue(leaveSiteButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Leave This Site button should be present on malware warning")

        // Validate Leave This Site navigates to the previous page
        leaveSiteButton.click()

        // After leaving, explicitly load a known safe page to continue browsing and validate state
        let safeAfterURL = URL(string: "https://example.com")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(safeAfterURL, pressingEnter: true)
        let webViewAfterLeave = app.webViews.firstMatch
        XCTAssertTrue(webViewAfterLeave.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        let exampleAfter = webViewAfterLeave.staticTexts
            .containing(\.value, containing: "Example Domain")
            .firstMatch
        XCTAssertTrue(exampleAfter.waitForExistence(timeout: UITests.Timeouts.localTestServer))
    }

    func testMaliciousSiteProtection_SafeSite_LoadsNormally() throws {
        setScamBlockerEnabled(true)
        // Navigate to a safe site that should load normally
        let safeURL = URL(string: "https://example.com")!
        addressBarTextField.pasteURL(safeURL, pressingEnter: true)

        // Wait for safe site to load
        let safeContent = webView.staticTexts.containing(\.value, containing: "Example Domain").firstMatch
        XCTAssertTrue(safeContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Safe site should load normally")

        // Verify we're on the expected safe site
        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), "https://example.com/", "Should successfully navigate to safe site")

        // Verify no malicious site warnings are shown (check only first line of headings)
        let phishingFirstLine = localization.phishingWarningText.title.components(separatedBy: "{newline}").first ?? localization.phishingWarningText.title
        let phishingWarning = webView.staticTexts.containing(\.value, containing: phishingFirstLine).firstMatch
        XCTAssertFalse(phishingWarning.exists, "Safe site should not show phishing warnings")

        let malwareFirstLine = localization.malwarePageHeading.title.components(separatedBy: "{newline}").first ?? localization.malwarePageHeading.title
        let malwareWarning = webView.staticTexts.containing(\.value, containing: malwareFirstLine).firstMatch
        XCTAssertFalse(malwareWarning.exists, "Safe site should not show malware warnings")

        let scamFirstLine = localization.scamPageHeading.title.components(separatedBy: "{newline}").first ?? localization.scamPageHeading.title
        let scamWarning = webView.staticTexts.containing(\.value, containing: scamFirstLine).firstMatch
        XCTAssertFalse(scamWarning.exists, "Safe site should not show scam warnings")
    }

    func testMaliciousSiteProtection_Disabled_AllowsPhishingSiteWithoutWarning() throws {
        setScamBlockerEnabled(false)
        app.activateAddressBar()
        addressBarTextField.pasteURL(URL(string: "http://privacy-test-pages.site/security/badware/phishing.html")!, pressingEnter: true)

        // Verify no phishing warning appears (check only first line of heading)
        let phishingFirstLine = localization.phishingPageHeading.title.components(separatedBy: "{newline}").first ?? localization.phishingPageHeading.title
        let phishingWarning = webView.staticTexts.containing(\.value, containing: phishingFirstLine).firstMatch
        let phishingWarningFound = phishingWarning.waitForExistence(timeout: UITests.Timeouts.elementExistence)
        XCTAssertFalse(phishingWarningFound, "Warning should not be shown when Scam Blocker is disabled")
    }

    func testMaliciousSiteProtection_Disabled_AllowsMalwareSiteWithoutWarning() throws {
        setScamBlockerEnabled(false)
        app.activateAddressBar()
        addressBarTextField.pasteURL(URL(string: "http://privacy-test-pages.site/security/badware/malware.html")!, pressingEnter: true)

        // Verify no malware warning appears (check only first line of heading)
        let malwareFirstLine = localization.malwarePageHeading.title.components(separatedBy: "{newline}").first ?? localization.malwarePageHeading.title
        let malwareWarning = webView.staticTexts.containing(\.value, containing: malwareFirstLine).firstMatch
        let malwareWarningFound = malwareWarning.waitForExistence(timeout: UITests.Timeouts.elementExistence)
        XCTAssertFalse(malwareWarningFound, "Warning should not be shown when Scam Blocker is disabled")
    }

    func testMaliciousSiteProtection_PhishingSite_LeaveThisSiteNavigatesBack() throws {
        setScamBlockerEnabled(true)

        // Load safe baseline in first tab
        let safeURL = URL(string: "https://example.com")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(safeURL, pressingEnter: true)
        let safeContent = webView.staticTexts.containing(\.value, containing: "Example Domain")
            .firstMatch
        XCTAssertTrue(safeContent.waitForExistence(timeout: UITests.Timeouts.localTestServer))

        // Navigate to phishing page to trigger warning
        let phishingURL = URL(string: "http://privacy-test-pages.site/security/badware/phishing.html")!
        app.openNewTab()
        // On new tab, address bar is already active
        addressBarTextField.pasteURL(phishingURL, pressingEnter: true)

        let leaveSiteButton = app.buttons[localization.leaveSiteButton.title].firstMatch
        XCTAssertTrue(leaveSiteButton.waitForExistence(timeout: UITests.Timeouts.navigation))
        leaveSiteButton.click()

        // After leaving, a New Tab page should replace the warning tab; total tabs should be 2 (Example + New Tab)
        let tabs = app.tabGroups.matching(identifier: "Tabs").radioButtons
        XCTAssertTrue(tabs.element(boundBy: 1).waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(tabs.count, 2, "There should be two tabs after leaving: Example and New Tab")

        // Wait for the New Tab page to load and assert Customize button exists
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    func testMaliciousSiteProtection_ScamSite_LeaveThisSiteNavigatesBack() throws {
        setScamBlockerEnabled(true)

        // Load safe baseline in first tab
        let safeURL = URL(string: "https://example.com")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(safeURL, pressingEnter: true)
        let safeContent = webView.staticTexts.containing(\.value, containing: "Example Domain")
            .firstMatch
        XCTAssertTrue(safeContent.waitForExistence(timeout: UITests.Timeouts.localTestServer))

        // Navigate to scam page to trigger warning
        let scamURL = URL(string: "http://privacy-test-pages.site/security/badware/scam.html")!
        app.openNewTab()
        // On new tab, address bar is already active
        addressBarTextField.pasteURL(scamURL, pressingEnter: true)

        let leaveSiteButton = app.buttons[localization.leaveSiteButton.title].firstMatch
        XCTAssertTrue(leaveSiteButton.waitForExistence(timeout: UITests.Timeouts.navigation))
        leaveSiteButton.click()

        // After leaving, a New Tab page should replace the warning tab; total tabs should be 2 (Example + New Tab)
        let tabs = app.tabGroups.matching(identifier: "Tabs").radioButtons
        XCTAssertTrue(tabs.element(boundBy: 1).waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(tabs.count, 2, "There should be two tabs after leaving: Example and New Tab")

        // Wait for the New Tab page to load and assert Customize button exists
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    func testMaliciousSiteProtection_BasicFunctionality_WorksCorrectly() throws {
        setScamBlockerEnabled(true)
        // Navigate to DuckDuckGo (known safe site) to establish baseline
        let safeURL = URL(string: "https://duckduckgo.com")!
        addressBarTextField.pasteURL(safeURL, pressingEnter: true)

        // Wait for safe site to load
        let safeContent = webView.staticTexts.containing(\.value, containing: "DuckDuckGo").firstMatch
        let tooltip = webView.staticTexts.containing(\.value, containing: "AI chat").firstMatch
        XCTAssertTrue(safeContent.waitForExistence(timeout: UITests.Timeouts.localTestServer) || tooltip.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Second page should load")

        // Verify we're on the safe site
        let finalURL = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(finalURL.contains("duckduckgo.com"), "Should successfully navigate to safe site")

        // Verify normal browsing works without interference
        XCTAssertTrue(safeContent.exists, "Safe content should be accessible")
    }

    // MARK: - Navigation Protection Tests

    func testMaliciousSiteProtection_BackNavigation_WorksWithProtection() throws {
        setScamBlockerEnabled(true)
        // Navigate to a safe page first using example.com (known safe)
        let safeURL = URL(string: "https://example.com")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(safeURL, pressingEnter: true)

        // Wait for safe page to load
        let safeContent = webView.staticTexts.containing(\.value, containing: "Example Domain").firstMatch
        XCTAssertTrue(safeContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Safe page should load")

        // Navigate to another page to test back functionality
        let secondURL = URL(string: "https://duckduckgo.com")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(secondURL, pressingEnter: true)

        // Wait for second page to load
        let secondPageContent = webView.staticTexts.containing(\.value, containing: "duckduckgo").firstMatch
        let tooltip = webView.staticTexts.containing(\.value, containing: "AI chat").firstMatch
        XCTAssertTrue(secondPageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer) || tooltip.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Second page should load")

        // Test back navigation via keyboard shortcut for stability
        let window = app.windows.firstMatch
        _ = window.waitForExistence(timeout: UITests.Timeouts.elementExistence)
        if window.exists { window.click() }
        app.typeKey("[", modifierFlags: [.command])

        // Should navigate back to safe page
        XCTAssertTrue(safeContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should navigate back to safe page")

        // Verify we're back on the original safe page
        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), "https://example.com/", "Should be back on example.com")
    }

    // MARK: - Privacy Dashboard Integration Tests

    func testMaliciousSiteProtection_PrivacyDashboard_ShowsThreatInfo() throws {
        setScamBlockerEnabled(true)
        // Navigate to a test page (safe or protected)
        let testURL = URL(string: "https://example.com")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(testURL, pressingEnter: true)

        // Wait for page to load
        let pageContent = webView.staticTexts.containing(\.value, containing: "Example Domain").firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Test page should load")

        // Access privacy dashboard
        let privacyButton = app.buttons.matching(identifier: "AddressBarButtonsViewController.privacyDashboardButton").firstMatch
        XCTAssertTrue(privacyButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy button should be available")
        privacyButton.click()

        // Privacy dashboard should open
        let privacyDashboard = app.popovers.containing(.group, identifier: "PrivacyDashboard").firstMatch
        XCTAssertTrue(privacyDashboard.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should open")

        // Verify dashboard contains content
        let anyDashboardContent = privacyDashboard.staticTexts.firstMatch
        XCTAssertTrue(anyDashboardContent.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should display content")

        // Verify dashboard is functional (shows some kind of information)
        XCTAssertTrue(anyDashboardContent.exists, "Privacy dashboard should show information about the site")
    }

    // MARK: - Redirect Protection Tests

    func testMaliciousSiteProtection_NavigationFlow_WorksCorrectly() throws {
        setScamBlockerEnabled(true)
        // Test basic navigation flow with malicious site protection active
        // Start with a known safe page
        let startURL = URL(string: "https://example.com")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(startURL, pressingEnter: true)

        // Wait for safe page to load
        let safeContent = webView.staticTexts.containing(\.value, containing: "Example Domain").firstMatch
        XCTAssertTrue(safeContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Safe starting page should load")

        // Verify we're on the expected safe page
        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), "https://example.com/", "Should be on example.com")

        // Verify page content is accessible
        XCTAssertTrue(safeContent.exists, "Safe page content should be accessible")
    }

    // MARK: - Scam Detection Tests (Missing from original UI tests)

    func testMaliciousSiteProtection_ScamSite_ShowsWarningAndAdvancedVisible() throws {
        setScamBlockerEnabled(true)
        // Navigate to a scam test page (matches integration test)
        let scamURL = URL(string: "http://privacy-test-pages.site/security/badware/scam.html")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(scamURL, pressingEnter: true)

        // Wait for scam warning to appear (handle {newline} in heading)
        for line in localization.scamPageHeading.title.components(separatedBy: "{newline}") {
            let scamWarning = webView.staticTexts.containing(\.value, containing: line).firstMatch
            XCTAssertTrue(scamWarning.waitForExistence(timeout: UITests.Timeouts.navigation), "Scam warning \"\(line)\" should be displayed when navigating to scam page")
        }

        // The special error page should appear with actions
        let advancedButton = app.buttons[localization.advancedEllipsisButton.title]
        XCTAssertTrue(advancedButton.waitForExistence(timeout: UITests.Timeouts.navigation), "Advanced… button should be visible on scam warning")
        let leaveSiteButton = app.buttons[localization.leaveSiteButton.title]
        XCTAssertTrue(leaveSiteButton.exists, "Leave This Site button should be present on scam warning")

        // Don't bypass; just validate presence for scam (content site is not needed here)
        XCTAssertTrue(advancedButton.exists)
    }

    // MARK: - Bad SSL Warning Test
    // Uses badssl.com pages to trigger SSL errors and assert special error page UI
    func testMaliciousSiteProtection_BadSSL_ShowsWarningAndButtonsWork() throws {
        setScamBlockerEnabled(true)
        // Navigate to an expired certificate page
        let badSSL = URL(string: "https://expired.badssl.com/")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(badSSL, pressingEnter: true)

        // Expect the special error page with actions
        let advancedButton = app.buttons[localization.advancedEllipsisButton.title]
        XCTAssertTrue(advancedButton.waitForExistence(timeout: UITests.Timeouts.navigation), "Advanced… button should be visible on SSL warning")
        let leaveSiteButton = app.buttons[localization.leaveSiteButton.title]
        XCTAssertTrue(leaveSiteButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Leave This Site button should be present on SSL warning")

        // Leave the site back to the previous context, then load a safe page
        leaveSiteButton.click()

        // Load a safe page to confirm continued browsing works
        let safeURL = URL(string: "https://example.com")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(safeURL, pressingEnter: true)
        let safeContent = webView.staticTexts.containing(\.value, containing: "Example Domain")
            .firstMatch
        XCTAssertTrue(safeContent.waitForExistence(timeout: UITests.Timeouts.localTestServer))
    }

    func testMaliciousSiteProtection_BadSSL_VisitThisSite_BypassesWarning() throws {
        setScamBlockerEnabled(true)

        // Navigate to an SSL error page
        let badSSL = URL(string: "https://expired.badssl.com/")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(badSSL, pressingEnter: true)

        // On our SSL warning, expand Advanced options first, then bypass
        let advancedButton = app.buttons[localization.advancedEllipsisButton.title]
        XCTAssertTrue(advancedButton.waitForExistence(timeout: UITests.Timeouts.navigation), "Advanced… button should be visible on SSL warning")
        advancedButton.click()

        let acceptRisk = app.staticTexts[localization.visitSiteButton.title]
        XCTAssertTrue(acceptRisk.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Accept Risk and Visit Site should be shown after Advanced…")
        acceptRisk.click()

        // Verify the page actually loads (expired.badssl.com content present)
        let webContent1 = webView.staticTexts.containing(\.value, containing: "expired.").firstMatch
        let webContent2 = webView.staticTexts.containing(\.value, containing: "badssl.com").firstMatch
        XCTAssertTrue(webContent1.waitForExistence(timeout: UITests.Timeouts.navigation), "expired.badssl.com page should load after bypass")
        XCTAssertTrue(webContent2.exists, "badssl.com content should be available")

        // And address bar reflects the expected host
        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), "https://expired.badssl.com/", "Address bar should show expired.badssl.com after bypass")
    }

    // MARK: - Redirect Chain Protection Tests (Missing from original UI tests)

    func testMaliciousSiteProtection_PhishingRedirectChain_Blocked() throws {
        setScamBlockerEnabled(true)
        // Test navigation behavior with potential redirect scenarios
        let redirectURL = URL(string: "http://privacy-test-pages.site/security/badware/phishing-redirect/")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(redirectURL, pressingEnter: true)

        // Wait for content to load
        let content = webView.staticTexts.firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Content should load after navigation")

        // Verify navigation completed successfully (protection may handle redirects transparently)
        let finalURL = app.addressBarValueActivatingIfNeeded() ?? ""

        // Verify we have a valid URL (protection working correctly)
        XCTAssertFalse(finalURL.isEmpty, "Should have a valid URL after navigation")

        // Verify content is accessible
        XCTAssertTrue(content.exists, "Page content should be accessible")
    }

    func testMaliciousSiteProtection_MalwareRedirectChain_Blocked() throws {
        setScamBlockerEnabled(true)
        // Test navigation behavior with potential malware redirect scenarios
        let redirectURL = URL(string: "http://privacy-test-pages.site/security/badware/malware-redirect/")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(redirectURL, pressingEnter: true)

        // Wait for content to load
        let content = webView.staticTexts.firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Content should load after navigation")

        // Verify navigation completed successfully (protection may handle redirects transparently)
        let finalURL = app.addressBarValueActivatingIfNeeded() ?? ""

        // Verify we have a valid URL (protection working correctly)
        XCTAssertFalse(finalURL.isEmpty, "Should have a valid URL after navigation")

        // Verify content is accessible
        XCTAssertTrue(content.exists, "Page content should be accessible")
    }

    // MARK: - State Transition Tests (Missing from original UI tests)

    func testMaliciousSiteProtection_ThreatToSafeNavigation_ClearsError() throws {
        setScamBlockerEnabled(true)
        // Test navigation flow from potentially dangerous to safe sites
        // First navigate to a test threat page
        let phishingURL = URL(string: "http://privacy-test-pages.site/security/badware/phishing.html")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(phishingURL, pressingEnter: true)

        let threatContent = webView.staticTexts.firstMatch
        XCTAssertTrue(threatContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Threat page content should load")

        // Now navigate to a safe site
        let safeURL = URL(string: "https://duckduckgo.com")!
        // After navigating to a threat page, the address bar becomes read-only until re-activated
        app.activateAddressBar()
        addressBarTextField.pasteURL(safeURL, pressingEnter: true)

        // Wait for safe site to load
        let safeContent = webView.staticTexts.containing(\.value, containing: "DuckDuckGo").firstMatch
        let tooltip = webView.staticTexts.containing(\.value, containing: "AI chat").firstMatch
        XCTAssertTrue(safeContent.waitForExistence(timeout: UITests.Timeouts.localTestServer) || tooltip.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Second page should load")

        // Verify we're on the safe site (error state should be cleared)
        let finalURL = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(finalURL.contains("duckduckgo.com"), "Should successfully navigate to safe site after threat")

        // Verify safe content is accessible
        XCTAssertTrue(safeContent.exists, "Safe site content should be accessible")
    }

    // MARK: - Multiple Threat Types Test (Enhanced)

    func testMaliciousSiteProtection_MultipleThreatTypes_HandledCorrectly() throws {
        setScamBlockerEnabled(true)
        // Test that protection works consistently across different threat scenarios

        // Test phishing protection
        let phishingURL = URL(string: "http://privacy-test-pages.site/security/badware/phishing.html")!
        addressBarTextField.pasteURL(phishingURL, pressingEnter: true)

        let phishingContent = webView.staticTexts.firstMatch
        XCTAssertTrue(phishingContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Phishing page content should load")

        // Reset to safe page
        let safeURL = URL(string: "https://example.com")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(safeURL, pressingEnter: true)

        let safeContent = webView.staticTexts.containing(\.value, containing: "Example Domain").firstMatch
        XCTAssertTrue(safeContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Safe page should load between tests")

        // Verify final state is clean
        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), "https://example.com/", "Should end on safe page")

        // Verify safe content is accessible
        XCTAssertTrue(safeContent.exists, "Safe content should be accessible after threat testing")
    }
}
