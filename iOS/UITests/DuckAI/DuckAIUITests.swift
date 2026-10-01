//
//  DuckAIUITests.swift
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

final class DuckAIUITests: DuckAIUITestCase {

    func testWhenOpeningDuckAIFromBrowserShortcutsThenClosingReturnsToPreviousTab() {
        XCTContext.runActivity(named: "Open Duck.ai from the new-tab page and verify native controls") { _ in
            app.buttons["Browser.OmniBar.Button.AIChat"].tapWhenHittable()
            assertDuckAIHeader()
            for identifier in ["AIChat.Header.RecentChats", "AIChat.Header.New", "AIChat.Toolbar.Button.ModelChip"] {
                XCTAssertTrue(
                    app.buttons[identifier].waitForExistence(timeout: UITestTimeouts.navigation),
                    "Duck.ai control did not appear: \(identifier).")
            }
            closeDuckAITab()
            XCTAssertTrue(app.searchEntry.waitForExistence(timeout: UITestTimeouts.elementExistence))
        }

        app.openURL("https://privacy-test-pages.site", expecting: "Privacy Test Pages")

        XCTContext.runActivity(named: "Open Duck.ai from the browsing menu and return to the webpage") { _ in
            app.openBrowsingMenuItem("Browser.Menu.DuckAI")
            assertDuckAIHeader()
            closeDuckAITab()
            app.assertPageContains("Privacy Test Pages")
        }

        XCTContext.runActivity(named: "Open Duck.ai from the tab switcher and return to the webpage") { _ in
            app.openTabSwitcher()
            app.buttons["TabSwitcher.Button.DuckChat"].tapWhenHittable()
            assertDuckAIHeader()
            closeDuckAITab()
            app.assertPageContains("Privacy Test Pages")
        }
    }

    func testWhenDuckAIIsDisabledThenAllBrowserShortcutsAreHidden() {
        app.openAIFeaturesSettings()
        app.setDuckAIEnabled(false)
        app.navigateBackInSettings(from: "Settings.List.AIFeatures", to: "Settings.List.Main")
        app.dismissSettings()

        XCTAssertTrue(
            app.buttons["Browser.OmniBar.Button.AIChat"].waitForNonExistence(timeout: UITestTimeouts.elementExistence),
            "Duck.ai remained in the address bar after disabling the feature.")

        app.openURL("https://privacy-test-pages.site", expecting: "Privacy Test Pages")
        XCTContext.runActivity(named: "Verify Duck.ai is absent from the browsing menu") { _ in
            app.buttons["Browser.Toolbar.Button.Menu"].tapWhenHittable()
            let menu = app.descendants(matching: .any)["Browser.Menu.List"]
            XCTAssertTrue(menu.waitForExistence(timeout: UITestTimeouts.elementExistence))
            // Check the header before scrolling; an off-screen tile must not satisfy this negative assertion.
            XCTAssertFalse(app.descendants(matching: .any)["Browser.Menu.DuckAI"].exists)
            let settings = menu.buttons["Browser.Menu.Settings"]
            menu.swipeUpToReveal(settings, timeout: UITestTimeouts.navigation)
            settings.tapWhenHittable()
            XCTAssertTrue(
                app.descendants(matching: .any)["Settings.List.Main"].waitForExistence(timeout: UITestTimeouts.elementExistence))
            app.dismissSettings()
        }

        app.openTabSwitcher()
        XCTAssertFalse(
            app.buttons["TabSwitcher.Button.DuckChat"].exists,
            "Duck.ai remained in the tab switcher after disabling the feature.")
    }

    private func assertDuckAIHeader(file: StaticString = #filePath, line: UInt = #line) {
        for identifier in ["AIChat.Header.FreePlan", "AIChat.Header.Upgrade"] {
            XCTAssertTrue(
                app.staticTexts[identifier].waitForExistence(timeout: UITestTimeouts.navigation),
                "Duck.ai header did not appear: \(identifier).", file: file, line: line)
        }
        XCTAssertTrue(
            app.buttons["AIChat.Header.Close"].wait(
                for: NSPredicate(format: "isHittable == true AND isEnabled == true"),
                timeout: UITestTimeouts.elementExistence),
            "Duck.ai close control did not become available.", file: file, line: line)
    }

    private func closeDuckAITab(file: StaticString = #filePath, line: UInt = #line) {
        app.buttons["AIChat.Header.Close"].tapWhenHittable(file: file, line: line)
        XCTAssertTrue(
            app.buttons["AIChat.Header.Close"].waitForNonExistence(timeout: UITestTimeouts.elementExistence),
            "Duck.ai tab did not close.", file: file, line: line)
    }
}
