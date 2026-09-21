//
//  DuckAISettingsUITests.swift
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

final class DuckAISettingsUITests: DuckAIUITestCase {

    func testDuckAISettingsRowFollowsPrimaryToggleAndOpensDuckAIInNewTab() {
        let duckAISettings = app.aiFeaturesSettingsList.buttons["Settings.AIFeatures.DuckAISettings"]

        XCTContext.runActivity(named: "Disable and restore the Duck.ai settings section") { _ in
            app.openAIFeaturesSettings()
            app.aiFeaturesSettingsList.swipeUpToReveal(duckAISettings, timeout: UITestTimeouts.navigation)
            XCTAssertTrue(duckAISettings.exists, "Duck.ai Settings did not appear while Duck.ai was enabled.")

            app.revealDuckAIEnableToggle()
            app.setDuckAIEnabled(false)
            XCTAssertTrue(
                duckAISettings.wait(for: NSPredicate(format: "exists == false"), timeout: UITestTimeouts.elementExistence),
                "Duck.ai Settings remained after Duck.ai was disabled.")

            app.revealDuckAIEnableToggle()
            app.setDuckAIEnabled(true)
            app.aiFeaturesSettingsList.swipeUpToReveal(duckAISettings, timeout: UITestTimeouts.navigation)
            XCTAssertTrue(duckAISettings.exists, "Duck.ai Settings did not return after Duck.ai was enabled.")
        }

        XCTContext.runActivity(named: "Open Duck.ai Settings in a new tab") { _ in
            duckAISettings.tapWhenHittable()
            XCTAssertTrue(
                app.aiFeaturesSettingsList.wait(for: NSPredicate(format: "exists == false"), timeout: UITestTimeouts.elementExistence),
                "AI Features settings remained visible after opening Duck.ai Settings.")
            // Duck.ai settings opens with native chat chrome, not the browser's URL field.
            let settingsHeading = app.webViews.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "Duck.ai Settings"))
                .firstMatch
            XCTAssertTrue(
                settingsHeading.waitForExistence(timeout: UITestTimeouts.navigation),
                "The Duck.ai Settings destination did not load.")
            app.buttons["AIChat.Header.TabSwitcher"].tapWhenHittable()
            app.assertTabCount(2)
        }
    }
}

final class DuckAIIPhoneIPadFlagsUITests: DuckAIUITestCase {

    override var duckAIFeatureFlagLaunchArguments: [String] {
        [
            "-ff.aiChatChromeShortcutIPad", "true",
            "-ff.iPadDuckAIBarControls", "true",
        ]
    }

    func testIPadDuckAIFlagsDoNotChangeIPhoneControlsOrSettings() {
        XCTContext.runActivity(named: "Verify iPhone browser controls") { _ in
            assertIPhoneBrowserControls()
        }

        XCTContext.runActivity(named: "Verify iPhone AI Features and shortcut settings") { _ in
            app.openAIFeaturesSettings()

            let searchOnly = app.aiFeaturesSettingsList.descendants(matching: .any)["Settings.AIFeatures.Picker.SearchOnly"]
            let searchAndDuckAI = app.aiFeaturesSettingsList.descendants(matching: .any)["Settings.AIFeatures.Picker.SearchAndDuckAI"]
            app.aiFeaturesSettingsList.swipeUpToReveal(searchOnly, timeout: UITestTimeouts.navigation)
            XCTAssertTrue(searchOnly.exists, "Search Only did not appear in AI Features settings.")
            XCTAssertTrue(searchAndDuckAI.exists, "Search & Duck.ai did not appear in AI Features settings.")

            app.openDuckAIShortcutsSettings()
            XCTAssertTrue(
                app.switches.matching(identifier: "Settings.AIChat.AddressBarToggle").firstMatch
                    .waitForExistence(timeout: UITestTimeouts.elementExistence),
                "The iPhone Address Bar shortcut setting did not appear.")
            app.navigateBackInSettings(from: "Settings.List.AIChatShortcuts", to: "Settings.List.AIFeatures")
        }

        XCTContext.runActivity(named: "Select Search and Duck.ai without exposing iPad controls") { _ in
            app.selectDuckAISearchInput(true)
            app.navigateBackInSettings(from: "Settings.List.AIFeatures", to: "Settings.List.Main")
            app.dismissSettings()
            assertIPhoneBrowserControls()
        }

        XCTContext.runActivity(named: "Select Search Only without exposing iPad controls") { _ in
            app.openAIFeaturesSettings()
            app.selectDuckAISearchInput(false)
            app.navigateBackInSettings(from: "Settings.List.AIFeatures", to: "Settings.List.Main")
            app.dismissSettings()
            assertIPhoneBrowserControls()
        }
    }

    private func assertIPhoneBrowserControls(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            app.searchEntry.waitForExistence(timeout: UITestTimeouts.navigation),
            "The iPhone address bar did not appear.",
            file: file,
            line: line)
        XCTAssertTrue(
            app.buttons["Browser.OmniBar.Button.AIChat"].waitForExistence(timeout: UITestTimeouts.elementExistence),
            "The iPhone Duck.ai address-bar button did not appear.",
            file: file,
            line: line)
        app.searchEntry.tapWhenHittable(file: file, line: line)
        XCTAssertFalse(
            app.buttons["Browser.OmniBar.Button.ModeToggle.Search"].exists,
            "The iPad Search mode toggle appeared on iPhone.",
            file: file,
            line: line)
        XCTAssertFalse(
            app.buttons["Browser.OmniBar.Button.ModeToggle.AIChat"].exists,
            "The iPad Duck.ai mode toggle appeared on iPhone.",
            file: file,
            line: line)
        app.dismissAddressBarEditing(file: file, line: line)
    }
}
