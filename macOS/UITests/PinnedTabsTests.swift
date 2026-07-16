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
    var featureFlags: [String: Bool] { [:] }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp(featureFlags: featureFlags)

        // Safety-net: close any pinned tabs left from a previous test that tearDown
        // might have missed (e.g. after a crash).  Primary cleanup happens in
        // tearDownWithError, which runs while the app is fully loaded.
        closeResidualPinnedTabs()

        app.openNewWindow()
    }

    override func tearDownWithError() throws {
        // Primary pinned-tab cleanup: runs while the app is still fully loaded, so
        // app.pinnedTabs.count is reliable.  This ensures the session file has 0 pinned
        // tabs when the app terminates, preventing accumulation across test iterations.
        if app.state == .runningForeground || app.state == .runningBackground {
            unpinAllPinnedTabs()
        }
        try super.tearDownWithError()
    }

    /// Unpins and closes every pinned tab. Safe to call from both setUp and tearDown.
    private func unpinAllPinnedTabs() {
        for _ in 0..<50 { // Safety limit — no test should accumulate > 50 pins
            guard app.pinnedTabs.count > 0 else { break }
            app.pinnedTabs.element(boundBy: 0).click()
            guard app.menuItems["Unpin Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence) else { break }
            app.menuItems["Unpin Tab"].tap()
            app.closeCurrentTab()
        }
    }

    /// Safety-net cleanup called from setUp.  Primary cleanup is tearDownWithError.
    private func closeResidualPinnedTabs() {
        _ = app.windows.firstMatch.waitForExistence(timeout: UITests.Timeouts.elementExistence)
        // Wait briefly for session restore to populate the pinned-tabs view.
        // If tearDownWithError ran correctly in the previous test this returns
        // immediately (no pins), adding only a negligible delay.
        _ = app.pinnedTabs.firstMatch.waitForExistence(timeout: 5)
        unpinAllPinnedTabs()
    }

    func testPinnedTabsFunctionality() {
        app.disableWarnBeforeQuitting(closeSettings: false)
        app.disableWarnBeforeClosingPinnedTabs(closeSettings: true)
        // Close any extra browser windows (from session restore or setUp's openNewWindow)
        // so the multi-window flow in this test starts from a known single-window state.
        // assertWindowTwoHasNoPinnedTabsFromWindowsOne expects windows.count == 1 after
        // closing the Page #4 window, which only holds if exactly 2 windows exist at
        // that point (this window + the Page #4 window opened by openNewWindowAndLoadSite).
        app.closeAllWindows()
        app.openNewWindow()
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

    func testReleaseNotesCannotBePinned() throws {
        if app.isSandboxed {
            throw XCTSkip("This test is only valid for non-App Store builds")
        }
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

    // MARK: - Modifier-key navigation from a pinned tab

    func testWhenPinnedTabNavigatesToDifferentDomain_CmdClick_ThenNewTabOpensInBackground() {
        let (sourceTitle, targetTitle, sourceURL) = makePinnedCrossDomainScenario(suffix: "CmdClick")
        app.setSwitchToNewTab(enabled: false)
        app.openURL(sourceURL, waitForWebViewAccessibilityLabel: sourceTitle)
        pinCurrentPage()

        let mainWindow = app.windows.firstMatch
        XCUIElement.perform(withKeyModifiers: [.command]) {
            mainWindow.webViews[sourceTitle].links["Go to \(targetTitle)"].click()
        }

        XCTAssertTrue(app.tabs[targetTitle].waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Cmd+click from pinned tab should open target in a new tab")
        XCTAssertEqual(app.windows.count, 1, "Should stay in the same window")
        XCTAssertTrue(mainWindow.webViews[sourceTitle].exists,
                      "Pinned tab should remain selected (cmd+click opens in background)")
        XCTAssertEqual(app.pinnedTabs.count, 1, "Pinned tab should still exist")
        XCTAssertEqual(app.tabGroups.matching(identifier: "Tabs").radioButtons.count, 1,
                       "Exactly one new unpinned tab should have been created")
    }

    func testWhenPinnedTabNavigatesToDifferentDomain_CmdShiftClick_ThenNewTabOpensInForeground() {
        let (sourceTitle, targetTitle, sourceURL) = makePinnedCrossDomainScenario(suffix: "CmdShiftClick")
        app.setSwitchToNewTab(enabled: false)
        app.openURL(sourceURL, waitForWebViewAccessibilityLabel: sourceTitle)
        pinCurrentPage()

        let mainWindow = app.windows.firstMatch
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            mainWindow.webViews[sourceTitle].links["Go to \(targetTitle)"].click()
        }

        XCTAssertTrue(mainWindow.webViews[targetTitle].waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Cmd+Shift+click from pinned tab should open target tab in foreground")
        XCTAssertEqual(app.windows.firstMatch.title, targetTitle,
                       "New tab should be selected (foreground)")
        XCTAssertEqual(app.windows.count, 1, "Should stay in the same window")
        XCTAssertEqual(app.pinnedTabs.count, 1, "Pinned tab should still exist")
        XCTAssertEqual(app.tabGroups.matching(identifier: "Tabs").radioButtons.count, 1,
                       "Exactly one new unpinned tab should have been created")
    }

    func testWhenPinnedTabNavigatesToDifferentDomain_CmdOptClick_ThenNewWindowOpensInBackground() {
        let (sourceTitle, targetTitle, sourceURL) = makePinnedCrossDomainScenario(suffix: "CmdOptClick")
        app.setSwitchToNewTab(enabled: false)
        app.openURL(sourceURL, waitForWebViewAccessibilityLabel: sourceTitle)
        pinCurrentPage()

        let mainWindow = app.windows.firstMatch
        XCUIElement.perform(withKeyModifiers: [.command, .option]) {
            mainWindow.webViews[sourceTitle].links["Go to \(targetTitle)"].click()
        }

        let newWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(newWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Cmd+Opt+click from pinned tab should open a new background window")
        XCTAssertEqual(app.windows.count, 2, "A second window should have been created")
        XCTAssertTrue(newWindow.webViews[targetTitle].waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Target should load in the new background window")
        XCTAssertTrue(mainWindow.webViews[sourceTitle].exists,
                      "Original pinned tab should remain selected in the main window")
        XCTAssertEqual(app.pinnedTabs.count, 1, "Pinned tab should still exist")
    }

    func testWhenPinnedTabNavigatesToDifferentDomain_OptClick_ThenDownloadStarts() {
        // Option+click without ⌘ is a "save link as" gesture — should trigger a download,
        // not open a new tab, even for cross-domain links from a pinned tab.
        let sourceTitle = "Pinned Source (OptDownload)"
        let uniqueName = "pinned-opt-\(UUID().uuidString).bin"
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        trackForCleanup(downloadsDir.appendingPathComponent(uniqueName).path)

        // Build a cross-domain download URL (127.0.0.1 vs localhost) so the pinned-tab
        // cross-domain logic is exercised.
        var downloadComponents = URLComponents(url: URL.testsDownload(size: "1KB", filename: uniqueName),
                                               resolvingAgainstBaseURL: false)!
        downloadComponents.host = "127.0.0.1"
        let downloadURL = downloadComponents.url!

        let sourceURL = UITests.simpleServedPage(titled: sourceTitle,
                                                  body: "<a href='\(downloadURL.absoluteString)'>Download File</a>")

        // Ensure "Always ask where to save" is off so the download proceeds silently.
        app.openPreferencesWindow()
        app.preferencesGoToGeneralPane()
        app.setAlwaysAskWhereToSaveFiles(enabled: false)
        app.enforceSingleWindow()

        app.openURL(sourceURL, waitForWebViewAccessibilityLabel: sourceTitle)
        pinCurrentPage()

        let mainWindow = app.windows.firstMatch
        let link = mainWindow.webViews[sourceTitle].links["Download File"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.option]) {
            link.click()
        }

        // No new tab should have been opened — the pinned tab cross-domain interception
        // must NOT redirect opt+click to a new tab.
        XCTAssertEqual(app.pinnedTabs.count, 1,
                       "Pinned source tab should still exist")
        XCTAssertEqual(app.tabGroups.matching(identifier: "Tabs").radioButtons.count, 0,
                       "Opt+click from pinned tab should not open a new unpinned tab")
        XCTAssertEqual(app.windows.count, 1,
                       "Opt+click from pinned tab should not open a new window")

        // The download should be listed in the downloads panel.
        let popover = app.popovers.containing(.table, identifier: "DownloadsViewController.table").firstMatch
        if !popover.exists {
            app.openDownloads()
            XCTAssertTrue(popover.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        }
        XCTAssertTrue(popover.staticTexts[uniqueName].waitForExistence(timeout: UITests.Timeouts.localTestServer),
                      "Download should appear in the Downloads panel after opt+click from a pinned tab")
    }

    func testWhenPinnedTabNavigatesToDifferentDomain_CmdOptShiftClick_ThenNewWindowOpensInForeground() {
        let (sourceTitle, targetTitle, sourceURL) = makePinnedCrossDomainScenario(suffix: "CmdOptShiftClick")
        app.setSwitchToNewTab(enabled: false)
        app.openURL(sourceURL, waitForWebViewAccessibilityLabel: sourceTitle)
        pinCurrentPage()

        let mainWindow = app.windows.firstMatch
        XCUIElement.perform(withKeyModifiers: [.command, .option, .shift]) {
            mainWindow.webViews[sourceTitle].links["Go to \(targetTitle)"].click()
        }

        XCTAssertTrue(app.windows.element(boundBy: 1).waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Cmd+Opt+Shift+click from pinned tab should open a new foreground window")
        XCTAssertEqual(app.windows.count, 2, "A second window should have been created")
        // The new window should be key (frontmost) — its title matches the target
        XCTAssertTrue(app.windows.matching(NSPredicate(format: "title == %@", targetTitle)).firstMatch
                        .waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "New window should be in the foreground (active)")
        // After opening a new foreground window, windows.firstMatch resolves to the NEW window
        // (now frontmost). The pinned tab lives in the ORIGINAL window — query it by title.
        let originalWindow = app.windows.matching(NSPredicate(format: "title == %@", sourceTitle)).firstMatch
        XCTAssertEqual(originalWindow.pinnedTabs.count, 1, "Pinned tab should still exist in the original window")
    }

    // MARK: - Helper

    /// Builds source/target page titles and source URL for a pinned-tab cross-domain scenario.
    private func makePinnedCrossDomainScenario(suffix: String) -> (sourceTitle: String, targetTitle: String, sourceURL: URL) {
        let sourceTitle = "Pinned Source (\(suffix))"
        let targetTitle = "Cross-Domain Target (\(suffix))"
        var targetComponents = URLComponents(url: UITests.simpleServedPage(titled: targetTitle), resolvingAgainstBaseURL: false)!
        targetComponents.host = "127.0.0.1"
        let targetURL = targetComponents.url!
        let sourceURL = UITests.simpleServedPage(titled: sourceTitle,
                                                  body: "<a href='\(targetURL.absoluteString)'>Go to \(targetTitle)</a>")
        return (sourceTitle, targetTitle, sourceURL)
    }

    func testWhenPinnedTabNavigatesToDifferentDomain_AndSwitchToNewTabIsDisabled_ThenNewTabStillOpensInForeground() {
        let (sourceTitle, targetTitle, sourceURL) = makePinnedCrossDomainScenario(suffix: "NoSwitch")

        // Disable "switch to new tab when opened" — new tabs would normally open in background
        app.setSwitchToNewTab(enabled: false)

        app.openURL(sourceURL, waitForWebViewAccessibilityLabel: sourceTitle)
        pinCurrentPage()

        let mainWindow = app.windows.firstMatch
        mainWindow.webViews[sourceTitle].links["Go to \(targetTitle)"].click()

        // Even with switchToNewTab disabled, a pinned tab's cross-domain link must open in the foreground,
        // because it's initiated by user action.
        // Use a generous timeout: prior test failures can leave session-restore windows that slow
        // down accessibility-tree updates (but the assertion itself is unchanged — foreground required).
        XCTAssertTrue(
            mainWindow.webViews[targetTitle].waitForExistence(timeout: UITests.Timeouts.localTestServer),
            "Cross-domain link from pinned tab should load in a new tab even when switchToNewTab is disabled"
        )
        // New tab is selected (foreground)
        XCTAssertEqual(
            app.windows.firstMatch.title, targetTitle,
            "New tab from pinned tab cross-domain navigation should always be selected, regardless of switchToNewTab preference"
        )
        // A new unpinned tab was created — not the same tab navigating away
        let unpinnedTabsAfter = app.tabGroups.matching(identifier: "Tabs").radioButtons
        XCTAssertEqual(unpinnedTabsAfter.count, 1,
                       "Exactly one new unpinned tab should have been created")
        // The pinned source tab is still pinned (it did not navigate away)
        XCTAssertEqual(app.pinnedTabs.count, 1,
                       "The pinned source tab should still exist after cross-domain navigation")
    }

    func testWhenPinnedTabNavigatesToDifferentDomain_ThenNewTabOpensInForeground() {
        let (sourceTitle, targetTitle, sourceURL) = makePinnedCrossDomainScenario(suffix: "Default")
        // Enable "switch to new tab when opened" — ensures plain click goes foreground via normal preference too
        app.setSwitchToNewTab(enabled: true)

        app.openURL(sourceURL, waitForWebViewAccessibilityLabel: sourceTitle)
        pinCurrentPage()

        let mainWindow = app.windows.firstMatch
        mainWindow.webViews[sourceTitle].links["Go to \(targetTitle)"].click()

        // The new tab should exist and be selected (foreground)
        XCTAssertTrue(
            mainWindow.webViews[targetTitle].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Cross-domain link from pinned tab should load in a new tab"
        )
        // New tab is selected (foreground)
        XCTAssertEqual(
            app.windows.firstMatch.title, targetTitle,
            "New tab opened from pinned tab cross-domain navigation should be selected (foreground)"
        )
        // A new unpinned tab was created — not the same tab navigating away
        let unpinnedTabsAfter = app.tabGroups.matching(identifier: "Tabs").radioButtons
        XCTAssertEqual(unpinnedTabsAfter.count, 1,
                       "Exactly one new unpinned tab should have been created")
        // The pinned source tab is still pinned (it did not navigate away)
        XCTAssertEqual(app.pinnedTabs.count, 1,
                       "The pinned source tab should still exist after cross-domain navigation")
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
        // Wait for the menu item to be available before tapping — the tab may still be
        // animating into position after a navigation (e.g. Cmd+Shift+[ / ]) which causes
        // an intermittent "No matches found" failure if we tap too early.
        XCTAssertTrue(
            app.menuItems["Pin Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Pin Tab menu item should be available"
        )
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
        // Use waitForExistence rather than .exists — after removing a pinned tab the
        // browser selects the first unpinned tab (Page #3) but the WebView needs a
        // brief moment to render its cached content before XCTest can find the text.
        XCTAssertTrue(
            app.staticTexts["Sample text for Page #3"].waitForExistence(timeout: UITests.Timeouts.elementExistence),
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
        // Wait for window 2 to fully disappear before returning — without this, callers
        // that immediately check pinnedTabs.count (via windows.firstMatch) can race
        // against the window-close animation and see stale state.
        XCTAssertTrue(
            app.wait(for: .keyPath(\.windows.count, equalTo: 1), timeout: UITests.Timeouts.elementExistence),
            "Window 2 should be closed and only window 1 should remain"
        )
    }

    private func assertPinnedTabsRestoredState(file: StaticString = #file, line: UInt = #line) {
        // Wait for the ⌘+Q quit to complete before relaunching. XCUIApplication.setUp() creates
        // a new object whose launch() can force-kill the quitting app mid-save, corrupting the session.
        // Using app.wait(for:) + app.launch() on the same object mirrors StateRestorationTests and
        // allows the session to be saved cleanly before a fresh launch restores it.
        _ = app.wait(for: .notRunning, timeout: UITests.Timeouts.localTestServer)
        app.launch()
        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: UITests.Timeouts.localTestServer),
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
