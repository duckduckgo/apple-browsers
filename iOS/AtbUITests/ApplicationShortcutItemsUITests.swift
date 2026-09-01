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
        app.launchEnvironment = ["UITEST_MODE": "1"]
        app.launch()

        XCTAssertTrue(searchEntry.waitForExistence(timeout: timeout))
    }

    override func tearDownWithError() throws {
        app.terminate()
        try super.tearDownWithError()
    }

    func testQuickActionsSurviveRepeatedBackgroundTransitions() {
        for iteration in 1...20 {
            XCUIDevice.shared.press(.home)

            XCTAssertTrue(waitForAppToLeaveForeground(), "App did not enter the background on iteration \(iteration).")
            XCTAssertNotEqual(app.state, .notRunning, "App terminated while entering the background on iteration \(iteration).")

            app.activate()

            XCTAssertTrue(app.wait(for: .runningForeground, timeout: timeout), "App did not return on iteration \(iteration).")
            XCTAssertTrue(searchEntry.waitForExistence(timeout: timeout), "Browser UI did not return on iteration \(iteration).")
        }

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(waitForAppToLeaveForeground())
        XCTAssertNotEqual(app.state, .notRunning)

        let appIcon = springboard.icons["DuckDuckGo"]
        XCTAssertTrue(appIcon.waitForExistence(timeout: timeout))
        appIcon.press(forDuration: 1.2)

        XCTAssertTrue(springboard.buttons["Duck.ai"].waitForExistence(timeout: timeout))
        XCTAssertTrue(springboard.buttons["Paste from Clipboard"].exists)
        XCTAssertFalse(springboard.buttons["Open VPN"].exists)
        XCTAssertNotEqual(app.state, .notRunning)
    }

    private var searchEntry: XCUIElement {
        app.descendants(matching: .any)["searchEntry"]
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
