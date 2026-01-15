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

    // MARK: - Test Cases

    func testWhenNavigatingToExpiredCertificate_ShowsExpectedSSLWarningPage() throws {
        // Navigate to an expired certificate page
        let badSSL = URL(string: "https://expired.badssl.com/")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(badSSL, pressingEnter: true)

        // Verify the SSL warning title appears
        let warningTitle = app.staticTexts["Warning: This site may be insecure"].firstMatch
        XCTAssertTrue(warningTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "SSL warning title should appear for expired certificate")

        // Verify the address bar shows globe icon (indicating error page, not the privacy shield)
        XCTAssertTrue(addressBarImageButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Globe icon should be visible in address bar for SSL error page")

        // Verify the certificate error message appears
        let certificateErrorText = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "certificate for this site is invalid")
        ).firstMatch
        XCTAssertTrue(certificateErrorText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Certificate error message should be displayed")

        // Verify the Advanced button is available
        let advancedButton = app.buttons["Advanced..."].firstMatch
        XCTAssertTrue(advancedButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Advanced button should be available")

        // Click Advanced to reveal more options
        advancedButton.click()

        // Verify the expanded warning text appears
        let expandedWarningText = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "DuckDuckGo warns you when a website has an invalid certificate")
        ).firstMatch
        XCTAssertTrue(expandedWarningText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Expanded warning text should appear after clicking Advanced")

        // Verify the expired-specific message - mentions "expired" or "system clock"
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
        let warningTitle = app.staticTexts["Warning: This site may be insecure"].firstMatch
        XCTAssertTrue(warningTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "SSL warning title should appear for wrong host certificate")

        // Verify the certificate error message appears
        let certificateErrorText = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "certificate for this site is invalid")
        ).firstMatch
        XCTAssertTrue(certificateErrorText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Certificate error message should be displayed for wrong host")

        // Verify the Advanced button is available
        let advancedButton = app.buttons["Advanced..."].firstMatch
        XCTAssertTrue(advancedButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Advanced button should be available")

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
        let warningTitle = app.staticTexts["Warning: This site may be insecure"].firstMatch
        XCTAssertTrue(warningTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "SSL warning title should appear for self-signed certificate")

        // Verify the certificate error message appears
        let certificateErrorText = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "certificate for this site is invalid")
        ).firstMatch
        XCTAssertTrue(certificateErrorText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Certificate error message should be displayed for self-signed")

        // Verify the Advanced button is available
        let advancedButton = app.buttons["Advanced..."].firstMatch
        XCTAssertTrue(advancedButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Advanced button should be available")

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
        let warningTitle = app.staticTexts["Warning: This site may be insecure"].firstMatch
        XCTAssertTrue(warningTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "SSL warning title should appear for untrusted root certificate")

        // Verify the certificate error message appears
        let certificateErrorText = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "certificate for this site is invalid")
        ).firstMatch
        XCTAssertTrue(certificateErrorText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Certificate error message should be displayed for untrusted root")

        // Verify the Advanced button is available
        let advancedButton = app.buttons["Advanced..."].firstMatch
        XCTAssertTrue(advancedButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Advanced button should be available")

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

}
