//
//  SettingsPersistenceTests.swift
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

class SettingsPersistenceTests: UITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()
    }

    func testFavoritesVisibilityIsPersistedThroughWindowCloseAndRestart() {
        restoreOnTeardown {
            self.favoritesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: self.app.ensureHittable)
        }
        openAppearanceSettings()
        favoritesToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: app.ensureHittable)

        app.closeWindow()
        XCTAssertTrue(app.windows.firstMatch.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "The window should close")
        app.openNewWindow()
        openAppearanceSettings()
        XCTAssertEqual(favoritesToggle.value as? Bool, false, "Hidden Favorites should stay hidden after closing the window")

        app.restart(forceTerminate: true)
        app.enforceSingleWindow()
        openAppearanceSettings()
        XCTAssertEqual(favoritesToggle.value as? Bool, false, "Hidden Favorites should stay hidden after restarting the browser")
    }

    func testThemeAppearanceIsPersistedThroughRestart() {
        restoreOnTeardown {
            self.themeAppearanceOption("System").clickAfterExistenceTestSucceeds()
            XCTAssertTrue(self.themeAppearanceOption("System").wait(for: \.isSelected, equals: true, timeout: UITests.Timeouts.elementExistence),
                          "System should be selected again after the test")
        }
        for appearance in ["Dark", "Light"] {
            openAppearanceSettings()
            themeAppearanceOption(appearance).clickAfterExistenceTestSucceeds()
            XCTAssertTrue(themeAppearanceOption(appearance).wait(for: \.isSelected, equals: true, timeout: UITests.Timeouts.elementExistence),
                          "\(appearance) should be selected after clicking it")

            app.restart(forceTerminate: true)
            app.enforceSingleWindow()
            openAppearanceSettings()
            XCTAssertTrue(themeAppearanceOption(appearance).wait(for: \.isSelected, equals: true, timeout: UITests.Timeouts.elementExistence),
                          "\(appearance) should still be selected after restarting the browser")
        }
    }

    // MARK: - Utilities

    /// The settings persist across launches, so they're restored on every exit path, failed assertions included,
    /// to keep later test classes from inheriting them.
    private func restoreOnTeardown(_ restore: @escaping () -> Void) {
        addTeardownBlock {
            if self.app.state != .runningForeground {
                self.app.restart(forceTerminate: true)
            }
            self.app.enforceSingleWindow()
            self.openAppearanceSettings()
            restore()
        }
    }

    private var favoritesToggle: XCUIElement {
        app.preferencesWindow.checkBoxes["Preferences.AppearanceView.showFavoritesToggle"]
    }

    /// The picker options have no identifiers; their label combines the icon and the "System", "Light" or "Dark" title.
    private func themeAppearanceOption(_ title: String) -> XCUIElement {
        app.preferencesWindow.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    private func openAppearanceSettings() {
        app.openSettings()
        app.preferencesGoToAppearancePane()
        app.scrollIntoViewInPreferences(favoritesToggle)
    }
}
