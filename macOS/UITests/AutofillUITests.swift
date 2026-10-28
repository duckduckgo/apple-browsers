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

        let filledPassword = app.autofillPasswordTextField.value as? String ?? ""
        app.autofillPasswordTextField.click()
        // Focusing the field reopens the autofill dropdown, which would take the typed password; closing it with Escape
        // can also take the focus off the field on some macOS versions, so focus it again
        app.typeKey(.escape, modifierFlags: [])
        app.autofillPasswordTextField.click()
        // Select All doesn't reach a secure web field on every macOS version, so delete the filled password key by key
        app.typeKey(.rightArrow, modifierFlags: .command)
        for _ in 0..<(filledPassword.count + 4) {
            app.typeKey(.delete, modifierFlags: [])
        }
        app.typeText("new-pa$$word")
        let changedPassword = app.autofillPasswordTextField.value as? String ?? ""
        app.submitLoginForm()

        if !app.updatePasswordPopoverTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence) {
            XCTFail("The Update password popover didn't appear after signing in with a changed password. " +
                    "Password field before: \(filledPassword.count) characters, after: \(changedPassword.count). Popover texts: \(popoverTextsInOneSnapshot())")
        }
    }

    // MARK: - Utilities

    /// Reading elements one by one fails when the UI changes in between, so take the texts from one snapshot.
    private func popoverTextsInOneSnapshot() -> [String] {
        guard let snapshot = try? app.snapshot() else { return [] }
        var texts: [String] = []
        var pending = [(element: snapshot, isInPopover: false)]
        while let (element, isInPopover) = pending.popLast() {
            let isPopoverContent = isInPopover || element.elementType == .popover
            if isPopoverContent {
                texts += [element.label, element.title, element.value as? String ?? ""].filter { !$0.isEmpty }
            }
            pending.append(contentsOf: element.children.map { ($0, isPopoverContent) })
        }
        return texts
    }
}
