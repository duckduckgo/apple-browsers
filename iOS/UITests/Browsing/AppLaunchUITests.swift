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

final class AppLaunchUITests: UITestCase {

    func testAppLaunchesIntoBrowser() {
        let searchEntry = app.searchEntry

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
            "-ff.appRebranding", "false",
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

        let tabCells = app.collectionViews["TabSwitcher.Collection.Tabs"].cells
        let newTab = tabCells.firstMatch.buttons.matching(
            NSPredicate(format: "identifier == %@ AND label == %@", "TabSwitcher.Tab.Open", "Open new tab"))
            .firstMatch
        let newTabExists = newTab.waitForExistence(timeout: UITestTimeouts.navigation)
        let tabCellCount = tabCells.count
        let newTabLabel = newTabExists ? newTab.label : ""
        let newTabIsHittable = newTabExists && newTab.isHittable

        if !newTabExists || tabCellCount != 1 || newTabLabel != "Open new tab" || !newTabIsHittable {
            let elementHierarchy = newTabExists ? newTab.debugDescription : app.debugDescription
            let diagnostic = XCTAttachment(
                string: "Tab cell count: \(tabCellCount)\nOpen control label: \(newTabLabel)\nOpen control hittable: \(newTabIsHittable)\nTab cells:\n\(tabCells.debugDescription)\nAccessibility hierarchy:\n\(elementHierarchy)")
            diagnostic.name = "Tab switcher New Tab control diagnostics"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
        }

        XCTAssertTrue(newTabExists, "Cleared tab should display New Tab.")
        XCTAssertEqual(tabCellCount, 1)
        XCTAssertEqual(newTabLabel, "Open new tab")
        XCTAssertTrue(
            newTabIsHittable,
            "Cleared tab's Open control was not hittable.")
    }
}
