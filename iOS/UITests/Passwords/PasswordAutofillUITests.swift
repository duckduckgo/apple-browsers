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
            assertWebInputDismissed()
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

    func testChoosingOwnPasswordAllowsEditingThePasswordOnTheNextTap() {
        app.openURL(TestPage.signup, expecting: "Password generation during signup")
        app.enterWebFormText(username, inFieldNamed: "Email")
        app.focusSecureWebFormField(named: "Password")

        let prompt = app.descendants(matching: .any)["Autofill.PasswordGeneration.Prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: UITestTimeouts.navigation), "Password-generation prompt did not appear.")
        assertWebInputDismissed()
        app.buttons["Autofill.PasswordGeneration.UseOwnPassword"].tapWhenHittable()
        XCTAssertTrue(prompt.waitForNonExistence(timeout: UITestTimeouts.elementExistence), "Password-generation prompt did not dismiss.")

        assertWebInputDismissed()
        let password = app.webViews.secureTextFields["Password"]
        password.tapWhenHittable()
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Tapping Password after dismissing the prompt did not open the web form keyboard.")
        password.typeText("Own-password-2026!")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Own-password editing after native prompt dismissal"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.enterWebFormText("Own-password-2026!", inFieldNamed: "Password Confirmation", secure: true)
        app.submitWebForm(buttonNamed: "Sign up")
        app.assertPageContains("Success")
    }

    func testChoosingOwnPasswordAllowsEditingADifferentFieldOnTheNextTap() {
        app.openURL(TestPage.signup, expecting: "Password generation during signup")
        app.enterWebFormText(username, inFieldNamed: "Email")
        app.focusSecureWebFormField(named: "Password")

        let prompt = app.descendants(matching: .any)["Autofill.PasswordGeneration.Prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: UITestTimeouts.navigation), "Password-generation prompt did not appear.")
        assertWebInputDismissed()
        app.buttons["Autofill.PasswordGeneration.UseOwnPassword"].tapWhenHittable()
        XCTAssertTrue(prompt.waitForNonExistence(timeout: UITestTimeouts.elementExistence), "Password-generation prompt did not dismiss.")
        assertWebInputDismissed()

        let email = app.webViews.textFields["Email"]
        email.tapWhenHittable()
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Tapping Email after dismissing the prompt did not open the web form keyboard.")
        email.typeText(".edited")
        XCTAssertTrue(
            email.wait(for: NSPredicate(format: "value CONTAINS %@", ".edited"), timeout: UITestTimeouts.elementExistence),
            "Typing after the first Email tap did not update the field.")
    }

    private func assertWebInputDismissed(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: UITestTimeouts.elementExistence),
            "Web form keyboard remained above the native prompt.", file: file, line: line)
        XCTAssertTrue(
            app.toolbars["Toolbar"].waitForNonExistence(timeout: UITestTimeouts.elementExistence),
            "Web form input accessory remained above the native prompt.", file: file, line: line)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Password-generation prompt with web input dismissed"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

}
