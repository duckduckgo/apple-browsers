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

    func testSwipeToDeleteRequiresCompletedDrag() {
        app.terminate()
        app.launchArguments += ["-ff.swipeToDelete", "true"]
        app.launch()

        let menuButton = app.buttons["Browser.Toolbar.Button.Menu"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: UITestTimeouts.navigation))
        menuButton.tap()
        let newTab = app.buttons["New Tab"]
        XCTAssertTrue(newTab.waitForExistence(timeout: UITestTimeouts.navigation))
        newTab.tap()
        let dismissInput = app.buttons["UnifiedToggleInput.Button.Dismiss"]
        XCTAssertTrue(dismissInput.waitForExistence(timeout: UITestTimeouts.navigation))
        dismissInput.tap()

        let fireButton = app.buttons["Browser.Toolbar.Button.Fire"]
        XCTAssertTrue(fireButton.waitForExistence(timeout: UITestTimeouts.navigation))
        fireButton.tap()

        let slider = app.buttons["alert.forget-data.confirm"]
        XCTAssertTrue(slider.waitForExistence(timeout: UITestTimeouts.navigation))
        XCTAssertEqual(slider.label, "Slide To Delete All")
        slider.tap()
        XCTAssertTrue(slider.exists)

        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5))
        let middle = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: middle)
        XCTAssertTrue(slider.exists)

        let end = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(slider.waitForNonExistence(timeout: UITestTimeouts.navigation))
        XCTAssertTrue(fireButton.waitForExistence(timeout: UITestTimeouts.navigation))
        if dismissInput.exists {
            dismissInput.tap()
        }
        app.buttons["Browser.Toolbar.Button.TabSwitcher"].tap()
        let newTabButton = app.buttons["Open new tab"]
        XCTAssertTrue(newTabButton.waitForExistence(timeout: UITestTimeouts.navigation))
        XCTAssertEqual(app.collectionViews.cells.containing(.button, identifier: "Open new tab").count, 1)
    }

    func testSwipeToDeleteDebugVariantsAndLongText() {
        let menu = app.buttons["Browser.Toolbar.Button.Menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: UITestTimeouts.navigation))
        let dismissInput = app.buttons["UnifiedToggleInput.Button.Dismiss"]
        if dismissInput.exists {
            dismissInput.tap()
        }
        menu.tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: UITestTimeouts.navigation))
        settings.tap()
        let debugOptions = app.buttons["All debug options"]
        for _ in 0..<8 where !debugOptions.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(debugOptions.isHittable)
        debugOptions.tap()
        let filter = app.searchFields["Filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: UITestTimeouts.navigation))
        filter.tap()
        filter.typeText("Swipe to Delete")
        let screen = app.buttons["Swipe to Delete"].firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: UITestTimeouts.navigation))
        screen.tap()

        let slider = app.buttons["SlideToDelete.Debug.Preview"]
        XCTAssertTrue(slider.waitForExistence(timeout: UITestTimeouts.navigation))
        app.switches["SlideToDelete.Debug.DoubleLength"]
            .coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(slider.wait(for: \.label, equals: "Slide To Delete All Slide To Delete All"))
        for variant in ["Basic", "Flame Burst", "Fire Sweep", "Shimmer"] {
            XCTContext.runActivity(named: variant) { _ in
                app.buttons[variant].tap()
                let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.5))
                let middle = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                start.press(forDuration: 0.2, thenDragTo: middle, withVelocity: .slow, thenHoldForDuration: 0.5)
                XCTAssertFalse(app.staticTexts["Slide completed. No data deleted."].exists)
                let end = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5))
                start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.8)
                XCTAssertTrue(app.staticTexts["Slide completed. No data deleted."].waitForExistence(timeout: UITestTimeouts.navigation))
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "\(variant) with double-length text"
                screenshot.lifetime = .keepAlways
                add(screenshot)
                app.buttons["Reset Preview"].tap()
                XCTAssertTrue(slider.isEnabled)
            }
        }

        app.terminate()
        app.launchArguments.removeAll { $0 == "-clearAllDefaults" }
        app.launchArguments += ["-ff.swipeToDelete", "true"]
        app.launch()
        let fireButton = app.buttons["Browser.Toolbar.Button.Fire"]
        XCTAssertTrue(fireButton.waitForExistence(timeout: UITestTimeouts.navigation))
        if dismissInput.exists {
            dismissInput.tap()
        }
        fireButton.tap()
        let deleteAll = app.buttons["alert.forget-data.confirm"]
        XCTAssertTrue(deleteAll.waitForExistence(timeout: UITestTimeouts.navigation))
        XCTAssertEqual(deleteAll.label, "Slide To Delete All")
        deleteAll.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.5))
            .press(forDuration: 0.2,
                   thenDragTo: deleteAll.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)),
                   withVelocity: .slow,
                   thenHoldForDuration: 0.8)
        XCTAssertTrue(deleteAll.waitForNonExistence(timeout: UITestTimeouts.navigation))
    }

    func testSwipeToDeleteDisabledKeepsDeleteAllButton() {
        app.terminate()
        app.launchArguments += ["-ff.swipeToDelete", "false"]
        app.launch()

        let fireButton = app.buttons["Browser.Toolbar.Button.Fire"]
        XCTAssertTrue(fireButton.waitForExistence(timeout: UITestTimeouts.navigation))
        fireButton.tap()

        let deleteAll = app.buttons["alert.forget-data.confirm"]
        XCTAssertTrue(deleteAll.waitForExistence(timeout: UITestTimeouts.navigation))
        XCTAssertEqual(deleteAll.label, "Delete All")
        deleteAll.tap()
        XCTAssertTrue(deleteAll.waitForNonExistence(timeout: UITestTimeouts.navigation))
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
