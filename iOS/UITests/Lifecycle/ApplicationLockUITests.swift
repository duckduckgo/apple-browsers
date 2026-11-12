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

    private var relaunchGap: TimeInterval = 0

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override var additionalLaunchEnvironment: [String: String] {
        var environment = super.additionalLaunchEnvironment
        environment["UITEST_APP_LOCK_DIAGNOSTICS"] = "1"
        if ProcessInfo.processInfo.environment["APP_LOCK_DISABLE_ANIMATIONS"] == "true" {
            environment["UITEST_DISABLE_ANIMATIONS"] = "1"
        }
        return environment
    }

    override func setUpWithError() throws {
        let environment = ProcessInfo.processInfo.environment
        let gap = environment["APP_LOCK_RELAUNCH_GAP"] ?? "0"
        let animations = environment["APP_LOCK_DISABLE_ANIMATIONS"] ?? "false"
        guard ["0", "1", "2", "5"].contains(gap), ["true", "false"].contains(animations) else {
            throw NSError(domain: "ApplicationLockUITests.Configuration", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid Application Lock experiment options."])
        }
        relaunchGap = TimeInterval(gap) ?? 0
        recordPhase("Configuration: relaunchGap=\(gap), disableUIKitAnimations=\(animations), "
                    + "executionMode=\(environment["UI_TEST_EXECUTION_MODE"] ?? "local"), iterations=\(environment["UI_TEST_ITERATIONS"] ?? "local")")
        try super.setUpWithError()
    }

    private func recordPhase(_ phase: String) {
        let attachment = XCTAttachment(string: "\(Date().ISO8601Format()) uptime=\(ProcessInfo.processInfo.systemUptime) \(phase)")
        attachment.name = "Application Lock phase: \(phase)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

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
        recordPhase("Enable Application Lock started")
        enableApplicationLock()
        recordPhase("Enable Application Lock completed")

        try XCTContext.runActivity(named: "Authenticate after relaunch") { _ in
            recordPhase("Relaunch started")
            try relaunchAppPreservingState(delayAfterTermination: relaunchGap)
            recordPhase("Relaunch completed")

            let authenticationReason = springboard.staticTexts["Unlock DuckDuckGo."]
            let needsRecovery = waitForAuthenticationPromptOrRecovery(authenticationReason)
            let route = needsRecovery ? "Authentication route: foreground recovery" : "Authentication route: automatic system prompt"
            XCTContext.runActivity(named: route) { _ in
                if needsRecovery {
                    requestAuthenticationFromRecoveryScreen()
                    waitForAuthenticationPrompt(authenticationReason)
                }
            }

            recordPhase("Authentication prompt ready")
            let passcodeField = springboard.secureTextFields.firstMatch
            XCTAssertTrue(
                passcodeField.waitForExistence(timeout: UITestTimeouts.elementExistence),
                "System passcode field did not appear.")
            passcodeField.typeText("password\n")

            XCTAssertTrue(
                app.searchEntry.waitForHittableInAppWindow(in: app, timeout: UITestTimeouts.navigation),
                "Browser did not unlock after entering the device passcode.")
            recordPhase("Authentication completed; browser interactive")
        }

        XCTContext.runActivity(named: "Disable Application Lock") { _ in
            recordPhase("Disable Application Lock: open fixture started")
            app.openURL("https://privacy-test-pages.site", expecting: "Privacy Test Pages")
            recordPhase("Disable Application Lock: open Settings started")
            app.openSettings()
            recordPhase("Disable Application Lock: open General started")
            app.openGeneralSettings()
            recordPhase("Disable Application Lock: General ready")

            let applicationLock = app.settingsToggle(withIdentifier: "Settings.General.ApplicationLock")
            applicationLock.tapWhenHittable(in: app)
            XCTAssertTrue(
                applicationLock.wait(for: \XCUIElement.value, equals: "0", timeout: UITestTimeouts.elementExistence),
                "Application Lock did not become disabled.")
            recordPhase("Disable Application Lock completed")
        }

        try XCTContext.runActivity(named: "Restore the page without authentication") { _ in
            recordPhase("Relaunch started")
            try relaunchAppPreservingState(delayAfterTermination: relaunchGap)
            recordPhase("Relaunch completed")

            XCTAssertTrue(
                app.searchEntry.waitForHittableInAppWindow(in: app, timeout: UITestTimeouts.navigation),
                "Browser did not become interactive after disabling Application Lock and relaunching.")
            app.assertPageContains("Privacy Test Pages")
            XCTAssertFalse(
                springboard.staticTexts["Unlock DuckDuckGo."].exists,
                "Application Lock appeared after it was disabled.")
            recordPhase("Entire Application Lock flow completed")
        }
    }

    private func enableApplicationLock() {
        XCTContext.runActivity(named: "Enable Application Lock") { _ in
            app.dismissAddressBarEditing()
            app.openSettings()
            app.openGeneralSettings()

            let applicationLock = app.settingsToggle(withIdentifier: "Settings.General.ApplicationLock")
            applicationLock.tapWhenHittable(in: app)
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
        XCTAssertFalse(app.descendants(matching: .any)["searchEntry"].exists, "Browser controls remained accessible while Application Lock was active.", file: file, line: line)
        XCTAssertFalse(springboard.staticTexts["Unlock DuckDuckGo."].exists, "Authentication prompt is still visible.", file: file, line: line)

        XCTContext.runActivity(named: "Request authentication from recovery screen") { _ in
            app.images["AuthRequired"].tapWhenHittable(in: app, file: file, line: line)
        }
    }
}
