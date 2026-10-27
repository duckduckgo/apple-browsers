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

    private static let savePopoverTitles = ["New password saved", "Save password in DuckDuckGo?"]

    private var email: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        app = XCUIApplication.setUp()
        app.resetAutofillData()
        app.enforceSingleWindow()
        email = "\(UITests.randomPageTitle(length: 8).lowercased())@duck.com"
    }

    func testSignUpWithGeneratedPasswordShowsSavedPasswordPopover() {
        app.openAutofillTestPage(.signUp)
        app.windows.firstMatch.webViews.firstMatch.tap()
        app.autofillEmailTextField.click()
        app.autofillEmailTextField.typeText(email)

        app.autofillPasswordTextField.click()
        app.autofillDropdownButton(labelBeginningWith: "Generated password").click()
        XCTAssertTrue(app.autofillPasswordTextField.wait(for: NSPredicate(format: "value != ''"), timeout: UITests.Timeouts.elementExistence),
                      "The generated password wasn't filled in.")

        app.submitSignUpForm()

        // Depending on whether the generated password was already stored, the popover confirms the save or asks for it
        let savePopoverTitle = app.popovers.staticTexts
            .matching(NSPredicate(format: "label IN %@ OR value IN %@", Self.savePopoverTitles, Self.savePopoverTitles)).firstMatch
        XCTAssertTrue(savePopoverTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "The save password popover didn't appear after signing up.")
    }

    func testAutofillFillsLoginAndOffersPasswordUpdate() {
        app.openAutofillTestPage(.login)
        app.signIn(email: email, password: "pa$$word")
        app.saveCredentialsFromPopover()

        app.openAutofillTestPage(.login)
        app.fillLoginUsingAutofill(email: email)
        XCTAssertNotEqual(app.autofillPasswordTextField.value as? String ?? "", "", "Autofill didn't fill the password field.")

        app.autofillPasswordTextField.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("new-pa$$word")
        app.submitLoginForm()

        XCTAssertTrue(app.updatePasswordPopoverTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "The Update password popover didn't appear after signing in with a changed password.")
    }
}
