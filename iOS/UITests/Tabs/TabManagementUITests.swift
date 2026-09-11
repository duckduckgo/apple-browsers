//
//  TabManagementUITests.swift
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

final class TabManagementUITests: UITestCase {

    func testWhenTabsAreCreatedSwitchedAndClosedThenRemainingTabIsPreserved() {
        app.openURL("https://privacy-test-pages.site", expecting: "Privacy Test Pages")
        app.openNewTab()
        app.openURL("https://www.search-company.site", expecting: "Search engine")

        app.openTabSwitcher()
        app.assertTabCount(2)
        let privacyTab = app.tabCell(at: 0)
        let searchTab = app.tabCell(at: 1)
        XCTAssertTrue(privacyTab.exists, "Privacy Test Pages tab is missing.")
        XCTAssertTrue(searchTab.exists, "Ad Click Flow tab is missing.")
        privacyTab.buttons["TabSwitcher.Tab.Open"].tapWhenHittable()

        app.assertPageContains("Privacy Test Pages")
        XCTAssertFalse(app.webViews.staticTexts["Search engine"].exists, "The other tab's page is still displayed.")

        app.openTabSwitcher()
        searchTab.buttons["TabSwitcher.Tab.Close"].tapWhenHittable()
        app.assertTabCount(1)
        XCTAssertTrue(
            searchTab.wait(for: NSPredicate(format: "exists == false"), timeout: UITestTimeouts.elementExistence),
            "The closed tab is still in the tab switcher.")
        XCTAssertTrue(privacyTab.exists, "Closing another tab removed the Privacy Test Pages tab.")
        app.buttons["TabSwitcher.Button.Done"].tapWhenHittable()
        app.assertPageContains("Privacy Test Pages")
    }

    func testWhenBackIsTappedInChildTabThenChildClosesAndParentIsSelected() {
        // Avoid XCTest's animation-idle timeouts while the WebKit context menu is open.
        app.terminate()
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launch()

        app.openURL("https://privacy-test-pages.site", expecting: "Privacy Test Pages")
        app.openNewTab()
        app.openURL("https://www.search-company.site", expecting: "Search engine")
        app.openTabSwitcher()
        app.assertTabCount(2)
        let privacyTab = app.tabCell(at: 0)
        let searchTab = app.tabCell(at: 1)
        privacyTab.buttons["TabSwitcher.Tab.Open"].tapWhenHittable()
        app.assertPageContains("Privacy Test Pages")

        let link = app.webViews.links["1 major tracker loaded via script"]
        XCTAssertTrue(
            link.wait(for: NSPredicate(format: "isHittable == true"), timeout: UITestTimeouts.elementExistence),
            "The link to open in a child tab is not tappable.")
        link.press(forDuration: 1)
        app.buttons["Browser.LinkMenu.OpenInNewTab"].tapWhenHittable()
        app.assertPageContains("1 major tracker loaded via script src")

        // Verify a child was created, rather than navigating the parent in place.
        app.openTabSwitcher()
        app.assertTabCount(3)
        // The child is inserted immediately after its parent, before the search tab.
        let childTab = app.tabCell(at: 1)
        app.buttons["TabSwitcher.Button.Done"].tapWhenHittable()
        app.buttons["Browser.Toolbar.Button.Back"].tapWhenHittable()

        app.assertPageContains("Privacy Test Pages")
        app.openTabSwitcher()
        app.assertTabCount(2)
        XCTAssertTrue(privacyTab.exists)
        XCTAssertTrue(searchTab.exists)
        XCTAssertFalse(
            childTab.exists,
            "Back did not close the child tab.")
    }
}
