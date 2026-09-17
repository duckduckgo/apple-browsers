//
//  XCUIApplication+PasswordAutofill.swift
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

extension XCUIApplication {

    func enterWebFormText(
        _ text: String,
        inFieldNamed fieldName: String,
        secure: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let field = secure ? webViews.secureTextFields[fieldName] : webViews.textFields[fieldName]
        field.tapWhenHittable(file: file, line: line)
        field.typeText(text)
    }

    func focusSecureWebFormField(
        named fieldName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        webViews.secureTextFields[fieldName].tapWhenHittable(file: file, line: line)
    }

    func submitWebForm(
        buttonNamed buttonName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        webViews.buttons[buttonName].tapWhenHittable(file: file, line: line)
    }

    func selectSavedPassword(
        username: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let prompt = descendants(matching: .any)["Autofill.LoginPrompt"]
        XCTAssertTrue(
            prompt.waitForExistence(timeout: UITestTimeouts.navigation),
            "Saved-password prompt did not appear.", file: file, line: line)

        let account = buttons
            .matching(identifier: "Autofill.LoginPrompt.Account")
            .matching(NSPredicate(format: "label == %@", username))
            .firstMatch
        account.tapWhenHittable(file: file, line: line)
    }
}
