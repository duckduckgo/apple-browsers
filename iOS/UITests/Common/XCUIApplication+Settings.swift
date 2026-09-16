//
//  XCUIApplication+Settings.swift
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

extension XCUIApplication {

    func openSettings(file: StaticString = #filePath, line: UInt = #line) {
        openBrowsingMenuItem("Browser.Menu.Settings", file: file, line: line)
        XCTAssertTrue(
            descendants(matching: .any)["Settings.List.Main"].waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Settings did not appear.",
            file: file,
            line: line)
    }

    func openGeneralSettings(file: StaticString = #filePath, line: UInt = #line) {
        let settingsList = descendants(matching: .any)["Settings.List.Main"]
        let general = settingsList.buttons["Settings.Main.General"]
        settingsList.swipeUpToReveal(
            general,
            timeout: UITestTimeouts.navigation,
            file: file,
            line: line)
        general.tapWhenHittable(file: file, line: line)
        XCTAssertTrue(
            descendants(matching: .any)["Settings.List.General"].waitForExistence(timeout: UITestTimeouts.elementExistence),
            "General settings did not appear.",
            file: file,
            line: line)
    }

    func openDataClearingSettings(file: StaticString = #filePath, line: UInt = #line) {
        let settingsList = descendants(matching: .any)["Settings.List.Main"]
        let dataClearing = settingsList.buttons["Settings.Main.DataClearing"]
        settingsList.swipeUpToReveal(
            dataClearing,
            timeout: UITestTimeouts.navigation,
            file: file,
            line: line)
        dataClearing.tapWhenHittable(file: file, line: line)
        XCTAssertTrue(
            descendants(matching: .any)["Settings.List.DataClearing"].waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Data Clearing settings did not appear.",
            file: file,
            line: line)
    }

    func dismissSettings(file: StaticString = #filePath, line: UInt = #line) {
        buttons["Settings.Button.Done"].tapWhenHittable(file: file, line: line)
        XCTAssertTrue(
            searchEntry.wait(for: NSPredicate(format: "isHittable == true"), timeout: UITestTimeouts.elementExistence),
            "Browser did not reappear after dismissing Settings.",
            file: file,
            line: line)
    }

    func settingsToggle(withIdentifier identifier: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let toggle = switches.matching(identifier: identifier).firstMatch
        XCTAssertTrue(
            toggle.waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Settings toggle did not appear: \(identifier).", file: file, line: line)
        // SwiftUI may repeat the identifier on wrappers whose value does not track the native switch.
        // Scope to this setting's single native switch for both interaction and state assertions.
        let nativeSwitch = toggle.switches.matching(NSPredicate(format: "identifier == %@", "")).element
        return nativeSwitch.exists ? nativeSwitch : toggle
    }

    func navigateBackInSettings(from currentListIdentifier: String,
                                to destinationListIdentifier: String,
                                file: StaticString = #filePath,
                                line: UInt = #line) {
        let currentList = descendants(matching: .any)[currentListIdentifier]
        XCTAssertTrue(
            currentList.waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Expected Settings screen before navigating back: \(currentListIdentifier).", file: file, line: line)
        let backButton = navigationBars.element.buttons["BackButton"]
        backButton.tapWhenHittable(file: file, line: line)
        XCTAssertTrue(
            descendants(matching: .any)[destinationListIdentifier].waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Expected Settings screen after navigating back: \(destinationListIdentifier).", file: file, line: line)
    }

}
