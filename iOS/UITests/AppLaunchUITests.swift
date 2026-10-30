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
        XCTAssertEqual(slider.frame.minY - deleteThis.frame.maxY, 16, accuracy: 1)
        XCTAssertGreaterThan(slider.frame.height, deleteThis.frame.height)
        let layout = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        layout.name = "60-point slider and 50-point button"
        layout.lifetime = .keepAlways
        add(layout)
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
        openSlideToDeleteDebugScreen()
        let dismissInput = app.buttons["UnifiedToggleInput.Button.Dismiss"]

        let slider = app.buttons["SlideToDelete.Debug.Preview"]
        XCTAssertTrue(slider.waitForExistence(timeout: UITestTimeouts.navigation))
        scrollDebugControlIntoView(app.switches["SlideToDelete.Debug.DoubleLength"])
        app.switches["SlideToDelete.Debug.DoubleLength"]
            .coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(slider.wait(for: \.label, equals: "Slide To Delete All Slide To Delete All"))
        for variant in ["Basic", "Flame Burst", "Fire Sweep", "Shimmer"] {
            XCTContext.runActivity(named: variant) { _ in
                scrollDebugControlIntoView(app.buttons[variant], abovePreview: true)
                app.buttons[variant].tap()
                scrollDebugControlIntoView(slider)
                let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.5))
                let middle = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                start.press(forDuration: 0.6, thenDragTo: middle, withVelocity: .slow, thenHoldForDuration: 0.5)
                XCTAssertFalse(app.staticTexts["Slide completed. No data deleted."].exists)
                let end = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5))
                start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.8)
                XCTAssertTrue(app.staticTexts["Slide completed. No data deleted."].waitForExistence(timeout: UITestTimeouts.navigation))
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "\(variant) with double-length text"
                screenshot.lifetime = .keepAlways
                add(screenshot)
                XCTAssertEqual(app.staticTexts["SlideToDelete.Debug.TouchDiagnostics"].label, "Touch requests: 2")
                if variant == "Shimmer" {
                    XCTAssertTrue(app.staticTexts["SlideToDelete.Debug.Diagnostics"]
                        .wait(for: \.label, equals: "Haptic requests: 1 · Label reveals: 1"))
                }
                scrollDebugControlIntoView(app.buttons["Reset Preview"])
                app.buttons["Reset Preview"].tap()
                XCTAssertTrue(slider.isEnabled)
            }
        }

        let diagnostics = app.staticTexts["SlideToDelete.Debug.Diagnostics"]
        scrollDebugControlIntoView(app.buttons["SlideToDelete.Debug.TestHaptic"])
        app.buttons["SlideToDelete.Debug.TestHaptic"].tap()
        XCTAssertTrue(diagnostics.wait(for: \.label, equals: "Haptic requests: 1 · Label reveals: 0"))
        app.buttons["Reset Preview"].tap()
        scrollDebugControlIntoView(slider)
        let fastStart = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.5))
        let fastEnd = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5))
        fastStart.press(forDuration: 0.05, thenDragTo: fastEnd, withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(app.staticTexts["Slide completed. No data deleted."].waitForExistence(timeout: UITestTimeouts.navigation))
        XCTAssertEqual(diagnostics.label, "Haptic requests: 1 · Label reveals: 0")

        app.terminate()
        app.launchArguments.removeAll { $0 == "-clearAllDefaults" }
        app.launchArguments += ["-ff.swipeToDelete", "true", "-ff.fireMode", "true", "-ff.fireButtonRefinements", "true"]
        app.launch()
        navigateToBlankPage()
        app.buttons["Browser.Toolbar.Button.Menu"].tap()
        let newTab = app.buttons["New Tab"]
        XCTAssertTrue(newTab.waitForExistence(timeout: UITestTimeouts.navigation))
        newTab.tap()
        navigateToBlankPage()
        let fireButton = app.buttons["Browser.Toolbar.Button.Fire"]
        XCTAssertTrue(fireButton.waitForExistence(timeout: UITestTimeouts.navigation))
        if dismissInput.exists {
            dismissInput.tap()
        }
        fireButton.tap()
        let deleteAll = app.buttons["alert.forget-data.confirm"]
        XCTAssertTrue(deleteAll.waitForExistence(timeout: UITestTimeouts.navigation))
        XCTAssertEqual(deleteAll.label, "Slide To Delete All")
        let deleteThis = app.buttons["Fire.Confirmation.Button.ThisTab"]
        XCTAssertTrue(deleteThis.waitForExistence(timeout: UITestTimeouts.navigation))
        XCTAssertEqual(deleteAll.frame.minY - deleteThis.frame.maxY, 16, accuracy: 1)
        XCTAssertGreaterThan(deleteAll.frame.height, deleteThis.frame.height)
        XCTAssertEqual(deleteAll.frame.width, deleteThis.frame.width, accuracy: 1)
        let sheetScreenshot = XCTAttachment(screenshot: app.screenshot())
        sheetScreenshot.name = "Fire sheet with 16-point button spacing"
        sheetScreenshot.lifetime = .keepAlways
        add(sheetScreenshot)
        deleteAll.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.5))
            .press(forDuration: 0.2,
                   thenDragTo: deleteAll.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)),
                   withVelocity: .slow,
                   thenHoldForDuration: 0.8)
        XCTAssertTrue(deleteAll.waitForNonExistence(timeout: UITestTimeouts.navigation))
    }

    func testSwipeToDeleteStylesAndAvailability() {
        openSlideToDeleteDebugScreen()
        let original = app.buttons["SlideToDelete.Debug.Style.original"]
        let glass = app.buttons["SlideToDelete.Debug.Style.glass"]
        XCTAssertTrue(original.isEnabled)
        XCTAssertTrue(original.isSelected)
        if #available(iOS 26.0, *) {
            XCTAssertTrue(glass.isEnabled)
        } else {
            XCTAssertFalse(glass.isEnabled)
            XCTAssertTrue(original.isSelected)
            XCTAssertEqual(app.staticTexts["SlideToDelete.Debug.StyleAvailability"].label,
                           "Liquid Glass requires iOS 26 or later. Original is used on this device.")
        }
        let availability = XCTAttachment(screenshot: app.screenshot())
        availability.name = "Slider styles and OS availability"
        availability.lifetime = .keepAlways
        add(availability)

        let styles = glass.isEnabled ? [("Original", original), ("Glass", glass)] : [("Original", original)]
        for (name, option) in styles {
            XCTContext.runActivity(named: "Slider style: \(name)") { _ in
                scrollDebugControlIntoView(option, abovePreview: true)
                option.tap()
                XCTAssertTrue(option.isSelected)
                let slider = app.buttons["SlideToDelete.Debug.Preview"]
                scrollDebugControlIntoView(slider)
                let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.5))
                start.press(forDuration: 0.8,
                            thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                            withVelocity: .slow, thenHoldForDuration: 0.6)
                XCTAssertFalse(app.staticTexts["Slide completed. No data deleted."].exists)
                start.press(forDuration: 0.2,
                            thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)),
                            withVelocity: .slow, thenHoldForDuration: 0.8)
                XCTAssertTrue(app.staticTexts["Slide completed. No data deleted."].waitForExistence(timeout: UITestTimeouts.navigation))
                XCTAssertEqual(app.staticTexts["SlideToDelete.Debug.TouchDiagnostics"].label, "Touch requests: 2")
            }
        }
    }

    private func openSlideToDeleteDebugScreen() {
        let menu = app.buttons["Browser.Toolbar.Button.Menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: UITestTimeouts.navigation))
        let dismissInput = app.buttons["UnifiedToggleInput.Button.Dismiss"]
        if dismissInput.waitForExistence(timeout: 3) {
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
        let screen = app.buttons["Slide to Delete"].firstMatch
        if filter.waitForExistence(timeout: 3) {
            filter.tap()
            filter.typeText("Slide to Delete")
        } else {
            for _ in 0..<12 where !screen.isHittable {
                app.swipeUp()
            }
        }
        XCTAssertTrue(screen.waitForExistence(timeout: UITestTimeouts.navigation))
        screen.tap()
    }

    private func scrollDebugControlIntoView(_ element: XCUIElement, abovePreview: Bool = false) {
        for _ in 0..<6 {
            if element.isHittable && element.frame.minY > 125 && element.frame.maxY < app.frame.maxY - 80 {
                return
            }
            if element.exists ? element.frame.minY <= 125 : abovePreview {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(element.isHittable)
    }

    private func navigateToBlankPage() {
        let search = app.descendants(matching: .any)["searchEntry"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: UITestTimeouts.navigation))
        search.tap()
        search.typeText("about:blank")
        app.keyboards.buttons["Go"].tap()
        let dismissInput = app.buttons["UnifiedToggleInput.Button.Dismiss"]
        if dismissInput.exists {
            dismissInput.tap()
        }
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
        XCTAssertGreaterThanOrEqual(slider.frame.height, 60)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertEqual(modal.frame.maxY - slider.frame.maxY, 48, accuracy: 1)
        }
        let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscape.name = "Landscape Fire confirmation"
        landscape.lifetime = .keepAlways
        add(landscape)

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

    func testSwipeToDeleteDisabledKeepsLandscapeModalWidth() {
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
        app.buttons["Fire.Confirmation.Button.Close"].tap()
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
