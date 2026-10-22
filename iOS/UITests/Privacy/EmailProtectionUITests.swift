//
//  EmailProtectionUITests.swift
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

final class EmailProtectionUITests: UITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()

        app.dismissAddressBarEditing()
        let menuButton = app.buttons["Browser.Toolbar.Button.Menu"]
        XCTAssertTrue(
            menuButton.wait(for: NSPredicate(format: "isHittable == true AND isEnabled == true"), timeout: UITestTimeouts.navigation),
            "Toolbar menu button did not become available.")
        menuButton.press(forDuration: 1)

        let debugList = app.descendants(matching: .any)["Debug.List"]
        XCTAssertTrue(debugList.waitForExistence(timeout: UITestTimeouts.navigation), "Debug screen did not appear.")
        let filter = app.searchFields.matching(NSPredicate(format: "placeholderValue == %@", "Filter")).firstMatch
        filter.tapWhenHittable()
        filter.typeText("Autofill")
        app.descendants(matching: .any)["Debug.Screen.Autofill"].tapWhenHittable()

        let clearSignInState = app.cells["Debug.Autofill.ClearEmailProtectionSignInState"]
        app.tables.firstMatch.swipeUpToReveal(clearSignInState, timeout: UITestTimeouts.navigation)
        clearSignInState.tapWhenHittable()
        app.assertActionMessage(contains: "Email Protection sign-in state cleared")

        app.navigationBars["Autofill"].buttons["BackButton"].tapWhenHittable()
        XCTAssertTrue(debugList.waitForExistence(timeout: UITestTimeouts.elementExistence), "Debug screen did not reappear.")
        if app.keyboards.firstMatch.exists {
            app.buttons.matching(NSPredicate(format: "label == %@", "close")).firstMatch.tapWhenHittable()
            XCTAssertTrue(
                app.keyboards.firstMatch.waitForNonExistence(timeout: UITestTimeouts.elementExistence),
                "Keyboard did not dismiss after clearing Email Protection sign-in state.")
        }
        app.buttons["Debug.Close"].tapWhenHittable()
        XCTAssertTrue(debugList.waitForNonExistence(timeout: UITestTimeouts.elementExistence), "Debug screen did not close.")

        app.openSettings()

        let settingsList = app.descendants(matching: .any)["Settings.List.Main"]
        let emailProtection = settingsList.buttons["Settings.Privacy.EmailProtection"]
        settingsList.swipeUpToReveal(emailProtection, timeout: UITestTimeouts.navigation)
        emailProtection.tapWhenHittable()

        XCTAssertTrue(
            app.descendants(matching: .any)["Settings.List.EmailProtection"]
                .waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Email Protection settings did not appear.")

        XCTAssertTrue(
            app.buttons["Settings.EmailProtection.Enable"].waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Email Protection did not reach the signed-out state after clearing sign-in state.")
    }

    func testEnablingEmailProtectionFromSettingsOpensSignupPage() {
        let enableEmailProtection = app.buttons["Settings.EmailProtection.Enable"]
        enableEmailProtection.tapWhenHittable()
        app.assertPageContains("Email protection, simplified.")

        XCTAssertTrue(
            app.searchEntry.wait(for: NSPredicate(format: "isHittable == true"), timeout: UITestTimeouts.navigation),
            "Browser address bar did not appear after opening Email Protection signup.")
        app.searchEntry.tap()
        XCTAssertTrue(
            app.searchEntry.wait(for: \.value, contains: "duckduckgo.com/email/", timeout: UITestTimeouts.elementExistence),
            "Email Protection signup URL did not appear in the address bar.")
    }
}
