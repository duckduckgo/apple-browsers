//
//  ApplicationShortcutItemsUITests.swift
//  AtbUITests
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

final class ApplicationShortcutItemsUITests: XCTestCase {

    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let timeout: TimeInterval = 20
    private let quickActionsMenuTimeout: TimeInterval = 5
    private let transitionCount = 5
    private let quickActionsMenuAttemptCount = 3

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        app.launchArguments = [
            "-clearAllDefaults",
            "isRunningUITests",
            "-isOnboardingCompleted", "true",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_GB",
        ]
        if ProcessInfo.processInfo.environment["INTERNAL_USER_MODE"] == "true" {
            app.launchArguments += ["-isInternalUser", "true"]
        }
        app.launchEnvironment = ["UITEST_MODE": "1"]
        app.launch()

        XCTAssertTrue(searchEntry.waitForExistence(timeout: timeout), "Browser UI did not appear after launch.")
    }

    override func tearDownWithError() throws {
        app.terminate()
        try super.tearDownWithError()
    }

    func testQuickActionsSurviveRepeatedBackgroundTransitions() {
        for iteration in 1...transitionCount {
            XCUIDevice.shared.press(.home)

            XCTAssertTrue(waitForAppToLeaveForeground(), "App did not enter the background on iteration \(iteration).")
            XCTAssertNotEqual(app.state, .notRunning, "App terminated while entering the background on iteration \(iteration).")

            app.activate()

            XCTAssertTrue(app.wait(for: .runningForeground, timeout: timeout), "App did not return on iteration \(iteration).")
            XCTAssertTrue(searchEntry.waitForExistence(timeout: timeout), "Browser UI did not return on iteration \(iteration).")
        }

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(waitForAppToLeaveForeground(), "App did not enter the background before inspecting Quick Actions.")
        XCTAssertNotEqual(app.state, .notRunning, "App terminated before inspecting Quick Actions.")
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: timeout), "SpringBoard did not enter the foreground.")

        guard openQuickActionsMenu() else { return }

        XCTAssertTrue(springboard.buttons["Paste from Clipboard"].waitForExistence(timeout: quickActionsMenuTimeout),
                      "Paste from Clipboard Quick Action did not appear.")
        XCTAssertFalse(springboard.buttons["Open VPN"].exists, "Open VPN Quick Action appeared without a subscription.")
        XCTAssertNotEqual(app.state, .notRunning, "App terminated while displaying Quick Actions.")
    }

    private var searchEntry: XCUIElement {
        app.descendants(matching: .any)["searchEntry"]
    }

    private func openQuickActionsMenu(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let appIcon = springboard.icons["DuckDuckGo"]
        let iconIsHittable = NSPredicate(format: "exists == true AND isHittable == true")

        for attempt in 1...quickActionsMenuAttemptCount {
            let iconExpectation = XCTNSPredicateExpectation(predicate: iconIsHittable, object: appIcon)
            guard XCTWaiter.wait(for: [iconExpectation], timeout: timeout) == .completed else {
                recordSpringboardDiagnostics()
                XCTFail("DuckDuckGo app icon did not become hittable.", file: file, line: line)
                return false
            }

            appIcon.press(forDuration: 1.2)

            if springboard.buttons["Duck.ai"].waitForExistence(timeout: quickActionsMenuTimeout) {
                return true
            }

            guard attempt < quickActionsMenuAttemptCount else { break }

            XCUIDevice.shared.press(.home)
            guard springboard.wait(for: .runningForeground, timeout: timeout) else {
                recordSpringboardDiagnostics()
                XCTFail("SpringBoard did not return to the foreground after Quick Actions attempt \(attempt).", file: file, line: line)
                return false
            }
        }

        recordSpringboardDiagnostics()
        XCTFail("Duck.ai Quick Action did not appear after \(quickActionsMenuAttemptCount) attempts.", file: file, line: line)
        return false
    }

    private func recordSpringboardDiagnostics() {
        let screenshot = XCTAttachment(screenshot: springboard.screenshot())
        screenshot.name = "SpringBoard Screenshot"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let hierarchy = XCTAttachment(string: springboard.debugDescription)
        hierarchy.name = "SpringBoard Accessibility Hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    private func waitForAppToLeaveForeground() -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch app.state {
            case .runningBackground, .runningBackgroundSuspended, .notRunning:
                return true
            default:
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
        }
        return false
    }
}
