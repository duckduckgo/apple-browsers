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

    override func tearDownWithError() throws {
        if (testRun?.totalFailureCount ?? 0) > 0 {
            XCTContext.runActivity(named: "Application Lock failure diagnostics") { activity in
                let appState = app.state
                let springboardState = springboard.state
                let stateAttachment = XCTAttachment(string: "App state: \(appState)\nSpringBoard state: \(springboardState)")
                stateAttachment.name = "Process states"
                activity.add(stateAttachment)

                let springboardHierarchy = XCTAttachment(string: springboard.debugDescription)
                springboardHierarchy.name = "SpringBoard hierarchy"
                activity.add(springboardHierarchy)
                activity.add(XCTAttachment(screenshot: springboard.screenshot()))

                if appState == .runningForeground {
                    let appWindow = app.windows.firstMatch
                    if appWindow.exists {
                        let windowFrame = appWindow.frame
                        if windowFrame.origin.x.isFinite, windowFrame.origin.y.isFinite,
                           windowFrame.width.isFinite, windowFrame.height.isFinite,
                           windowFrame.width > 0, windowFrame.height > 0 {
                            let appHierarchy = XCTAttachment(string: app.debugDescription)
                            appHierarchy.name = "App hierarchy"
                            activity.add(appHierarchy)
                        }
                    }
                }
            }
        }

        try super.tearDownWithError()
    }

    func testWhenApplicationLockIsEnabledThenRelaunchRequiresAuthenticationUntilLockIsDisabled() throws {
        enableApplicationLock()

        try XCTContext.runActivity(named: "Authenticate after relaunch") { _ in
            try relaunchAppPreservingState()

            let authenticationReason = springboard.staticTexts["Unlock DuckDuckGo."]
            if waitForAuthenticationPromptOrRecovery(authenticationReason) {
                requestAuthenticationFromRecoveryScreen()
                waitForAuthenticationPrompt(authenticationReason)
            }

            let passcodeField = springboard.secureTextFields.firstMatch
            XCTAssertTrue(
                passcodeField.waitForExistence(timeout: UITestTimeouts.elementExistence),
                "System passcode field did not appear.")
            passcodeField.typeText("password\n")

            XCTAssertTrue(
                app.searchEntry.waitForHittableInAppWindow(in: app, timeout: UITestTimeouts.navigation),
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

    func testWhenAuthenticationFailsThenUnlockInstructionsAllowRetry() throws {
        enableApplicationLock()

        try XCTContext.runActivity(named: "Wait for authentication or recovery screen") { _ in
            try relaunchAppPreservingState()

            let authenticationReason = springboard.staticTexts["Unlock DuckDuckGo."]
            if !waitForAuthenticationPromptOrRecovery(authenticationReason) {
                XCTContext.runActivity(named: "Cancel authentication prompt") { _ in
                    springboard.buttons["Cancel"].tapWhenHittable()
                }
                waitForRecoveryInstructions(authenticationReason)
            }
        }

        XCTContext.runActivity(named: "Retry authentication from the recovery screen") { _ in
            requestAuthenticationFromRecoveryScreen()
            let authenticationReason = springboard.staticTexts["Unlock DuckDuckGo."]
            waitForAuthenticationPrompt(authenticationReason)

            let passcodeField = springboard.secureTextFields.firstMatch
            XCTAssertTrue(passcodeField.waitForExistence(timeout: UITestTimeouts.elementExistence))
            passcodeField.typeText("password\n")
            XCTAssertTrue(
                app.searchEntry.waitForHittableInAppWindow(in: app, timeout: UITestTimeouts.navigation),
                "Browser did not unlock after retrying authentication.")
        }
    }

    private func enableApplicationLock() {
        XCTContext.runActivity(named: "Enable Application Lock") { _ in
            app.openSettings()
            app.openGeneralSettings()

            let applicationLock = app.settingsToggle(withIdentifier: "Settings.General.ApplicationLock")
            applicationLock.tapWhenHittable()
            XCTAssertTrue(
                applicationLock.wait(for: \XCUIElement.value, equals: "1", timeout: UITestTimeouts.elementExistence),
                "Application Lock did not become enabled.")
        }
    }

    private func waitForAuthenticationPromptOrRecovery(_ authenticationReason: XCUIElement,
                                                       file: StaticString = #filePath,
                                                       line: UInt = #line) -> Bool {
        let recoveryInstructions = app.staticTexts["Tap anywhere to unlock"]
        let authenticationStateReady = NSPredicate { _, _ in
            authenticationReason.exists
                || (self.app.state == .runningForeground && recoveryInstructions.exists)
                || self.app.state == .notRunning
        }
        let expectation = XCTNSPredicateExpectation(predicate: authenticationStateReady, object: springboard)
        _ = XCTWaiter.wait(for: [expectation], timeout: UITestTimeouts.navigation)

        let isRecoveryScreen = app.state == .runningForeground && recoveryInstructions.exists
        XCTAssertTrue(
            authenticationReason.exists || isRecoveryScreen,
            app.state == .notRunning
                ? "Application Lock process stopped before authentication completed."
                : "Timed out waiting for the authentication prompt or foreground recovery screen.",
            file: file,
            line: line)
        return isRecoveryScreen && !authenticationReason.exists
    }

    private func waitForRecoveryInstructions(_ authenticationReason: XCUIElement,
                                             file: StaticString = #filePath,
                                             line: UInt = #line) {
        let recoveryInstructions = app.staticTexts["Tap anywhere to unlock"]
        let recoveryOrAppStopped = NSPredicate { _, _ in
            (self.app.state == .runningForeground && recoveryInstructions.exists && !authenticationReason.exists)
                || self.app.state == .notRunning
        }
        let expectation = XCTNSPredicateExpectation(predicate: recoveryOrAppStopped, object: springboard)
        _ = XCTWaiter.wait(for: [expectation], timeout: UITestTimeouts.navigation)

        XCTAssertTrue(
            app.state == .runningForeground && recoveryInstructions.exists && !authenticationReason.exists,
            "Authentication failure did not leave the foreground recovery instructions visible.",
            file: file,
            line: line)
    }

    private func waitForAuthenticationPrompt(_ authenticationReason: XCUIElement,
                                             file: StaticString = #filePath,
                                             line: UInt = #line) {
        let promptOrAppStopped = NSPredicate { _, _ in
            authenticationReason.exists || self.app.state == .notRunning
        }
        let expectation = XCTNSPredicateExpectation(predicate: promptOrAppStopped, object: springboard)
        _ = XCTWaiter.wait(for: [expectation], timeout: UITestTimeouts.navigation)

        XCTAssertTrue(authenticationReason.exists, "Authentication prompt did not appear after retrying.", file: file, line: line)
    }

    private func requestAuthenticationFromRecoveryScreen(file: StaticString = #filePath, line: UInt = #line) {
        let recoveryInstructions = app.staticTexts["Tap anywhere to unlock"]
        XCTAssertEqual(app.state, .runningForeground, "Application Lock recovery screen was not foregrounded.", file: file, line: line)
        XCTAssertTrue(recoveryInstructions.exists, "Application Lock recovery instructions were not visible.", file: file, line: line)
        XCTAssertFalse(app.searchEntry.exists, "Browser controls remained accessible while Application Lock was active.", file: file, line: line)
        XCTAssertFalse(springboard.staticTexts["Unlock DuckDuckGo."].exists, "Authentication prompt is still visible.", file: file, line: line)

        XCTContext.runActivity(named: "Request authentication from recovery screen") { _ in
            app.images["AuthRequired"].tapWhenHittable(file: file, line: line)
        }
    }
}
