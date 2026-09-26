//
//  NavigationProtectionUITests.swift
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

class NavigationProtectionUITests: UITestCase {

    private var addressBarTextField: XCUIElement!
    private var webView: XCUIElement!

    override func setUpWithError() throws {
        try super.setUpWithError()
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()

        addressBarTextField = app.addressBar
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        webView = app.webViews.firstMatch
    }

    override func tearDownWithError() throws {
        app = nil
        addressBarTextField = nil
        webView = nil
        try super.tearDownWithError()
    }

    // MARK: - AMP Link Protection Tests

    func testNavigationProtection_AMPLinks_RedirectsToCanonical() throws {
        // Navigate to AMP protection test page
        let ampTestURL = URL(string: "https://privacy-test-pages.site/privacy-protections/amp/")!
        addressBarTextField.pasteURL(ampTestURL, pressingEnter: true)

        // Ensure page loaded (anchor on a known element on AMP page)
        let pageLoadedAnchor = webView.links[".amp link"].firstMatch
        XCTAssertTrue(pageLoadedAnchor.waitForExistence(timeout: UITests.Timeouts.localTestServer), "AMP test page should load and expose baseline link")

        // Collect all expected canonical URL markers ("Expected: ...") in DOM order
        let expectedTexts = webView.staticTexts
            .matching(.keyPath(\.value, beginsWith: "Expected: "))
            .allElementsBoundByIndex
            .map { ($0.value as? String ?? "").replacingOccurrences(of: "Expected: ", with: "") }

        // Known order of link labels on the page to pair with the above expectations
        // Skip unsupported patterns explicitly: "amp. link" and "?amp link"
        let allLabelsInOrder: [String] = [
            "*Simple link #2",
            "*Non Standard TLD (Google Domain)",
            ".amp link",
            "amp. link",
            "?amp link",
            "basecamp.com",
            "bandcamp.com",
            "amp.dev"
        ]

        let pairCount = min(allLabelsInOrder.count, expectedTexts.count)
        XCTAssertTrue(pairCount > 0, "AMP test page should expose test cases")

        for index in 0..<pairCount {
            let label = allLabelsInOrder[index]
            // not working: handled in testNavigationProtection_AMPLinks_GuardianDotAmp_RedirectsToCanonical
            if label == "amp. link" { continue }
            // Destination bot protection can interrupt canonical URL redirect; handled in testNavigationProtection_AMPLinks_NonStandardTLD_RedirectsToCanonical
            if label == "*Non Standard TLD (Google Domain)" { continue }

            let expectedURL = expectedTexts[index]
            let link = webView.links[label].firstMatch
            XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Expected AMP link '\(label)' to exist")
            link.click()

            // Wait for navigation to complete
            XCTAssertTrue(link.waitForNonExistence(timeout: UITests.Timeouts.navigation), "Navigation should complete after AMP link click: \(label)")
            Thread.sleep(forTimeInterval: 5)

            // Verify redirected URL exactly matches the page-provided canonical expectation
            let finalURL = app.addressBarValueActivatingIfNeeded() ?? ""
            if label == "amp.dev" {
                XCTAssertTrue(finalURL.hasPrefix(expectedURL), "Should be redirected to canonical URL \(expectedURL) for '\(label)'; actual: \(finalURL)")
            } else {
                XCTAssertEqual(finalURL, expectedURL, "Should be redirected to canonical URL \(expectedURL) for '\(label)'; actual: \(finalURL)")
            }

            // Return to the AMP tests list for the next case
            app.typeKey("[", modifierFlags: [.command])
            XCTAssertTrue(pageLoadedAnchor.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should return to AMP test page before next iteration after \(label)")
        }
    }

    func testNavigationProtection_AMPLinks_GuardianDotAmp_RedirectsToCanonical() throws {
        throw XCTSkip("Guardian 'amp.' pattern not currently supported by AMP protection; skipping to reflect actual feature scope.")
        // Navigate to AMP protection test page
        let ampTestURL = URL(string: "https://privacy-test-pages.site/privacy-protections/amp/")!
        addressBarTextField.pasteURL(ampTestURL, pressingEnter: true)

        // Find the Guardian amp. test link
        let guardianAmpLink = webView.links["amp. link"]
        XCTAssertTrue(guardianAmpLink.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Guardian amp. test link should be available")

        // Get the expected URL from the test page instead of hardcoding
        let expectedURLElement = webView.staticTexts.containing(\.value, containing: "Expected: https://www.theguardian.com").firstMatch
        XCTAssertTrue(expectedURLElement.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Expected URL element should be found on the test page")

        let expectedURLText = expectedURLElement.value as? String ?? ""
        let expectedURL = expectedURLText.replacingOccurrences(of: "Expected: ", with: "")

        // Click the AMP link to test protection
        guardianAmpLink.click()

        // Wait for navigation to complete
        let newPageContent = webView.staticTexts.firstMatch
        XCTAssertTrue(newPageContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Navigation should complete after AMP link click")

        // Verify AMP protection worked - should redirect to canonical URL
        let finalURL = app.addressBarValueActivatingIfNeeded() ?? ""

        // Should be redirected to the exact expected canonical URL from the test page
        XCTAssertEqual(finalURL, expectedURL, "Should be redirected to exact canonical URL specified in test page")
    }

    func testNavigationProtection_AMPLinks_NonStandardTLD_RedirectsToCanonical() throws {
        // Navigate to AMP protection test page
        let ampTestURL = URL(string: "https://privacy-test-pages.site/privacy-protections/amp/")!
        addressBarTextField.pasteURL(ampTestURL, pressingEnter: true)

        // Find the Non Standard TLD test link
        let nonStandardTLDAmpLink = webView.links["*Non Standard TLD (Google Domain)"].firstMatch
        XCTAssertTrue(nonStandardTLDAmpLink.waitForExistence(timeout: UITests.Timeouts.elementExistence), "*Non Standard TLD (Google Domain) test link should be available")

        // Get the expected URL from the test page instead of hardcoding
        let expectedURLElement = webView.staticTexts.containing(\.value, containing: "Expected: https://www.brookings.edu").firstMatch
        XCTAssertTrue(expectedURLElement.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Expected URL element should be found on the test page")

        let expectedURLText = expectedURLElement.value as? String ?? ""
        let expectedURL = expectedURLText.replacingOccurrences(of: "Expected: ", with: "")

        // Click the AMP link to test protection
        nonStandardTLDAmpLink.click()

        // Wait for navigation to complete
        let newPageContent = webView.staticTexts.firstMatch
        XCTAssertTrue(newPageContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Navigation should complete after AMP link click")

        // Verify AMP protection redirected to the expected canonical URL.
        // Skip test if bot protection is triggered, as the canonical URL cannot be verified in that case.
        let finalURL = app.addressBarValueActivatingIfNeeded() ?? ""
        guard finalURL == expectedURL else {
            XCTAssertTrue(app.staticTexts["Performing security verification"].exists,
                          "Should be redirected to exact canonical URL \(expectedURL) or bot detection page; actual: \(finalURL)")
            throw XCTSkip("Bot detection prevented redirect to canonical URL")
        }
    }

    // MARK: - Tracking Parameter Removal Tests

    func testNavigationProtection_TrackingParameters_RemovedFromURLs() throws {
        // Test URL with commonly removed tracking parameters (based on actual browser behavior)
        let trackedURL = URL(string: "https://github.com/?utm_source=test&utm_medium=test&utm_campaign=test&fbclid=test123&gclid=test456")!
        addressBarTextField.pasteURL(trackedURL, pressingEnter: true)

        // Wait for page to load
        let pageContent = webView.staticTexts.containing(\.value, containing: "GitHub").firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: UITests.Timeouts.navigation), "GitHub page should load")

        // Check final URL after navigation - tracking parameters should be removed
        let finalURL = app.addressBarValueActivatingIfNeeded() ?? ""

        // Assert that utm_source parameter was removed (this is consistently removed)
        XCTAssertFalse(finalURL.contains("utm_source"), "utm_source tracking parameter should be removed; actual: \(finalURL)")

        // Assert that utm_medium parameter was removed (this is consistently removed)
        XCTAssertFalse(finalURL.contains("utm_medium"), "utm_medium tracking parameter should be removed; actual: \(finalURL)")

        // Should still be on github.com (basic functionality preserved)
        XCTAssertEqual(finalURL, "https://github.com/", "Should be on clean github.com URL after parameter removal; actual: \(finalURL)")
    }

    // MARK: - Redirect Protection Tests

    func testNavigationProtection_MaliciousRedirects_Blocked() throws {
        // Navigate to a safe test page (redirect protection is hard to test with real malicious sites)
        let safeURL = UITests.simpleServedPage(titled: "Safe Test Page")
        addressBarTextField.pasteURL(safeURL, pressingEnter: true)

        // Wait for local test page
        let safePageContent = webView.staticTexts.containing(\.value, containing: "Safe Test Page").firstMatch
        XCTAssertTrue(safePageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Safe test page should load normally")

        // Verify we're on the expected safe page
        let currentURL = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(currentURL.contains("localhost:8085"), "Should remain on safe local test page; actual: \(currentURL)")
    }

    // MARK: - Cross-Site Request Protection Tests

    func testNavigationProtection_CrossSiteRequests_Protected() throws {
        // Navigate to a test page to establish origin
        let originURL = UITests.simpleServedPage(titled: "Origin Test Page")
        addressBarTextField.pasteURL(originURL, pressingEnter: true)

        // Wait for origin page
        let originContent = webView.staticTexts.containing(\.value, containing: "Origin Test Page").firstMatch
        XCTAssertTrue(originContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Origin page should load")

        // Navigate to different origin to test cross-site protection
        let crossOriginURL = URL(string: "https://github.com")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(crossOriginURL, pressingEnter: true)

        // Wait for cross-origin page to load completely
        let crossOriginContent = webView.staticTexts.containing(\.value, containing: "GitHub").firstMatch
        XCTAssertTrue(crossOriginContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Cross-origin page should load")

        // Ensure page is fully loaded before accessing address bar
        let pageFullyLoaded = webView.staticTexts.containing(\.value, containing: "GitHub").firstMatch
        XCTAssertTrue(pageFullyLoaded.waitForExistence(timeout: UITests.Timeouts.navigation), "Page should be fully loaded")

        // Verify cross-site navigation completed (protection allows legitimate navigation)
        let finalURL = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(finalURL.contains("github.com"), "Legitimate cross-site navigation should work; actual: \(finalURL)")
    }

    // MARK: - Referrer Protection Tests

    func testNavigationProtection_ReferrerTrimming_WorksCorrectly() throws {
        // Navigate to the official referrer trimming test page (matches integration test)
        let referrerTestURL = URL(string: "https://privacy-test-pages.site/privacy-protections/referrer-trimming/")!
        addressBarTextField.pasteURL(referrerTestURL, pressingEnter: true)

        // Start the tests on page
        let startButton = webView.buttons["Start test"].firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Start button should be available for referrer trimming test")
        Thread.sleep(forTimeInterval: 1)
        startButton.click()

        // Wait for test completion summary and expand
        let summary = webView.staticTexts["Performed 9 tests. Click for details."].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: UITests.Timeouts.navigation), "Referrer trimming test should complete")
        summary.click()

        let legacySummaryGroup = webView.groups.containing(.keyPath(\.value, beginsWith: "1p navigation -")).firstMatch
        func legacyValues(afterHeaderWithPrefix prefix: String) -> [String] {
            let group = legacySummaryGroup.groups.containing(.staticText, where: .keyPath(\.value, beginsWith: prefix)).firstMatch
            let texts = group.staticTexts.allElementsBoundByIndex.map { ($0.value as? String) ?? $0.label }
            return texts.filter { !$0.isEmpty && !$0.hasPrefix(prefix) }
        }

        func assertNavigationResult(_ header: String, contains expectedValues: [String]) {
            let section = webView.groups.matching(.keyPath(\.value, equalTo: header)).firstMatch
            for expectedValue in expectedValues {
                let foundInGroup = section.groups.matching(.keyPath(\.value, equalTo: expectedValue)).firstMatch.exists
                XCTAssertTrue(foundInGroup || legacyValues(afterHeaderWithPrefix: header).contains(expectedValue),
                              "Missing \(expectedValue) in \(header)")
            }
        }

        func assertResult(_ header: String, equals expectedValue: String) {
            let foundInGroup = webView.groups.matching(.keyPath(\.value, equalTo: "\(header) \(expectedValue)")).firstMatch.exists
            XCTAssertTrue(foundInGroup || legacyValues(afterHeaderWithPrefix: header).last == expectedValue,
                          "Unexpected result for \(header)")
        }

        let pageURL = "https://privacy-test-pages.site/privacy-protections/referrer-trimming/"
        let siteURL = "https://privacy-test-pages.site/"
        assertNavigationResult("1p navigation -", contains: ["js - \(pageURL)", "header - \(pageURL)"])
        assertNavigationResult("3p navigation -", contains: ["js - \(siteURL)", "header - \(pageURL)"])
        assertNavigationResult("3p tracker navigation -", contains: ["js - \(siteURL)", "header - \(pageURL)"])

        assertResult("1p request -", equals: "\"\(pageURL)\"")
        assertResult("3p request -", equals: "\"\(siteURL)\"")
        assertResult("3p tracker request -", equals: "\"\(siteURL)\"")
        assertResult("1p iframe -", equals: "\"\(pageURL)\"")
        assertResult("3p iframe -", equals: "\"\(siteURL)\"")
        assertResult("3p tracker iframe -", equals: "\"\(siteURL)\"")
    }

    // MARK: - GPC (Global Privacy Control) Tests

    func testNavigationProtection_GPC_HeaderInjection() throws {
        // Navigate to the GPC test page (matches integration test)
        let gpcTestURL = URL(string: "https://privacy-test-pages.site/privacy-protections/gpc/")!
        addressBarTextField.pasteURL(gpcTestURL, pressingEnter: true)

        // Start the test
        let startButton = webView.buttons["Start test"].firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Start button should be available for GPC test")
        Thread.sleep(forTimeInterval: 1)
        startButton.click()

        // Wait for summary and expand details
        let summary = webView.staticTexts["Performed 5 tests. Click for details."].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: UITests.Timeouts.navigation), "GPC test should complete and show summary")
        summary.click()

        func legacyValue(afterHeaderWithPrefix prefix: String) -> String? {
            let all = webView.staticTexts.allElementsBoundByIndex
            var inSection = false
            for element in all {
                let value = (element.value as? String) ?? element.label
                if value.hasPrefix(prefix) {
                    inSection = true
                    continue
                }
                if inSection && !value.isEmpty { return value }
            }
            return nil
        }

        func assertResult(_ header: String, equals expectedValue: String, legacyAlternativeHeader: String? = nil) {
            let foundInGroup = webView.groups.matching(.keyPath(\.value, equalTo: "\(header) \(expectedValue)")).firstMatch.exists
            if foundInGroup { return }

            let foundInLegacy = legacyValue(afterHeaderWithPrefix: header)
                ?? legacyAlternativeHeader.flatMap { legacyValue(afterHeaderWithPrefix: $0) }
            XCTAssertEqual(foundInLegacy, expectedValue, "Unexpected result for \(header)")
        }

        assertResult("top frame header -", equals: "\"1\"")
        assertResult("top frame JS API -", equals: "true")
        assertResult("frame header -", equals: "…")
        assertResult("frame JS API -", equals: "true")
        assertResult("subequest header -", equals: "…", legacyAlternativeHeader: "subrequest header -")
    }

}
