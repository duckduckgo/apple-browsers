//
//  BackgroundingUITests.swift
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

final class BackgroundingUITests: UITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        app.resetBookmarks()
    }

    func testWhenAppIsBackgroundedFromPageAndNewTabThenBrowserStateAndControlsRemainAvailable() {
        XCTContext.runActivity(named: "Restore a loaded page after backgrounding") { _ in
            app.openURL("https://privacy-test-pages.site", expecting: "Privacy Test Pages")
            app.backgroundAndActivate()

            app.assertPageContains("Privacy Test Pages")
            app.openBrowsingMenuItem("Browser.Menu.AddBookmark")

            app.descendants(matching: .any)["privacy-icon-shield.button"].firstMatch.tapWhenHittable()
            XCTAssertTrue(
                app.switches["Disable Protections"].wait(
                    for: NSPredicate(format: "value == %@", "1"),
                    timeout: UITestTimeouts.elementExistence),
                "Privacy protections did not appear after backgrounding.")
            app.buttons["Done"].tapWhenHittable()
        }

        XCTContext.runActivity(named: "Use browser surfaces after backgrounding a new tab") { _ in
            app.openNewTab()
            app.backgroundAndActivate()

            XCTAssertTrue(
                app.searchEntry.wait(for: NSPredicate(format: "isHittable == true"), timeout: UITestTimeouts.elementExistence),
                "New tab did not become interactive after backgrounding.")
            app.dismissAddressBarEditing()

            app.openSettings()
            app.dismissSettings()

            app.openBookmarks()
            XCTAssertTrue(
                app.staticTexts["Privacy Test Pages - Home"].waitForExistence(timeout: UITestTimeouts.elementExistence),
                "Bookmark created before backgrounding is missing.")
            app.buttons["Bookmarks.Done"].tapWhenHittable()

            app.openTabSwitcher()
            app.assertTabCount(2)
        }
    }
}
