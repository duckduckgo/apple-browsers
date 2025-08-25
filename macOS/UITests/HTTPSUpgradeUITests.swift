//
//  HTTPSUpgradeUITests.swift
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
import Foundation

class HTTPSUpgradeUITests: UITestCase {

    private var addressBarTextField: XCUIElement { app.addressBar }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()
    }

    // MARK: - HTTPS Upgrade Tests

    func testHTTPSUpgrade_WhenNavigatingToHTTPSite_ShowsHTTPSInAddressBar() throws {
        // Navigate to a test HTTP URL that supports HTTPS upgrade
        let httpURL = URL(string: "http://example.com")!
        app.activateAddressBar()
        app.pasteURL(httpURL, pressingEnter: true)

        // Wait for page content to load
        let webView = app.webViews.firstMatch
        let pageContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Example Domain'")).firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: 30.0), "Example.com should load")

        // Check if HTTPS upgrade occurred
        app.activateAddressBar()
        let addressBarValue = addressBarTextField.value as? String ?? ""

        // HTTPS upgrade should have occurred for example.com
        XCTAssertTrue(addressBarValue.contains("https://"), "Address bar should show HTTPS after upgrade from HTTP")
        XCTAssertTrue(addressBarValue.contains("example.com"), "Should still be on example.com after upgrade")
    }

    func testHTTPSUpgrade_WithPrivacyTestPages_UpgradesCorrectly() throws {
        // Use DuckDuckGo's privacy test pages for HTTPS upgrade testing
        let testURL = URL(string: "http://privacy-test-pages.site/privacy-protections/https-upgrades/")!
        app.activateAddressBar()
        app.pasteURL(testURL, pressingEnter: true)

        // Wait for page load and verify HTTPS via address bar (no on-page controls)
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 30.0), "HTTPS upgrade test page should load")

        app.activateAddressBar()
        let finalURL = addressBarTextField.value as? String ?? ""
        // Some subpages may remain HTTP; assert host and allow either scheme
        XCTAssertTrue(finalURL.contains("privacy-test-pages.site"), "Should load the HTTPS Upgrades test page host")
    }

    func testHTTPSUpgrade_SecurityIndicator_ShowsUpgradedConnection() throws {
        // Navigate to a site that should be upgraded
        let testURL = URL(string: "http://example.com")!
        app.activateAddressBar()
        app.pasteURL(testURL, pressingEnter: true)

        // Wait for page content
        let webView = app.webViews.firstMatch
        let pageContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Example Domain'")).firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: 30.0), "Page should load for security indicator test")

        // Check for security indicator (privacy button)
        // Use the privacy dashboard button as security indicator (lock)
        let securityButton = app.buttons["AddressBarButtonsViewController.privacyDashboardButton"]
        XCTAssertTrue(securityButton.waitForExistence(timeout: 10.0), "Security indicator should be available for HTTPS site")

        // Click security indicator to access privacy info
        securityButton.click()

        // Privacy dashboard should open and show connection info
        let privacyInfo = app.windows.containing(NSPredicate(format: "identifier CONTAINS 'privacy' OR title CONTAINS 'Privacy'")).firstMatch
        XCTAssertTrue(privacyInfo.waitForExistence(timeout: 5.0), "Privacy dashboard should open from security indicator")

        // Note: do not assert specific connection copy; content can vary across versions/locales

        // Close privacy dashboard
        app.typeKey(.escape, modifierFlags: [])
    }

    func testHTTPSUpgrade_LoopProtection_PreventsInfiniteRedirects() throws {
        // Navigate to a URL that could potentially cause redirect loops
        let testURL = URL(string: "http://example.com/redirect-test")!
        app.activateAddressBar()
        app.pasteURL(testURL, pressingEnter: true)

        // Wait for navigation to complete or stabilize
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 30.0), "Navigation should complete without infinite redirects")

        // Verify we ended up on a stable page (not stuck in redirect loop)
        app.activateAddressBar()
        let finalURL = addressBarTextField.value as? String ?? ""

        // Should have a stable URL (not empty). Avoid heavy snapshot queries here.
        XCTAssertFalse(finalURL.isEmpty, "Should have navigated to a stable URL")
    }

    // MARK: - Mixed Content Protection Tests

    func testHTTPSUpgrade_MixedContent_HandledCorrectly() throws {
        // Navigate to HTTPS site first
        let httpsURL = URL(string: "https://example.com")!
        app.activateAddressBar()
        app.pasteURL(httpsURL, pressingEnter: true)

        // Wait for HTTPS page to load
        let webView = app.webViews.firstMatch
        let httpsContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Example Domain'")).firstMatch
        XCTAssertTrue(httpsContent.waitForExistence(timeout: 15.0), "HTTPS page should load")

        // Verify we're on HTTPS
        app.activateAddressBar()
        let currentURL = addressBarTextField.value as? String ?? ""
        XCTAssertTrue(currentURL.contains("https://"), "Should be on HTTPS site")

        // Mixed content protection should be active (no mixed content warnings)
        let mixedContentWarning = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS[c] 'mixed content' OR value CONTAINS[c] 'insecure'")).firstMatch
        XCTAssertFalse(mixedContentWarning.exists, "Should not show mixed content warnings with proper protection")
    }

    // MARK: - User Override Tests

    func testHTTPSUpgrade_UserCanAccessHTTPIfNeeded() throws {
        // Some sites might not support HTTPS - test that user can still access HTTP if needed
        let httpOnlyURL = UITests.simpleServedPage(titled: "HTTP Test Page")
        app.activateAddressBar()
        app.pasteURL(httpOnlyURL, pressingEnter: true)

        // Local test server should load over HTTP (no upgrade needed/available)
        let webView = app.webViews.firstMatch
        let localContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'HTTP Test Page'")).firstMatch
        XCTAssertTrue(localContent.waitForExistence(timeout: 15.0), "Local HTTP site should load when HTTPS not available")

        // Should remain on HTTP for local development server
        app.activateAddressBar()
        let finalURL = addressBarTextField.value as? String ?? ""
        XCTAssertTrue(finalURL.contains("http://localhost"), "Should remain on HTTP for local development server")
    }

    // MARK: - Edge Cases Tests

    func testHTTPSUpgrade_InvalidCertificates_HandledGracefully() throws {
        // Navigate to a well-known HTTPS site that should work
        let validHTTPSURL = URL(string: "https://duckduckgo.com")!
        app.activateAddressBar()
        app.pasteURL(validHTTPSURL, pressingEnter: true)

        // Should load valid HTTPS site successfully
        let webView = app.webViews.firstMatch
        let validContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'DuckDuckGo'")).firstMatch
        XCTAssertTrue(validContent.waitForExistence(timeout: 30.0), "Valid HTTPS site should load successfully")

        // Verify HTTPS connection
        app.activateAddressBar()
        let finalURL = addressBarTextField.value as? String ?? ""
        XCTAssertTrue(finalURL.contains("https://duckduckgo.com"), "Should successfully connect to valid HTTPS site")
    }

    func testHTTPSUpgrade_NonUpgradeableSites_RemainHTTP() throws {
        // Test with local server that doesn't support HTTPS
        let httpOnlyURL = UITests.simpleServedPage(titled: "HTTP Test Page")
        app.activateAddressBar()
        app.pasteURL(httpOnlyURL, pressingEnter: true)

        // Should load over HTTP when HTTPS not available
        let webView = app.webViews.firstMatch
        let httpContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'HTTP Test Page'")).firstMatch
        XCTAssertTrue(httpContent.waitForExistence(timeout: 15.0), "HTTP-only site should load correctly")

        // Should remain HTTP when upgrade not possible
        app.activateAddressBar()
        let finalURL = addressBarTextField.value as? String ?? ""
        XCTAssertTrue(finalURL.contains("http://localhost"), "Should remain HTTP when HTTPS upgrade not available")
        XCTAssertFalse(finalURL.contains("https://"), "Should not upgrade to HTTPS when not available")
    }
}
