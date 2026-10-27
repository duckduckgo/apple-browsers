//
//  AutofillTestHelpers.swift
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

/// Sign-up and login flows on local autofill test pages, so the tests don't depend on an outside site.
extension XCUIApplication {

    enum AutofillTestPage {
        case login
        case signUp

        var url: URL {
            UITests.simpleServedPage(titled: title, body: body)
        }

        var title: String {
            switch self {
            case .login: "Autofill login"
            case .signUp: "Autofill sign up"
            }
        }

        // Submitting keeps the page loaded, so the save and update popovers have a form to come from.
        private var body: String {
            switch self {
            case .login:
                """
                <form id="login" onsubmit="event.preventDefault(); document.title = 'Signed in';">
                  <label for="email">Email</label>
                  <input id="email" type="email" autocomplete="username">
                  <label for="password">Password</label>
                  <input id="password" type="password" autocomplete="current-password">
                  <button type="submit">Sign in</button>
                </form>
                """
            case .signUp:
                """
                <form id="signup" onsubmit="event.preventDefault(); document.title = 'Signed up';">
                  <label for="email">Email</label>
                  <input id="email" type="email" autocomplete="email">
                  <label for="password">Password</label>
                  <input id="password" type="password" autocomplete="new-password" passwordrules="minlength: 5; maxlength: 10">
                  <label for="password-2">Password Confirmation</label>
                  <input id="password-2" type="password" autocomplete="new-password" passwordrules="minlength: 5; maxlength: 10">
                  <button type="submit">Sign up</button>
                </form>
                """
            }
        }
    }

    var savePasswordPopoverTitle: XCUIElement {
        popovers.staticTexts["Save password in DuckDuckGo?"]
    }

    var updatePasswordPopoverTitle: XCUIElement {
        popovers.staticTexts["Update password?"]
    }

    /// Logins saved by earlier tests change which popover shows up, so tests that save one start from an empty vault.
    func resetAutofillData() {
        debugMenu.click()
        menuItems["MainMenu.resetData"].hover()
        menuItems["MainMenu.resetSecureVaultData"].clickAfterExistenceTestSucceeds()
    }

    func openAutofillTestPage(_ page: AutofillTestPage) {
        activateAddressBar()
        openURL(page.url, waitForWebViewAccessibilityLabel: page.title)
    }

    var autofillEmailTextField: XCUIElement {
        windows.firstMatch.webViews.firstMatch.textFields["Email"].firstMatch
    }

    var autofillPasswordTextField: XCUIElement {
        windows.firstMatch.webViews.firstMatch.secureTextFields["Password"].firstMatch
    }

    /// Fills email, password and password confirmation on the sign-up page.
    func fillSignUpForm(email: String, password: String) {
        windows.firstMatch.webViews.firstMatch.tap()
        autofillEmailTextField.click()
        autofillEmailTextField.typeText(email)

        autofillPasswordTextField.click()
        autofillPasswordTextField.typeText(password)
        typeKey("\t", modifierFlags: [])
        typeText(password)
    }

    func submitSignUpForm() {
        windows.firstMatch.webViews.firstMatch.buttons["Sign up"].firstMatch.click()
    }

    func signIn(email: String, password: String) {
        windows.firstMatch.webViews.firstMatch.tap()
        autofillEmailTextField.click()
        autofillEmailTextField.typeText(email)
        typeKey("\t", modifierFlags: [])
        typeText(password)
        submitLoginForm()
    }

    func submitLoginForm() {
        windows.firstMatch.webViews.firstMatch.buttons["Sign in"].firstMatch.click()
    }

    func saveCredentialsFromPopover() {
        XCTAssertTrue(
            savePasswordPopoverTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The Save password popover didn't appear after signing in."
        )
        popovers.buttons["Save"].click()
        XCTAssertTrue(
            savePasswordPopoverTitle.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "The Save password popover didn't close after saving."
        )
    }

    /// Picks the saved login from the autofill dropdown and checks that it filled the email field.
    func fillLoginUsingAutofill(email: String) {
        windows.firstMatch.webViews.firstMatch.tap()
        autofillEmailTextField.click()

        let savedLogin = autofillDropdownButton(labelBeginningWith: email)
        savedLogin.click()

        XCTAssertTrue(
            autofillEmailTextField.wait(for: \.value, equals: email, timeout: UITests.Timeouts.elementExistence),
            "Autofill didn't fill the email field."
        )
    }

    /// The dropdown is a child window with its own web view, so it can't be found inside the page's web view.
    func autofillDropdownButton(labelBeginningWith prefix: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let button = buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        if !button.waitForExistence(timeout: UITests.Timeouts.elementExistence) {
            let labels = buttons.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
            XCTFail("The autofill dropdown didn't offer \"\(prefix)…\". Windows: \(windows.count), buttons: \(labels)", file: file, line: line)
        }
        return button
    }
}
