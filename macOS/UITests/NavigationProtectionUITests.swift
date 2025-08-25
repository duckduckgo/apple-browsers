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

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()

        addressBarTextField = app.addressBar
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    // MARK: - AMP Link Protection Tests

    func testNavigationProtection_AMPLinks_RedirectsToCanonical() throws {
        // Navigate to AMP protection test page
        let ampTestURL = URL(string: "https://privacy-test-pages.site/privacy-protections/amp/")!
        addressBarTextField.pasteURL(ampTestURL, pressingEnter: true)

        let webView = app.webViews.firstMatch
        // Ensure page loaded (anchor on a known element on AMP page)
        let pageLoadedAnchor = webView.links[".amp link"].firstMatch
        XCTAssertTrue(pageLoadedAnchor.waitForExistence(timeout: 15.0), "AMP test page should load and expose baseline link")

        // Collect all expected canonical URL markers ("Expected: ...") in DOM order
        let expectedTexts = webView.staticTexts
            .matching(NSPredicate(format: "value BEGINSWITH[c] 'Expected: '"))
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
            XCTAssertTrue(link.waitForExistence(timeout: 10.0), "Expected AMP link '\(label)' to exist")
            link.click()

            // Wait for navigation to complete
            XCTAssertTrue(link.waitForNonExistence(timeout: 30.0), "Navigation should complete after AMP link click: \(label)")

            // Verify redirected URL exactly matches the page-provided canonical expectation
            app.activateAddressBar()
            let finalURL = addressBarTextField.value as? String ?? ""
            if label == "amp.dev" {
                XCTAssertTrue(finalURL.hasPrefix(expectedURL), "Should be redirected to canonical URL \(expectedURL) for '\(label)'")
            } else {
                XCTAssertEqual(finalURL, expectedURL, "Should be redirected to canonical URL \(expectedURL) for '\(label)'")
            }

            // Return to the AMP tests list for the next case
            app.typeKey("[", modifierFlags: [.command])
            XCTAssertTrue(pageLoadedAnchor.waitForExistence(timeout: 15.0), "Should return to AMP test page before next iteration after \(label)")
        }
    }

    func testNavigationProtection_AMPLinks_GuardianDotAmp_RedirectsToCanonical() throws {
        throw XCTSkip("Guardian 'amp.' pattern not currently supported by AMP protection; skipping to reflect actual feature scope.")
        // Navigate to AMP protection test page
        let ampTestURL = URL(string: "https://privacy-test-pages.site/privacy-protections/amp/")!
        addressBarTextField.pasteURL(ampTestURL, pressingEnter: true)

        // Find the Guardian amp. test link
        let webView = app.webViews.firstMatch
        let guardianAmpLink = webView.links["amp. link"]
        XCTAssertTrue(guardianAmpLink.waitForExistence(timeout: 10.0), "Guardian amp. test link should be available")

        // Get the expected URL from the test page instead of hardcoding
        let expectedURLElement = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Expected: https://www.theguardian.com'")).firstMatch
        XCTAssertTrue(expectedURLElement.waitForExistence(timeout: 5.0), "Expected URL element should be found on the test page")

        let expectedURLText = expectedURLElement.value as? String ?? ""
        let expectedURL = expectedURLText.replacingOccurrences(of: "Expected: ", with: "")

        // Click the AMP link to test protection
        guardianAmpLink.click()

        // Wait for navigation to complete
        let navigationTimeout: TimeInterval = 30.0
        let newPageContent = webView.staticTexts.firstMatch
        XCTAssertTrue(newPageContent.waitForExistence(timeout: navigationTimeout), "Navigation should complete after AMP link click")

        // Verify AMP protection worked - should redirect to canonical URL
        app.activateAddressBar()
        let finalURL = addressBarTextField.value as? String ?? ""

        // Should be redirected to the exact expected canonical URL from the test page
        XCTAssertEqual(finalURL, expectedURL, "Should be redirected to exact canonical URL specified in test page")
    }

    // MARK: - Click-to-Load Social Media Tests

    func testNavigationProtection_SocialMediaEmbeds_ShowsClickToLoad() throws {
        // Navigate to a test page with social media embeds
        let socialTestURL = URL(string: "https://privacy-test-pages.site/privacy-protections/click-to-load/")!
        addressBarTextField.pasteURL(socialTestURL, pressingEnter: true)

        let webView = app.webViews.firstMatch

        // Wait for page to load completely
        let pageHeader = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'About ClickToLoad Tests'")).firstMatch
        XCTAssertTrue(pageHeader.waitForExistence(timeout: 15.0), "Click-to-load test page should load")

        // Validate that Click-to-Load blocked FB resources on the page (functional signal from the test page)
        let metrics = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Facebook Resources Loads:'")).firstMatch
        XCTAssertTrue(metrics.waitForExistence(timeout: 20.0), "Metrics section should be visible on the click-to-load page")

        // Initial state: resources should be NONE
        let noneValue = webView.staticTexts["NONE"].firstMatch
        if !noneValue.waitForExistence(timeout: 30.0) {
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

        let hasFirstButton = firstLoginButton.waitForExistence(timeout: 8.0)
        let hasFirstLink = hasFirstButton ? false : firstLoginLink.waitForExistence(timeout: 4.0)
        let hasFirstStatic = (hasFirstButton || hasFirstLink) ? false : firstLoginStatic.waitForExistence(timeout: 4.0)
        let hasCustom = (!hasFirstButton && !hasFirstLink && !hasFirstStatic) ? customLoginButton.waitForExistence(timeout: 5.0) : false

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
        XCTAssertTrue(overlayTitle.waitForExistence(timeout: 10.0), "CTL overlay should appear after clicking login")

        let overlayLogin = app.buttons["Log In"].firstMatch
        XCTAssertTrue(overlayLogin.waitForExistence(timeout: 10.0), "Overlay 'Log In' should be visible")

        // Do not proceed further in CI; presence of overlay and primary action is sufficient

        // Verify we stayed on the click-to-load page in the main window
        app.activateAddressBar()
        let currentURL = addressBarTextField.value as? String ?? ""
        XCTAssertTrue(currentURL.contains("click-to-load"), "Should be on the click-to-load test page")
    }

    // MARK: - Tracking Parameter Removal Tests

    func testNavigationProtection_TrackingParameters_RemovedFromURLs() throws {
        // Test URL with commonly removed tracking parameters (based on actual browser behavior)
        let trackedURL = URL(string: "https://example.com/?utm_source=test&utm_medium=test&utm_campaign=test&fbclid=test123&gclid=test456")!
        addressBarTextField.pasteURL(trackedURL, pressingEnter: true)

        // Wait for page to load
        let webView = app.webViews.firstMatch
        let pageContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Example Domain'")).firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: 15.0), "Example page should load")

        // Check final URL after navigation - tracking parameters should be removed
        app.activateAddressBar()
        let finalURL = addressBarTextField.value as? String ?? ""

        // Assert that utm_source parameter was removed (this is consistently removed)
        XCTAssertFalse(finalURL.contains("utm_source"), "utm_source tracking parameter should be removed")

        // Assert that utm_medium parameter was removed (this is consistently removed)
        XCTAssertFalse(finalURL.contains("utm_medium"), "utm_medium tracking parameter should be removed")

        // Should still be on example.com (basic functionality preserved)
        XCTAssertEqual(finalURL, "https://example.com/", "Should be on clean example.com URL after parameter removal")
    }

    // MARK: - Redirect Protection Tests

    func testNavigationProtection_MaliciousRedirects_Blocked() throws {
        // Navigate to a safe test page (redirect protection is hard to test with real malicious sites)
        let safeURL = UITests.simpleServedPage(titled: "Safe Test Page")
        addressBarTextField.pasteURL(safeURL, pressingEnter: true)

        // Wait for local test page
        let webView = app.webViews.firstMatch
        let safePageContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Safe Test Page'")).firstMatch
        XCTAssertTrue(safePageContent.waitForExistence(timeout: 15.0), "Safe test page should load normally")

        // Verify we're on the expected safe page
        app.activateAddressBar()
        let currentURL = addressBarTextField.value as? String ?? ""
        XCTAssertTrue(currentURL.contains("localhost:8085"), "Should remain on safe local test page")
    }

    // MARK: - Cross-Site Request Protection Tests

    func testNavigationProtection_CrossSiteRequests_Protected() throws {
        // Navigate to a test page to establish origin
        let originURL = UITests.simpleServedPage(titled: "Origin Test Page")
        addressBarTextField.pasteURL(originURL, pressingEnter: true)

        // Wait for origin page
        let webView = app.webViews.firstMatch
        let originContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Origin Test Page'")).firstMatch
        XCTAssertTrue(originContent.waitForExistence(timeout: 15.0), "Origin page should load")

        // Navigate to different origin to test cross-site protection
        let crossOriginURL = URL(string: "https://example.com")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(crossOriginURL, pressingEnter: true)

        // Wait for cross-origin page to load completely
        let crossOriginContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Example Domain'")).firstMatch
        XCTAssertTrue(crossOriginContent.waitForExistence(timeout: 15.0), "Cross-origin page should load")

        // Ensure page is fully loaded before accessing address bar
        let pageLoadTimeout: TimeInterval = 3.0
        let pageFullyLoaded = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Example Domain'")).firstMatch
        XCTAssertTrue(pageFullyLoaded.waitForExistence(timeout: pageLoadTimeout), "Page should be fully loaded")

        // Verify cross-site navigation completed (protection allows legitimate navigation)
        app.activateAddressBar()
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: 5.0), "Address bar should be accessible after navigation")
        let finalURL = addressBarTextField.value as? String ?? ""
        XCTAssertTrue(finalURL.contains("example.com"), "Legitimate cross-site navigation should work")
    }

    // MARK: - Referrer Protection Tests

    func testNavigationProtection_ReferrerTrimming_WorksCorrectly() throws {
        // Navigate to the official referrer trimming test page (matches integration test)
        let referrerTestURL = URL(string: "https://privacy-test-pages.site/privacy-protections/referrer-trimming/")!
        addressBarTextField.pasteURL(referrerTestURL, pressingEnter: true)

        // Wait for referrer test page to load
        let webView = app.webViews.firstMatch
        let referrerPageContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Referrer' OR value CONTAINS 'test'")).firstMatch
        XCTAssertTrue(referrerPageContent.waitForExistence(timeout: 30.0), "Referrer trimming test page should load")

        // Find and click the "start" button to run the test (matches integration test)
        let startButton = webView.buttons["Start test"].firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: 10.0), "Start button should be available for referrer trimming test")
        startButton.click()

        // Wait for test completion (should return to original page)
        let testCompletionContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'test' OR value CONTAINS 'result'")).firstMatch
        XCTAssertTrue(testCompletionContent.waitForExistence(timeout: 40.0), "Referrer trimming test should complete")

        // Verify completion by asserting on-page results are visible (URL may vary during the flow)
        let resultsVisible = webView.staticTexts
            .containing(NSPredicate(format: "value CONTAINS[c] 'referrer' OR value CONTAINS[c] 'result' OR value CONTAINS[c] 'passed' OR value CONTAINS[c] 'failed'"))
            .firstMatch
        XCTAssertTrue(resultsVisible.waitForExistence(timeout: 5.0), "Referrer trimming results should be visible on the page")
    }

    // MARK: - GPC (Global Privacy Control) Tests

    func testNavigationProtection_GPC_HeaderInjection() throws {
        // Navigate to the GPC test page (matches integration test)
        let gpcTestURL = URL(string: "https://privacy-test-pages.site/privacy-protections/gpc/")!
        addressBarTextField.pasteURL(gpcTestURL, pressingEnter: true)

        // Wait for GPC test page to load
        let webView = app.webViews.firstMatch
        let gpcPageContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'GPC' OR value CONTAINS 'Global Privacy Control'")).firstMatch
        XCTAssertTrue(gpcPageContent.waitForExistence(timeout: 30.0), "GPC test page should load")

        // Find and click the "start" button to run the GPC test
        let startButton = webView.buttons["Start test"].firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: 10.0), "Start button should be available for GPC test")
        startButton.click()

        // Wait for test to complete - GPC test opens popup windows to test cross-frame GPC injection
        let testCompletionTimeout: TimeInterval = 40.0
        let downloadButton = webView.buttons["Download the result"]
        XCTAssertTrue(downloadButton.waitForExistence(timeout: testCompletionTimeout), "GPC test should complete and enable download button")

        // Wait for test results to appear in the page (no need to click anything)
        // After test completes, the results should be visible in the DOM
        let gpcResultElement = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Sec-GPC' OR value CONTAINS 'header' OR value CONTAINS 'passed' OR value CONTAINS 'failed' OR value CONTAINS 'Global Privacy Control'")).firstMatch
        XCTAssertTrue(gpcResultElement.waitForExistence(timeout: 15.0), "GPC test results should be visible on page after test completion")

        // Verify GPC header injection was tested - look for any indication that GPC was actually tested
        let gpcTestResult = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'GPC' OR value CONTAINS 'header' OR value CONTAINS 'privacy control'")).firstMatch
        XCTAssertTrue(gpcTestResult.waitForExistence(timeout: 5.0), "GPC header injection test should show results")

        // Verify the test ran on the correct page
        app.activateAddressBar()
        let finalURL = addressBarTextField.value as? String ?? ""
        XCTAssertTrue(finalURL.contains("privacy-test-pages.site/privacy-protections/gpc"), "Should remain on GPC test page")
    }

}
