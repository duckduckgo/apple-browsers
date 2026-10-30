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
        app.launchArguments += ["-ff.swipeToDelete", "true", "-ff.fireMode", "true", "-ff.fireButtonRefinements", "true"]
        app.launch()

        let menuButton = app.buttons["Browser.Toolbar.Button.Menu"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: UITestTimeouts.navigation))
        let dismissInput = app.buttons["UnifiedToggleInput.Button.Dismiss"]
        if dismissInput.waitForExistence(timeout: 3) {
            dismissInput.tap()
        }
        menuButton.tap()
        let newTab = app.buttons["New Tab"]
        XCTAssertTrue(newTab.waitForExistence(timeout: UITestTimeouts.navigation))
        newTab.tap()
        XCTAssertTrue(dismissInput.waitForExistence(timeout: UITestTimeouts.navigation))
        dismissInput.tap()

        let fireButton = app.buttons["Browser.Toolbar.Button.Fire"]
        XCTAssertTrue(fireButton.waitForExistence(timeout: UITestTimeouts.navigation))
        fireButton.tap()

        let slider = app.buttons["alert.forget-data.confirm"]
        XCTAssertTrue(slider.waitForExistence(timeout: UITestTimeouts.navigation))
        XCTAssertEqual(slider.label, "Slide To Delete All")
        let deleteThis = app.buttons["Fire.Confirmation.Button.ThisTab"]
        XCTAssertTrue(deleteThis.waitForExistence(timeout: UITestTimeouts.navigation))
        app.swipeUp()
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

    func testSwipeToDeleteDisabledKeepsDeleteAllButton() {
        openFireConfirmationForWidthTest(swipeToDelete: false, orientation: .landscapeLeft)
        defer { XCUIDevice.shared.orientation = .portrait }
        let deleteAll = app.buttons["alert.forget-data.confirm"]
        XCTAssertEqual(deleteAll.label, "Delete All")
        let modal = app.scrollViews.containing(.button, identifier: "alert.forget-data.confirm").firstMatch
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertEqual(modal.frame.width, 375, accuracy: 1)
        } else {
            XCTAssertGreaterThan(modal.frame.width, app.frame.height)
        }
        deleteAll.tap()
        XCTAssertTrue(deleteAll.waitForNonExistence(timeout: UITestTimeouts.navigation))
    }

    func testSwipeToDeleteLandscapeModalWidthAndRotation() {
        openFireConfirmationForWidthTest(swipeToDelete: true, orientation: .portrait)
        defer { XCUIDevice.shared.orientation = .portrait }
        let slider = app.buttons["alert.forget-data.confirm"]
        XCTAssertEqual(slider.label, "Slide To Delete All")
        let modal = app.scrollViews.containing(.button, identifier: "alert.forget-data.confirm").firstMatch
        XCTAssertTrue(modal.exists)
        let portraitWidth = modal.frame.width
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertEqual(portraitWidth, 375, accuracy: 1)
        }

        XCUIDevice.shared.orientation = .landscapeLeft
        let landscapeWidth = UIDevice.current.userInterfaceIdiom == .pad ? 375 : app.frame.height
        assertFireModalWidth(modal, equals: landscapeWidth)

        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: slider.frame.height / (2 * slider.frame.width), dy: 0.5))
        start.press(forDuration: 0.3,
                    thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                    withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(slider.exists)

        XCUIDevice.shared.orientation = .portrait
        assertFireModalWidth(modal, equals: portraitWidth)
        app.buttons["Fire.Confirmation.Button.Close"].tap()
        XCTAssertTrue(slider.waitForNonExistence(timeout: UITestTimeouts.navigation))
        XCUIDevice.shared.orientation = .landscapeLeft
        let fire = app.buttons["Browser.Toolbar.Button.Fire"]
        let ready = NSPredicate { _, _ in
            self.app.frame.width > self.app.frame.height && fire.isHittable && fire.frame.maxY < self.app.frame.height
        }
        XCTAssertTrue(fire.wait(for: ready, timeout: UITestTimeouts.navigation))
        fire.tap()
        XCTAssertTrue(slider.waitForExistence(timeout: UITestTimeouts.navigation))
        assertFireModalWidth(modal, equals: landscapeWidth)
        let thumbRadius = (slider.frame.height - 6) / 2
        slider.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: slider.frame.height / 2, dy: slider.frame.height / 2 - thumbRadius * 1.05))
            .press(forDuration: 0.3,
                   thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(slider.waitForNonExistence(timeout: UITestTimeouts.navigation))
    }

    private func openFireConfirmationForWidthTest(swipeToDelete: Bool, orientation: UIDeviceOrientation) {
        app.terminate()
        XCUIDevice.shared.orientation = orientation
        app.launchArguments += ["-ff.swipeToDelete", String(swipeToDelete), "-ff.fireMode", "true", "-ff.fireButtonRefinements", "true"]
        app.launch()
        let dismissInput = app.buttons.matching(NSPredicate(format: "identifier IN %@", [
            "UnifiedToggleInput.Button.Dismiss", "Browser.OmniBar.Button.Dismiss"
        ])).firstMatch
        if dismissInput.waitForExistence(timeout: 3) { dismissInput.tap() }
        if swipeToDelete && UIDevice.current.userInterfaceIdiom == .pad {
            app.buttons["Browser.OmniBar.Button.BrowsingMenu"].tap()
            let newTab = app.buttons["New Tab"]
            XCTAssertTrue(newTab.waitForExistence(timeout: UITestTimeouts.navigation))
            newTab.tap()
            if dismissInput.waitForExistence(timeout: 3) { dismissInput.tap() }
        }
        let fire = app.buttons["Browser.Toolbar.Button.Fire"]
        XCTAssertTrue(fire.waitForExistence(timeout: UITestTimeouts.navigation))
        fire.tap()
        XCTAssertTrue(app.buttons["alert.forget-data.confirm"].waitForExistence(timeout: UITestTimeouts.navigation))
    }

    private func assertFireModalWidth(_ modal: XCUIElement, equals width: CGFloat) {
        let expectedWidth = NSPredicate { _, _ in abs(modal.frame.width - width) <= 1 }
        XCTAssertTrue(modal.wait(for: expectedWidth, timeout: UITestTimeouts.navigation))
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
