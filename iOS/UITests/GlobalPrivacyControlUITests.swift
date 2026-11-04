//
//  GlobalPrivacyControlUITests.swift
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

final class GlobalPrivacyControlUITests: XCTestCase {

    private let app = XCUIApplication()
    private let timeout = UITestTimeouts.navigation
    private let gpcLabel = "Global Privacy Control (GPC)"

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app.launchArguments = [
            "-clearAllDefaults",
            "isRunningUITests",
            "-isOnboardingCompleted", "true",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launchEnvironment = ["UITEST_MODE": "1"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        try super.tearDownWithError()
    }

    func testGPCPreferencePersistsAfterReopeningAndRelaunching() {
        openWebTrackingProtection()
        assertGPC(isOn: true)
        gpcToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        assertGPC(isOn: false)

        app.navigationBars["Web Tracking Protection"].buttons.firstMatch.tap()
        openWebTrackingProtectionFromSettings()
        assertGPC(isOn: false)

        app.terminate()
        app.launchArguments.removeAll { $0 == "-clearAllDefaults" }
        app.launch()
        openWebTrackingProtection()
        assertGPC(isOn: false)
        gpcToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        assertGPC(isOn: true)

        app.terminate()
        app.launch()
        openWebTrackingProtection()
        assertGPC(isOn: true)
    }

    private var gpcToggle: XCUIElement {
        app.cells.containing(.staticText, identifier: gpcLabel).switches.firstMatch
    }

    private func assertGPC(isOn: Bool, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(gpcToggle.waitForExistence(timeout: timeout), file: file, line: line)
        XCTAssertEqual(gpcToggle.value as? String, isOn ? "1" : "0", file: file, line: line)
    }

    private func openWebTrackingProtection() {
        let menu = app.descendants(matching: .any)["Browser.Toolbar.Button.Menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: timeout))
        for identifier in ["UnifiedToggleInput.Button.Dismiss", "Browser.OmniBar.Button.Dismiss"] {
            let dismiss = app.buttons[identifier]
            if dismiss.isHittable {
                dismiss.tap()
            }
        }
        menu.tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: timeout))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: timeout))
        openWebTrackingProtectionFromSettings()
    }

    private func openWebTrackingProtectionFromSettings() {
        let protection = app.staticTexts["Web Tracking Protection"]
        for _ in 0..<5 where !protection.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(protection.waitForExistence(timeout: timeout))
        protection.tap()
        XCTAssertTrue(app.navigationBars["Web Tracking Protection"].waitForExistence(timeout: timeout))
    }
}
