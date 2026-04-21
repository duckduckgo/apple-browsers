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
            "tabSuspensionDebugging": true
        ])
        app.openNewWindow()
    }

    // MARK: - Tests

    func testInactiveBackgroundTabGetsSuspendedOnMemoryPressure() {
        // Enable short inactivity interval (5s) via the debug menu
        enableShortInactivityInterval()

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
        suspendedTab.rightClick()
        let resumeMenuItem = app.menuItems["Resume Tab"]
        XCTAssertTrue(
            resumeMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Suspended tab's context menu should show 'Resume Tab'"
        )
        app.typeKey(.escape, modifierFlags: [])

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

        enableShortInactivityInterval()

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
        tab.rightClick()
        let resumeMenuItem = app.menuItems["Resume Tab"]
        XCTAssertTrue(
            resumeMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Tab without input focus should be suspended and show 'Resume Tab'"
        )
        app.typeKey(.escape, modifierFlags: [])

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
        tabAfterFocus.rightClick()
        let suspendMenuItem = app.menuItems["Suspend Tab"]
        XCTAssertTrue(
            suspendMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Tab with input focus should NOT be suspended and show 'Suspend Tab'"
        )
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - Helpers

    private func simulateCriticalMemoryPressure() {
        app.debugMenu.click()
        let memoryReportingMenu = app.menuItems["Memory Usage Reporting"]
        XCTAssertTrue(
            memoryReportingMenu.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Memory Usage Reporting menu didn't appear"
        )
        memoryReportingMenu.click()

        let simulateMenuItem = app.menuItems["Simulate Memory Pressure (Critical)"]
        XCTAssertTrue(
            simulateMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Simulate Memory Pressure menu item didn't appear"
        )
        simulateMenuItem.click()
    }

    private func enableShortInactivityInterval() {
        app.debugMenu.click()
        let tabSuspensionMenu = app.menuItems["Tab Suspension"]
        XCTAssertTrue(
            tabSuspensionMenu.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Tab Suspension menu didn't appear"
        )
        tabSuspensionMenu.click()

        let shortIntervalMenuItem = app.menuItems["Use Short Inactivity Interval (5s)"]
        XCTAssertTrue(
            shortIntervalMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Short Inactivity Interval menu item didn't appear"
        )
        shortIntervalMenuItem.click()
    }
}
