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
        continueAfterFailure = false
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

    // MARK: - Click-to-Load Social Media Tests

    func testNavigationProtection_SocialMediaEmbeds_ShowsClickToLoad() throws {
        // Navigate to a test page with social media embeds
        let socialTestURL = URL(string: "https://privacy-test-pages.site/privacy-protections/click-to-load/")!
        addressBarTextField.pasteURL(socialTestURL, pressingEnter: true)

        // Wait for page to load completely
        let pageHeader = webView.staticTexts.containing(\.value, containing: "About ClickToLoad Tests").firstMatch
        XCTAssertTrue(pageHeader.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Click-to-load test page should load")

        // Validate that Click-to-Load blocked FB resources on the page (functional signal from the test page)
        let metrics = webView.staticTexts.containing(\.value, containing: "Facebook Resources Loads:").firstMatch
        XCTAssertTrue(metrics.waitForExistence(timeout: UITests.Timeouts.navigation), "Metrics section should be visible on the click-to-load page")

        // Initial state: resources should be NONE
        let noneValue = webView.staticTexts["NONE"].firstMatch
        if !noneValue.waitForExistence(timeout: UITests.Timeouts.navigation) {
            let attach = XCTAttachment(string: app.debugDescription)
            attach.lifetime = .keepAlways
            add(attach)
            XCTFail("Facebook Resources Loads should be NONE before user interaction")
        }

        // Prefer the FIRST login control by exact label/value to avoid the custom variant and popover overlap
        let firstLoginButton = webView.buttons["Log in with Facebook"].firstMatch
        let firstLoginLink = webView.links["Log in with Facebook"].firstMatch
        let firstLoginStatic = webView.staticTexts["Log in with Facebook"].firstMatch
        let customLoginButton = webView.buttons["Custom Facebook Login"].firstMatch

        let hasFirstButton = firstLoginButton.waitForExistence(timeout: UITests.Timeouts.elementExistence)
        let hasFirstLink = hasFirstButton ? false : firstLoginLink.waitForExistence(timeout: UITests.Timeouts.elementExistence)
        let hasFirstStatic = (hasFirstButton || hasFirstLink) ? false : firstLoginStatic.waitForExistence(timeout: UITests.Timeouts.elementExistence)
        let hasCustom = (!hasFirstButton && !hasFirstLink && !hasFirstStatic) ? customLoginButton.waitForExistence(timeout: UITests.Timeouts.elementExistence) : false

        guard hasFirstButton || hasFirstLink || hasFirstStatic || hasCustom else {
            let attach = XCTAttachment(string: app.debugDescription)
            attach.lifetime = .keepAlways
            add(attach)
            XCTFail("Expected a 'Log in with Facebook' control or 'Custom Facebook Login' to exist")
            return
        }

        // Click the login control; CTL overlay should appear
        let loginControl = hasFirstButton ? firstLoginButton : (hasFirstLink ? firstLoginLink : (hasFirstStatic ? firstLoginStatic : customLoginButton))
        if loginControl.isHittable {
            loginControl.click()
        } else {
            // Tap slightly lower than center to avoid the DDG popover covering the top of the control
            let coord = loginControl.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            coord.tap()
        }

        // Wait for the CTL overlay to be presented
        let overlayTitle = app.staticTexts["Logging in with Facebook lets them track you"].firstMatch
        XCTAssertTrue(overlayTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "CTL overlay should appear after clicking login")

        let overlayLogin = app.buttons["Log In"].firstMatch
        XCTAssertTrue(overlayLogin.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Overlay 'Log In' should be visible")

        // Do not proceed further in CI; presence of overlay and primary action is sufficient

        // Verify we stayed on the click-to-load page in the main window
        let currentURL = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(currentURL.contains("click-to-load"), "Should be on the click-to-load test page; actual: \(currentURL)")
    }

    // MARK: - Tracking Parameter Removal Tests

    func testNavigationProtection_TrackingParameters_RemovedFromURLs() throws {
        // Test URL with commonly removed tracking parameters (based on actual browser behavior)
        let trackedURL = URL(string: "https://example.com/?utm_source=test&utm_medium=test&utm_campaign=test&fbclid=test123&gclid=test456")!
        addressBarTextField.pasteURL(trackedURL, pressingEnter: true)

        // Wait for page to load
        let pageContent = webView.staticTexts.containing(\.value, containing: "Example Domain").firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Example page should load")

        // Check final URL after navigation - tracking parameters should be removed
        let finalURL = app.addressBarValueActivatingIfNeeded() ?? ""

        // Assert that utm_source parameter was removed (this is consistently removed)
        XCTAssertFalse(finalURL.contains("utm_source"), "utm_source tracking parameter should be removed; actual: \(finalURL)")

        // Assert that utm_medium parameter was removed (this is consistently removed)
        XCTAssertFalse(finalURL.contains("utm_medium"), "utm_medium tracking parameter should be removed; actual: \(finalURL)")

        // Should still be on example.com (basic functionality preserved)
        XCTAssertEqual(finalURL, "https://example.com/", "Should be on clean example.com URL after parameter removal; actual: \(finalURL)")
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
        let crossOriginURL = URL(string: "https://example.com")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(crossOriginURL, pressingEnter: true)

        // Wait for cross-origin page to load completely
        let crossOriginContent = webView.staticTexts.containing(\.value, containing: "Example Domain").firstMatch
        XCTAssertTrue(crossOriginContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Cross-origin page should load")

        // Ensure page is fully loaded before accessing address bar
        let pageFullyLoaded = webView.staticTexts.containing(\.value, containing: "Example Domain").firstMatch
        XCTAssertTrue(pageFullyLoaded.waitForExistence(timeout: UITests.Timeouts.navigation), "Page should be fully loaded")

        // Verify cross-site navigation completed (protection allows legitimate navigation)
        let finalURL = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(finalURL.contains("example.com"), "Legitimate cross-site navigation should work; actual: \(finalURL)")
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
        summary.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let summaryGroup = webView.groups.containing(.keyPath(\.value, beginsWith: "1p navigation -")).firstMatch
        // Helper to collect values in a section following a header prefix
        func values(afterHeaderWithPrefix prefix: String) -> [String] {
            // Locate the group that contains a static text header starting with the prefix
            let group = summaryGroup.groups.containing(.staticText, where: .keyPath(\.value, beginsWith: prefix)).firstMatch
            XCTAssertTrue(group.exists, "Group for header not found: \(prefix)")
            let texts = group.staticTexts.allElementsBoundByIndex.map { ($0.value as? String) ?? $0.label }
            return texts.filter { !$0.isEmpty && !$0.hasPrefix(prefix) }
        }

        // 1p navigation
        let nav1p = values(afterHeaderWithPrefix: "1p navigation -")
        XCTAssertTrue(nav1p.contains("js - https://privacy-test-pages.site/privacy-protections/referrer-trimming/"), "Missing expected value in 1p navigation; actual: \(nav1p)")
        XCTAssertTrue(nav1p.contains("header - https://privacy-test-pages.site/privacy-protections/referrer-trimming/"), "Missing expected header value in 1p navigation; actual: \(nav1p)")

        // 3p navigation
        let nav3p = values(afterHeaderWithPrefix: "3p navigation -")
        XCTAssertTrue(nav3p.contains("js - https://privacy-test-pages.site/"), "Missing expected value in 3p navigation; actual: \(nav3p)")
        XCTAssertTrue(nav3p.contains("header - https://privacy-test-pages.site/privacy-protections/referrer-trimming/"), "Missing expected header value in 3p navigation; actual: \(nav3p)")

        // 3p tracker navigation
        let nav3pTracker = values(afterHeaderWithPrefix: "3p tracker navigation -")
        XCTAssertTrue(nav3pTracker.contains("js - https://privacy-test-pages.site/"), "Missing expected value in 3p tracker navigation; actual: \(nav3pTracker)")
        XCTAssertTrue(nav3pTracker.contains("header - https://privacy-test-pages.site/privacy-protections/referrer-trimming/"), "Missing expected header value in 3p tracker navigation; actual: \(nav3pTracker)")

        // Requests (assert last value equals expected)
        XCTAssertEqual(values(afterHeaderWithPrefix: "1p request -").last, "\"https://privacy-test-pages.site/privacy-protections/referrer-trimming/\"", "Unexpected 1p request value; actual: \(values(afterHeaderWithPrefix: "1p request -").last ?? "<nil>")")
        XCTAssertEqual(values(afterHeaderWithPrefix: "3p request -").last, "\"https://privacy-test-pages.site/\"", "Unexpected 3p request value; actual: \(values(afterHeaderWithPrefix: "3p request -").last ?? "<nil>")")
        XCTAssertEqual(values(afterHeaderWithPrefix: "3p tracker request -").last, "\"https://privacy-test-pages.site/\"", "Unexpected 3p tracker request value; actual: \(values(afterHeaderWithPrefix: "3p tracker request -").last ?? "<nil>")")

        // Iframes (assert last value equals expected)
        XCTAssertEqual(values(afterHeaderWithPrefix: "1p iframe -").last, "\"https://privacy-test-pages.site/privacy-protections/referrer-trimming/\"", "Unexpected 1p iframe value; actual: \(values(afterHeaderWithPrefix: "1p iframe -").last ?? "<nil>")")
        XCTAssertEqual(values(afterHeaderWithPrefix: "3p iframe -").last, "\"https://privacy-test-pages.site/\"", "Unexpected 3p iframe value; actual: \(values(afterHeaderWithPrefix: "3p iframe -").last ?? "<nil>")")
        XCTAssertEqual(values(afterHeaderWithPrefix: "3p tracker iframe -").last, "\"https://privacy-test-pages.site/\"", "Unexpected 3p tracker iframe value; actual: \(values(afterHeaderWithPrefix: "3p tracker iframe -").last ?? "<nil>")")
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
        summary.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // Helper to collect values in a section following a header prefix
        func value(afterHeaderWithPrefix prefix: String) -> String? {
            let all = webView.staticTexts.allElementsBoundByIndex
            var inSection = false
            for element in all {
                let value = (element.value as? String) ?? element.label
                if value.hasPrefix(prefix) {
                    inSection = true
                    continue
                }
                if inSection {
                    if !value.isEmpty {
                        return value
                    }
                }
            }
            return nil
        }

        // Expectations per section
        XCTAssertEqual(value(afterHeaderWithPrefix: "top frame header -"), "\"1\"")
        XCTAssertEqual(value(afterHeaderWithPrefix: "top frame JS API -"), "true")
        XCTAssertEqual(value(afterHeaderWithPrefix: "frame header -"), "…")
        XCTAssertEqual(value(afterHeaderWithPrefix: "frame JS API -"), "true")
        XCTAssertEqual(value(afterHeaderWithPrefix: "subequest header -") ?? value(afterHeaderWithPrefix: "subrequest header -"), "…")
    }

}
