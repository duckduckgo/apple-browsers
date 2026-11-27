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

final class KeyboardSettingsUITests: UITestCase {

    private let timeout = UITestTimeouts.navigation

    func testKeyboardPreferencesPersistAfterReopeningAndRelaunching() {
        openKeyboardSettings()
        assertSwitch("New Tab", isOn: true)
        assertSwitch("App Launch", isOn: false)
        attachScreenshot(named: "Keyboard defaults")

        tapSwitch("New Tab")
        assertSwitch("New Tab", isOn: false)
        assertSwitch("App Launch", isOn: false)
        tapSwitch("App Launch")
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

        tapSwitch("App Launch")
        assertSwitch("New Tab", isOn: false)
        assertSwitch("App Launch", isOn: false)
        tapSwitch("New Tab")
        assertSwitch("New Tab", isOn: true)
        assertSwitch("App Launch", isOn: false)
    }

    private func openKeyboardSettings() {
        let menu = app.descendants(matching: .any)["Browser.Toolbar.Button.Menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: timeout))
        // Launch lands on the New Tab page, which raises the keyboard over the toolbar.
        app.dismissLaunchKeyboard()
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

    /// SwiftUI exposes the whole row as the switch, so tap its trailing edge where the toggle is drawn.
    private func tapSwitch(_ label: String) {
        keyboardSwitch(label).coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    private func assertSwitch(_ label: String, isOn: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let toggle = keyboardSwitch(label)
        XCTAssertTrue(toggle.waitForExistence(timeout: timeout), file: file, line: line)
        // SwiftUI updates the switch's value asynchronously after a tap.
        let expected = isOn ? "1" : "0"
        XCTAssertTrue(toggle.wait(for: NSPredicate(format: "value == %@", expected), timeout: UITestTimeouts.elementExistence),
                      "\(label) switch value: \(String(describing: toggle.value)), expected \(expected)", file: file, line: line)
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
