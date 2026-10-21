//
//  DuplicateTabTests.swift
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

// Duplicate-tab rendering (#4512) and popup-copy (#6827) regression coverage.
final class DuplicateTabTests: UITestCase, TabNavigationTestHelpers {

    override func setUpWithError() throws {
        try super.setUpWithError()
        let featureFlags: [String: Bool]
        switch invocation?.selector {
        case #selector(testDuplicateRestoredBackgroundTab):
            featureFlags = ["warnBeforeQuit": false, "firstTimeQuitSurvey": false]
        case #selector(testDuplicateSuspendedBackgroundTab):
            featureFlags = ["tabSuspension": true, "tabSuspensionDebugging": true]
        default:
            featureFlags = [:]
        }
        app = XCUIApplication.setUp(featureFlags: featureFlags)
        app.enforceSingleWindow()
        resetPinnedTabs()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try super.tearDownWithError()
    }

    func testDuplicateTabAppearsNextToOriginalAndCanBeClosedIndependently() {
        openPage("Original")
        let window = app.windows.firstMatch
        duplicateFromWindowMenu()
        assertCount(2, in: window.tabs)
        assertTab("Original", at: 0, in: window.tabs)
        assertTab("Original", at: 1, in: window.tabs, selected: true)
        assertPage("Original", in: window, url: UITests.simpleServedPage(titled: "Original"))

        openPage("Copy Only")
        assertTab("Original", at: 0, in: window.tabs)
        app.closeCurrentTab()
        assertCount(1, in: window.tabs)
        assertPage("Original", in: window)
    }

    func testDuplicatePreservesHistoryWithoutNavigatingOriginal() {
        openPage("History First")
        openPage("History Second")
        duplicateFromWindowMenu()
        // Exercise the copied back/forward list without depending on keyboard focus.
        XCTAssertTrue(app.backButton.wait(for: \.isEnabled, equals: true, timeout: UITests.Timeouts.localTestServer))
        app.backButton.rightClick()
        app.backButton.children(matching: .menu).menuItems["History First"].clickAfterExistenceTestSucceeds()
        assertPage("History First", in: app.windows.firstMatch)
        assertTab("History Second", at: 0, in: app.tabs)
        app.tabs.element(boundBy: 0).click()
        assertPage("History Second", in: app.windows.firstMatch)
        assertCount(2, in: app.tabs)
    }

    func testContextMenuDuplicatesInactiveTabRatherThanSelectedTab() {
        openPage("Background Source")
        app.openNewTab()
        openPage("Active Other")
        duplicateFromContextMenu(app.tabs.element(boundBy: 0))
        assertCount(3, in: app.tabs)
        assertTab("Background Source", at: 0, in: app.tabs)
        assertTab("Background Source", at: 1, in: app.tabs, selected: true)
        assertTab("Active Other", at: 2, in: app.tabs)
        assertPage("Background Source", in: app.windows.firstMatch)
    }

    func testPopupDuplicateOpensIndependentCopyInParentWindow() {
        assertPopupDuplication(fire: false, closeParent: false)
    }

    func testFirePopupDuplicateStaysInFireParentWindow() {
        assertPopupDuplication(fire: true, closeParent: false)
    }

    func testPopupDuplicateAfterParentClosesOpensRegularWindow() {
        assertPopupDuplication(fire: false, closeParent: true)
    }

    func testFirePopupDuplicateAfterParentClosesOpensFireWindow() {
        assertPopupDuplication(fire: true, closeParent: true)
    }

    func testDuplicatePinnedTabWithSeparatePinnedTabs() {
        assertPinnedDuplication(shared: false)
    }

    func testDuplicatePinnedTabWithSharedPinnedTabs() {
        assertPinnedDuplication(shared: true)
    }

    func testDuplicateRestoredBackgroundTab() {
        app.openPreferencesWindow()
        app.preferencesSetRestorePreviousSession(to: .restoreLastSession)
        app.closePreferencesWindow()
        app.enforceSingleWindow()
        openPage("Restored Source")
        app.openNewTab()
        openPage("Restored Active")
        // A normal quit flushes the debounced session state before relaunching.
        app.restart()
        assertCount(2, in: app.tabs)
        assertPage("Restored Active", in: app.windows.firstMatch)

        duplicateFromContextMenu(app.tabs.element(boundBy: 0))
        assertCount(3, in: app.tabs)
        assertTab("Restored Source", at: 0, in: app.tabs)
        assertTab("Restored Source", at: 1, in: app.tabs, selected: true)
        assertPage("Restored Source", in: app.windows.firstMatch)
        app.closeCurrentTab()
        app.tabs.element(boundBy: 0).click()
        assertPage("Restored Source", in: app.windows.firstMatch)
    }

    func testDuplicateSuspendedBackgroundTab() {
        openPage("Suspended Source")
        app.openNewTab()
        openPage("Suspension Active")
        // The test-mode inactivity threshold is five seconds, as in TabSuspensionTests.
        Thread.sleep(forTimeInterval: 6)
        app.debugMenu.click()
        let searchField = app.searchFields["Search debug menu..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Debug menu search field must appear")
        searchField.typeText("Simulate Memory Pressure")
        app.menuItems["Simulate Memory Pressure (Critical)"].clickAfterExistenceTestSucceeds()
        let source = app.tabs.element(boundBy: 0)
        source.rightClick()
        XCTAssertTrue(app.menuItems["isSuspended: true"].waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "The source must actually be suspended")
        app.typeKey(.escape, modifierFlags: [])

        duplicateFromContextMenu(source)
        assertCount(3, in: app.tabs)
        assertTab("Suspended Source", at: 1, in: app.tabs, selected: true)
        assertPage("Suspended Source", in: app.windows.firstMatch)
        app.closeCurrentTab()
        app.tabs.element(boundBy: 0).click()
        assertPage("Suspended Source", in: app.windows.firstMatch)
    }

    func testDuplicateInOverflowRemainsVisibleAndSelectable() {
        for _ in 0..<40 {
            app.openNewTab()
        }
        openPage("Overflow Source")
        // Newer XCTest omits offscreen tabs; older XCTest includes them.
        let hasOffscreenTabs = app.tabs.count < 41 || !app.tabs.element(boundBy: 0).isHittable
        XCTAssertTrue(hasOffscreenTabs, "The tab bar must actually overflow")
        duplicateFromWindowMenu()
        let copies = app.tabs.matching(identifier: "Overflow Source")
        assertCount(2, in: copies)
        let original = copies.element(boundBy: 0)
        let copy = copies.element(boundBy: 1)
        XCTAssertTrue(copy.isSelected)
        XCTAssertTrue(copy.isHittable, "The copy must be visible in the overflowing tab bar")
        XCTAssertGreaterThan(copy.frame.minX, original.frame.minX, "The copy should appear to the right")
        app.typeKey("[", modifierFlags: [.command, .shift])
        XCTAssertTrue(original.isSelected)
        XCTAssertTrue(original.isHittable, "Selecting the original must scroll it into view")
        original.click()
        assertPage("Overflow Source", in: app.windows.firstMatch)
        app.typeKey("]", modifierFlags: [.command, .shift])
        XCTAssertTrue(copy.isHittable, "Selecting the copy must scroll it into view")
        copy.click()
        XCTAssertTrue(copy.isSelected)
        app.closeCurrentTab()
        assertCount(1, in: copies)
        assertPage("Overflow Source", in: app.windows.firstMatch)
    }

    func testRepeatedDuplicationCreatesIndependentTabs() {
        openPage("Repeated Source")
        for expectedCount in 2...4 {
            duplicateFromWindowMenu()
            assertCount(expectedCount, in: app.tabs)
            assertTab("Repeated Source", at: expectedCount - 1, in: app.tabs, selected: true)
        }
        for index in 0..<4 {
            app.tabs.element(boundBy: index).click()
            assertPage("Repeated Source", in: app.windows.firstMatch)
        }
        for expectedCount in stride(from: 3, through: 1, by: -1) {
            app.closeCurrentTab()
            assertCount(expectedCount, in: app.tabs)
        }
        assertPage("Repeated Source", in: app.windows.firstMatch)
    }

    func testDuplicateCanBePinnedReorderedMovedAndClosedWithoutLosingOriginal() {
        setPinnedTabsMode(shared: false)
        openPage("Chain Original")
        duplicateFromWindowMenu()
        openPage("Chain Copy")
        app.pinCurrentTab()
        assertCount(1, in: app.pinnedTabs)
        assertCount(1, in: app.tabs)
        assertTab("Chain Copy", at: 0, in: app.pinnedTabs, selected: true)
        app.unpinCurrentTab()
        assertCount(0, in: app.pinnedTabs)
        assertCount(2, in: app.tabs)

        assertTab("Chain Copy", at: 0, in: app.tabs, selected: true)
        assertTab("Chain Original", at: 1, in: app.tabs)
        let copy = app.tabs["Chain Copy"]
        let original = app.tabs["Chain Original"]
        copy.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(forDuration: 0.5, thenDragTo: original.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        assertTab("Chain Original", at: 0, in: app.tabs)
        assertTab("Chain Copy", at: 1, in: app.tabs, selected: true)
        copy.rightClick()
        copy.children(matching: .menu).menuItems["Move Tab to New Window"].clickAfterExistenceTestSucceeds()
        assertCount(2, in: app.windows)
        let originalWindow = app.windows.containing(.radioButton, identifier: "Chain Original").firstMatch
        let copyWindow = app.windows.containing(.radioButton, identifier: "Chain Copy").firstMatch
        assertCount(1, in: originalWindow.tabs)
        assertCount(1, in: copyWindow.tabs)
        assertPage("Chain Copy", in: copyWindow)
        app.closeWindow()
        assertCount(1, in: app.windows)
        assertPage("Chain Original", in: app.windows.firstMatch)
    }

    // MARK: - Helpers

    private func openPage(_ title: String) {
        app.activateAddressBar()
        app.openSite(pageTitle: title)
    }

    private func duplicateFromWindowMenu() {
        app.menuBarItems["Window"].click()
        app.menuItems["Duplicate Tab"].clickAfterExistenceTestSucceeds()
    }

    private func duplicateFromContextMenu(_ tab: XCUIElement) {
        tab.rightClick()
        tab.children(matching: .menu).menuItems["Duplicate Tab"].clickAfterExistenceTestSucceeds()
    }

    private func assertCount(_ expected: Int, in query: XCUIElementQuery, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(query.wait(for: \.count, equals: expected, timeout: UITests.Timeouts.elementExistence),
                      "Expected \(expected) elements, found \(query.count)", file: file, line: line)
    }

    private func assertTab(_ title: String, at index: Int, in tabs: XCUIElementQuery, selected: Bool = false,
                           file: StaticString = #file, line: UInt = #line) {
        let tab = tabs.element(boundBy: index)
        XCTAssertTrue(tab.waitForExistence(timeout: UITests.Timeouts.elementExistence), file: file, line: line)
        XCTAssertEqual(tab.title, title, file: file, line: line)
        if selected {
            XCTAssertTrue(tab.isSelected, "The duplicate must be selected", file: file, line: line)
        }
    }

    private func assertPage(_ title: String, in window: XCUIElement, url: URL? = nil,
                            file: StaticString = #file, line: UInt = #line) {
        let webView = window.webViews[title]
        XCTAssertTrue(webView.waitForExistence(timeout: UITests.Timeouts.localTestServer), file: file, line: line)
        if let url {
            let selectedTab = window.tabs.element(matching: \.isSelected, equalTo: true)
            XCTAssertEqual(selectedTab.url, url.absoluteString, file: file, line: line)
        }
    }

    private func resetPinnedTabs() {
        app.debugMenu.click()
        app.menuItems["MainMenu.resetData"].hover()
        app.menuItems["Reset Pinned Tabs"].clickAfterExistenceTestSucceeds()
    }

    private func setPinnedTabsMode(shared: Bool) {
        app.openPreferencesWindow()
        app.preferencesGoToGeneralPane()
        let picker = app.preferencesWindow.popUpButtons["PreferencesGeneralView.pinnedTabsModePicker"]
        picker.clickAfterExistenceTestSucceeds()
        app.menuItems[shared ? "Shared across all windows" : "Separate in each window"].clickAfterExistenceTestSucceeds()
        app.closePreferencesWindow()
        app.enforceSingleWindow()
    }

    private func assertPinnedDuplication(shared: Bool) {
        setPinnedTabsMode(shared: shared)
        openPage("Pinned Source")
        app.pinCurrentTab()
        let sourceWindow = app.windows.firstMatch
        let regularCount = sourceWindow.tabs.count
        assertCount(1, in: sourceWindow.pinnedTabs)
        duplicateFromWindowMenu()
        assertCount(2, in: sourceWindow.pinnedTabs)
        assertCount(regularCount, in: sourceWindow.tabs)
        assertTab("Pinned Source", at: 0, in: sourceWindow.pinnedTabs)
        assertTab("Pinned Source", at: 1, in: sourceWindow.pinnedTabs, selected: true)
        assertPage("Pinned Source", in: sourceWindow)
        openPage("Pinned Copy Only")
        assertTab("Pinned Source", at: 0, in: sourceWindow.pinnedTabs)
        assertTab("Pinned Copy Only", at: 1, in: sourceWindow.pinnedTabs, selected: true)

        app.openNewWindow()
        assertCount(shared ? 2 : 0, in: app.pinnedTabs)
        app.closeWindow()
        sourceWindow.pinnedTabs.element(boundBy: 0).click()
        assertPage("Pinned Source", in: sourceWindow)
        app.unpinCurrentTab()
        assertCount(1, in: sourceWindow.pinnedTabs)
        assertPage("Pinned Source", in: sourceWindow)
    }

    private func assertPopupDuplication(fire: Bool, closeParent: Bool) {
        if fire {
            app.openFireWindow()
        }
        let popupTitle = "Popup Menu Page"
        let popupURL = UITests.simpleServedPage(titled: popupTitle, body: "<p>Popup menu actions</p>")
        openPopupSourcePage(sourceTitle: "Popup Parent")
        let parent = app.windows.containing(.radioButton, identifier: "Popup Parent").firstMatch
        parent.webViews["Popup Parent"].links["Open popup"].click()
        let popup = app.windows.containing(.webView, identifier: popupTitle).firstMatch
        XCTAssertTrue(popup.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        if closeParent {
            parent.tabs["Popup Parent"].click()
            app.closeWindow()
        }
        popup.webViews[popupTitle].click()
        let windowCount = app.windows.count
        duplicateFromWindowMenu()
        assertCount(closeParent ? windowCount + 1 : windowCount, in: app.windows)
        let destination = app.windows.containing(.radioButton, identifier: closeParent ? popupTitle : "Popup Parent").firstMatch
        assertCount(closeParent ? 1 : 2, in: destination.tabs)
        assertPage(popupTitle, in: destination, url: popupURL)
        assertCount(2, in: app.windows.webViews.matching(identifier: popupTitle))
        if fire {
            app.menuBarItems["Window"].click()
            XCTAssertFalse(app.mainMenuPinTabMenuItem.isEnabled, "A duplicate of a Fire tab must stay in Fire mode")
            app.typeKey(.escape, modifierFlags: [])
        }
        openPage("Popup Copy Only")
        XCTAssertTrue(app.windows.webViews[popupTitle].exists, "Navigating the copy must preserve the popup")
        app.closeCurrentTab()
        XCTAssertTrue(app.windows.webViews[popupTitle].exists, "Closing the copy must preserve the popup")
        if !closeParent {
            assertPage("Popup Parent", in: parent)
        }
    }
}
