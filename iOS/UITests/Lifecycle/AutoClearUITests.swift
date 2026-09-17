//
//  AutoClearUITests.swift
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

final class AutoClearUITests: UITestCase {

    override var additionalLaunchArguments: [String] {
        ["autoclear-ui-test"]
    }

    func testWhenAutoClearIsEnabledThenTabsCookiesAndLocalStorageAreClearedAfterBackgrounding() {
        XCTContext.runActivity(named: "Enable Auto Clear after inactivity") { _ in
            app.openSettings()
            app.openDataClearingSettings()

            let dataClearingList = app.descendants(matching: .any)["Settings.List.DataClearing"]
            let automaticallyDelete = dataClearingList.buttons["Settings.DataClearing.AutomaticallyDelete"]
            dataClearingList.swipeUpToReveal(automaticallyDelete, timeout: UITestTimeouts.navigation)
            automaticallyDelete.tapWhenHittable()

            let autoClearList = app.descendants(matching: .any)["Settings.List.AutoClear"]
            XCTAssertTrue(
                autoClearList.waitForExistence(timeout: UITestTimeouts.elementExistence),
                "Auto Clear settings did not appear.")
            let autoClearToggle = app.settingsToggle(withIdentifier: "AutoclearEnabledToggle")
            autoClearToggle.tapWhenHittable()
            XCTAssertTrue(
                autoClearToggle.wait(for: \XCUIElement.value, equals: "1", timeout: UITestTimeouts.elementExistence),
                "Auto Clear did not become enabled.")

            let fiveMinutes = app.descendants(matching: .any)["Settings.AutoClear.Timing.FiveMinutes"]
            autoClearList.swipeUpToReveal(fiveMinutes, timeout: UITestTimeouts.navigation)
            fiveMinutes.tapWhenHittable()
            XCTAssertTrue(
                fiveMinutes.wait(for: \XCUIElement.isSelected, equals: true, timeout: UITestTimeouts.elementExistence),
                "Auto Clear's five-minute timing option was not selected.")

            app.navigateBackInSettings(from: "Settings.List.AutoClear", to: "Settings.List.DataClearing")
            app.navigateBackInSettings(from: "Settings.List.DataClearing", to: "Settings.List.Main")
            app.dismissSettings()
        }

        XCTContext.runActivity(named: "Create tabs and website data") { _ in
            app.openStorageCounterPage()
            app.resetStorageCounters()
            app.incrementStorageCounters()

            app.openNewTab()
            app.openURL("https://example.com", expecting: "Example Domain")
        }

        XCTContext.runActivity(named: "Clear tabs and website data after backgrounding") { _ in
            // The existing UI-test launch argument shortens the five-minute interval to five seconds.
            app.backgroundAndActivate(minimumBackgroundDuration: 6)

            XCTAssertTrue(
                app.searchEntry.wait(for: NSPredicate(format: "isHittable == true"), timeout: UITestTimeouts.fireAnimation),
                "Browser did not become available after Auto Clear.")
            XCTAssertFalse(app.webViews.staticTexts["Example Domain"].exists, "Cleared page is still visible.")

            app.openTabSwitcher()
            app.assertTabCount(1)
            XCTAssertFalse(app.staticTexts["Example Domain"].exists, "Cleared tab is still present in the tab switcher.")
            app.buttons["TabSwitcher.Button.Done"].tapWhenHittable()

            app.openStorageCounterPage()
            app.assertStorageCountersEmpty()
        }
    }
}
