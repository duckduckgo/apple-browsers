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
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        app.dismissAddressBarEditing()
        app.resetPasswords()
    }

    func testGeneratedPasswordCanBeSavedAndAutofilledIntoStandardAndMultistepForms() throws {
        let fixture = PasswordAutofillFixture()
        try fixture.start()
        defer { fixture.stop() }

        var signupCredentials: PasswordAutofillFixture.Credentials?
        XCTContext.runActivity(named: "Generate and save credentials during signup") { _ in
            app.openURL(fixture.signupURL, expecting: "Password generation during signup")
            app.enterWebFormText(username, inFieldNamed: "Email")
            app.focusSecureWebFormField(named: "Password")

            XCTAssertTrue(
                app.descendants(matching: .any)["Autofill.PasswordGeneration.Prompt"]
                    .waitForExistence(timeout: UITestTimeouts.navigation),
                "Password-generation prompt did not appear.")
            assertWebInputDismissed()
            app.buttons["Autofill.PasswordGeneration.UseGeneratedPassword"].tapWhenHittable()
            app.submitWebForm(buttonNamed: "Sign up")
            app.assertPageContains("Signup captured")
            signupCredentials = fixture.submittedSignupCredentials
        }

        guard let signupCredentials else {
            XCTFail("Signup fixture did not capture the generated credentials.")
            return
        }
        XCTAssertTrue(signupCredentials.username == username, "Signup fixture captured a different username.")
        assertFixtureRejectsIncorrectPassword(at: fixture.standardLoginURL, username: username)

        XCTContext.runActivity(named: "Verify generated credentials were saved") { _ in
            app.openPasswordManagerFromBrowsingMenu()
            app.authenticateForPasswordAccess(using: springboard)

            let item = app.passwordItem(named: fixture.credentialDomain)
            XCTAssertTrue(
                item.waitForExistence(timeout: UITestTimeouts.elementExistence),
                "Generated credential was not saved for the fixture origin.")
            XCTAssertTrue(
                item.staticTexts[username].exists,
                "Generated credential did not retain the signup email.")
            item.tapWhenHittable()
            app.buttons["Autofill.Passwords.Details.TogglePasswordVisibility"].tapWhenHittable()
            XCTAssertTrue(
                app.staticTexts[signupCredentials.password].waitForExistence(timeout: UITestTimeouts.elementExistence),
                "Saved password did not match the password submitted by the generated-password signup.")
            app.buttons["Autofill.Passwords.Details.TogglePasswordVisibility"].tapWhenHittable()
            app.navigationBars.buttons["BackButton"].firstMatch.tapWhenHittable()
            XCTAssertTrue(
                app.passwordItem(named: fixture.credentialDomain).waitForExistence(timeout: UITestTimeouts.elementExistence),
                "Passwords list did not reappear after verifying the saved credential.")
            app.closePasswordManagerToBrowser()
            app.backgroundAndActivate()
        }

        XCTContext.runActivity(named: "Autofill and submit the standard login form") { _ in
            app.openURL(fixture.standardLoginURL, expecting: "Sign in form")
            app.selectSavedPassword(username: username)
            app.authenticateForSavedPasswordFill(using: springboard)
            app.assertPageContains("Standard credentials match")
            app.backgroundAndActivate()
        }

        XCTContext.runActivity(named: "Autofill and submit the multistep login form") { _ in
            app.openURL(fixture.multistepLoginURL, expecting: "Log in")
            app.selectSavedPassword(username: username)
            app.authenticateForSavedPasswordFill(using: springboard)

            app.focusSecureWebFormField(named: "Password")
            app.selectSavedPassword(username: username)
            app.assertPageContains("Multistep credentials match")
        }
    }

    func testChoosingOwnPasswordReturnsKeyboardToPasswordField() {
        app.openURL(TestPage.signup, expecting: "Password generation during signup")
        app.enterWebFormText(username, inFieldNamed: "Email")
        app.focusSecureWebFormField(named: "Password")

        let prompt = app.descendants(matching: .any)["Autofill.PasswordGeneration.Prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: UITestTimeouts.navigation), "Password-generation prompt did not appear.")
        assertWebInputDismissed()
        app.buttons["Autofill.PasswordGeneration.UseOwnPassword"].tapWhenHittable()
        XCTAssertTrue(prompt.waitForNonExistence(timeout: UITestTimeouts.elementExistence), "Password-generation prompt did not dismiss.")

        assertWebKeyboardVisible()
        let password = app.webViews.secureTextFields["Password"]
        let valueBeforeTyping = password.value as? String
        app.keyboards.firstMatch.keys["a"].tapWhenHittable()
        let valueAfterTyping = password.value as? String
        XCTAssertNotEqual(
            valueAfterTyping,
            valueBeforeTyping,
            "Tapping the restored software keyboard did not change the Password field.")
        app.typeText("Own-password-2026!")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Own-password editing after native prompt dismissal"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.enterWebFormText("aOwn-password-2026!", inFieldNamed: "Password Confirmation", secure: true)
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
        assertWebKeyboardVisible()

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

    func testClosingPasswordGenerationPromptKeepsKeyboardHiddenUntilNextFieldTap() {
        app.openURL(TestPage.signup, expecting: "Password generation during signup")
        app.enterWebFormText(username, inFieldNamed: "Email")
        app.focusSecureWebFormField(named: "Password")

        let prompt = app.descendants(matching: .any)["Autofill.PasswordGeneration.Prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: UITestTimeouts.navigation), "Password-generation prompt did not appear.")
        assertWebInputDismissed()
        app.buttons["Autofill.Prompt.Close"].tapWhenHittable()
        XCTAssertTrue(prompt.waitForNonExistence(timeout: UITestTimeouts.elementExistence), "Password-generation prompt did not dismiss.")
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: UITestTimeouts.elementExistence),
            "Closing the prompt unexpectedly reopened the keyboard.")

        let email = app.webViews.textFields["Email"]
        email.tapWhenHittable()
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: UITestTimeouts.elementExistence),
            "The first Email tap after closing the prompt did not reopen the keyboard.")
        email.typeText(".edited")
        XCTAssertTrue(
            email.wait(for: NSPredicate(format: "value CONTAINS %@", ".edited"), timeout: UITestTimeouts.elementExistence),
            "Email did not accept input after closing the prompt.")
    }

    private func assertWebKeyboardVisible(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Web form keyboard did not return after the password-generation prompt dismissed.",
            file: file,
            line: line)
        XCTAssertTrue(
            app.keyboards.firstMatch.keys["a"].wait(
                for: NSPredicate(format: "isHittable == true"), timeout: UITestTimeouts.elementExistence),
            "The restored web keyboard did not expose a tappable letter key.",
            file: file,
            line: line)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Web keyboard restored before typing"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func assertFixtureRejectsIncorrectPassword(at url: String, username: String) {
        guard let url = URL(string: url) else {
            XCTFail("Password fixture URL was invalid.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: "known-incorrect-password")
        ]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let responseReceived = expectation(description: "Incorrect password response")
        var responseBody: String?
        var responseError: Error?
        URLSession.shared.dataTask(with: request) { data, _, error in
            responseBody = data.flatMap { String(data: $0, encoding: .utf8) }
            responseError = error
            responseReceived.fulfill()
        }.resume()
        wait(for: [responseReceived], timeout: UITestTimeouts.navigation)

        guard let responseBody else {
            XCTFail("Password fixture did not return a mismatch response: \(responseError?.localizedDescription ?? "empty response").")
            return
        }
        XCTAssertTrue(responseBody.contains("Standard credentials mismatch"), "Password fixture did not reject an incorrect password.")
        XCTAssertFalse(responseBody.contains("Standard credentials match"), "Password fixture mismatch response also contained the success marker.")
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
