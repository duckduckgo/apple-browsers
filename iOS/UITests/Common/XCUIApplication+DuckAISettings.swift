//
//  XCUIApplication+DuckAISettings.swift
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

    var aiFeaturesSettingsList: XCUIElement {
        descendants(matching: .any)["Settings.List.AIFeatures"]
    }

    func openAIFeaturesSettings(file: StaticString = #filePath, line: UInt = #line) {
        openSettings(file: file, line: line)

        let settingsList = descendants(matching: .any)["Settings.List.Main"]
        let aiFeatures = settingsList.buttons["Settings.Main.AIFeatures"]
        settingsList.swipeUpToReveal(
            aiFeatures,
            timeout: UITestTimeouts.navigation,
            file: file,
            line: line)
        aiFeatures.tapWhenHittable(file: file, line: line)

        XCTAssertTrue(
            aiFeaturesSettingsList.waitForExistence(timeout: UITestTimeouts.elementExistence),
            "AI Features settings did not appear.",
            file: file,
            line: line)
    }

    func setDuckAIEnabled(_ enabled: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let toggle = settingsToggle(withIdentifier: "Settings.AIFeatures.EnableToggle", file: file, line: line)
        let expectedValue = enabled ? "1" : "0"

        if toggle.value as? String != expectedValue {
            toggle.tapWhenHittable(file: file, line: line)
        }

        XCTAssertTrue(
            toggle.wait(for: \XCUIElement.value, equals: expectedValue, timeout: UITestTimeouts.elementExistence),
            "Duck.ai did not become \(enabled ? "enabled" : "disabled").",
            file: file,
            line: line)
    }

    func revealDuckAIEnableToggle(file: StaticString = #filePath, line: UInt = #line) {
        // SwiftUI removes off-screen rows from the hierarchy. Reveal the row before resolving its native switch.
        let toggle = switches.matching(identifier: "Settings.AIFeatures.EnableToggle").firstMatch
        let deadline = Date().addingTimeInterval(UITestTimeouts.navigation)

        while Date() < deadline {
            if toggle.exists && toggle.isHittable {
                return
            }
            aiFeaturesSettingsList.swipeDown()
            let remaining = deadline.timeIntervalSinceNow
            if remaining > 0,
               toggle.wait(for: NSPredicate(format: "isHittable == true"), timeout: min(1, remaining)) {
                return
            }
        }

        XCTFail("Duck.ai enable toggle did not become tappable.", file: file, line: line)
    }

    func selectDuckAISearchInput(_ enabled: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let identifier = enabled
            ? "Settings.AIFeatures.Picker.SearchAndDuckAI"
            : "Settings.AIFeatures.Picker.SearchOnly"
        let option = aiFeaturesSettingsList.descendants(matching: .any)[identifier]
        aiFeaturesSettingsList.swipeUpToReveal(
            option,
            timeout: UITestTimeouts.navigation,
            file: file,
            line: line)
        option.tapWhenHittable(file: file, line: line)
    }

    func openDuckAIShortcutsSettings(file: StaticString = #filePath, line: UInt = #line) {
        let manageShortcuts = aiFeaturesSettingsList.buttons["Settings.AIFeatures.ManageShortcuts"]
        aiFeaturesSettingsList.swipeUpToReveal(
            manageShortcuts,
            timeout: UITestTimeouts.navigation,
            file: file,
            line: line)
        manageShortcuts.tapWhenHittable(file: file, line: line)

        XCTAssertTrue(
            descendants(matching: .any)["Settings.List.AIChatShortcuts"]
                .waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Manage Duck.ai Shortcuts settings did not appear.",
            file: file,
            line: line)
    }
}
