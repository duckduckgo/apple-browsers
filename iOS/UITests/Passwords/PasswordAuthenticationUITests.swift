//
//  PasswordAuthenticationUITests.swift
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

final class PasswordAuthenticationUITests: UITestCase {

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let passwordName = "Example"

    override func setUpWithError() throws {
        try super.setUpWithError()
        app.resetPasswords()
    }

    func testWhenPasswordVaultIsReopenedThenDeviceAuthenticationIsRequired() {
        createPassword()
        app.closePasswordManager()

        app.openPasswordManager()
        app.authenticateForPasswordAccess(using: springboard)

        XCTAssertTrue(
            app.passwordItem(named: passwordName).waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Saved password did not appear after authentication.")
    }

    func testWhenAppReturnsFromBackgroundBeforeOpeningPasswordVaultThenAuthenticationIsRequired() {
        createPassword()
        app.closePasswordManager()
        app.backgroundAndActivate()

        app.openPasswordManager()
        app.authenticateForPasswordAccess(using: springboard)

        XCTAssertTrue(
            app.passwordItem(named: passwordName).waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Saved password did not appear after backgrounding and authentication.")
    }

    func testWhenPasswordVaultReturnsFromBackgroundThenDeviceAuthenticationIsRequired() {
        createPassword()
        app.backgroundAndActivate()

        app.authenticateForPasswordAccess(using: springboard)

        XCTAssertTrue(
            app.passwordItem(named: passwordName).waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Saved password did not reappear after the vault was unlocked.")
    }

    private func createPassword() {
        XCTContext.runActivity(named: "Create a password") { _ in
            app.openPasswordManager()
            app.addPassword(named: passwordName)
        }
    }
}
