//
//  SaveCredentialsPopoverUITests.swift
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

import XCTest

final class SaveCredentialsPopoverUITests: UITestCase {

    private static let loginPageTitle = "Save Credentials Login"
    private static let securityInfoPrefix = "Passwords are encrypted."
    private static let loginPageBody = """
    <form id="login" onsubmit="event.preventDefault(); document.title = 'Signed in';">
      <input type="email" name="email" id="email" autocomplete="username" placeholder="Email">
      <input type="password" name="password" id="password" autocomplete="current-password" placeholder="Password">
      <button type="submit">Sign in</button>
    </form>
    """

    override func setUpWithError() throws {
        try super.setUpWithError()
        // A fresh class profile can show the import promo over the login form.
        app = XCUIApplication.setUp(arguments: ["-com.duckduckgo.logins.isCredentialsImportPromptPermanantlyDismissed", "YES"])
        app.enforceSingleWindow()
    }

    /// Regression test: on macOS 12 the Save Credentials popover's `loadView` used to set a `CGRect.null`
    /// frame on its tooltip view, which made AppKit throw `NSInternalInconsistencyException`.
    func testSavePasswordPopoverShowsSecurityInfoTooltipOnLockHover() {
        let url = UITests.simpleServedPage(titled: Self.loginPageTitle, body: Self.loginPageBody)
        app.openURL(url, waitForWebViewAccessibilityLabel: Self.loginPageTitle)

        signIn()

        let savePasswordTitle = app.popovers.staticTexts["Save password in DuckDuckGo?"]
        XCTAssertTrue(
            savePasswordTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The Save password popover didn't appear after signing in."
        )
        XCTAssertTrue(app.popovers.buttons["Save"].exists)
        XCTAssertEqual(app.state, .runningForeground)

        // The security info tooltip is anchored to the view whose frame used to be CGRect.null
        let lockImage = app.popovers.images["SaveCredentialsViewController.lockImage"]
        XCTAssertTrue(lockImage.exists, "The lock image isn't shown in the Save password popover.")
        // Hover tracking is active only in the key window; the popover opens without taking focus
        savePasswordTitle.click()
        lockImage.hover()

        let securityInfo = app.popovers.staticTexts["PopoverInfoView.text"]
        XCTAssertTrue(
            securityInfo.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The security info tooltip didn't appear when hovering the lock image."
        )
        let securityInfoText = (securityInfo.value as? String) ?? securityInfo.label
        XCTAssertTrue(securityInfoText.hasPrefix(Self.securityInfoPrefix), "Unexpected tooltip text: \(securityInfoText)")

        // hover out
        app.popovers.firstMatch.hover()
        XCTAssertTrue(securityInfo.waitForNonExistence(timeout: UITests.Timeouts.elementExistence))
    }

    private func signIn() {
        let webView = app.windows.firstMatch.webViews[Self.loginPageTitle]
        let emailTextField = webView.textFields.firstMatch
        XCTAssertTrue(
            emailTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The email text field didn't appear."
        )
        emailTextField.click()
        emailTextField.typeText("test@duck.com")
        app.typeKey("\t", modifierFlags: [])
        app.typeText("pa$$word")
        webView.buttons["Sign in"].firstMatch.click()
    }
}
