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
import XCTest

final class SSLErrorTests: UITestCase {

    private var addressBarTextField: XCUIElement!
    private var webView: XCUIElement!

    /// The globe icon shown in the address bar for error pages
    private var addressBarImageButton: XCUIElement {
        app.buttons["AddressBarButtonsViewController.imageButton"]
    }

    /// The privacy dashboard button (shield icon) in the address bar
    private var privacyDashboardButton: XCUIElement {
        app.buttons.matching(identifier: "AddressBarButtonsViewController.privacyDashboardButton").firstMatch
    }

    /// The SSL warning page title
    private var warningTitle: XCUIElement {
        app.staticTexts["Warning: This site may be insecure"].firstMatch
    }

    /// The "expired." text shown on expired.badssl.com
    private var expiredSiteContent: XCUIElement {
        app.staticTexts["expired."].firstMatch
    }

    /// The home page element
    private var homePageElement: XCUIElement {
        app.groups["DuckDuckGo"].firstMatch
    }

    /// Back navigation button
    private var backButton: XCUIElement {
        app.buttons["NavigationBarViewController.BackButton"].firstMatch
    }

    /// Forward navigation button
    private var forwardButton: XCUIElement {
        app.buttons["NavigationBarViewController.ForwardButton"].firstMatch
    }

    /// The Advanced button on SSL warning pages
    private var advancedButton: XCUIElement {
        app.buttons["Advanced..."].firstMatch
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()
        addressBarTextField = app.addressBar
        webView = app.webViews.firstMatch
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Address bar should be available")
    }

    override func tearDown() {
        addressBarTextField = nil
        webView = nil
        app = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    /// Navigates to the given URL
    private func navigateTo(_ url: URL) {
        app.activateAddressBar()
        addressBarTextField.pasteURL(url, pressingEnter: true)
    }

    /// Clicks "Advanced..." then "Accept Risk and Visit Site" to bypass the SSL warning
    private func acceptRiskAndVisitSite() {
        verifyAdvancedButtonIsAvailable()
        advancedButton.click()

        let acceptRiskLink = app.staticTexts["Accept Risk and Visit Site"].firstMatch
        XCTAssertTrue(acceptRiskLink.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Accept Risk and Visit Site link should be available")
        acceptRiskLink.click()
    }

    /// Verifies the address bar contains the expected URL substring
    private func verifyAddressBarContains(_ substring: String, message: String) {
        let addressBarValue = app.addressBarValueActivatingIfNeeded()
        XCTAssertTrue(
            addressBarValue?.contains(substring) == true,
            "\(message), got: \(addressBarValue ?? "nil")"
        )
        app.typeKey(.escape, modifierFlags: [])
    }

    /// Verifies the address bar is empty (home page)
    private func verifyAddressBarIsEmpty(message: String) {
        let addressBarValue = app.addressBarValueActivatingIfNeeded()
        XCTAssertTrue(
            addressBarValue?.isEmpty == true,
            "\(message), got: \(addressBarValue ?? "nil")"
        )
    }

    /// Verifies we're on the SSL site with the expected content, URL, and shield with dot
    private func verifyOnSSLSite(context: String) {
        XCTAssertTrue(expiredSiteContent.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "SSL site content should be visible \(context)")
        verifyAddressBarContains("expired.badssl.com", message: "Address bar should show SSL site URL \(context)")
        XCTAssertTrue(privacyDashboardButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Privacy dashboard button should be visible \(context)")
        XCTAssertEqual(privacyDashboardButton.value as? String, "shieldDot",
                       "Shield should show dot indicator \(context)")
    }

    /// Verifies we're on the home page with the expected element and empty address bar
    private func verifyOnHomePage(context: String) {
        XCTAssertTrue(homePageElement.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Home page should be displayed \(context)")
        verifyAddressBarIsEmpty(message: "Address bar should be empty \(context)")
    }

    /// Verifies the SSL warning title appears
    private func verifySSLWarningTitleAppears(for certificateType: String) {
        XCTAssertTrue(warningTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "SSL warning title should appear for \(certificateType)")
    }

    /// Verifies the certificate error message appears
    private func verifyCertificateErrorMessageAppears(for certificateType: String? = nil) {
        let certificateErrorText = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "certificate for this site is invalid")
        ).firstMatch
        let context = certificateType.map { " for \($0)" } ?? ""
        XCTAssertTrue(certificateErrorText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Certificate error message should be displayed\(context)")
    }

    /// Verifies the Advanced button is available
    private func verifyAdvancedButtonIsAvailable() {
        XCTAssertTrue(advancedButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Advanced button should be available")
    }

    // MARK: - Error Page Content Tests

    func testWhenNavigatingToExpiredCertificate_ShowsExpectedSSLWarningPage() throws {
        // Navigate to an expired certificate page
        let badSSL = URL(string: "https://expired.badssl.com/")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(badSSL, pressingEnter: true)

        // Verify the SSL warning title appears
        verifySSLWarningTitleAppears(for: "expired certificate")

        // Verify the address bar shows globe icon (indicating error page, not the privacy shield)
        XCTAssertTrue(addressBarImageButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Globe icon should be visible in address bar for SSL error page")

        // Verify the certificate error message appears
        verifyCertificateErrorMessageAppears()

        // Verify the Advanced button is available
        verifyAdvancedButtonIsAvailable()

        // Click Advanced to reveal more options
        advancedButton.click()

        // Verify the expanded warning text appears
        let expandedWarningText = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "DuckDuckGo warns you when a website has an invalid certificate")
        ).firstMatch
        XCTAssertTrue(expandedWarningText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Expanded warning text should appear after clicking Advanced")

        // Verify the expired-specific message (contains "is expired")
        let expiredSpecificText = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "is expired")
        ).firstMatch
        XCTAssertTrue(expiredSpecificText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Expired certificate specific message should be shown")

        // Verify the Leave This Site button is available
        let leaveButton = app.buttons["Leave This Site"].firstMatch
        XCTAssertTrue(leaveButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Leave This Site button should be available")
    }

    func testWhenNavigatingToWrongHostCertificate_ShowsSSLWarningPage() throws {
        // Navigate to a wrong host certificate page (hostname mismatch)
        let wrongHostURL = URL(string: "https://wrong.host.badssl.com/")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(wrongHostURL, pressingEnter: true)

        // Verify the SSL warning title appears
        verifySSLWarningTitleAppears(for: "wrong host certificate")

        // Verify the certificate error message appears
        verifyCertificateErrorMessageAppears(for: "wrong host")

        // Verify the Advanced button is available
        verifyAdvancedButtonIsAvailable()

        // Click Advanced to reveal more options
        advancedButton.click()

        // Verify the expanded warning text appears
        let expandedWarningText = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "DuckDuckGo warns you when a website has an invalid certificate")
        ).firstMatch
        XCTAssertTrue(expandedWarningText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Expanded warning text should appear after clicking Advanced")

        // Verify the wrong host specific message - "does not match"
        let wrongHostSpecificText = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "does not match")
        ).firstMatch
        XCTAssertTrue(wrongHostSpecificText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Wrong host specific message should be shown (does not match)")

        // Verify the Leave This Site button is available
        let leaveButton = app.buttons["Leave This Site"].firstMatch
        XCTAssertTrue(leaveButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Leave This Site button should be available")
    }

    func testWhenNavigatingToSelfSignedCertificate_ShowsSSLWarningPage() throws {
        // Navigate to a self-signed certificate page
        let selfSignedURL = URL(string: "https://self-signed.badssl.com/")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(selfSignedURL, pressingEnter: true)

        // Verify the SSL warning title appears
        verifySSLWarningTitleAppears(for: "self-signed certificate")

        // Verify the certificate error message appears
        verifyCertificateErrorMessageAppears(for: "self-signed")

        // Verify the Advanced button is available
        verifyAdvancedButtonIsAvailable()

        // Click Advanced to reveal more options
        advancedButton.click()

        // Verify the expanded warning text appears
        let expandedWarningText = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "DuckDuckGo warns you when a website has an invalid certificate")
        ).firstMatch
        XCTAssertTrue(expandedWarningText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Expanded warning text should appear after clicking Advanced")

        // Verify the self-signed specific message - "not trusted by your device's operating system"
        let selfSignedSpecificText = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "not trusted by your device")
        ).firstMatch
        XCTAssertTrue(selfSignedSpecificText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Self-signed specific message should be shown (not trusted by device)")

        // Verify the Leave This Site button is available
        let leaveButton = app.buttons["Leave This Site"].firstMatch
        XCTAssertTrue(leaveButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Leave This Site button should be available")
    }

    func testWhenNavigatingToUntrustedRootCertificate_ShowsSSLWarningPage() throws {
        // Navigate to an untrusted root certificate page (certificate chain not trusted)
        let untrustedRootURL = URL(string: "https://untrusted-root.badssl.com/")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(untrustedRootURL, pressingEnter: true)

        // Verify the SSL warning title appears
        verifySSLWarningTitleAppears(for: "untrusted root certificate")

        // Verify the certificate error message appears
        verifyCertificateErrorMessageAppears(for: "untrusted root")

        // Verify the Advanced button is available
        verifyAdvancedButtonIsAvailable()

        // Click Advanced to reveal more options
        advancedButton.click()

        // Verify the expanded warning text appears
        let expandedWarningText = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "DuckDuckGo warns you when a website has an invalid certificate")
        ).firstMatch
        XCTAssertTrue(expandedWarningText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Expanded warning text should appear after clicking Advanced")

        // Verify the invalid/untrusted root specific message - "not trusted by your device's operating system"
        let untrustedSpecificText = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "not trusted by your device")
        ).firstMatch
        XCTAssertTrue(untrustedSpecificText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Untrusted root specific message should be shown (not trusted by device)")

        // Verify the Leave This Site button is available
        let leaveButton = app.buttons["Leave This Site"].firstMatch
        XCTAssertTrue(leaveButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Leave This Site button should be available")
    }

    // MARK: - Navigation Tests

    func testWhenClickingLeaveSiteButton_NavigatesToHomePageAndCanGoBackAndForward() throws {
        // Navigate to an SSL error page
        let badSSL = URL(string: "https://expired.badssl.com/")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(badSSL, pressingEnter: true)

        // Wait for SSL warning page to appear
        let warningTitle = app.staticTexts["Warning: This site may be insecure"].firstMatch
        XCTAssertTrue(warningTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "SSL warning page should appear")

        // Click "Leave This Site" button
        let leaveButton = app.buttons["Leave This Site"].firstMatch
        XCTAssertTrue(leaveButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Leave This Site button should be available")
        leaveButton.click()

        // Verify home page is displayed by checking for the DuckDuckGo home page element
        let homePageElement = app.groups["DuckDuckGo"].firstMatch
        XCTAssertTrue(homePageElement.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Home page should be displayed after leaving SSL error site")
        let addressBarValue = app.addressBarValueActivatingIfNeeded()
        XCTAssertTrue(
            addressBarValue?.isEmpty == true,
            "Address bar should be empty on home page, got: \(addressBarValue ?? "nil")"
        )

        // Navigate forward using the forward button
        let forwardButton = app.buttons["NavigationBarViewController.ForwardButton"].firstMatch
        XCTAssertTrue(forwardButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Forward button should exist")
        XCTAssertTrue(forwardButton.isEnabled, "Forward button should be enabled after leaving site")
        forwardButton.click()

        // Verify we're back on the SSL error page
        XCTAssertTrue(warningTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "SSL warning page should appear again after navigating forward")

        // Navigate back using the back button
        let backButton = app.buttons["NavigationBarViewController.BackButton"].firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Back button should exist")
        XCTAssertTrue(backButton.isEnabled, "Back button should be enabled on SSL error page")
        backButton.click()

        // Verify we're back on the home page
        XCTAssertTrue(homePageElement.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Home page should be displayed after navigating back from SSL error")
        let finalAddressBarValue = app.addressBarValueActivatingIfNeeded()
        XCTAssertTrue(
            finalAddressBarValue?.isEmpty == true,
            "Address bar should be empty after navigating back to home page, got: \(finalAddressBarValue ?? "nil")"
        )
    }

    func testWhenClickingAdvancedThenLeaveSite_NavigatesToHomePage() throws {
        // Navigate to an SSL error page
        let badSSL = URL(string: "https://expired.badssl.com/")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(badSSL, pressingEnter: true)

        // Wait for SSL warning page to appear
        let warningTitle = app.staticTexts["Warning: This site may be insecure"].firstMatch
        XCTAssertTrue(warningTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "SSL warning page should appear")

        // Click "Advanced..." button
        verifyAdvancedButtonIsAvailable()
        advancedButton.click()

        // Verify the advanced section is expanded (check for expanded warning text)
        let expandedWarningText = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "DuckDuckGo warns you when a website has an invalid certificate")
        ).firstMatch
        XCTAssertTrue(expandedWarningText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Advanced section should be expanded")

        // Click "Leave This Site" button
        let leaveButton = app.buttons["Leave This Site"].firstMatch
        XCTAssertTrue(leaveButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Leave This Site button should be available")
        leaveButton.click()

        // Verify home page is displayed
        let homePageElement = app.groups["DuckDuckGo"].firstMatch
        XCTAssertTrue(homePageElement.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Home page should be displayed after leaving SSL error site")
        let addressBarValue = app.addressBarValueActivatingIfNeeded()
        XCTAssertTrue(
            addressBarValue?.isEmpty == true,
            "Address bar should be empty on home page, got: \(addressBarValue ?? "nil")"
        )
    }

    func testWhenClickingAcceptRiskAndVisitSite_LoadsSiteAndCanNavigateBackAndForward() throws {
        // Navigate to an SSL error page
        let badSSL = URL(string: "https://expired.badssl.com/")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(badSSL, pressingEnter: true)

        // Wait for SSL warning page to appear
        let warningTitle = app.staticTexts["Warning: This site may be insecure"].firstMatch
        XCTAssertTrue(warningTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "SSL warning page should appear")

        // Click "Advanced..." button
        verifyAdvancedButtonIsAvailable()
        advancedButton.click()

        // Verify the advanced section is expanded
        let expandedWarningText = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "DuckDuckGo warns you when a website has an invalid certificate")
        ).firstMatch
        XCTAssertTrue(expandedWarningText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Advanced section should be expanded")

        // Click "Accept Risk and Visit Site" link
        let acceptRiskLink = app.staticTexts["Accept Risk and Visit Site"].firstMatch
        XCTAssertTrue(acceptRiskLink.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Accept Risk and Visit Site link should be available")
        acceptRiskLink.click()

        // Verify the actual site content is loaded (badssl.com shows "expired." text prominently)
        let siteContent = app.staticTexts["expired."].firstMatch
        XCTAssertTrue(siteContent.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Site content should be visible after accepting risk")

        // Verify address bar shows the site URL
        let siteAddressBarValue = app.addressBarValueActivatingIfNeeded()
        XCTAssertTrue(
            siteAddressBarValue?.contains("expired.badssl.com") == true,
            "Address bar should show the site URL, got: \(siteAddressBarValue ?? "nil")"
        )

        // Navigate back using the back button
        let backButton = app.buttons["NavigationBarViewController.BackButton"].firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Back button should exist")
        XCTAssertTrue(backButton.isEnabled, "Back button should be enabled after visiting site")
        backButton.click()

        // Verify we're on the home page
        let homePageElement = app.groups["DuckDuckGo"].firstMatch
        XCTAssertTrue(homePageElement.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Home page should be displayed after navigating back")
        let homeAddressBarValue = app.addressBarValueActivatingIfNeeded()
        XCTAssertTrue(
            homeAddressBarValue?.isEmpty == true,
            "Address bar should be empty on home page, got: \(homeAddressBarValue ?? "nil")"
        )

        // Navigate forward using the forward button
        let forwardButton = app.buttons["NavigationBarViewController.ForwardButton"].firstMatch
        XCTAssertTrue(forwardButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Forward button should exist")
        XCTAssertTrue(forwardButton.isEnabled, "Forward button should be enabled after going back")
        forwardButton.click()

        // Verify we're back on the site (not the error page)
        let finalAddressBarValue = app.addressBarValueActivatingIfNeeded()
        XCTAssertTrue(
            finalAddressBarValue?.contains("expired.badssl.com") == true,
            "Address bar should show the site URL after navigating forward, got: \(finalAddressBarValue ?? "nil")"
        )

        // Verify the warning is NOT shown (we should see the actual site, not the error page)
        XCTAssertFalse(warningTitle.exists,
                       "SSL warning should not appear - should show actual site after accepting risk")
    }

    func testWhenOnAcceptedRiskSite_ShowsShieldWithDotAndPrivacyDashboardShowsCertificateError() throws {
        // Navigate to SSL error page and verify address bar shows URL
        let badSSL = URL(string: "https://expired.badssl.com/")!
        navigateTo(badSSL)
        XCTAssertTrue(warningTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "SSL warning page should appear")
        verifyAddressBarContains("expired.badssl.com", message: "Address bar should show site URL on error page")

        // Accept risk and verify we're on the SSL site
        acceptRiskAndVisitSite()
        verifyOnSSLSite(context: "after accepting risk")

        // Verify privacy dashboard shows certificate error
        privacyDashboardButton.click()
        let certificateErrorInDashboard = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "certificate")
        ).firstMatch
        XCTAssertTrue(certificateErrorInDashboard.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Privacy dashboard should show certificate error information")
        let domainInDashboard = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "expired.badssl.com")
        ).firstMatch
        XCTAssertTrue(domainInDashboard.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Privacy dashboard should show the domain name")
        app.typeKey(.escape, modifierFlags: [])

        // Navigate to Wikipedia and verify shield without dot
        let wikipediaURL = URL(string: "https://www.wikipedia.org/")!
        navigateTo(wikipediaURL)
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Wikipedia should load")
        verifyAddressBarContains("wikipedia.org", message: "Address bar should show Wikipedia URL")
        XCTAssertTrue(privacyDashboardButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Privacy dashboard button should be visible on Wikipedia")
        XCTAssertEqual(privacyDashboardButton.value as? String, "shield",
                       "Shield should NOT show dot indicator for normal secure site")

        // Navigate back to SSL site and verify
        backButton.click()
        verifyOnSSLSite(context: "after navigating back from Wikipedia")

        // Navigate back to home page and verify
        backButton.click()
        verifyOnHomePage(context: "after navigating back from SSL site")

        // Navigate forward to SSL site and verify
        forwardButton.click()
        verifyOnSSLSite(context: "after navigating forward from home")
    }

}
