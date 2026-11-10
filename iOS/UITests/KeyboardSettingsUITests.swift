//
//  KeyboardSettingsUITests.swift
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

final class KeyboardSettingsUITests: XCTestCase {

    private let app = XCUIApplication()
    private let timeout = UITestTimeouts.navigation

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app.launchArguments = [
            "-clearAllDefaults",
            "isRunningUITests",
            "-isOnboardingCompleted", "true",
            "-ff.alwaysShowKeyboardOnNewTabPage", "false",
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

    func testKeyboardPreferencesPersistAfterReopeningAndRelaunching() {
        openKeyboardSettings()
        assertSwitch("New Tab", isOn: true)
        assertSwitch("App Launch", isOn: false)
        attachScreenshot(named: "Keyboard defaults")

        keyboardSwitch("New Tab").tap()
        assertSwitch("New Tab", isOn: false)
        assertSwitch("App Launch", isOn: false)
        keyboardSwitch("App Launch").tap()
        assertSwitch("New Tab", isOn: false)
        assertSwitch("App Launch", isOn: true)
        attachScreenshot(named: "Keyboard preferences changed")

        app.navigationBars["Keyboard"].buttons.firstMatch.tap()
        openKeyboardFromGeneral()
        assertSwitch("New Tab", isOn: false)
        assertSwitch("App Launch", isOn: true)

        app.terminate()
        app.launchArguments.removeAll { $0 == "-clearAllDefaults" }
        app.launch()
        openKeyboardSettings()
        assertSwitch("New Tab", isOn: false)
        assertSwitch("App Launch", isOn: true)
        attachScreenshot(named: "Keyboard preferences after relaunch")

        keyboardSwitch("App Launch").tap()
        assertSwitch("New Tab", isOn: false)
        assertSwitch("App Launch", isOn: false)
        keyboardSwitch("New Tab").tap()
        assertSwitch("New Tab", isOn: true)
        assertSwitch("App Launch", isOn: false)
    }

    func testKeyboardPreferencesSurviveFeatureFlagChange() throws {
        openKeyboardSettings()
        keyboardSwitch("New Tab").tap()
        keyboardSwitch("App Launch").tap()
        app.terminate()
        app.launchArguments.removeAll { $0 == "-clearAllDefaults" }
        let flagIndex = try XCTUnwrap(app.launchArguments.firstIndex(of: "-ff.alwaysShowKeyboardOnNewTabPage"))
        app.launchArguments[flagIndex + 1] = "true"
        app.launch()

        openKeyboardSettings()
        assertSwitch("New Tab", isOn: false)
        assertSwitch("App Launch", isOn: true)
    }

    private func openKeyboardSettings() {
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
        let general = app.staticTexts["General"]
        for _ in 0..<5 where !general.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(general.waitForExistence(timeout: timeout))
        general.tap()
        openKeyboardFromGeneral()
    }

    private func openKeyboardFromGeneral() {
        let keyboard = app.staticTexts["Keyboard"]
        for _ in 0..<5 where !keyboard.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(keyboard.waitForExistence(timeout: timeout))
        keyboard.tap()
        XCTAssertTrue(app.navigationBars["Keyboard"].waitForExistence(timeout: timeout))
    }

    private func keyboardSwitch(_ label: String) -> XCUIElement {
        app.cells.containing(.staticText, identifier: label).switches.firstMatch
    }

    private func assertSwitch(_ label: String, isOn: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let toggle = keyboardSwitch(label)
        XCTAssertTrue(toggle.waitForExistence(timeout: timeout), file: file, line: line)
        XCTAssertEqual(toggle.value as? String, isOn ? "1" : "0", file: file, line: line)
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
