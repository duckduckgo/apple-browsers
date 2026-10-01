//
//  DuckAIIPadUITests.swift
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

final class DuckAIIPadUITests: DuckAIUITestCase {

    override var duckAIFeatureFlagLaunchArguments: [String] {
        [
            "-ff.aiChatChromeShortcutIPad", "true",
            "-ff.iPadDuckAIBarControls", "true",
        ]
    }

    func testWhenChangingDuckAISearchInputThenIPadModeControlsFollowTheSetting() {
        XCTContext.runActivity(named: "Verify iPad AI settings and enable Search & Duck.ai") { _ in
            app.openAIFeaturesSettings()
            app.revealDuckAIEnableToggle()
            let duckAIEnabled = app.settingsToggle(withIdentifier: "Settings.AIFeatures.EnableToggle")
            XCTAssertEqual(duckAIEnabled.value as? String, "1", "Duck.ai should be enabled after resetting settings.")

            for identifier in ["Settings.AIFeatures.Picker.SearchOnly", "Settings.AIFeatures.Picker.SearchAndDuckAI"] {
                let option = app.aiFeaturesSettingsList.descendants(matching: .any)[identifier]
                app.aiFeaturesSettingsList.swipeUpToReveal(option, timeout: UITestTimeouts.navigation)
                XCTAssertTrue(option.isHittable, "The iPad search-input choice did not become visible: \(identifier).")
            }
            app.selectDuckAISearchInput(true)
        }

        XCTContext.runActivity(named: "Verify the iPad Duck.ai shortcut setting") { _ in
            app.openDuckAIShortcutsSettings()
            let shortcuts = app.descendants(matching: .any)["Settings.List.AIChatShortcuts"]
            let tabBarShortcut = shortcuts.switches.matching(identifier: "Settings.AIChat.TabBarToggle").firstMatch
            shortcuts.swipeUpToReveal(tabBarShortcut, timeout: UITestTimeouts.navigation)
            XCTAssertTrue(tabBarShortcut.isHittable, "The iPad Tab Bar shortcut setting did not appear.")
            // With the current iPad chrome feature, Tab Bar replaces Maestro's older Address Bar shortcut row.
            XCTAssertFalse(shortcuts.switches.matching(identifier: "Settings.AIChat.AddressBarToggle").firstMatch.exists)
            app.navigateBackInSettings(from: "Settings.List.AIChatShortcuts", to: "Settings.List.AIFeatures")
            app.navigateBackInSettings(from: "Settings.List.AIFeatures", to: "Settings.List.Main")
            app.dismissSettings()
        }

        XCTContext.runActivity(named: "Verify both mode controls while the iPad address bar is focused") { _ in
            app.searchEntry.tapWhenHittable()
            for identifier in ["Browser.OmniBar.Button.ModeToggle.Search", "Browser.OmniBar.Button.ModeToggle.AIChat"] {
                XCTAssertTrue(
                    app.buttons[identifier].wait(
                        for: NSPredicate(format: "isHittable == true AND isEnabled == true"),
                        timeout: UITestTimeouts.elementExistence),
                    "The focused iPad address bar did not show its mode control: \(identifier).")
            }
        }

        XCTContext.runActivity(named: "Select Search Only and verify both mode controls stay hidden when focused") { _ in
            app.openAIFeaturesSettings()
            app.selectDuckAISearchInput(false)
            app.navigateBackInSettings(from: "Settings.List.AIFeatures", to: "Settings.List.Main")
            app.dismissSettings()
            app.searchEntry.tapWhenHittable()
            XCTAssertTrue(
                app.keyboards.firstMatch.waitForExistence(timeout: UITestTimeouts.elementExistence),
                "The address bar did not enter editing before checking Search Only controls.")
            for identifier in ["Browser.OmniBar.Button.ModeToggle.Search", "Browser.OmniBar.Button.ModeToggle.AIChat"] {
                XCTAssertTrue(
                    app.buttons[identifier].waitForNonExistence(timeout: UITestTimeouts.elementExistence),
                    "An iPad mode control remained visible after selecting Search Only: \(identifier).")
            }
        }
    }
}
