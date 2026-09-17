//
//  ApplicationLockUITests.swift
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

final class ApplicationLockUITests: UITestCase {

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    func testWhenApplicationLockIsEnabledThenRelaunchRequiresAuthenticationUntilLockIsDisabled() throws {
        XCTContext.runActivity(named: "Enable Application Lock") { _ in
            app.openSettings()
            app.openGeneralSettings()

            let applicationLock = app.settingsToggle(withIdentifier: "Settings.General.ApplicationLock")
            applicationLock.tapWhenHittable()
            XCTAssertTrue(
                applicationLock.wait(for: \XCUIElement.value, equals: "1", timeout: UITestTimeouts.elementExistence),
                "Application Lock did not become enabled.")
        }

        try XCTContext.runActivity(named: "Authenticate after relaunch") { _ in
            try relaunchAppPreservingState()

            let authenticationReason = springboard.staticTexts["Unlock DuckDuckGo."]
            XCTAssertTrue(
                authenticationReason.waitForExistence(timeout: UITestTimeouts.navigation),
                "Application Lock authentication did not appear after relaunch.")

            let passcodeField = springboard.secureTextFields.firstMatch
            XCTAssertTrue(
                passcodeField.waitForExistence(timeout: UITestTimeouts.elementExistence),
                "System passcode field did not appear.")
            passcodeField.typeText("password\n")

            XCTAssertTrue(
                app.searchEntry.wait(for: NSPredicate(format: "isHittable == true"), timeout: UITestTimeouts.navigation),
                "Browser did not unlock after entering the device passcode.")
        }

        XCTContext.runActivity(named: "Disable Application Lock") { _ in
            app.openURL("https://privacy-test-pages.site", expecting: "Privacy Test Pages")
            app.openSettings()
            app.openGeneralSettings()

            let applicationLock = app.settingsToggle(withIdentifier: "Settings.General.ApplicationLock")
            applicationLock.tapWhenHittable()
            XCTAssertTrue(
                applicationLock.wait(for: \XCUIElement.value, equals: "0", timeout: UITestTimeouts.elementExistence),
                "Application Lock did not become disabled.")
        }

        try XCTContext.runActivity(named: "Restore the page without authentication") { _ in
            try relaunchAppPreservingState()

            app.assertPageContains("Privacy Test Pages")
            XCTAssertFalse(
                springboard.staticTexts["Unlock DuckDuckGo."].exists,
                "Application Lock appeared after it was disabled.")
        }
    }
}
