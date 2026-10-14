//
//  SSLErrorTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import Common
import FoundationExtensions
import XCTest

final class SSLErrorTests: UITestCase {

    // MARK: - Properties

    private var addressBarTextField: XCUIElement!

    /// Public hosts serving an expired certificate. badssl.com goes first; the others keep the tests running when it is slow or down.
    private let expiredCertificateURLs = [
        URL(string: "https://expired.badssl.com/")!,
        URL(string: "https://expired-rsa-dv.ssl.com/")!,
        URL(string: "https://expired.sca1a.amazontrust.com/")!
    ]

    /// Host that served the SSL error page in the current test
    private var sslSiteHost = ""

    private var addressBarImageButton: XCUIElement {
        app.buttons["AddressBarButtonsViewController.imageButton"]
    }

    private var privacyDashboardButton: XCUIElement {
        app.buttons.matching(identifier: "AddressBarButtonsViewController.privacyDashboardButton").firstMatch
    }

    private var warningTitle: XCUIElement {
        app.staticTexts["Warning: This site may be insecure"].firstMatch
    }

    /// Content of the badssl.com expired page, shown once the risk is accepted
    private var expiredSiteContent: XCUIElement {
        app.staticTexts["expired."].firstMatch
    }

    /// Text that only the loaded site shows (the warning page doesn't contain it), for each host in `expiredCertificateURLs`
    private var loadedSiteContent: XCUIElement {
        switch sslSiteHost {
        case "expired-rsa-dv.ssl.com":
            return staticText(containing: "authenticated by SSL.com")
        case "expired.sca1a.amazontrust.com":
            return staticText(containing: "loads this page without warning")
        default:
            return expiredSiteContent
        }
    }

    private func staticText(containing text: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "value CONTAINS[c] %@ OR label CONTAINS[c] %@", text, text)).firstMatch
    }

    private var homePageElement: XCUIElement {
        app.groups["DuckDuckGo"].firstMatch
    }

    private var backButton: XCUIElement {
        app.buttons["NavigationBarViewController.BackButton"].firstMatch
    }

    private var forwardButton: XCUIElement {
        app.buttons["NavigationBarViewController.ForwardButton"].firstMatch
    }

    private var advancedButton: XCUIElement {
        app.buttons["Advanced..."].firstMatch
    }

    private var leaveThisSiteButton: XCUIElement {
        app.buttons["Leave This Site"].firstMatch
    }

    private var acceptRiskLink: XCUIElement {
        app.staticTexts["Accept Risk and Visit Site"].firstMatch
    }

    // MARK: - Setup & Teardown

    override func setUpWithError() throws {
        try super.setUpWithError()
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()
        addressBarTextField = app.addressBar
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Address bar should be available")
    }

    override func tearDown() {
        addressBarTextField = nil
        app = nil
        super.tearDown()
    }

    // MARK: - Navigation Helpers

    private func navigateTo(_ url: URL) {
        app.activateAddressBar()
        addressBarTextField.pasteURL(url, pressingEnter: true)
    }

    private func navigateToExpiredSSLErrorPage() {
        navigateToSSLErrorPage(candidates: expiredCertificateURLs)
    }

    /// Navigates to the first candidate that shows the SSL warning page, so a slow or unreachable test host
    /// doesn't fail the test. A repeated URL is a retry of the same host.
    private func navigateToSSLErrorPage(candidates: [URL]) {
        for url in candidates {
            navigateTo(url)
            guard warningTitle.waitForExistence(timeout: UITests.Timeouts.localTestServer) else { continue }
            sslSiteHost = url.host ?? ""
            return
        }
        XCTFail("SSL warning page should appear for one of \(candidates.map(\.absoluteString))")
    }

    private func clickAdvancedButton() {
        XCTAssertTrue(advancedButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Advanced button should be available")
        advancedButton.click()
    }

    private func clickLeaveThisSiteButton() {
        XCTAssertTrue(leaveThisSiteButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Leave This Site button should be available")
        leaveThisSiteButton.click()
    }

    private func acceptRiskAndVisitSite() {
        clickAdvancedButton()
        XCTAssertTrue(acceptRiskLink.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Accept Risk and Visit Site link should be available")
        acceptRiskLink.click()
    }

    // MARK: - Verification Helpers

    private func verifyAddressBarContains(_ substring: String, context: String = "") {
        let addressBarValue = app.addressBarValueActivatingIfNeeded()
        let message = context.isEmpty ? "Address bar should contain \(substring)" : "Address bar should contain \(substring) \(context)"
        XCTAssertTrue(addressBarValue?.contains(substring) == true, "\(message), got: \(addressBarValue ?? "nil")")
        app.typeKey(.escape, modifierFlags: [])
    }

    private func verifyAddressBarIsEmpty(context: String = "") {
        let addressBarValue = app.addressBarValueActivatingIfNeeded()
        let message = context.isEmpty ? "Address bar should be empty" : "Address bar should be empty \(context)"
        XCTAssertTrue(addressBarValue?.isEmpty == true, "\(message), got: \(addressBarValue ?? "nil")")
    }

    private func verifyOnSSLSite(context: String = "") {
        XCTAssertTrue(loadedSiteContent.waitForExistence(timeout: UITests.Timeouts.navigation),
                      "SSL site content should be visible \(context)")
        verifyAddressBarContains(sslSiteHost, context: context)
        verifyShieldWithDot(context: context)
    }

    private func verifyOnHomePage(context: String = "") {
        XCTAssertTrue(homePageElement.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Home page should be displayed \(context)")
        verifyAddressBarIsEmpty(context: context)
    }

    private func verifyOnSSLErrorPage(context: String = "") {
        XCTAssertTrue(warningTitle.waitForExistence(timeout: UITests.Timeouts.navigation),
                      "SSL warning page should appear \(context)")
    }

    private func verifyShieldWithDot(context: String = "") {
        XCTAssertTrue(privacyDashboardButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Privacy dashboard button should be visible \(context)")
        // The shield updates once the navigation to the accepted site commits
        _ = privacyDashboardButton.wait(for: NSPredicate(format: "value == %@", "shieldDot"), timeout: UITests.Timeouts.navigation)
        XCTAssertEqual(privacyDashboardButton.value as? String, "shieldDot",
                       "Shield should show dot indicator \(context)")
    }

    private func verifyShieldWithoutDot(context: String = "") {
        XCTAssertTrue(privacyDashboardButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Privacy dashboard button should be visible \(context)")
        XCTAssertEqual(privacyDashboardButton.value as? String, "shield",
                       "Shield should NOT show dot indicator \(context)")
    }

    private func verifyGlobeIconIsVisible() {
        XCTAssertTrue(addressBarImageButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Globe icon should be visible in address bar for SSL error page")
    }

    private func verifyCertificateErrorMessageAppears() {
        let certificateErrorText = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "certificate for this site is invalid")
        ).firstMatch
        XCTAssertTrue(certificateErrorText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Certificate error message should be displayed")
    }

    private func verifyExpandedWarningTextAppears() {
        let expandedWarningText = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "DuckDuckGo warns you when a website has an invalid certificate")
        ).firstMatch
        XCTAssertTrue(expandedWarningText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Expanded warning text should appear after clicking Advanced")
    }

    private func verifySpecificErrorMessage(containing text: String, context: String) {
        let specificText = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", text)
        ).firstMatch
        XCTAssertTrue(specificText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "\(context) specific message should be shown")
    }

    private func verifyLeaveThisSiteButtonIsAvailable() {
        XCTAssertTrue(leaveThisSiteButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Leave This Site button should be available")
    }

    /// Unified helper for testing SSL warning page content for different certificate types
    private func verifySSLWarningPageContent(
        candidates: [URL],
        certificateType: String,
        specificErrorText: String
    ) {
        navigateToSSLErrorPage(candidates: candidates)

        // Verify warning page elements
        verifyOnSSLErrorPage(context: "for \(certificateType)")
        verifyGlobeIconIsVisible()
        verifyCertificateErrorMessageAppears()

        // Click Advanced and verify expanded content
        clickAdvancedButton()
        verifyExpandedWarningTextAppears()
        verifySpecificErrorMessage(containing: specificErrorText, context: certificateType)
        verifyLeaveThisSiteButtonIsAvailable()
    }

    /// badssl.com is the only public host for this certificate error, so the URL is tried twice
    private func retried(_ url: URL) -> [URL] {
        [url, url]
    }

    // MARK: - Error Page Content Tests

    func testWhenNavigatingToExpiredCertificate_ShowsExpectedSSLWarningPage() throws {
        verifySSLWarningPageContent(
            candidates: expiredCertificateURLs,
            certificateType: "expired certificate",
            specificErrorText: "is expired"
        )
    }

    func testWhenNavigatingToWrongHostCertificate_ShowsSSLWarningPage() throws {
        verifySSLWarningPageContent(
            candidates: retried(URL(string: "https://wrong.host.badssl.com/")!),
            certificateType: "wrong host certificate",
            specificErrorText: "does not match"
        )
    }

    func testWhenNavigatingToSelfSignedCertificate_ShowsSSLWarningPage() throws {
        verifySSLWarningPageContent(
            candidates: retried(URL(string: "https://self-signed.badssl.com/")!),
            certificateType: "self-signed certificate",
            specificErrorText: "not trusted by your device"
        )
    }

    func testWhenNavigatingToUntrustedRootCertificate_ShowsSSLWarningPage() throws {
        verifySSLWarningPageContent(
            candidates: retried(URL(string: "https://untrusted-root.badssl.com/")!),
            certificateType: "untrusted root certificate",
            specificErrorText: "not trusted by your device"
        )
    }

    // MARK: - Navigation Tests

    func testWhenClickingLeaveSiteButton_NavigatesToHomePageAndCanGoBackAndForward() throws {
        navigateToExpiredSSLErrorPage()
        clickLeaveThisSiteButton()

        // Verify home page, then navigate forward to error page, then back to home
        verifyOnHomePage(context: "after leaving SSL error site")
        forwardButton.click()
        verifyOnSSLErrorPage(context: "after navigating forward")
        backButton.click()
        verifyOnHomePage(context: "after navigating back")
    }

    func testWhenClickingAdvancedThenLeaveSite_NavigatesToHomePage() throws {
        navigateToExpiredSSLErrorPage()
        clickAdvancedButton()
        verifyExpandedWarningTextAppears()
        clickLeaveThisSiteButton()
        verifyOnHomePage(context: "after leaving SSL error site")
    }

    func testWhenClickingAcceptRiskAndVisitSite_LoadsSiteAndCanNavigateBackAndForward() throws {
        navigateToExpiredSSLErrorPage()
        acceptRiskAndVisitSite()

        // Verify on SSL site, then navigate back to home, then forward to SSL site
        verifyOnSSLSite(context: "after accepting risk")
        backButton.click()
        verifyOnHomePage(context: "after navigating back")
        forwardButton.click()
        verifyOnSSLSite(context: "after navigating forward")
    }

    func testWhenOnAcceptedRiskSite_ShowsShieldWithDotAndPrivacyDashboardShowsCertificateError() throws {
        // Navigate to SSL error page and accept risk
        navigateToExpiredSSLErrorPage()
        verifyAddressBarContains(sslSiteHost, context: "on error page")
        acceptRiskAndVisitSite()
        verifyOnSSLSite(context: "after accepting risk")

        // Verify privacy dashboard shows certificate error
        privacyDashboardButton.click()
        verifySpecificErrorMessage(containing: "certificate", context: "Privacy dashboard")
        verifySpecificErrorMessage(containing: sslSiteHost, context: "Privacy dashboard domain")
        app.typeKey(.escape, modifierFlags: [])

        // Navigate to secure site and verify shield without dot
        navigateTo(URL(string: "https://www.wikipedia.org/")!)
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: UITests.Timeouts.navigation),
                      "Wikipedia should load")
        verifyAddressBarContains("wikipedia.org", context: "on Wikipedia")
        verifyShieldWithoutDot(context: "on secure site")

        // Navigate back through history: SSL site → home → forward to SSL site
        backButton.click()
        verifyOnSSLSite(context: "after navigating back from Wikipedia")
        backButton.click()
        verifyOnHomePage(context: "after navigating back from SSL site")
        forwardButton.click()
        verifyOnSSLSite(context: "after navigating forward from home")
    }

}
