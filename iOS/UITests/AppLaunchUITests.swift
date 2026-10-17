//
//  AppLaunchUITests.swift
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

final class AppLaunchUITests: XCTestCase {

    private let app = XCUIApplication()
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

    func testAppLaunchesIntoBrowser() {
        let searchEntry = app.descendants(matching: .any)["searchEntry"]

        XCTAssertTrue(
            searchEntry.waitForExistence(timeout: UITestTimeouts.navigation),
            "Browser UI did not appear after launch."
        )
    }

    func testAutoClearOnRelaunchShowsNewTabInTabSwitcher() {
        app.terminate()
        app.launchArguments += [
            "-ff.fireMode", "true",
            "-ff.floatingUIiOS26", "true",
            "-ff.floatingUIiOS27", "true",
            "-com.duckduckgo.app.autoClearActionKey", "3",
            "-com.duckduckgo.app.autoClearTimingKey", "0",
        ]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["searchEntry"].waitForExistence(timeout: UITestTimeouts.navigation))

        app.terminate()
        app.launchArguments.removeAll { $0 == "-clearAllDefaults" }
        app.launch()

        let tabSwitcher = app.descendants(matching: .any)["Browser.Toolbar.Button.TabSwitcher"]
        XCTAssertTrue(tabSwitcher.waitForExistence(timeout: UITestTimeouts.navigation))
        tabSwitcher.tap()

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Tab switcher after automatic tab clearing"
        add(screenshot)

        let newTab = app.buttons["Open new tab"]
        XCTAssertTrue(newTab.waitForExistence(timeout: UITestTimeouts.navigation), "Cleared tab should display New Tab.")
        XCTAssertTrue(newTab.isHittable)
        let tabCells = app.collectionViews.cells.containing(.button, identifier: "Open new tab")
        XCTAssertEqual(tabCells.count, 1)
    }
}
