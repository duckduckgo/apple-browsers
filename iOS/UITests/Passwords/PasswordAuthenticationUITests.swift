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
        app.dismissAddressBarEditing()
        app.resetPasswords()
    }

    override func tearDownWithError() throws {
        if (testRun?.totalFailureCount ?? 0) > 0 {
            let hierarchy = XCTAttachment(string: springboard.debugDescription)
            hierarchy.name = "Password authentication SpringBoard hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        try super.tearDownWithError()
    }

    func testWhenPasswordVaultIsReopenedThenDeviceAuthenticationIsRequired() {
        createPassword()
        app.closePasswordManager()

        app.openPasswordManager()
        let authenticationReason = springboard.staticTexts["Unlock device to access passwords"]
        let passcodeField = springboard.secureTextFields["Passcode field"]
        XCTAssertTrue(
            authenticationReason.waitForExistence(timeout: UITestTimeouts.navigation),
            "Password access did not request device authentication.")
        XCTAssertFalse(app.passwordList.exists, "Password list was accessible before authentication.")

        XCTAssertTrue(
            passcodeField.waitForExistence(timeout: UITestTimeouts.elementExistence),
            "System passcode field did not appear before empty submission.")
        XCTAssertEqual(passcodeField.placeholderValue, "Passcode", "System passcode placeholder changed.")
        // No passcode characters have been entered into this fresh prompt. Submit only Return;
        // SpringBoard's opaque accessibility value does not reliably report the empty contents.
        passcodeField.typeText("\n")
        XCTAssertTrue(passcodeField.exists, "System passcode field disappeared after empty submission.")
        XCTAssertEqual(passcodeField.placeholderValue, "Passcode", "System passcode placeholder changed after empty submission.")

        // Observe the simulator UI for a bounded interval; this is not a physical-device security claim.
        let unexpectedUnlock = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.passwordList.exists || !authenticationReason.exists
        }, object: app)
        unexpectedUnlock.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [unexpectedUnlock], timeout: 2), .completed,
                       "Empty passcode submission exposed the vault or dismissed authentication.")

        XCTAssertTrue(
            authenticationReason.waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Submitting an empty passcode dismissed password authentication.")
        XCTAssertFalse(app.passwordList.exists, "Password list became accessible after an empty passcode.")

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
