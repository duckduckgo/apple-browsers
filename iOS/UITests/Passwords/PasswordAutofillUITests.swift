//
//  PasswordAutofillUITests.swift
//  DuckDuckGo
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
import UITestingSupport

final class PasswordAutofillUITests: UITestCase {

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let username = "test@example.com"

    private enum TestPage {
        static let signup = "https://privacy-test-pages.site/autofill/autoprompt/0-standard-signup-form.html"
        static let standardLogin = "https://privacy-test-pages.site/autofill/autoprompt/1-standard-login-form.html"
        static let multistepLogin = "https://privacy-test-pages.site/autofill/autoprompt/3-multistep-form.html"
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        app.resetPasswords()
    }

    func testGeneratedPasswordCanBeSavedAndAutofilledIntoStandardAndMultistepForms() {
        XCTContext.runActivity(named: "Generate and save credentials during signup") { _ in
            app.openURL(TestPage.signup, expecting: "Password generation during signup")
            app.enterWebFormText(username, inFieldNamed: "Email")
            app.focusSecureWebFormField(named: "Password")

            XCTAssertTrue(
                app.descendants(matching: .any)["Autofill.PasswordGeneration.Prompt"]
                    .waitForExistence(timeout: UITestTimeouts.navigation),
                "Password-generation prompt did not appear.")
            app.buttons["Autofill.PasswordGeneration.UseGeneratedPassword"].tapWhenHittable()
            app.submitWebForm(buttonNamed: "Sign up")
            app.assertPageContains("Success")
        }

        XCTContext.runActivity(named: "Verify generated credentials were saved") { _ in
            app.openPasswordManagerFromBrowsingMenu()
            app.authenticateForPasswordAccess(using: springboard)

            let item = app.passwordItem(named: "privacy-test-pages.site")
            XCTAssertTrue(
                item.waitForExistence(timeout: UITestTimeouts.elementExistence),
                "Generated credential was not saved for privacy-test-pages.site.")
            XCTAssertTrue(
                item.staticTexts[username].exists,
                "Generated credential did not retain the signup email.")
            app.closePasswordManagerToBrowser()
            app.backgroundAndActivate()
        }

        XCTContext.runActivity(named: "Autofill and submit the standard login form") { _ in
            app.openURL(TestPage.standardLogin, expecting: "Sign in form")
            app.selectSavedPassword(username: username)
            app.authenticateForSavedPasswordFill(using: springboard)
            app.assertPageContains("Submitted!")
            app.backgroundAndActivate()
        }

        XCTContext.runActivity(named: "Autofill and submit the multistep login form") { _ in
            app.openURL(TestPage.multistepLogin, expecting: "Log in")
            app.selectSavedPassword(username: username)
            app.authenticateForSavedPasswordFill(using: springboard)

            app.focusSecureWebFormField(named: "Password")
            app.selectSavedPassword(username: username)
            app.assertPageContains("Submitted!")
        }
    }
}
