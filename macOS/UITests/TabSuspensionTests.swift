//
//  TabSuspensionTests.swift
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

class TabSuspensionTests: UITestCase {

    private let pageTitle = "Suspension Test Page"

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp(featureFlags: [
            "tabSuspension": true,
            "tabSuspensionDebugging": true,
            "aiChatChromeSidebar": true,  // sidebar and floating sidebar feature flags
            "aiChatSidebarFloating": true // are required for testing AI Chat sidebar suspension
        ])
        app.openNewWindow()
    }

    // MARK: - Tests

    func testInactiveBackgroundTabGetsSuspendedOnMemoryPressure() {
        // Open a page in the current tab
        app.openSite(pageTitle: pageTitle)

        // Open a new tab so the first tab becomes a background tab
        app.openNewTab()

        // Wait for the inactivity interval to elapse
        Thread.sleep(forTimeInterval: 6)

        // Simulate critical memory pressure via the debug menu
        simulateCriticalMemoryPressure()

        // Verify the background tab is suspended by checking its context menu
        let suspendedTab = app.tabGroups.matching(identifier: "Tabs").radioButtons[pageTitle]
        XCTAssertTrue(
            suspendedTab.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Background tab should still exist in the tab bar after suspension"
        )
        assertIsSuspended(suspendedTab, expected: true, "Background tab should be suspended after memory pressure")

        // Switch back to the first tab — selecting a suspended tab triggers a reload
        app.typeKey("1", modifierFlags: [.command])

        let webView = app.windows.firstMatch.webViews[pageTitle]
        XCTAssertTrue(
            webView.waitForExistence(timeout: UITests.Timeouts.navigation),
            "Suspended tab should reload its web view after being selected"
        )
    }

    func testWhenTabHadInputFocusThenItIsNotSuspended() throws {
        throw XCTSkip("Disabled until the C-S-S feature is released publicly")

        let inputPageTitle = "Input Focus Test Page"
        let inputPageURL = UITests.simpleServedPage(
            titled: inputPageTitle,
            body: "<input type=\"text\" id=\"testInput\" />"
        )

        // First: open a page without focusing the input, verify it gets suspended
        app.openURL(inputPageURL)
        app.openNewTab()

        Thread.sleep(forTimeInterval: 6)
        simulateCriticalMemoryPressure()

        let tab = app.tabGroups.matching(identifier: "Tabs").radioButtons[inputPageTitle]
        XCTAssertTrue(
            tab.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Tab should still exist in the tab bar"
        )
        assertIsSuspended(tab, expected: true, "Tab without input focus should be suspended")

        // Resume the tab for the second part of the test
        app.typeKey("1", modifierFlags: [.command])
        let webView = app.windows.firstMatch.webViews[inputPageTitle]
        XCTAssertTrue(
            webView.waitForExistence(timeout: UITests.Timeouts.navigation),
            "Tab should reload after being selected"
        )

        // Second: focus the input field, then switch away and verify it's NOT suspended
        let inputField = webView.textFields.firstMatch
        XCTAssertTrue(
            inputField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Input field should exist on the page"
        )
        inputField.click()

        app.typeKey("2", modifierFlags: [.command])

        Thread.sleep(forTimeInterval: 6)
        simulateCriticalMemoryPressure()

        let tabAfterFocus = app.tabGroups.matching(identifier: "Tabs").radioButtons[inputPageTitle]
        XCTAssertTrue(
            tabAfterFocus.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Tab should still exist in the tab bar"
        )
        assertIsSuspended(tabAfterFocus, expected: false, "Tab with input focus should not be suspended")
    }

    func testThatInternalPagesAndDuckAIAreNotSuspended() {
        // Open Duck.ai in tab 1
        app.openURL(URL(string: "https://duck.ai")!)
        let duckAITab = app.tabGroups.matching(identifier: "Tabs").radioButtons.firstMatch
        XCTAssertTrue(
            duckAITab.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Settings tab should exist"
        )

        // Open History in tab 2
        app.openHistory()
        let historyTab = app.tabGroups.matching(identifier: "Tabs").radioButtons["History"]
        XCTAssertTrue(
            historyTab.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "History tab should exist"
        )

        // Open Release Notes in tab 3
        app.openNewTab()
        let addressBar = app.addressBar
        XCTAssertTrue(addressBar.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        addressBar.typeURL(URL(string: "duck://release-notes")!)
        let releaseNotesTab = app.tabGroups.matching(identifier: "Tabs").radioButtons["Release Notes"]
        XCTAssertTrue(
            releaseNotesTab.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Release Notes tab should exist"
        )

        // Open a new tab so all internal pages are background tabs
        app.openNewTab()

        Thread.sleep(forTimeInterval: 6)
        simulateCriticalMemoryPressure()

        // Verify none of the internal tabs were suspended
        for (name, tab) in [
            ("Duck.ai", duckAITab),
            ("History", historyTab),
            ("Release Notes", releaseNotesTab)
        ] {
            XCTAssertTrue(tab.waitForExistence(timeout: UITests.Timeouts.elementExistence), "\(name) tab should still exist")
            assertIsSuspended(tab, expected: false, "\(name) tab should not be suspended")
        }
    }

    func testThatTabsWithAIChatAreNotSuspended() {
        let tabs = app.tabGroups.matching(identifier: "Tabs")
        let sidebarButton = app.buttons["TabBarViewController.duckAIChromeSidebarButton"]

        // Tab 1: plain page (no AI Chat)
        let tab1Title = "Plain Page"
        app.openSite(pageTitle: tab1Title)

        // Tab 2: page with docked AI Chat sidebar
        let tab2Title = "Docked Sidebar Page"
        app.openNewTab()
        app.openSite(pageTitle: tab2Title)
        sidebarButton.click()
        XCTAssertTrue(
            waitForButtonTitle(sidebarButton, expectedTitle: "Close Duck.ai sidebar"),
            "AI Chat sidebar should open"
        )

        // Tab 3: page where AI Chat sidebar was opened and closed
        let tab3Title = "Closed Sidebar Page"
        app.openNewTab()
        app.openSite(pageTitle: tab3Title)
        sidebarButton.click()
        XCTAssertTrue(
            waitForButtonTitle(sidebarButton, expectedTitle: "Close Duck.ai sidebar"),
            "AI Chat sidebar should open on tab 3"
        )
        sidebarButton.click()
        XCTAssertTrue(
            waitForButtonTitle(sidebarButton, expectedTitle: "Open Duck.ai sidebar"),
            "AI Chat sidebar should close on tab 3"
        )

        // Tab 4: page with detached (floating) AI Chat sidebar
        let tab4Title = "Floating Sidebar Page"
        app.openNewTab()
        app.openSite(pageTitle: tab4Title)
        sidebarButton.click()
        XCTAssertTrue(
            waitForButtonTitle(sidebarButton, expectedTitle: "Close Duck.ai sidebar"),
            "AI Chat sidebar should open before detaching"
        )
        let detachButton = app.buttons["AIChatViewController.detachButton"]
        XCTAssertTrue(
            detachButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Detach button should exist in the sidebar"
        )
        detachButton.click()
        XCTAssertTrue(
            waitForButtonTitle(sidebarButton, expectedTitle: "Show Duck.ai"),
            "Sidebar should be detached into a floating panel"
        )

        // Re-focus the main window after detaching (floating panel takes focus)
        tabs.radioButtons[tab4Title].click()

        // Tab 5: new empty tab to push others to background
        app.openNewTab()

        Thread.sleep(forTimeInterval: 6)
        simulateCriticalMemoryPressure()

        // Tab 1 should be suspended (no AI Chat session)
        let tab1 = tabs.radioButtons[tab1Title]
        XCTAssertTrue(tab1.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Tab 1 should exist")
        assertIsSuspended(tab1, expected: true, "Tab without AI Chat should be suspended")

        // Tab 2 should NOT be suspended (docked sidebar session)
        let tab2 = tabs.radioButtons[tab2Title]
        XCTAssertTrue(tab2.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Tab 2 should exist")
        assertIsSuspended(tab2, expected: false, "Tab with docked AI Chat sidebar should not be suspended")

        // Tab 3 should NOT be suspended (closed sidebar still has a session)
        let tab3 = tabs.radioButtons[tab3Title]
        XCTAssertTrue(tab3.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Tab 3 should exist")
        assertIsSuspended(tab3, expected: false, "Tab with closed AI Chat sidebar should not be suspended")

        // Tab 4 should NOT be suspended (detached/floating sidebar session)
        let tab4 = tabs.radioButtons[tab4Title]
        XCTAssertTrue(tab4.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Tab 4 should exist")
        assertIsSuspended(tab4, expected: false, "Tab with floating AI Chat sidebar should not be suspended")
    }

    func testThatPinnedTabsCannotBeSuspended() {
        // Tab 1: pinned tab
        let tab1Title = "Pinned Page 1"
        app.openSite(pageTitle: tab1Title)
        app.pinCurrentTab()
        XCTAssertTrue(
            app.wait(for: .keyPath(\.pinnedTabs.count, equalTo: 1), timeout: UITests.Timeouts.elementExistence),
            "Should have 1 pinned tab"
        )

        // Tab 2: another pinned tab
        let tab2Title = "Pinned Page 2"
        app.openNewTab()
        app.openSite(pageTitle: tab2Title)
        app.pinCurrentTab()
        XCTAssertTrue(
            app.wait(for: .keyPath(\.pinnedTabs.count, equalTo: 2), timeout: UITests.Timeouts.elementExistence),
            "Should have 2 pinned tabs"
        )

        // Tab 3: unpinned tab to push pinned tabs to background
        app.openNewTab()

        Thread.sleep(forTimeInterval: 6)
        simulateCriticalMemoryPressure()

        // Verify neither pinned tab was suspended
        // Close each tab after verifying to clean up after the test
        let pinnedTab1 = app.pinnedTabs[tab1Title]
        XCTAssertTrue(pinnedTab1.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Pinned tab 1 should exist")
        assertIsSuspended(pinnedTab1, expected: false, "Pinned tab 1 should not be suspended")
        pinnedTab1.rightClick()
        app.menuItems["closeButtonAction:"].click()

        let pinnedTab2 = app.pinnedTabs[tab2Title]
        XCTAssertTrue(pinnedTab2.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Pinned tab 2 should exist")
        assertIsSuspended(pinnedTab2, expected: false, "Pinned tab 2 should not be suspended")
        pinnedTab2.rightClick()
        app.menuItems["closeButtonAction:"].click()

        // wait a bit to allow persistent state to get updated with 0 tabs
        Thread.sleep(forTimeInterval: 2)
    }

    func testThatFireWindowTabsCannotBeSuspended() {
        app.openFireWindow()

        let firePageTitle = "Fire Window Page"
        app.openSite(pageTitle: firePageTitle)

        app.openNewTab()

        Thread.sleep(forTimeInterval: 6)
        simulateCriticalMemoryPressure()

        let tab = app.tabGroups.matching(identifier: "Tabs").radioButtons[firePageTitle]
        XCTAssertTrue(
            tab.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Fire Window tab should still exist"
        )
        assertIsSuspended(tab, expected: false, "Fire Window tab should not be suspended")
    }

    // MARK: - Helpers

    private func assertIsSuspended(_ tab: XCUIElement, expected: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        tab.rightClick()
        let menuItemTitle = expected ? "isSuspended: true" : "isSuspended: false"
        XCTAssertTrue(
            app.menuItems[menuItemTitle].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            message,
            file: file,
            line: line
        )
        app.typeKey(.escape, modifierFlags: [])
    }

    private func waitForButtonTitle(_ button: XCUIElement, expectedTitle: String) -> Bool {
        let predicate = NSPredicate(format: "title == %@", expectedTitle)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: button)
        return XCTWaiter.wait(for: [expectation], timeout: UITests.Timeouts.elementExistence) == .completed
    }

    private func simulateCriticalMemoryPressure() {
        app.debugMenu.click()

        let searchField = app.searchFields["Search debug menu…"]
        XCTAssertTrue(
            searchField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Debug menu search field didn't appear"
        )
        searchField.typeText("Simulate Memory Pressure")

        let simulateMenuItem = app.menuItems["Simulate Memory Pressure (Critical)"]
        XCTAssertTrue(
            simulateMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Simulate Memory Pressure menu item didn't appear"
        )
        simulateMenuItem.click()
    }
}
