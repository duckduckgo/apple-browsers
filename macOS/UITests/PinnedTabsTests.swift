//
//  PinnedTabsTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

class PinnedTabsTests: UITestCase {
    private static let failureObserver = TestFailureObserver()
    var featureFlags: [String: Bool] {
        [:]
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp(featureFlags: featureFlags)

        app.openNewWindow()
    }

    func testPinnedTabsFunctionality() {
        app.disableWarnBeforeQuitting(closeSettings: false)
        app.disableWarnBeforeClosingPinnedTabs(closeSettings: true)

        openThreeSitesOnSameWindow()
        openNewWindowAndLoadSite()
        moveBackToPreviousWindows()

        waitForSite(pageTitle: "Page #3")
        pinPageOne()
        pinPageTwo()
        assertsPageTwoIsPinned()
        assertsPageOneIsPinned()
        dragsPageTwoPinnedTabToTheFirstPosition()
        assertsCommandWFunctionality()
        assertWindowTwoHasNoPinnedTabsFromWindowsOne()

        pinCurrentPage()
        XCTAssertTrue(
            app.wait(for: .keyPath(\.pinnedTabs.count, equalTo: 2), timeout: UITests.Timeouts.elementExistence),
            "Should have 2 pinned tabs after pinning current page"
        )

        app.typeKey("q", modifierFlags: .command)
        assertPinnedTabsRestoredState()
    }

    func testPinnedStateCanBeEffectivelySetAndUnset() {
        app.openNewTab()
        pinCurrentPage()
        unpinCurrentPage()
        assertCurrentPageCanBePinned()
    }

    func testSettingsCanBePinned() {
        app.openSettings()
        pinCurrentPage()
        assertCurrentPageCanBeUnpinned()
    }

    func testBookmarksCanBePinned() {
        app.openBookmarksManager()
        pinCurrentPage()
        assertCurrentPageCanBeUnpinned()
    }

    func testHistoryCanBePinned() {
        app.openHistory()
        pinCurrentPage()
        assertCurrentPageCanBeUnpinned()
    }

    func testNewTabPageCanBePinned() {
        app.openNewTab()
        pinCurrentPage()
        assertCurrentPageCanBeUnpinned()
    }

    func testReleaseNotesCannotBePinned() {
        app.openHelp()
        app.openReleaseNotes()
        assertCurrentPageCannotBePinned()
    }

    func testUnpinnedTabCanBeDraggedIntoNewWindowAndMapsIntoAnUnpinnedTab() {
        app.closeAllWindows()
        app.openNewWindow()

        app.openNewTab()
        app.openNewTab()
        pinCurrentPage()

        dragLastUnpinnedTabAboveWindow()
        waitForSecondWindow()

        bringForemostWindowToForeground()
        assertCurrentPageCanBePinned()
    }

    func testPinnedTabCannotBeDraggedIntoNewWindow() {
        app.closeAllWindows()
        app.openNewWindow()

        app.openNewTab()
        pinCurrentPage()

        dragFirstPinnedTabAboveWindow()
        assertSingleWindowScenario()
    }

    func testDraggingOnlyTabAboveWindowDoesNotResultInNewWindowBeingCreated() {
        app.closeAllWindows()
        app.openNewWindow()

        dragLastUnpinnedTabAboveWindow()
        assertSingleWindowScenario()
    }

    // MARK: - Utilities

    private func openThreeSitesOnSameWindow() {
        app.openSite(pageTitle: "Page #1")
        app.openNewTab()
        app.openSite(pageTitle: "Page #2")
        app.openNewTab()
        app.openSite(pageTitle: "Page #3")
    }

    private func openNewWindowAndLoadSite() {
        app.openNewWindow()
        app.openSite(pageTitle: "Page #4")
    }

    private func moveBackToPreviousWindows(file: StaticString = #file, line: UInt = #line) {
        let menuItem = app.menuItems["Page #3"].firstMatch
        XCTAssertTrue(
            menuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Reset bookmarks menu item didn't become available in a reasonable timeframe (line \(#line))",
            file: file,
            line: line
        )
        menuItem.hover()
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
    }

    private func pinPageOne() {
        app.typeKey("[", modifierFlags: [.command, .shift])
        app.typeKey("[", modifierFlags: [.command, .shift])
        pinCurrentPage()
    }

    private func pinPageTwo() {
        app.typeKey("]", modifierFlags: [.command, .shift])
        pinCurrentPage()
    }

    private func pinCurrentPage() {
        app.menuItems["Pin Tab"].tap()
    }

    private func unpinCurrentPage() {
        app.menuItems["Unpin Tab"].tap()
    }

    private func assertsPageTwoIsPinned(file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(
            app.menuItems["Unpin Tab"].firstMatch.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Unpin Tab menu item should exist for Page #2 (line \(#line))",
            file: file,
            line: line
        )
        XCTAssertTrue(
            app.menuItems["Unpin Tab"].firstMatch.exists,
            "Unpin Tab menu item should be present (line \(#line))",
            file: file,
            line: line
        )
        XCTAssertFalse(
            app.menuItems["Pin Tab"].firstMatch.exists,
            "Pin Tab menu item should not exist when tab is pinned (line \(#line))",
            file: file,
            line: line
        )
    }

    private func assertsPageOneIsPinned(file: StaticString = #file, line: UInt = #line) {
        app.typeKey("[", modifierFlags: [.command, .shift])
        XCTAssertTrue(
            app.menuItems["Unpin Tab"].firstMatch.exists,
            "Unpin Tab menu item should exist for Page #1 (line \(#line))",
            file: file,
            line: line
        )
        XCTAssertFalse(
            app.menuItems["Pin Tab"].firstMatch.exists,
            "Pin Tab menu item should not exist when tab is pinned (line \(#line))",
            file: file,
            line: line
        )
    }

    private func dragsPageTwoPinnedTabToTheFirstPosition(file: StaticString = #file, line: UInt = #line) {
        app.typeKey("]", modifierFlags: [.command, .shift])
        let pinnedTab2 = app.pinnedTabs.element(boundBy: 1)
        let pinnedTab1 = app.pinnedTabs.element(boundBy: 0)
        let startPoint = pinnedTab2.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let endPoint = pinnedTab1.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        startPoint.press(forDuration: 0, thenDragTo: endPoint)

        sleep(1)

        /// Asserts the re-order worked by moving to the next tab and checking is Page #1
        app.typeKey("]", modifierFlags: [.command, .shift])
        XCTAssertTrue(
            app.staticTexts["Sample text for Page #1"].exists,
            "Page #1 should be displayed after tab reorder (line \(#line))",
            file: file,
            line: line
        )
    }

    private func assertsCommandWFunctionality(file: StaticString = #file, line: UInt = #line) {
        app.closeCurrentTab()
        XCTAssertTrue(
            app.staticTexts["Sample text for Page #3"].exists,
            "Should switch to Page #3 after closing pinned tab (line \(#line))",
            file: file,
            line: line
        )
    }

    private func assertWindowTwoHasNoPinnedTabsFromWindowsOne(file: StaticString = #file, line: UInt = #line) {
        let items = app.menuItems.matching(identifier: "Page #4")
        let pageFourMenuItem = items.element(boundBy: 1)
        XCTAssertTrue(
            pageFourMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Reset bookmarks menu item didn't become available in a reasonable timeframe (line \(#line))",
            file: file,
            line: line
        )
        pageFourMenuItem.hover()
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        sleep(1)

        /// Goes to Page #2 to check the state
        app.typeKey("[", modifierFlags: [.command, .shift])
        app.typeKey("[", modifierFlags: [.command, .shift])
        XCTAssertFalse(
            app.staticTexts["Sample text for Page #2"].exists,
            "Page #2 should not exist in window 2 (line \(#line))",
            file: file,
            line: line
        )
        /// Goes to Page #1 to check the state
        app.typeKey("]", modifierFlags: [.command, .shift])
        XCTAssertFalse(
            app.staticTexts["Sample text for Page #1"].exists,
            "Page #1 should not exist in window 2 (line \(#line))",
            file: file,
            line: line
        )

        app.closeWindow()
    }

    private func assertPinnedTabsRestoredState(file: StaticString = #file, line: UInt = #line) {
        app = XCUIApplication.setUp(featureFlags: featureFlags)
        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "App window didn't become available in a reasonable timeframe (line \(#line))",
            file: file,
            line: line
        )

        XCTAssertEqual(
            app.pinnedTabs.count,
            2,
            "Should have 2 pinned tabs after app restart (line \(#line))",
            file: file,
            line: line
        )

        /// Goes to Page #2 to check the state
        app.typeKey("[", modifierFlags: [.command, .shift])
        app.typeKey("[", modifierFlags: [.command, .shift])
        XCTAssertTrue(
            app.staticTexts["Sample text for Page #2"].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Page #2 should exist (line \(#line))",
            file: file,
            line: line
        )
        /// Goes to Page #1 to check the state
        app.typeKey("]", modifierFlags: [.command, .shift])
        XCTAssertTrue(
            app.staticTexts["Sample text for Page #3"].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Page #3 should exist (line \(#line))",
            file: file,
            line: line
        )
    }

    private func assertCurrentPageCanBeUnpinned(file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(
            app.menuItems["Unpin Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Unpin Tab menu item should be available (line \(#line))",
            file: file,
            line: line
        )
    }

    private func assertCurrentPageCanBePinned(file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(
            app.menuItems["Pin Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Pin Tab menu item should be available (line \(#line))",
            file: file,
            line: line
        )
    }

    private func assertCurrentPageCannotBePinned(file: StaticString = #file, line: UInt = #line) {
        let pinItem = app.menuItems["Pin Tab"]

        XCTAssertTrue(
            pinItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Pin Tab menu item didn't become available in a reasonable timeframe (line \(#line))",
            file: file,
            line: line
        )
        XCTAssertFalse(
            pinItem.isHittable,
            "Pin Tab menu item should not be hittable for release notes (line \(#line))",
            file: file,
            line: line
        )
    }

    private func waitForSite(pageTitle: String, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(
            app.windows.webViews[pageTitle].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Web view for '\(pageTitle)' should exist (line \(#line))",
            file: file,
            line: line
        )
    }

    private func waitForSecondWindow(file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(
            app.windows.element(boundBy: 1).waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Second window should exist (line \(#line))",
            file: file,
            line: line
        )
        XCTAssertEqual(
            app.windows.count,
            2,
            "Should have exactly 2 windows (line \(#line))",
            file: file,
            line: line
        )
    }

    private func assertSingleWindowScenario(file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(
            app.windows.count,
            1,
            "Should have exactly 1 window (line \(#line))",
            file: file,
            line: line
        )
    }

    private func bringForemostWindowToForeground() {
        app.windows.element(boundBy: 0).click()
    }

    private func dragFirstPinnedTabAboveWindow(file: StaticString = #file, line: UInt = #line) {
        let pinnedTabs = app.tabGroups.matching(identifier: "Pinned Tabs").radioButtons
        let firstPinnedTab = pinnedTabs.element(boundBy: .zero)
        XCTAssertTrue(
            firstPinnedTab.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "First pinned tab should exist (line \(#line))",
            file: file,
            line: line
        )

        dragTabElementAboveWindow(firstPinnedTab)
    }

    private func dragLastUnpinnedTabAboveWindow(file: StaticString = #file, line: UInt = #line) {
        let unpinnedTabs = app.tabGroups.matching(identifier: "Tabs").radioButtons
        let lastUnpinnedTab = unpinnedTabs.element(boundBy: unpinnedTabs.count - 1)
        XCTAssertTrue(
            lastUnpinnedTab.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Last unpinned tab should exist (line \(#line))",
            file: file,
            line: line
        )

        dragTabElementAboveWindow(lastUnpinnedTab)
    }

    private func dragTabElementAboveWindow(_ tabElement: XCUIElement) {
        let frame = tabElement.frame
        let tabCenterCoordinate = tabElement
            .coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.width * 0.5, dy: frame.height * 0.5))

        let aboveWindow = tabCenterCoordinate.withOffset(CGVector(dx: 0, dy: -100))

        tabCenterCoordinate.press(forDuration: 0.5, thenDragTo: aboveWindow)
    }
}
