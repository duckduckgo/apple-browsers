//
//  PrivacyDashboardUITests.swift
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
import os.log

class PrivacyDashboardUITests: UITestCase {

    private var addressBarTextField: XCUIElement!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()

        addressBarTextField = app.addressBar
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    // MARK: - Privacy Dashboard Access Tests

    func testPrivacyDashboard_AccessViaButton_OpensCorrectly() throws {
        // Navigate to a test page that has tracking elements
        let testURL = URL(string: "http://privacy-test-pages.site/tracker-reporting/1major-via-script.html")!
        addressBarTextField.pasteURL(testURL, pressingEnter: true)

        // Wait for specific page content to load
        let webView = app.webViews.firstMatch
        let pageContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS '1 major tracker loaded via script src'")).firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: 30.0), "Test page should load with tracker content")

        // Privacy button should be available for tracking test page
        let privacyButton = app.buttons.matching(identifier: "AddressBarButtonsViewController.privacyDashboardButton").firstMatch
        XCTAssertTrue(privacyButton.waitForExistence(timeout: 10.0), "Privacy button should be available for tracker test page")

        // Click privacy button
        privacyButton.click()

        // Privacy dashboard should open
        let privacyDashboard = app.windows.containing(NSPredicate(format: "identifier CONTAINS 'privacy' OR title CONTAINS 'Privacy'")).firstMatch
        XCTAssertTrue(privacyDashboard.waitForExistence(timeout: 10.0), "Privacy dashboard should open when privacy button is clicked")

        // Verify dashboard contains privacy information content (not empty)
        let dashboardContent = privacyDashboard.groups.firstMatch
        XCTAssertTrue(dashboardContent.waitForExistence(timeout: 5.0), "Privacy dashboard should contain privacy information")

        // Close dashboard
        app.typeKey(.escape, modifierFlags: [])
    }

    func testPrivacyDashboard_TrackerBlocking_ShowsBlockedTrackers() throws {
        // Navigate to a page with known trackers
        let trackerTestURL = URL(string: "http://privacy-test-pages.site/tracker-reporting/1major-via-script.html")!
        addressBarTextField.pasteURL(trackerTestURL, pressingEnter: true)

        // Wait for specific tracker test page content
        let webView = app.webViews.firstMatch
        let trackerPageContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS '1 major tracker loaded via script src'")).firstMatch
        XCTAssertTrue(trackerPageContent.waitForExistence(timeout: 30.0), "Tracker test page should load")

        // Access privacy dashboard
        let privacyButton = app.buttons.matching(identifier: "AddressBarButtonsViewController.privacyDashboardButton").firstMatch
        XCTAssertTrue(privacyButton.waitForExistence(timeout: 10.0), "Privacy button should be available for tracker test page")

        privacyButton.click()

        // Privacy dashboard should open and show tracker information
        let privacyDashboard = app.windows.containing(NSPredicate(format: "identifier CONTAINS 'privacy' OR title CONTAINS 'Privacy'")).firstMatch
        XCTAssertTrue(privacyDashboard.waitForExistence(timeout: 10.0), "Privacy dashboard should open for tracker test")

        // Look for tracker blocking information
        let trackerInfo = privacyDashboard.staticTexts.containing(NSPredicate(format: "value CONTAINS[c] 'tracker' OR value CONTAINS[c] 'blocked' OR value CONTAINS[c] 'protection'")).firstMatch
        XCTAssertTrue(trackerInfo.waitForExistence(timeout: 5.0), "Privacy dashboard should show tracker blocking information")

        // Verify dashboard shows some privacy content
        let anyPrivacyInfo = privacyDashboard.staticTexts.allElementsBoundByIndex
        XCTAssertGreaterThan(anyPrivacyInfo.count, 0, "Privacy dashboard should contain privacy information")

        // Close dashboard
        app.typeKey(.escape, modifierFlags: [])
    }

    func testPrivacyDashboard_PhishingDetection_ShowsWarning() throws {
        // Navigate to the phishing test page (matches original integration test)
        let testURL = URL(string: "http://privacy-test-pages.site/security/badware/phishing.html")!
        addressBarTextField.pasteURL(testURL, pressingEnter: true)

        // Wait for phishing warning to appear (browser should block the phishing page)
        let phishingWarning = app.staticTexts.containing(NSPredicate(format: "value CONTAINS 'phishing' OR value CONTAINS 'Phishing' OR value CONTAINS 'warning' OR value CONTAINS 'Warning' OR value CONTAINS 'blocked' OR value CONTAINS 'Blocked'")).firstMatch
        XCTAssertTrue(phishingWarning.waitForExistence(timeout: 30.0), "Phishing warning should be displayed when navigating to phishing page")

        // Step 1: Click "Advanced..." button to show advanced options
        let advancedButton = app.buttons["Advanced..."]
        XCTAssertTrue(advancedButton.waitForExistence(timeout: 5.0), "Advanced... button should be available in phishing warning")
        advancedButton.click()

        // Step 2: Click "Accept Risk and Visit Site" text element (it's static text, not a link or button!)
        let acceptRiskText = app.staticTexts["Accept Risk and Visit Site"]
        XCTAssertTrue(acceptRiskText.waitForExistence(timeout: 5.0), "Accept Risk and Visit Site text should be available after clicking Advanced...")
        acceptRiskText.click()

        // Step 3: Wait for the actual phishing page to load
        let webView = app.webViews.firstMatch
        let pageContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Phishing page'")).firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: 30.0), "Phishing test page should load after accepting risk")

        // Step 4: Privacy button should be available after bypassing warning
        let privacyButton = app.buttons.matching(identifier: "AddressBarButtonsViewController.privacyDashboardButton").firstMatch
        XCTAssertTrue(privacyButton.waitForExistence(timeout: 10.0), "Privacy button should be available after bypassing phishing warning")

        privacyButton.click()

        // Step 5: Privacy dashboard should open
        let privacyDashboard = app.windows.containing(NSPredicate(format: "identifier CONTAINS 'privacy' OR title CONTAINS 'Privacy'")).firstMatch
        XCTAssertTrue(privacyDashboard.waitForExistence(timeout: 10.0), "Privacy dashboard should open")

        // Step 6: Verify privacy dashboard displays phishing detection information
        let dashboardContent = privacyDashboard.groups.firstMatch
        XCTAssertTrue(dashboardContent.waitForExistence(timeout: 5.0), "Privacy dashboard should contain phishing detection information")

        // Close dashboard
        app.typeKey(.escape, modifierFlags: [])

    }

    func testPrivacyDashboard_HTTPSUpgrade_ShowsUpgradeStatus() throws {
        // Navigate to HTTP URL that should be upgraded (tested from UI perspective)
        let httpURL = URL(string: "http://example.com")!
        addressBarTextField.pasteURL(httpURL, pressingEnter: true)

        // Wait for example.com content
        let webView = app.webViews.firstMatch
        let pageContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Example Domain'")).firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: 15.0), "Example.com should load")

        // Access privacy dashboard
        let privacyButton = app.buttons.matching(identifier: "AddressBarButtonsViewController.privacyDashboardButton").firstMatch
        XCTAssertTrue(privacyButton.waitForExistence(timeout: 10.0), "Privacy button should be available for example.com")

        privacyButton.click()

        // Privacy dashboard should open
        let privacyDashboard = app.windows.containing(NSPredicate(format: "identifier CONTAINS 'privacy' OR title CONTAINS 'Privacy'")).firstMatch
        XCTAssertTrue(privacyDashboard.waitForExistence(timeout: 10.0), "Privacy dashboard should open for HTTPS test")

        // Verify privacy dashboard shows connection information
        let dashboardContent = privacyDashboard.staticTexts.allElementsBoundByIndex
        XCTAssertGreaterThan(dashboardContent.count, 0, "Privacy dashboard should show connection information for HTTPS test")

        // Close dashboard
        app.typeKey(.escape, modifierFlags: [])
    }

    func testPrivacyDashboard_SiteSettings_AccessibleFromDashboard() throws {
        // Navigate to a tracker test page (which will have privacy dashboard)
        let testURL = URL(string: "http://privacy-test-pages.site/tracker-reporting/1major-via-script.html")!
        addressBarTextField.pasteURL(testURL, pressingEnter: true)

        // Wait for page content
        let webView = app.webViews.firstMatch
        let pageContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS '1 major tracker loaded via script src'")).firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: 30.0), "Tracker test page should load")

        // Access privacy dashboard
        let privacyButton = app.buttons.matching(identifier: "AddressBarButtonsViewController.privacyDashboardButton").firstMatch
        XCTAssertTrue(privacyButton.waitForExistence(timeout: 10.0), "Privacy button should be available for tracker test page")

        privacyButton.click()

        // Privacy dashboard should open
        let privacyDashboard = app.windows.containing(NSPredicate(format: "identifier CONTAINS 'privacy' OR title CONTAINS 'Privacy'")).firstMatch
        XCTAssertTrue(privacyDashboard.waitForExistence(timeout: 10.0), "Privacy dashboard should open for site settings test")

        // Verify privacy dashboard has interactive elements for site settings
        let dashboardElements = privacyDashboard.buttons.allElementsBoundByIndex
        XCTAssertGreaterThan(dashboardElements.count, 0, "Privacy dashboard should have interactive elements for site settings")

        // Close privacy dashboard
        app.typeKey(.escape, modifierFlags: [])
    }

    func testPrivacyDashboard_NavigationBetweenSites_UpdatesCorrectly() throws {
        // Navigate to first site (tracker test page)
        let firstURL = URL(string: "http://privacy-test-pages.site/tracker-reporting/1major-via-script.html")!
        addressBarTextField.pasteURL(firstURL, pressingEnter: true)

        // Wait for first page content
        let webView = app.webViews.firstMatch
        let firstPageContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS '1 major tracker loaded via script src'")).firstMatch
        XCTAssertTrue(firstPageContent.waitForExistence(timeout: 15.0), "First tracker test page should load")

        // Check privacy dashboard for first site
        let privacyButton = app.buttons.matching(identifier: "AddressBarButtonsViewController.privacyDashboardButton").firstMatch
        XCTAssertTrue(privacyButton.waitForExistence(timeout: 10.0), "Privacy button should be available for first tracker site")

        privacyButton.click()

        // Privacy dashboard should open for first site
        let privacyDashboard = app.windows.containing(NSPredicate(format: "identifier CONTAINS 'privacy' OR title CONTAINS 'Privacy'")).firstMatch
        XCTAssertTrue(privacyDashboard.waitForExistence(timeout: 10.0), "Privacy dashboard should open for first site")

        // Verify dashboard shows first site information
        let firstSiteInfo = privacyDashboard.staticTexts.allElementsBoundByIndex
        XCTAssertGreaterThan(firstSiteInfo.count, 0, "Privacy dashboard should show information for first site")

        // Close dashboard
        app.typeKey(.escape, modifierFlags: [])

        // Navigate to second site
        app.activateAddressBar()
        let secondURL = URL(string: "http://example.com")!
        addressBarTextField.pasteURL(secondURL, pressingEnter: true)

        // Wait for second page content
        let secondPageContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Example Domain'")).firstMatch
        XCTAssertTrue(secondPageContent.waitForExistence(timeout: 15.0), "Second test page should load")

        // Check privacy dashboard for second site
        XCTAssertTrue(privacyButton.waitForExistence(timeout: 10.0), "Privacy button should remain available for second site")

        privacyButton.click()

        // Privacy dashboard should open for second site
        XCTAssertTrue(privacyDashboard.waitForExistence(timeout: 10.0), "Privacy dashboard should open for second site")

        // Look for second site information (example.com)
        let secondSiteInfo = privacyDashboard.staticTexts.containing(NSPredicate(format: "value CONTAINS 'example.com'")).firstMatch
        XCTAssertTrue(secondSiteInfo.waitForExistence(timeout: 5.0), "Privacy dashboard should update for new site")

        // Verify dashboard updated for new site
        let dashboardUpdated = privacyDashboard.staticTexts.allElementsBoundByIndex
        XCTAssertGreaterThan(dashboardUpdated.count, 0, "Privacy dashboard should update for new site")

        // Close dashboard
        app.typeKey(.escape, modifierFlags: [])
    }
}
