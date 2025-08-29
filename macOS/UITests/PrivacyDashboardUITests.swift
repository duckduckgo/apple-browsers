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

// MARK: - Request Blocking Results JSON Structure
struct RequestBlockingResults: Decodable {
    let page: String
    let results: [RequestResult]
    let date: String
}

struct RequestResult: Decodable {
    let id: String
    let category: String
    let status: String
}

class PrivacyDashboardUITests: UITestCase {

    private var addressBarTextField: XCUIElement!
    private var webView: XCUIElement!
    private var privacyButton: XCUIElement!
    private var privacyDashboard: XCUIElement!
    private var localization: SpecialErrorPageLocalization!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()

        addressBarTextField = app.addressBar
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        webView = app.webViews.firstMatch
        privacyButton = app.buttons.matching(identifier: "AddressBarButtonsViewController.privacyDashboardButton").firstMatch
        privacyDashboard = app.popovers.containing(.group, identifier: "PrivacyDashboard").firstMatch
        localization = try SpecialErrorPageLocalization.load(for: app)
    }

    override func tearDown() {
        webView = nil
        privacyButton = nil
        privacyDashboard = nil
        addressBarTextField = nil
        app = nil
        localization = nil
        super.tearDown()
    }

    // MARK: - File Helper Methods

    private func getExistingRequestBlockingFiles() -> Set<String> {
        let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let baseFileName = "request-blocking-results"
        let fileExtension = "json"

        var existingFiles: Set<String> = []

        // Check for base file and numbered variants
        for i in 0..<20 { // Check up to 20 variants
            let fileName = i == 0 ? "\(baseFileName).\(fileExtension)" : "\(baseFileName) \(i).\(fileExtension)"
            let filePath = downloadsDirectory.appendingPathComponent(fileName).path

            if FileManager.default.fileExists(atPath: filePath) {
                existingFiles.insert(filePath)
            }
        }

        return existingFiles
    }

    private func waitForNewRequestBlockingFile(excluding existingFiles: Set<String>) -> String? {
        let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let baseFileName = "request-blocking-results"
        let fileExtension = "json"

        let maxAttempts = 10

        for _ in 0..<maxAttempts {
            // Check for base file and numbered variants
            for i in 0..<20 {
                let fileName = i == 0 ? "\(baseFileName).\(fileExtension)" : "\(baseFileName) \(i).\(fileExtension)"
                let filePath = downloadsDirectory.appendingPathComponent(fileName).path

                if FileManager.default.fileExists(atPath: filePath) && !existingFiles.contains(filePath) {
                    return filePath
                }
            }

            Thread.sleep(forTimeInterval: 0.5)
        }

        return nil
    }

    // MARK: - Privacy Dashboard Access Tests

    func testPrivacyDashboard_TrackerBlocking_ShowsBlockedTrackers() throws {
        throw XCTSkip("Flaky test")
        // Navigate to a page with known trackers
        let trackerTestURL = URL(string: "http://privacy-test-pages.site/tracker-reporting/1major-via-script.html")!
        addressBarTextField.pasteURL(trackerTestURL, pressingEnter: true)

        // Wait for specific tracker test page content
        let trackerPageContent = webView.staticTexts.containing(\.value, containing: "1 major tracker loaded via script src").firstMatch
        XCTAssertTrue(trackerPageContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Tracker test page should load")

        // Access privacy dashboard
        XCTAssertTrue(privacyButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy button should be available for tracker test page")

        privacyButton.click()

        // Privacy dashboard should open and show tracker information
        XCTAssertTrue(privacyDashboard.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should open")

        // Find and click "Enable Protections" checkbox (if it‘s unchecked)
        let enableProtectionsCheckbox = privacyDashboard.switches["Enable Protections"]
        if enableProtectionsCheckbox.waitForExistence(timeout: 1.0) {
            enableProtectionsCheckbox.click()
            // Wait for privacy dashboard to disappear (indicating page reload)
            XCTAssertTrue(privacyDashboard.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should disappear after re-enabling protections")

            privacyButton.click()

            // Privacy dashboard should open and show tracker information
            XCTAssertTrue(privacyDashboard.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should open")
        }

        // Click "View Tracker Companies" button to see detailed tracker information
        let viewTrackerCompaniesButton = privacyDashboard.buttons.containing(\.label, containing: "View Tracker Companies").firstMatch
        XCTAssertTrue(viewTrackerCompaniesButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "View Tracker Companies button should be available")

        viewTrackerCompaniesButton.click()

        // Verify that Google Ads (Google) appears in the tracker companies list
        let googleAdsTracker = privacyDashboard.staticTexts.containing(\.value, containing: "Google Ads").firstMatch
        XCTAssertTrue(googleAdsTracker.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Google Ads (Google) should appear in tracker companies list")

        // Close dashboard
        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(privacyDashboard.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should close")
    }

    func testPrivacyDashboard_TrackerBlocking_ShowsBlockedTrackersAtNYTimes() throws {
        // Navigate to a page with known trackers
        let trackerTestURL = URL(string: "https://nytimes.com")!
        addressBarTextField.pasteURL(trackerTestURL, pressingEnter: true)

        // Wait for specific tracker test page content
        let trackerPageContent = webView.staticTexts.containing(\.value, containing: "New York Times").firstMatch
        XCTAssertTrue(trackerPageContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Page should load")

        // Access privacy dashboard
        XCTAssertTrue(privacyButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy button should be available for tracker test page")

        privacyButton.click()

        // Privacy dashboard should open and show tracker information
        XCTAssertTrue(privacyDashboard.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should open")

        // Click "View Tracker Companies" button to see detailed tracker information
        let viewTrackerCompaniesButton = privacyDashboard.buttons.containing(\.label, containing: "View Tracker Companies").firstMatch
        XCTAssertTrue(viewTrackerCompaniesButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "View Tracker Companies button should be available")

        viewTrackerCompaniesButton.click()

        // Verify that Google Ads (Google) appears in the tracker companies list
        let googleAdsTracker = privacyDashboard.staticTexts.containing(\.value, containing: "Google Ads").firstMatch
        XCTAssertTrue(googleAdsTracker.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Google Ads (Google) should appear in tracker companies list")

        // Close dashboard
        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(privacyDashboard.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should close")
    }

    func testPrivacyDashboard_PhishingDetection_ShowsWarning() throws {
        // Navigate to the phishing test page (matches original integration test)
        let testURL = URL(string: "http://privacy-test-pages.site/security/badware/phishing.html")!
        addressBarTextField.pasteURL(testURL, pressingEnter: true)

        // Wait for phishing warning to appear (browser should block the phishing page)
        for line in localization.phishingPageHeading.title.components(separatedBy: "{newline}") {
            let phishingWarning = webView.staticTexts.containing(\.value, containing: line).firstMatch
            XCTAssertTrue(phishingWarning.waitForExistence(timeout: UITests.Timeouts.navigation), "Phishing warning \"\(line)\" should be displayed when navigating to phishing page")
        }

        // Step 1: Click "Advanced..." button to show advanced options
        let advancedButton = webView.buttons[localization.advancedEllipsisButton.title]
        XCTAssertTrue(advancedButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Advanced... button should be available in phishing warning")
        advancedButton.click()

        // Step 2: Click "Accept Risk and Visit Site" text element (it's static text, not a link or button!)
        let acceptRiskText = webView.staticTexts[localization.visitSiteButton.title]
        XCTAssertTrue(acceptRiskText.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Accept Risk and Visit Site text should be available after clicking Advanced...")
        acceptRiskText.hover()
        Thread.sleep(forTimeInterval: 0.5)
        acceptRiskText.click()

        // Step 3: Wait for the actual phishing page to load
        let pageContent = webView.staticTexts.containing(\.value, containing: "Phishing page").firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Phishing test page should load after accepting risk")

        // Step 4: Privacy button should be available after bypassing warning
        XCTAssertTrue(privacyButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy button should be available after bypassing phishing warning")

        privacyButton.click()

        // Step 5: Privacy dashboard should open
        XCTAssertTrue(privacyDashboard.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should open")

        // Step 6: Verify privacy dashboard displays phishing detection information
        let phishingInfo = privacyDashboard.staticTexts.containing(\.value, containing: "Site May Be a Security Risk").firstMatch
        XCTAssertTrue(phishingInfo.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should show phishing detection information")
    }

    func testPrivacyDashboard_HTTPSUpgrade_ShowsUpgradeStatus() throws {
        // Navigate to HTTP URL that should be upgraded (tested from UI perspective)
        let upgradedURL = URL(string: "http://example.com")!
        addressBarTextField.pasteURL(upgradedURL, pressingEnter: true)

        // Wait for example.com content
        let pageContent = webView.staticTexts.containing(\.value, containing: "Example Domain").firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Example.com should load")

        // Access privacy dashboard
        XCTAssertTrue(privacyButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy button should be available for example.com")

        privacyButton.click()

        // Privacy dashboard should open
        XCTAssertTrue(privacyDashboard.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should open for HTTPS test")

        // Verify privacy dashboard shows HTTPS connection information
        let connectionInfoButton = privacyDashboard.buttons["View Connection Information"]
        XCTAssertTrue(connectionInfoButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should show connection information button")
        connectionInfoButton.click()

        let encryptedConnectionInfo = privacyDashboard.staticTexts.containing(\.value, containing: "This page uses an encrypted connection").firstMatch
        XCTAssertTrue(encryptedConnectionInfo.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should show HTTPS connection information")
        XCTAssertTrue(privacyDashboard.staticTexts["Security Certificate Detail"].exists, "Privacy dashboard should show HTTPS connection information")
        XCTAssertTrue(privacyDashboard.staticTexts["Common Name"].exists, "Privacy dashboard should show Certificate Common Name")
        XCTAssertTrue(privacyDashboard.staticTexts["Summary"].exists, "Privacy dashboard should show Certificate summary")
        XCTAssertTrue(privacyDashboard.staticTexts["*.example.com"].exists, "Privacy dashboard should show Certificate domain name")

        // Close the dashboard
        app.typeKey(.escape, modifierFlags: [])

        // Navigate to HTTP (unsecure) privacy test pages site
        app.activateAddressBar()
        let httpURL = URL(string: "http://privacy-test-pages.site/privacy-protections/https-upgrades/")!
        addressBarTextField.pasteURL(httpURL, pressingEnter: true)

        // Wait for page content to load
        let pageContent2 = webView.staticTexts.containing(\.value, containing: "HTTPS Upgrades").firstMatch
        XCTAssertTrue(pageContent2.waitForExistence(timeout: UITests.Timeouts.localTestServer), "HTTP privacy test page should load")

        // Open privacy dashboard
        XCTAssertTrue(privacyButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy button should be available for HTTP site")
        privacyButton.click()

        // Privacy dashboard should open
        XCTAssertTrue(privacyDashboard.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should open for HTTP site")

        // Verify dashboard shows unencrypted connection status
        let unencryptedStatus = privacyDashboard.staticTexts.containing(\.value, containing: "This site is not secure").firstMatch
        XCTAssertTrue(unencryptedStatus.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should show 'This site is not secure' connection status for HTTP site")

        // Verify site URL is shown as HTTP
        let siteURL = privacyDashboard.staticTexts.containing(\.value, containing: "privacy-test-pages.site").firstMatch
        XCTAssertTrue(siteURL.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should show the site URL")
    }

    func testPrivacyDashboard_RequestBlocking_ValidatesProtectionToggle() throws {
        // Navigate to request blocking test page
        let testURL = URL(string: "http://privacy-test-pages.site/privacy-protections/request-blocking/")!
        addressBarTextField.pasteURL(testURL, pressingEnter: true)

        // Wait for page content to load
        let pageContent = webView.staticTexts.containing(\.value, containing: "Request Blocking Test Page").firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Request blocking test page should load")

        // Click "Start the test" button
        let startTestButton = webView.buttons.containing(\.title, containing: "Start the test").firstMatch
        XCTAssertTrue(startTestButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Start the test button should be available")
        startTestButton.click()

        // Wait for "Download the results" button to become enabled
        let downloadResultsButton = webView.buttons.containing(\.title, containing: "Download the results").firstMatch
        XCTAssertTrue(downloadResultsButton.wait(for: \.isEnabled, equals: true, timeout: UITests.Timeouts.elementExistence), "Download the results button should become available after test completion")

        // Check for existing files before downloading
        let existingFiles = getExistingRequestBlockingFiles()

        // Click download button
        downloadResultsButton.click()

        // Wait for new file to appear
        guard let filePath = waitForNewRequestBlockingFile(excluding: existingFiles) else {
            XCTFail("Downloaded request-blocking-results.json file not found in Downloads directory")
            return
        }
        trackForCleanup(filePath)

        // Parse and validate the JSON file via local server
        Logger.log("Reading file at \(filePath)")
        let jsonData = try readFileViaLocalServer(filePath: filePath)
        Logger.log("Result: \(String(data: jsonData, encoding: .utf8) ?? "Data of \(jsonData.count)")")
        let results = try JSONDecoder().decode(RequestBlockingResults.self, from: jsonData)

        // Validate that no trackers are "loaded" (they should be blocked)
        let loadedTrackers = results.results.filter { $0.status == "loaded" }
        XCTAssertTrue(loadedTrackers.isEmpty, "No trackers should be loaded - found loaded trackers: \(loadedTrackers.map { $0.id })")

        // Verify we have some blocked/failed requests
        let blockedTrackers = results.results.filter { $0.status == "failed" || $0.status == "not loaded" }
        XCTAssertFalse(blockedTrackers.isEmpty, "Should have some blocked/failed requests indicating tracker blocking is working")

        // PART 2: Test with protections disabled

        // Open privacy dashboard to disable protections
        XCTAssertTrue(privacyButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy button should be available")
        privacyButton.click()

        // Privacy dashboard should open
        XCTAssertTrue(privacyDashboard.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should open")

        // Find and click "Disable Protections" checkbox
        let disableProtectionsCheckbox = privacyDashboard.switches["Disable Protections"]
        XCTAssertTrue(disableProtectionsCheckbox.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Disable Protections checkbox should be available")
        disableProtectionsCheckbox.click()

        let dontSendButton = privacyDashboard.buttons["Don't Send"]
        if dontSendButton.waitForExistence(timeout: UITests.Timeouts.elementExistence) {
            dontSendButton.click()

            XCTAssertTrue(privacyDashboard.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should disapppear after clicking 'Don't Send'")

            // Open privacy dashboard to disable protections
            XCTAssertTrue(privacyButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy button should be available")
            privacyButton.click()

            // Privacy dashboard should open
            XCTAssertTrue(privacyDashboard.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should open")

            // Find and click "Disable Protections" checkbox
            XCTAssertTrue(disableProtectionsCheckbox.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Disable Protections checkbox should be available")
            disableProtectionsCheckbox.click()
        }
        XCTAssertTrue(privacyDashboard.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should close")

        // Wait for page to reload - "Start the test" button should become enabled again
        XCTAssertTrue(startTestButton.wait(for: \.isEnabled, equals: true, timeout: UITests.Timeouts.navigation), "Start the test button should become enabled within reasonable time after disabling protections")

        // Start the test again with protections disabled
        startTestButton.click()

        // Wait for "Download the results" button to become enabled again
        XCTAssertTrue(downloadResultsButton.wait(for: \.isEnabled, equals: true, timeout: UITests.Timeouts.navigation), "Download the results button should become enabled after test completion")

        // Check for existing files before second download (including first downloaded file)
        let existingFilesBeforeSecond = getExistingRequestBlockingFiles()

        // Click download button for disabled protections results
        downloadResultsButton.click()

        // Wait for new file to appear (excluding all existing files including the first one)
        guard let secondFilePath = waitForNewRequestBlockingFile(excluding: existingFilesBeforeSecond) else {
            XCTFail("Second downloaded request-blocking-results.json file not found in Downloads directory")
            return
        }
        trackForCleanup(secondFilePath)

        // Parse and validate the second JSON file (with protections disabled) via local server
        Logger.log("Reading file at \(secondFilePath)")
        let secondJsonData = try readFileViaLocalServer(filePath: secondFilePath)
        Logger.log("Result: \(String(data: secondJsonData, encoding: .utf8) ?? "Data of \(secondJsonData.count)")")
        let secondResults = try JSONDecoder().decode(RequestBlockingResults.self, from: secondJsonData)

        // Validate that trackers ARE "loaded" now (protections disabled)
        let loadedTrackersDisabled = secondResults.results.filter { $0.status == "loaded" }
        XCTAssertFalse(loadedTrackersDisabled.isEmpty, "Some trackers should be loaded when protections are disabled - found loaded trackers: \(loadedTrackersDisabled.map { $0.id })")

        // Verify fewer requests are blocked/failed when protections are disabled
        let blockedTrackersDisabled = secondResults.results.filter { $0.status == "failed" || $0.status == "not loaded" }
        XCTAssertTrue(blockedTrackersDisabled.count < blockedTrackers.count, "Fewer trackers should be blocked when protections are disabled (enabled: \(blockedTrackers.count), disabled: \(blockedTrackersDisabled.count))")

        // PART 3: Re-enable protections and verify blocking works again

        // Open privacy dashboard to re-enable protections
        XCTAssertTrue(privacyButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy button should be available")
        privacyButton.click()

        // Privacy dashboard should open
        XCTAssertTrue(privacyDashboard.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should open")

        // Find and click "Enable Protections" checkbox (it should be unchecked now)
        let enableProtectionsCheckbox = privacyDashboard.switches["Enable Protections"]
        enableProtectionsCheckbox.click()

        // Wait for privacy dashboard to disappear (indicating page reload)
        XCTAssertTrue(privacyDashboard.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should disappear after re-enabling protections")

        // Wait for page to reload - "Start the test" button should become enabled again
        XCTAssertTrue(startTestButton.wait(for: \.isEnabled, equals: true, timeout: UITests.Timeouts.navigation), "Start the test button should become enabled again after re-enabling protections")

        // Start the test again with protections re-enabled
        startTestButton.click()

        // Wait for "Download the results" button to become enabled again
        XCTAssertTrue(downloadResultsButton.wait(for: \.isEnabled, equals: true, timeout: UITests.Timeouts.navigation), "Download the results button should become enabled after test completion with protections re-enabled")

        // Check for existing files before third download
        let existingFilesBeforeThird = getExistingRequestBlockingFiles()

        // Click download button for re-enabled protections results
        downloadResultsButton.click()

        // Wait for new file to appear (excluding all existing files)
        guard let thirdFilePath = waitForNewRequestBlockingFile(excluding: existingFilesBeforeThird) else {
            XCTFail("Third downloaded request-blocking-results.json file not found in Downloads directory")
            return
        }
        trackForCleanup(thirdFilePath)

        // Parse and validate the third JSON file (with protections re-enabled) via local server
        Logger.log("Reading file at \(thirdFilePath)")
        let thirdJsonData = try readFileViaLocalServer(filePath: thirdFilePath)
        Logger.log("Result: \(String(data: thirdJsonData, encoding: .utf8) ?? "Data of \(thirdJsonData.count)")")
        let thirdResults = try JSONDecoder().decode(RequestBlockingResults.self, from: thirdJsonData)

        // Validate that trackers are NOT "loaded" again (protections re-enabled)
        let loadedTrackersReEnabled = thirdResults.results.filter { $0.status == "loaded" }
        XCTAssertTrue(loadedTrackersReEnabled.isEmpty, "No trackers should be loaded when protections are re-enabled - found loaded trackers: \(loadedTrackersReEnabled.map { $0.id })")

        // Verify more requests are blocked/failed when protections are re-enabled (should be similar to first test)
        let blockedTrackersReEnabled = thirdResults.results.filter { $0.status == "failed" || $0.status == "not loaded" }
        XCTAssertTrue(blockedTrackersReEnabled.count > blockedTrackersDisabled.count, "More trackers should be blocked when protections are re-enabled (disabled: \(blockedTrackersDisabled.count), re-enabled: \(blockedTrackersReEnabled.count))")

        // Verify re-enabled results are similar to original enabled results
        XCTAssertEqual(blockedTrackersReEnabled.count, blockedTrackers.count, "Re-enabled protections should block the same number of trackers as initially enabled (original: \(blockedTrackers.count), re-enabled: \(blockedTrackersReEnabled.count))")
    }

    func testPrivacyDashboard_NavigationBetweenSites_UpdatesCorrectly() throws {
        // Navigate to first site (tracker test page)
        let firstURL = URL(string: "http://privacy-test-pages.site/tracker-reporting/1major-via-script.html")!
        addressBarTextField.pasteURL(firstURL, pressingEnter: true)

        // Wait for first page content
        let firstPageContent = webView.staticTexts.containing(\.value, containing: "1 major tracker loaded via script src").firstMatch
        XCTAssertTrue(firstPageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "First tracker test page should load")

        // Check privacy dashboard for first site
        XCTAssertTrue(privacyButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy button should be available for first tracker site")

        privacyButton.click()

        // Privacy dashboard should open for first site
        XCTAssertTrue(privacyDashboard.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should open for first site")

        // Verify dashboard shows first site information (tracker test page)
        let firstSiteInfo = privacyDashboard.staticTexts.containing(\.value, containing: "privacy-test-pages").firstMatch
        XCTAssertTrue(firstSiteInfo.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should show information for first site (privacy-test-pages)")

        // Close dashboard
        app.typeKey(.escape, modifierFlags: [])

        // Navigate to second site
        app.activateAddressBar()
        let secondURL = URL(string: "http://example.com")!
        addressBarTextField.pasteURL(secondURL, pressingEnter: true)

        // Wait for second page content
        let secondPageContent = webView.staticTexts.containing(\.value, containing: "Example Domain").firstMatch
        XCTAssertTrue(secondPageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Second test page should load")

        // Check privacy dashboard for second site
        XCTAssertTrue(privacyButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy button should remain available for second site")

        privacyButton.click()

        // Privacy dashboard should open for second site
        XCTAssertTrue(privacyDashboard.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should open for second site")

        // Verify dashboard updated to show second site information (example.com)
        let secondSiteInfo = privacyDashboard.staticTexts.containing(\.value, containing: "example.com").firstMatch
        XCTAssertTrue(secondSiteInfo.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should update to show example.com information")
    }

}
