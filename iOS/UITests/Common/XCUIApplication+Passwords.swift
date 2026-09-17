//
//  XCUIApplication+Passwords.swift
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

    var passwordList: XCUIElement {
        tables["Autofill.Passwords.List"]
    }

    func resetPasswords(file: StaticString = #filePath, line: UInt = #line) {
        XCTContext.runActivity(named: "Reset saved passwords") { _ in
            let menuButton = buttons["Browser.Toolbar.Button.Menu"]
            XCTAssertTrue(
                menuButton.wait(
                    for: NSPredicate(format: "isHittable == true AND isEnabled == true"),
                    timeout: UITestTimeouts.elementExistence),
                "Toolbar menu button did not become available.", file: file, line: line)
            menuButton.press(forDuration: 1)

            let debugList = descendants(matching: .any)["Debug.List"]
            guard debugList.waitForExistence(timeout: UITestTimeouts.navigation) else {
                XCTFail(
                    "Debug screen did not appear. Password reset requires a Debug build or an internal-user build.",
                    file: file,
                    line: line)
                return
            }

            let filter = searchFields.matching(
                NSPredicate(format: "placeholderValue == %@", "Filter")
            ).firstMatch
            filter.tapWhenHittable(file: file, line: line)
            filter.typeText("Autofill")

            descendants(matching: .any)["Debug.Screen.Autofill"]
                .tapWhenHittable(file: file, line: line)
            descendants(matching: .any)["Debug.Autofill.DeleteAllCredentials"]
                .tapWhenHittable(file: file, line: line)
            assertActionMessage(contains: "All credentials deleted", file: file, line: line)

            let autofillNavigationBar = navigationBars["Autofill"]
            autofillNavigationBar.buttons["BackButton"].tapWhenHittable(file: file, line: line)
            XCTAssertTrue(
                debugList.waitForExistence(timeout: UITestTimeouts.elementExistence),
                "Debug screen did not reappear after resetting passwords.", file: file, line: line)

            let debugNavigationBar = navigationBars["Debug"]
            let dragStart = debugNavigationBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let dragEnd = windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
            dragStart.press(forDuration: 0.1, thenDragTo: dragEnd)

            XCTAssertTrue(
                debugList.wait(for: NSPredicate(format: "exists == false"), timeout: UITestTimeouts.elementExistence),
                "Debug screen did not close after resetting passwords.", file: file, line: line)
            XCTAssertTrue(
                searchEntry.wait(for: NSPredicate(format: "isHittable == true"), timeout: UITestTimeouts.elementExistence),
                "Browser did not become available after resetting passwords.", file: file, line: line)
        }
    }

    func openPasswordManager(file: StaticString = #filePath, line: UInt = #line) {
        openSettings(file: file, line: line)

        let settingsList = descendants(matching: .any)["Settings.List.Main"]
        let passwordsAndAutofill = descendants(matching: .any)["Settings.Main.Passwords"]
        settingsList.swipeUpToReveal(
            passwordsAndAutofill,
            timeout: UITestTimeouts.navigation,
            file: file,
            line: line)
        passwordsAndAutofill.tapWhenHittable(file: file, line: line)

        XCTAssertTrue(
            descendants(matching: .any)["Autofill.Settings.List"]
                .waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Passwords & Autofill settings did not appear.", file: file, line: line)
        descendants(matching: .any)["Autofill.Settings.Passwords"]
            .tapWhenHittable(file: file, line: line)

        XCTAssertTrue(
            passwordList.waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Password list did not appear.", file: file, line: line)
    }

    func closePasswordManager(file: StaticString = #filePath, line: UInt = #line) {
        navigationBars.buttons["BackButton"].firstMatch.tapWhenHittable(file: file, line: line)
        XCTAssertTrue(
            descendants(matching: .any)["Autofill.Settings.List"]
                .waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Passwords & Autofill settings did not reappear.", file: file, line: line)

        navigationBars.buttons["BackButton"].firstMatch.tapWhenHittable(file: file, line: line)
        XCTAssertTrue(
            descendants(matching: .any)["Settings.List.Main"]
                .waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Settings did not reappear after closing Passwords & Autofill.", file: file, line: line)
        dismissSettings(file: file, line: line)
    }

    func addPassword(
        named name: String,
        username: String = "",
        password: String = "",
        address: String = "",
        notes: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        buttons["Autofill.Passwords.Add"].tapWhenHittable(file: file, line: line)

        let detailsList = descendants(matching: .any)["Autofill.Passwords.Details.List"]
        XCTAssertTrue(
            detailsList.waitForExistence(timeout: UITestTimeouts.elementExistence),
            "New password editor did not appear.", file: file, line: line)

        enterText(name, in: descendants(matching: .any)["Field_PasswordName"], file: file, line: line)
        if !username.isEmpty {
            enterText(username, in: descendants(matching: .any)["Field_Username"], file: file, line: line)
        }
        if !password.isEmpty {
            enterText(password, in: descendants(matching: .any)["Field_Password"], file: file, line: line)
        }
        if !address.isEmpty {
            enterText(address, in: descendants(matching: .any)["Field_Address"], file: file, line: line)
        }
        if !notes.isEmpty {
            let notesField = descendants(matching: .any)["Field_Notes"]
            detailsList.swipeUpToReveal(notesField, file: file, line: line)
            enterText(notes, in: notesField, file: file, line: line)
        }

        buttons["Autofill.Passwords.Editor.Save"].tapWhenHittable(file: file, line: line)
        XCTAssertTrue(
            buttons["Autofill.Passwords.Details.Edit"].waitForExistence(timeout: UITestTimeouts.navigation),
            "Saved password details did not appear.", file: file, line: line)

        navigationBars.buttons["BackButton"].firstMatch.tapWhenHittable(file: file, line: line)
        XCTAssertTrue(
            passwordItem(named: name).waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Saved password '\(name)' did not appear in the password list.", file: file, line: line)
    }

    func authenticateForPasswordAccess(
        using springboard: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let authenticationReason = springboard.staticTexts["Unlock device to access passwords"]
        XCTAssertTrue(
            authenticationReason.waitForExistence(timeout: UITestTimeouts.navigation),
            "Password access did not request device authentication.", file: file, line: line)

        let passcodeField = springboard.secureTextFields.firstMatch
        XCTAssertTrue(
            passcodeField.waitForExistence(timeout: UITestTimeouts.elementExistence),
            "System passcode field did not appear.", file: file, line: line)
        passcodeField.typeText("password\n")

        XCTAssertTrue(
            passwordList.wait(
                for: NSPredicate(format: "exists == true AND isHittable == true"),
                timeout: UITestTimeouts.navigation),
            "Password list did not unlock after entering the device passcode.", file: file, line: line)
    }

    func passwordItem(named name: String) -> XCUIElement {
        passwordList.cells
            .matching(identifier: "Autofill.Passwords.Item")
            .containing(.staticText, identifier: name)
            .firstMatch
    }

    func enterText(
        _ text: String,
        in field: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        field.tapWhenHittable(file: file, line: line)
        field.typeText(text)
    }

    func replaceText(
        in field: XCUIElement,
        with text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        field.tapWhenHittable(file: file, line: line)
        let currentValue = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count))
        field.typeText(text)
    }
}
