//
//  AutofillUITests.swift
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

class AutofillUITests: UITestCase {

    private var email: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        app = XCUIApplication.setUp()
        app.resetAutofillData()
        app.enforceSingleWindow()
        email = "\(UITests.randomPageTitle(length: 8).lowercased())@duck.com"
    }

    func testSignUpWithGeneratedPasswordSavesIt() {
        app.openAutofillTestPage(.signUp)
        app.windows.firstMatch.webViews.firstMatch.tap()
        app.autofillEmailTextField.click()
        app.autofillEmailTextField.typeText(email)

        app.autofillPasswordTextField.click()
        app.clickAutofillDropdownButton(titleBeginningWith: "Generated password")
        XCTAssertTrue(app.autofillPasswordTextField.wait(for: NSPredicate(format: "value != ''"), timeout: UITests.Timeouts.elementExistence),
                      "The generated password wasn't filled in.")

        app.submitSignUpForm()

        // A generated password is saved as soon as the form is submitted, so instead of asking, a message confirms the save
        let passwordSavedMessage = app.staticTexts.matching(NSPredicate { element, _ in
            ["label", "value"].contains { ((element as? NSObject)?.value(forKey: $0) as? String)?.hasPrefix("Password saved for") == true }
        }).firstMatch
        XCTAssertTrue(passwordSavedMessage.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "The \"Password saved\" message didn't appear after signing up.")
    }

    func testAutofillFillsLoginAndOffersPasswordUpdate() {
        app.openAutofillTestPage(.login)
        app.signIn(email: email, password: "pa$$word")
        app.saveCredentialsFromPopover()

        app.openAutofillTestPage(.login)
        app.fillLoginUsingAutofill(email: email)
        XCTAssertNotEqual(app.autofillPasswordTextField.value as? String ?? "", "", "Autofill didn't fill the password field.")

        app.autofillPasswordTextField.click()
        // Focusing the field reopens the autofill dropdown, which would take the typed password
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("a", modifierFlags: .command)
        app.typeText("new-pa$$word")
        app.submitLoginForm()

        XCTAssertTrue(app.updatePasswordPopoverTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "The Update password popover didn't appear after signing in with a changed password.")
    }
}
