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
            let authPromptOrAppStopped = NSPredicate { _, _ in
                authenticationReason.exists || self.app.state == .notRunning
            }
            let authenticationExpectation = XCTNSPredicateExpectation(predicate: authPromptOrAppStopped, object: springboard)
            let waitResult = XCTWaiter.wait(for: [authenticationExpectation], timeout: UITestTimeouts.navigation)
            XCTAssertTrue(
                authenticationReason.exists,
                waitResult == .completed
                    ? "Application Lock process stopped before the authentication prompt appeared."
                    : "Timed out waiting for the automatic Application Lock authentication prompt.")

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
}
