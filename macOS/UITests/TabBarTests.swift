//
//  TabBarTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

class TabBarTests: UITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        app = XCUIApplication.setUp()

        app.openNewWindow()
        resetPinnedTabs()
    }

    func testClosesChildTabIsSelected_whenSibilingTabIsClosed() {
        openPrivacyTestPagesSite()

        /// Opens the first link with CMD pressed so we open it on a new tab
        let tab1Link = app.webViews.firstMatch.links["Downloads"]
        tab1Link.rightClick()
        app.menuItems["Open Link in New Tab"].firstMatch.clickAfterExistenceTestSucceeds()

        let tab2Link = app.webViews.firstMatch.links["Print"]
        tab2Link.rightClick()
        app.menuItems["Open Link in New Tab"].firstMatch.clickAfterExistenceTestSucceeds()

        /// Move to the next tab and closes it
        app.typeKey("]", modifierFlags: [.command, .shift])
        app.closeCurrentTab()

        /// Asserts that the next child tab is shown
        XCTAssertTrue(app.staticTexts["Print"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    func testClosesChildTabIsSelected_whenParentTabIsClosed() {
        /// We open three empty tabs and then we load the parent privacy site
        app.openNewTab()
        app.openNewTab()
        app.openNewTab()
        openPrivacyTestPagesSite()
        let tabCountBeforeChildren = app.tabs.count

        /// Opens two child sites (downloads and print)
        let downloadsChildSiteLink = app.webViews.firstMatch.links["Downloads"]
        downloadsChildSiteLink.rightClick()
        app.menuItems["Open Link in New Tab"].firstMatch.clickAfterExistenceTestSucceeds()

        let printChildSiteLink = app.webViews.firstMatch.links["Print"]
        printChildSiteLink.rightClick()
        app.menuItems["Open Link in New Tab"].firstMatch.clickAfterExistenceTestSucceeds()
        XCTAssertTrue(app.wait(for: .keyPath(\.tabs.count, equalTo: tabCountBeforeChildren + 2), timeout: UITests.Timeouts.elementExistence),
                      "Both child tabs should open before closing their parent")

        /// We pin the privacy site and we close it. We do this to position the parent child first in the tab collection
        /// The reason why we unpin it, is because we do not want for it to be pinned for other tests.
        app.pinCurrentTab()
        app.unpinCurrentTab()
        app.closeCurrentTab()

        /// Asserts that the first child next to the closed parent tab is shown. In this case si the Downloads site
        XCTAssertTrue(app.staticTexts["Download PDF"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    func testParentTabIsSelected_whenChildTabIsClosedAndNoOtherChildTabsAreOpened() {
        /// We open three empty tabs and then we load the parent privacy site
        app.openNewTab()
        app.openNewTab()
        app.openNewTab()
        openPrivacyTestPagesSite()

        /// Opens one child sites (downloads and print)
        let downloadsChildSiteLink = app.webViews.firstMatch.links["Downloads"]
        downloadsChildSiteLink.rightClick()
        app.menuItems["Open Link in New Tab"].firstMatch.clickAfterExistenceTestSucceeds()

        /// We pin the privacy site and we close it. We do this to position the parent child first in the tab collection
        /// The reason why we unpin it, is because we do not want for it to be pinned for other tests.
        app.pinCurrentTab()
        app.unpinCurrentTab()

        /// We move through tabs until we are in the child position tab and we close it
        app.typeKey("]", modifierFlags: [.command, .shift])
        app.typeKey("]", modifierFlags: [.command, .shift])
        app.typeKey("]", modifierFlags: [.command, .shift])
        app.typeKey("]", modifierFlags: [.command, .shift])

        app.closeCurrentTab()

        /// Asserts that the first child next to the closed parent tab is shown. In this case si the Downloads site
        XCTAssertTrue(app.staticTexts["Privacy Test Pages"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    func testRecentlyActiveTabIsSelected_whenNewTabIsClosedAndNoOtherTabWasSelected() {
        /// We open three sites  and then we select the first tab
        openFourSitesOnSameWindow()
        app.typeKey("1", modifierFlags: [.command])

        /// We open a new tab and we close it
        app.openNewTab()
        app.closeCurrentTab()

        /// Asserts that the recently active tab is visible
        XCTAssertTrue(app.staticTexts["Sample text for Page #1"].waitForExistence(timeout: UITests.Timeouts.localTestServer))
    }

    func testRecentlyActiveTabIsNotSelected_ifAnotherTabWasSelectedBeforeTheTabWasClosed() {
        /// We open three sites  and then we select the first tab
        openFourSitesOnSameWindow()
        app.typeKey("1", modifierFlags: [.command])

        /// We open a new tab
        app.openNewTab()
        /// We move to the third tab
        app.typeKey("3", modifierFlags: [.command])
        /// We move to the last tab and we close it
        app.typeKey("5", modifierFlags: [.command])
        app.closeCurrentTab()

        /// Asserts that the tab to the right is shown
        XCTAssertTrue(app.staticTexts["Sample text for Page #4"].waitForExistence(timeout: UITests.Timeouts.localTestServer))
    }

    func testContextMenuOpens_withRightClickOnTab() {
        let tab = app.tabGroups.matching(identifier: "Tabs").radioButtons.firstMatch
        tab.rightClick()

        let contextMenu = tab.children(matching: .menu).firstMatch

        XCTAssertTrue(contextMenu.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Context menu should appear on right click")
    }

    func testContextMenuOpens_withContextClickOnTab() {
        let tab = app.tabGroups.matching(identifier: "Tabs").radioButtons.firstMatch
        XCUIElement.perform(withKeyModifiers: .control) {
            tab.click()
        }

        let contextMenu = tab.children(matching: .menu).firstMatch

        XCTAssertTrue(contextMenu.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Context menu should appear on control click")
    }

    func testNewTabButtonOpensTab_andCloseButtonClosesIt() {
        app.enforceSingleWindow()
        let window = app.windows.firstMatch
        let tabCount = window.tabs.count

        hittableElement(in: window.buttons.matching(identifier: "NewTabButton")).click()
        XCTAssertTrue(window.wait(for: .keyPath(\.tabs.count, equalTo: tabCount + 1), timeout: UITests.Timeouts.elementExistence),
                      "Clicking the new tab button should open a tab")

        let selectedTab = window.tabs.element(matching: \.isSelected, equalTo: true)
        selectedTab.buttons["TabBarViewItem.closeButton"].clickAfterExistenceTestSucceeds()
        XCTAssertTrue(window.wait(for: .keyPath(\.tabs.count, equalTo: tabCount), timeout: UITests.Timeouts.elementExistence),
                      "Clicking the tab's close button should close it")
    }

    func testDraggingTabIntoAnotherOpenWindow_movesTabThere() {
        app.enforceSingleWindow()
        app.openSite(pageTitle: "Page #1")

        app.openNewWindow()
        app.openSite(pageTitle: "Page #2")
        app.openNewTab()
        app.openSite(pageTitle: "Page #3")

        // The new window is cascaded over the first one; move it down so the first window's tab bar can take the drop
        let targetWindow = app.windows.element(boundBy: 1)
        let sourceWindow = app.windows.element(boundBy: 0)
        let sourceTitleBar = sourceWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0)).withOffset(CGVector(dx: 0, dy: 10))
        sourceTitleBar.click(forDuration: 0.5, thenDragTo: sourceTitleBar.withOffset(CGVector(dx: 0, dy: 300)))
        XCTAssertGreaterThan(sourceWindow.frame.minY, targetWindow.frame.minY + 100, "The second window should have moved out of the way")

        let draggedTab = sourceWindow.tabs["Page #3"]
        let lastTargetTab = targetWindow.tabs.element(boundBy: targetWindow.tabs.count - 1)
        let dropPoint = lastTargetTab.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: 40, dy: 0))
        draggedTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(forDuration: 0.5, thenDragTo: dropPoint, withVelocity: .slow, thenHoldForDuration: 0.5)

        XCTAssertTrue(targetWindow.tabs["Page #3"].waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "The dragged tab should be in the first window")
        XCTAssertEqual(targetWindow.tabs.count, 2, "The first window should have its own tab and the dragged one")
        XCTAssertEqual(sourceWindow.tabs.count, 1, "The second window should have only its remaining tab")
    }

    func testTabBarScrollButtons_bringFirstAndLastTabsIntoView() {
        app.enforceSingleWindow()
        let window = app.windows.firstMatch
        let leftScrollButton = window.buttons["TabBarViewController.leftScrollButton"]
        let rightScrollButton = window.buttons["TabBarViewController.rightScrollButton"]

        // How many tabs it takes to overflow depends on the screen size, so keep adding until the scroll buttons show up
        var openedTabs = 0
        while !leftScrollButton.exists && openedTabs < 80 {
            app.openNewTab()
            openedTabs += 1
        }
        XCTAssertTrue(leftScrollButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "The tab bar should overflow")

        let firstTab = window.tabs.element(boundBy: 0)
        let lastTab = window.tabs.element(boundBy: window.tabs.count - 1)
        XCTAssertFalse(firstTab.isHittable, "The first tab should be scrolled out of view")

        clickRepeatedly(leftScrollButton, until: { firstTab.isHittable })
        XCTAssertTrue(firstTab.isHittable, "The left scroll button should bring the first tab into view")
        XCTAssertFalse(lastTab.isHittable, "The last tab should be scrolled out of view")

        clickRepeatedly(rightScrollButton, until: { lastTab.isHittable })
        XCTAssertTrue(lastTab.isHittable, "The right scroll button should bring the last tab into view")
    }

    // MARK: - Utilities

    /// The tab bar has two new tab buttons, one after the last tab and one pinned to the right when tabs overflow; only one is shown.
    private func hittableElement(in query: XCUIElementQuery) -> XCUIElement {
        let element = query.allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(element, "No hittable element in \(query)")
        return element ?? query.firstMatch
    }

    private func clickRepeatedly(_ button: XCUIElement, until condition: () -> Bool) {
        var clicks = 0
        while !condition() && clicks < 40 {
            button.click()
            clicks += 1
        }
    }

    private func resetPinnedTabs() {
        app.debugMenu.click()
        app.menuItems["MainMenu.resetData"].hover()
        app.menuItems["Reset Pinned Tabs"].clickAfterExistenceTestSucceeds()
    }

    private func moveToRightEndTab() {
        let toolbar = app.toolbars.firstMatch
        let toolbarCoordinate = toolbar.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let startPoint = toolbarCoordinate.withOffset(CGVector(dx: 160, dy: 0))
        startPoint.press(forDuration: 0.1)

        sleep(1)
    }

    private func openFourSitesOnSameWindow() {
        app.openSite(pageTitle: "Page #1")
        app.openNewTab()
        app.openSite(pageTitle: "Page #2")
        app.openNewTab()
        app.openSite(pageTitle: "Page #3")
        app.openNewTab()
        app.openSite(pageTitle: "Page #4")
    }

    private func pinsPageOne() {
        app.typeKey("[", modifierFlags: [.command, .shift])
        app.typeKey("[", modifierFlags: [.command, .shift])
        app.typeKey("[", modifierFlags: [.command, .shift])
        app.menuItems["Pin Tab"].tap()
    }

    private func openPrivacyTestPagesSite() {
        let url = URL(string: "http://privacy-test-pages.site/index.html")!
        let addressBar = app.addressBar
        XCTAssertTrue(
            addressBar.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The address bar text field didn't become available in a reasonable timeframe."
        )
        addressBar.typeURL(url)
        XCTAssertTrue(
            app.windows.firstMatch.webViews["Privacy Test Pages - Home"].waitForExistence(timeout: UITests.Timeouts.navigation),
            "Visited site didn't load with the expected title in a reasonable timeframe."
        )
    }
}
