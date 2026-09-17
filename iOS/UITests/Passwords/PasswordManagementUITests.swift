//
//  PasswordManagementUITests.swift
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

final class PasswordManagementUITests: UITestCase {

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        try super.setUpWithError()
        app.resetPasswords()
    }

    func testPasswordCanBeCreatedViewedEditedSearchedAndDeleted() {
        XCTContext.runActivity(named: "Create and persist a password") { _ in
            app.openPasswordManager()
            app.addPassword(
                named: "Netflix",
                username: "test2@example.com",
                password: "secure!password",
                address: "netflix.com",
                notes: "A subscription based streaming site.")
            app.closePasswordManager()

            app.openPasswordManager()
            app.authenticateForPasswordAccess(using: springboard)

            assertPasswordItem(named: "Netflix", username: "test2@example.com")
        }

        XCTContext.runActivity(named: "View the saved password") { _ in
            app.passwordItem(named: "Netflix").tapWhenHittable()

            assertVisibleDetails(
                name: "Netflix",
                username: "test2@example.com",
                address: "netflix.com",
                notes: "A subscription based streaming site.")
            assertPasswordCanBeRevealed("secure!password")
        }

        XCTContext.runActivity(named: "Edit every password field") { _ in
            app.buttons["Autofill.Passwords.Details.Edit"].tapWhenHittable()
            let detailsList = app.descendants(matching: .any)["Autofill.Passwords.Details.List"]

            app.replaceText(
                in: app.descendants(matching: .any)["Field_PasswordName"],
                with: "Netflix Streaming")
            app.replaceText(
                in: app.descendants(matching: .any)["Field_Username"],
                with: "test3@example.com")
            app.replaceText(
                in: app.descendants(matching: .any)["Field_Password"],
                with: "secure?password")
            app.replaceText(
                in: app.descendants(matching: .any)["Field_Address"],
                with: "netflix.com/login")

            let notesField = app.descendants(matching: .any)["Field_Notes"]
            detailsList.swipeUpToReveal(notesField)
            app.replaceText(in: notesField, with: "A subscription site.")

            app.buttons["Autofill.Passwords.Editor.Save"].tapWhenHittable()
            XCTAssertTrue(
                app.buttons["Autofill.Passwords.Details.Edit"]
                    .waitForExistence(timeout: UITestTimeouts.navigation),
                "Edited password details did not reappear after saving.")
            app.navigationBars.buttons["BackButton"].firstMatch.tapWhenHittable()

            assertPasswordItem(named: "Netflix Streaming", username: "test3@example.com")
            XCTAssertFalse(
                app.passwordItem(named: "Netflix").exists,
                "The old password title remained after editing.")
        }

        XCTContext.runActivity(named: "Search for the edited password") { _ in
            let searchField = app.searchFields["Autofill.Passwords.Search"]
            searchField.tapWhenHittable()
            searchField.typeText("ZZZ")

            XCTAssertTrue(
                app.descendants(matching: .any)["Autofill.Passwords.Search.NoResults"]
                    .waitForExistence(timeout: UITestTimeouts.elementExistence),
                "No-results state did not appear for an unmatched password search.")
            XCTAssertFalse(
                app.passwordItem(named: "Netflix Streaming").exists,
                "Password remained visible for an unmatched search.")

            app.replaceText(in: searchField, with: "Net")
            assertPasswordItem(named: "Netflix Streaming", username: "test3@example.com")
            app.buttons["Cancel"].tapWhenHittable()
        }

        XCTContext.runActivity(named: "Verify edited details and delete the password") { _ in
            app.passwordItem(named: "Netflix Streaming").tapWhenHittable()

            assertVisibleDetails(
                name: "Netflix Streaming",
                username: "test3@example.com",
                address: "netflix.com",
                notes: "A subscription site.")
            assertPasswordCanBeRevealed("secure?password")

            let detailsList = app.descendants(matching: .any)["Autofill.Passwords.Details.List"]
            let deleteButton = app.buttons["Autofill.Passwords.Details.Delete"]
            detailsList.swipeUpToReveal(deleteButton)
            deleteButton.tapWhenHittable()

            let confirmationSheet = app.sheets.firstMatch
            XCTAssertTrue(
                confirmationSheet.staticTexts["Are you sure you want to delete this password?"]
                    .waitForExistence(timeout: UITestTimeouts.elementExistence),
                "Password deletion confirmation did not appear.")
            confirmationSheet.buttons["Delete Password"].tapWhenHittable()

            XCTAssertTrue(
                app.passwordItem(named: "Netflix Streaming").wait(
                    for: NSPredicate(format: "exists == false"),
                    timeout: UITestTimeouts.elementExistence),
                "Deleted password remained in the password list.")
        }
    }

    private func assertPasswordItem(named name: String, username: String) {
        let item = app.passwordItem(named: name)
        XCTAssertTrue(
            item.waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Password '\(name)' did not appear in the password list.")
        XCTAssertTrue(
            item.staticTexts[username].exists,
            "Password '\(name)' did not show username '\(username)'.")
    }

    private func assertVisibleDetails(name: String, username: String, address: String, notes: String) {
        for value in [name, username, address, notes] {
            XCTAssertTrue(
                app.staticTexts[value].waitForExistence(timeout: UITestTimeouts.elementExistence),
                "Password details did not show '\(value)'.")
        }
    }

    private func assertPasswordCanBeRevealed(_ password: String) {
        let hiddenPassword = "•••••••••••••••"
        XCTAssertTrue(
            app.staticTexts[hiddenPassword].waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Saved password was not masked.")

        let visibilityButton = app.buttons["Autofill.Passwords.Details.TogglePasswordVisibility"]
        visibilityButton.tapWhenHittable()
        XCTAssertTrue(
            app.staticTexts[password].waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Saved password was not revealed.")

        visibilityButton.tapWhenHittable()
        XCTAssertTrue(
            app.staticTexts[hiddenPassword].waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Saved password was not hidden again.")
    }
}
