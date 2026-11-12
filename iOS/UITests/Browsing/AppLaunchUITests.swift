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

    override var launchesAppInSetUp: Bool {
        false
    }

    func testAppLaunchesIntoBrowser() {
        app.launch()
        let searchEntry = app.searchEntry

        XCTAssertTrue(
            searchEntry.waitForExistence(timeout: UITestTimeouts.navigation),
            "Browser UI did not appear after launch."
        )
    }

    func testRegularToolbarReadyWithoutKeyboard() {
        assertToolbarActionAfterDismissal(floating: false, editing: false)
    }

    func testRegularAddressEditingDismissesKeyboard() {
        assertToolbarActionAfterDismissal(floating: false, editing: true)
    }

    func testFloatingToolbarReadyWithoutKeyboard() {
        assertToolbarActionAfterDismissal(floating: true, editing: false)
    }

    func testFloatingAddressEditingDismissesKeyboard() {
        assertToolbarActionAfterDismissal(floating: true, editing: true)
    }

    func testRegularContextMenusKeepBrowserControlsVisible() throws {
        try assertContextMenusKeepBrowserControlsVisible(floating: false)
    }

    func testFloatingContextMenusKeepBrowserControlsVisible() throws {
        try assertContextMenusKeepBrowserControlsVisible(floating: true)
    }

    private func assertContextMenusKeepBrowserControlsVisible(floating: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        let site = try localWebsite()
        for index in app.launchArguments.indices where ["-ff.floatingUIiOS26", "-ff.floatingUIiOS27"].contains(app.launchArguments[index]) {
            app.launchArguments[index + 1] = String(floating)
        }
        app.launchArguments += [
            "-ff.fireMode", "true",
            "-ff.fireButtonRefinements", "true",
            "-ff.slideToDelete", "false",
            // Pass a Boolean UserDefaults value so new tabs open without taking keyboard focus.
            "-com.duckduckgo.ios.keyboard.newtab", "<false/>",
        ]
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launch()
        app.dismissAddressBarEditing(file: file, line: line)

        let tabs = app.buttons["Browser.Toolbar.Button.TabSwitcher"]
        let fire = app.buttons["Browser.Toolbar.Button.Fire"]
        let newTab = app.buttons["Browser.NewTabMenu.NewTab"]
        var expectedTabs = 1
        for loadedPage in [false, true] {
            XCTContext.runActivity(named: loadedPage ? "Context menus on a loaded page" : "Context menus on a new tab") { _ in
                if loadedPage {
                    site.open(.first, in: app, file: file, line: line)
                    fire.tapWhenHittable(in: app, file: file, line: line)
                    let close = app.buttons["Fire.Confirmation.Button.Close"]
                    close.tapWhenHittable(in: app, file: file, line: line)
                    XCTAssertTrue(close.waitForNonExistence(timeout: UITestTimeouts.navigation), file: file, line: line)
                    app.assertPageContains(LocalUITestWebsite.Page.first.title, file: file, line: line)
                }

                XCTAssertTrue(tabs.waitForHittableInAppWindow(in: app, timeout: UITestTimeouts.navigation), file: file, line: line)
                tabs.press(forDuration: 1)
                XCTAssertTrue(newTab.waitForExistence(timeout: UITestTimeouts.navigation), file: file, line: line)
                attachContextMenuState(loadedPage: loadedPage, checkpoint: "open menu")
                app.browserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
                XCTAssertTrue(newTab.waitForNonExistence(timeout: UITestTimeouts.navigation), file: file, line: line)
                XCTAssertTrue(tabs.waitForHittableInAppWindow(in: app, timeout: UITestTimeouts.navigation), file: file, line: line)
                XCTAssertTrue(fire.waitForHittableInAppWindow(in: app, timeout: UITestTimeouts.navigation), file: file, line: line)
                attachContextMenuState(loadedPage: loadedPage, checkpoint: "cancelled")
                app.openTabSwitcher(file: file, line: line)
                app.assertTabCount(expectedTabs, file: file, line: line)
                let originalTab = app.tabCell(at: expectedTabs - 1)
                app.buttons["TabSwitcher.Button.Done"].tapWhenHittable(in: app, file: file, line: line)

                tabs.press(forDuration: 1)
                newTab.tapWhenHittable(in: app, file: file, line: line)
                XCTAssertTrue(newTab.waitForNonExistence(timeout: UITestTimeouts.navigation), file: file, line: line)
                app.dismissAddressBarEditing(file: file, line: line)
                XCTAssertTrue(tabs.waitForHittableInAppWindow(in: app, timeout: UITestTimeouts.navigation), file: file, line: line)
                XCTAssertTrue(fire.waitForHittableInAppWindow(in: app, timeout: UITestTimeouts.navigation), file: file, line: line)
                attachContextMenuState(loadedPage: loadedPage, checkpoint: "created tab")
                expectedTabs += 1
                app.openTabSwitcher(file: file, line: line)
                app.assertTabCount(expectedTabs, file: file, line: line)
                XCTAssertTrue(originalTab.exists, "Creating a tab removed an existing tab.", file: file, line: line)
                if loadedPage {
                    originalTab.buttons["TabSwitcher.Tab.Open"].tapWhenHittable(in: app, file: file, line: line)
                    app.assertPageContains(LocalUITestWebsite.Page.first.title, file: file, line: line)
                } else {
                    app.buttons["TabSwitcher.Button.Done"].tapWhenHittable(in: app, file: file, line: line)
                }
            }
        }
    }

    private func attachContextMenuState(loadedPage: Bool, checkpoint: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Context menu \(loadedPage ? "loaded page" : "new tab") — \(checkpoint)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testReadinessRejectsMissingAndDisabledControlsWithoutTapping() {
        app.launch()
        app.dismissAddressBarEditing()
        let missing = app.buttons["Readiness.Test.Missing"]
        XCTAssertFalse(missing.waitForHittableInAppWindow(in: app, timeout: 0.3))

        let tabSwitcher = app.buttons["Browser.Toolbar.Button.TabSwitcher"]
        XCTAssertTrue(tabSwitcher.waitForHittableInAppWindow(in: app, timeout: UITestTimeouts.elementExistence))
        XCTAssertFalse(app.buttons["TabSwitcher.Button.Done"].exists, "A readiness wait must not tap its target.")
        app.openTabSwitcher()
        app.assertTabCount(1)
        let edit = app.buttons["TabSwitcher.Button.Edit"]
        XCTAssertTrue(edit.exists)
        XCTAssertFalse(edit.isEnabled, "Editing must be disabled for the single empty tab.")
        XCTAssertFalse(edit.waitForHittableInAppWindow(in: app, timeout: 0.3))
        XCTAssertTrue(app.buttons["TabSwitcher.Button.Done"].exists)
        app.assertTabCount(1)
    }

    func testReadinessInPortraitAndLandscape() {
        app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            app.dismissAddressBarEditing()
            let tabSwitcher = app.buttons["Browser.Toolbar.Button.TabSwitcher"]
            XCTAssertTrue(tabSwitcher.waitForHittableInAppWindow(in: app, timeout: UITestTimeouts.elementExistence))
            XCTAssertEqual(app.windows.matching(identifier: "Browser.Window.Main").count, 1)
            let applicationFrame = app.frame
            let windowFrame = app.browserWindow.frame
            let attachment = XCTAttachment(string: "orientation=\(orientation.rawValue)\napplicationFrame=\(applicationFrame)\nselectedWindowFrame=\(windowFrame)")
            attachment.name = "Readiness application and window geometry"
            attachment.lifetime = .keepAlways
            add(attachment)
            tabSwitcher.tapWhenHittable(in: app)
            app.assertTabCount(1)
            app.buttons["TabSwitcher.Button.Done"].tapWhenHittable(in: app)
        }
    }

    private func assertToolbarActionAfterDismissal(floating: Bool, editing: Bool, file: StaticString = #filePath, line: UInt = #line) {
        for index in app.launchArguments.indices where ["-ff.floatingUIiOS26", "-ff.floatingUIiOS27"].contains(app.launchArguments[index]) {
            app.launchArguments[index + 1] = String(floating)
        }
        app.launch()
        XCTAssertTrue(app.searchEntry.waitForExistence(timeout: UITestTimeouts.navigation), file: file, line: line)
        if editing {
            app.searchEntry.tapWhenHittable(in: app, file: file, line: line)
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: UITestTimeouts.elementExistence), file: file, line: line)
        } else {
            XCTAssertFalse(app.keyboards.firstMatch.exists, file: file, line: line)
        }

        app.dismissAddressBarEditing(file: file, line: line)
        XCTAssertFalse(app.keyboards.firstMatch.exists, file: file, line: line)
        app.buttons["Browser.Toolbar.Button.TabSwitcher"].tapWhenHittable(in: app, file: file, line: line)
        XCTAssertTrue(
            app.buttons["TabSwitcher.Button.Done"].waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Tab switcher did not open after address editing dismissal.", file: file, line: line)
        app.assertTabCount(1, file: file, line: line)
    }

    func testSlideToDeleteRequiresCompletedDrag() {
        app.launchArguments += ["-ff.slideToDelete", "true", "-ff.fireMode", "true", "-ff.fireButtonRefinements", "true"]
        app.launch()

        let dismissInput = app.buttons.matching(NSPredicate(format: "identifier IN %@", [
            "UnifiedToggleInput.Button.Dismiss", "Browser.OmniBar.Button.Dismiss"
        ])).firstMatch
        if dismissInput.waitForExistence(timeout: 3) { dismissInput.tap() }

        let menuIdentifier = UIDevice.current.userInterfaceIdiom == .pad
            ? "Browser.OmniBar.Button.BrowsingMenu"
            : "Browser.Toolbar.Button.Menu"
        let menuButton = app.buttons[menuIdentifier]
        XCTAssertTrue(menuButton.waitForExistence(timeout: UITestTimeouts.navigation))
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
        if UIDevice.current.userInterfaceIdiom != .pad {
            app.swipeUp()
        }
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
        app.openTabSwitcher()
        let tabSwitcher = app.collectionViews["TabSwitcher.Collection.Tabs"]
        let newTabButton = tabSwitcher.buttons["Open new tab"]
        XCTAssertTrue(newTabButton.waitForExistence(timeout: UITestTimeouts.navigation))
        let tabSwitcherCells = tabSwitcher.cells
        XCTAssertEqual(tabSwitcherCells.containing(.button, identifier: "TabSwitcher.Tab.Open").count, 1)
    }

    func testSlideToDeleteDisabledKeepsDeleteAllButton() {
        openFireConfirmationForWidthTest(slideToDelete: false, orientation: .landscapeLeft)
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

    func testSlideToDeleteLandscapeModalWidthAndRotation() {
        // This case checks the sheet's layout and drag behavior independently of the Fire animation.
        app.launchArguments += ["-com.duckduckgo.app.currentFireButtonAnimationKey", "none"]
        openFireConfirmationForWidthTest(slideToDelete: true, orientation: .portrait)
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

    private func openFireConfirmationForWidthTest(slideToDelete: Bool, orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        app.launchArguments += [
            "-ff.slideToDelete", String(slideToDelete),
            "-ff.fireMode", "true",
            "-ff.fireButtonRefinements", "true",
            // Keep automatic keyboard focus out of the Fire modal layout tests.
            "-ff.alwaysShowKeyboardOnNewTabPage", "false",
        ]
        app.launch()
        let dismissInput = app.buttons.matching(NSPredicate(format: "identifier IN %@", [
            "UnifiedToggleInput.Button.Dismiss", "Browser.OmniBar.Button.Dismiss"
        ])).firstMatch
        if dismissInput.waitForExistence(timeout: 3) { dismissInput.tap() }
        if slideToDelete && UIDevice.current.userInterfaceIdiom == .pad {
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
        for flag in ["-ff.floatingUIiOS26", "-ff.floatingUIiOS27"] {
            let indices = app.launchArguments.indices.filter { app.launchArguments[$0] == flag }
            XCTAssertEqual(indices.count, 1, "Expected one launch value for \(flag).")
            if let index = indices.first {
                app.launchArguments[index + 1] = "true"
            }
        }

        app.launchArguments += [
            "-ff.fireMode", "true",
            // The launch keyboard covers the tab switcher button, so the tap would race it.
            "-ff.alwaysShowKeyboardOnNewTabPage", "false",
        ]
        app.launch()
        app.dismissAddressBarEditing()
        let tabSwitcher = app.buttons["Browser.Toolbar.Button.TabSwitcher"]
        XCTAssertTrue(tabSwitcher.waitForHittableInAppWindow(in: app, timeout: UITestTimeouts.navigation))
        tabSwitcher.press(forDuration: 1)
        app.buttons["Browser.NewTabMenu.NewTab"].tapWhenHittable(in: app)
        app.openTabSwitcher()
        app.assertTabCount(2)
        let originalTabs = [app.tabCell(at: 0), app.tabCell(at: 1)]
        app.buttons["TabSwitcher.Button.Done"].tapWhenHittable(in: app)

        app.terminate()
        app.launchArguments.removeAll { $0 == "-clearAllDefaults" }
        app.launchArguments += [
            "-com.duckduckgo.app.autoClearActionKey", "3",
            "-com.duckduckgo.app.autoClearTimingKey", "0",
        ]
        app.launch()

        let newTabPage = app.browserWindow.scrollViews.firstMatch
        XCTAssertTrue(
            newTabPage.wait(for: NSPredicate(format: "isHittable == true"), timeout: UITestTimeouts.navigation),
            "The New Tab page did not appear after automatic tab clearing.")
        app.openTabSwitcher()
        for tab in originalTabs {
            XCTAssertFalse(tab.exists, "An original tab survived automatic tab clearing.")
        }

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
