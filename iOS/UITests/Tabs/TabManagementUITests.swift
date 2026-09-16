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
        let tabs = XCTContext.runActivity(named: "Create two tabs") { _ in
            app.openURL("https://privacy-test-pages.site", expecting: "Privacy Test Pages")
            app.openNewTab()
            app.openURL("https://www.search-company.site", expecting: "Search engine")

            app.openTabSwitcher()
            app.assertTabCount(2)
            let privacyTab = app.tabCell(at: 0)
            let searchTab = app.tabCell(at: 1)
            XCTAssertTrue(privacyTab.exists, "Privacy Test Pages tab is missing.")
            XCTAssertTrue(searchTab.exists, "Ad Click Flow tab is missing.")
            return (privacy: privacyTab, search: searchTab)
        }

        XCTContext.runActivity(named: "Switch to the first tab") { _ in
            tabs.privacy.buttons["TabSwitcher.Tab.Open"].tapWhenHittable()
            app.assertPageContains("Privacy Test Pages")
            XCTAssertFalse(app.webViews.staticTexts["Search engine"].exists, "The other tab's page is still displayed.")
        }

        XCTContext.runActivity(named: "Close the other tab and preserve the selected tab") { _ in
            app.openTabSwitcher()
            tabs.search.buttons["TabSwitcher.Tab.Close"].tapWhenHittable()
            app.assertTabCount(1)
            XCTAssertTrue(
                tabs.search.wait(for: NSPredicate(format: "exists == false"), timeout: UITestTimeouts.elementExistence),
                "The closed tab is still in the tab switcher.")
            XCTAssertTrue(tabs.privacy.exists, "Closing another tab removed the Privacy Test Pages tab.")
            app.buttons["TabSwitcher.Button.Done"].tapWhenHittable()
            app.assertPageContains("Privacy Test Pages")
        }
    }

    func testWhenBackIsTappedInChildTabThenChildClosesAndParentIsSelected() {
        XCTContext.runActivity(named: "Configure the app for the WebKit context menu") { _ in
            // Avoid XCTest's animation-idle timeouts while the WebKit context menu is open.
            app.terminate()
            app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
            app.launch()
        }

        let tabs = XCTContext.runActivity(named: "Create parent and reference tabs") { _ in
            app.openURL("https://privacy-test-pages.site", expecting: "Privacy Test Pages")
            app.openNewTab()
            app.openURL("https://www.search-company.site", expecting: "Search engine")
            app.openTabSwitcher()
            app.assertTabCount(2)
            let privacyTab = app.tabCell(at: 0)
            let searchTab = app.tabCell(at: 1)
            privacyTab.buttons["TabSwitcher.Tab.Open"].tapWhenHittable()
            app.assertPageContains("Privacy Test Pages")
            return (privacy: privacyTab, search: searchTab)
        }

        let childTab = XCTContext.runActivity(named: "Open a link in a child tab") { _ in
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
            return app.tabCell(at: 1)
        }

        XCTContext.runActivity(named: "Go back to close the child tab and select its parent") { _ in
            app.buttons["TabSwitcher.Button.Done"].tapWhenHittable()
            app.buttons["Browser.Toolbar.Button.Back"].tapWhenHittable()

            app.assertPageContains("Privacy Test Pages")
            app.openTabSwitcher()
            app.assertTabCount(2)
            XCTAssertTrue(tabs.privacy.exists)
            XCTAssertTrue(tabs.search.exists)
            XCTAssertFalse(
                childTab.exists,
                "Back did not close the child tab.")
        }
    }

    func testWhenTabSwitcherStyleIsChangedThenGridAndListLayoutsAreApplied() {
        XCTContext.runActivity(named: "Open the default grid tab switcher") { _ in
            app.openTabSwitcher()
            app.assertTabCount(1)
        }

        let tab = app.tabCell(at: 0)
        let styleButton = app.buttons["TabSwitcher.Button.ViewStyle"]
        XCTAssertTrue(styleButton.waitForExistence(timeout: UITestTimeouts.elementExistence))
        XCTAssertEqual(styleButton.label, "Switch to list view")
        let gridCellHeight = tab.frame.height

        XCTContext.runActivity(named: "Switch to list view") { _ in
            styleButton.tapWhenHittable()
            XCTAssertTrue(
                styleButton.wait(for: NSPredicate(format: "label == %@", "Switch to grid view"), timeout: UITestTimeouts.elementExistence),
                "The tab switcher did not change to list view.")
            XCTAssertTrue(
                waitForHeight(of: tab, satisfying: { $0 < gridCellHeight }),
                "The list tab cell did not become shorter than the grid tab cell.")
        }

        let listCellHeight = tab.frame.height
        XCTContext.runActivity(named: "Switch back to grid view") { _ in
            styleButton.tapWhenHittable()
            XCTAssertTrue(
                styleButton.wait(for: NSPredicate(format: "label == %@", "Switch to list view"), timeout: UITestTimeouts.elementExistence),
                "The tab switcher did not change back to grid view.")
            XCTAssertTrue(
                waitForHeight(of: tab, satisfying: { $0 > listCellHeight }),
                "The grid tab cell did not become taller than the list tab cell.")
        }
    }

    func testWhenTabsAreSelectedThenSelectionStateUpdatesAndSelectedTabCanBeClosed() {
        XCTContext.runActivity(named: "Create two tabs") { _ in
            app.openNewTab()
            app.openURL("https://privacy-test-pages.site", expecting: "Privacy Test Pages")
            app.openTabSwitcher()
            app.assertTabCount(2)
        }

        XCTContext.runActivity(named: "Enter selection mode") { _ in
            app.buttons["TabSwitcher.Button.Edit"].tapWhenHittable()
            app.buttons["TabSwitcher.Menu.SelectTabs"].tapWhenHittable()
            app.assertTabSwitcherTitle("2 Private Tabs")
        }

        XCTContext.runActivity(named: "Select and deselect all tabs") { _ in
            app.buttons["TabSwitcher.Button.SelectAll"].tapWhenHittable()
            app.assertTabSwitcherTitle("2 Selected")
            app.buttons["TabSwitcher.Button.DeselectAll"].tapWhenHittable()
            app.assertTabSwitcherTitle("2 Private Tabs")
            XCTAssertTrue(app.buttons["TabSwitcher.Button.SelectAll"].exists)
        }

        XCTContext.runActivity(named: "Close one selected tab") { _ in
            app.tabCell(at: 0).buttons["TabSwitcher.Tab.Open"].tapWhenHittable()
            app.assertTabSwitcherTitle("1 Selected")

            app.buttons["TabSwitcher.Button.More"].tapWhenHittable()
            app.buttons["TabSwitcher.Menu.CloseSelected"].tapWhenHittable()

            app.buttons
                .matching(identifier: "TabSwitcher.CloseTabs.Confirm")
                .firstMatch
                .tapWhenHittable()

            app.assertTabCount(1)
            app.assertTabSwitcherTitle("1 Private Tab")
        }

        XCTContext.runActivity(named: "Exit selection mode") { _ in
            app.buttons["TabSwitcher.Button.Done"].tapWhenHittable()
            XCTAssertTrue(app.buttons["TabSwitcher.Button.ViewStyle"].waitForExistence(timeout: UITestTimeouts.elementExistence))
        }
    }

    func testWhenTabIsLongPressedThenSelectionModeStartsWithThatTabSelected() {
        XCTContext.runActivity(named: "Long-press a home tab") { _ in
            app.openTabSwitcher()
            app.assertTabCount(1)
            app.tabCell(at: 0).buttons["TabSwitcher.Tab.Open"].press(forDuration: 1)
            app.buttons["TabSwitcher.Menu.SelectTab"].tapWhenHittable()
        }

        XCTContext.runActivity(named: "Verify and exit selection mode") { _ in
            app.assertTabSwitcherTitle("1 Selected")
            app.buttons["TabSwitcher.Button.Done"].tapWhenHittable()
            XCTAssertTrue(app.buttons["TabSwitcher.Button.ViewStyle"].waitForExistence(timeout: UITestTimeouts.elementExistence))
        }
    }

    private func waitForHeight(of element: XCUIElement, satisfying condition: @escaping (CGFloat) -> Bool) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return condition(element.frame.height)
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: UITestTimeouts.elementExistence) == .completed
    }
}
