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

/// Sign-up and login flows on the privacy-test-pages.site autofill pages.
extension XCUIApplication {

    enum AutofillTestPage {
        case login
        case signUp

        var url: URL {
            switch self {
            case .login: URL(string: "https://privacy-test-pages.site/autofill/autoprompt/1-standard-login-form.html")!
            case .signUp: URL(string: "https://privacy-test-pages.site/autofill/signup.html")!
            }
        }

        var title: String {
            switch self {
            case .login: "Autofill autoprompt for signin forms"
            case .signUp: "Password generation during signup"
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
        XCTAssertTrue(
            addressBar.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The address bar text field didn't become available in a reasonable timeframe."
        )
        addressBar.typeURL(page.url)
        XCTAssertTrue(
            windows.firstMatch.webViews[page.title].waitForExistence(timeout: UITests.Timeouts.navigation),
            "Visited site didn't load with the expected title in a reasonable timeframe."
        )
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

        // The dropdown is a child window with its own web view, so it can't be found inside the page's web view.
        let savedLogin = buttons.matching(NSPredicate(format: "label BEGINSWITH %@", email)).firstMatch
        XCTAssertTrue(
            savedLogin.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The autofill dropdown didn't offer the saved login for \(email)."
        )
        savedLogin.click()

        XCTAssertTrue(
            autofillEmailTextField.wait(for: \.value, equals: email, timeout: UITests.Timeouts.elementExistence),
            "Autofill didn't fill the email field."
        )
    }
}
