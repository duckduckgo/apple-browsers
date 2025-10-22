//
//  FireDialogHistoryDateDeletionUITests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/// History View Date-based Deletion Fire Dialog UI tests
final class FireDialogHistoryDateDeletionUITests: UITestCase, FireDialogUITests {

    override func setUp() {
        super.setUp()
        setUpFireDialogUITests()
    }

    func test_historyView_deleteToday_historyAndCookies() throws {
        // First, populate fake history from debug menu to have yesterday/older history
        populateFakeHistoryFromDebugMenu()

        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!

        // Visit sites and set storage TODAY
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        let todaySite1Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: todaySite1Title)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Verify today's sites exist
        XCTAssertTrue(historyWebView.links[todaySite1Title].waitForExistence(timeout: UITests.Timeouts.elementExistence), "Today's site should be in history")
        XCTAssertTrue(historyWebView.links.element(matching: .keyPath(\.title, contains: "Local Storage")).exists, "Storage site should be in today's history")

        // Verify yesterday section exists (from fake history)
        let yesterdayButton = historyWebView.buttons["Show history for yesterday"]
        XCTAssertTrue(yesterdayButton.exists, "Yesterday button should exist from fake history")

        // Hover "today" section button to reveal delete button
        let todayButton = historyWebView.buttons["Show history for today"]
        XCTAssertTrue(todayButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Today button should exist")
        todayButton.hover()

        // Click delete button for today
        let deleteTodayButton = historyWebView.buttons["Delete history for today"]
        XCTAssertTrue(deleteTodayButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Delete today button should appear on hover")
        deleteTodayButton.click()

        // Verify Fire dialog opens
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Verify no scope pill appears
        XCTAssertFalse(app.fireDialogSegmentedControl.exists, "Scope pill should not appear for date deletion")

        // Configure toggles: history + cookies
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })

        // Burn
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify History view still open
        XCTAssertTrue(historyWebView.exists, "History view should still be open")

        // Navigate to "today" section to verify it's now empty
        todayButton.click()

        let emptyHistoryText = historyWebView.staticTexts["No browsing history yet."]
        XCTAssertTrue(emptyHistoryText.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Today section should show empty message after deletion")

        // Navigate to yesterday section to verify it still has history
        yesterdayButton.click()
        XCTAssertFalse(emptyHistoryText.exists, "Yesterday section should not be empty")

        // Refresh history (Cmd+R)
        app.typeKey("r", modifierFlags: [.command])
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should still exist after refresh")

        // Verify today still shows empty state after refresh
        todayButton.click()
        XCTAssertTrue(emptyHistoryText.exists, "Today section should still show empty message after refresh")

        // Verify yesterday still has history after refresh
        yesterdayButton.click()
        XCTAssertFalse(emptyHistoryText.exists, "Yesterday section should still have history after refresh")

        // Verify storage was cleared
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyCountersCleared()
    }

    func test_historyView_deleteYesterday_onlyHistory() throws {
        // Populate fake history from debug menu to ensure we have yesterday's history
        populateFakeHistoryFromDebugMenu()

        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!

        // Visit sites and set storage today
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        let todaySiteTitle = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: todaySiteTitle)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Verify yesterday section exists
        let yesterdayButton = historyWebView.buttons["Show history for yesterday"]
        XCTAssertTrue(yesterdayButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Yesterday button should exist")

        // Hover "yesterday" section button to reveal delete button
        yesterdayButton.hover()

        // Click delete button for yesterday
        let deleteYesterdayButton = historyWebView.buttons["Delete history for yesterday"]
        XCTAssertTrue(deleteYesterdayButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Delete yesterday button should appear on hover")
        deleteYesterdayButton.click()

        // Verify Fire dialog opens
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Verify no scope pill appears
        XCTAssertFalse(app.fireDialogSegmentedControl.exists, "Scope pill should not appear for date deletion")

        // Verify no Close tabs toggle
        XCTAssertFalse(fireDialogTabsToggle.exists, "Tabs toggle should not appear for date-based deletion")

        // Configure toggles: only history
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })

        // Burn
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify History view still open
        XCTAssertTrue(historyWebView.exists, "History view should still be open")

        // Navigate to "today" section to verify it still has history
        let todayButton = historyWebView.buttons["Show history for today"]
        todayButton.click()
        XCTAssertTrue(historyWebView.links[todaySiteTitle].exists, "Today's site should still be in history")

        // Navigate to "yesterday" section to verify it's now empty
        yesterdayButton.click()

        let emptyHistoryText = historyWebView.staticTexts["No browsing history yet."]
        XCTAssertTrue(emptyHistoryText.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Yesterday section should show empty message after deletion")

        // Refresh history (Cmd+R)
        app.typeKey("r", modifierFlags: [.command])
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should still exist after refresh")

        // Verify today's site still preserved after refresh
        todayButton.click()
        XCTAssertTrue(historyWebView.links[todaySiteTitle].exists, "Today's site should still be in history after refresh")

        // Verify yesterday still shows empty state after refresh
        yesterdayButton.click()
        XCTAssertTrue(emptyHistoryText.exists, "Yesterday section should still show empty message after refresh")

        // Verify storage was preserved (cookies toggle was off)
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyInitialCountersSet()
    }

    func test_historyView_deleteWeekDay_onlyCookies() throws {
        // Populate fake history from debug menu to ensure we have week day history
        populateFakeHistoryFromDebugMenu()

        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!

        // Visit sites and set storage
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        let todaySiteTitle = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: todaySiteTitle)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Find any week day button (Monday through Sunday)
        let weekDays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        var foundWeekDayButton: XCUIElement?
        var foundDay = ""
        for day in weekDays {
            let button = historyWebView.buttons["Show history for \(day)"]
            if button.exists {
                foundWeekDayButton = button
                foundDay = day
                break
            }
        }

        XCTAssertNotNil(foundWeekDayButton, "At least one week day section should exist")

        // Hover week day section button to reveal delete button
        foundWeekDayButton!.hover()

        // Click delete button for week day
        let deleteWeekDayButton = historyWebView.buttons["Delete history for \(foundDay)"]
        XCTAssertTrue(deleteWeekDayButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Delete week day button should appear on hover")
        deleteWeekDayButton.click()

        // Verify Fire dialog opens
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Verify no scope pill appears
        XCTAssertFalse(app.fireDialogSegmentedControl.exists, "Scope pill should not appear for date deletion")

        // Verify no Close tabs toggle
        XCTAssertFalse(fireDialogTabsToggle.exists, "Tabs toggle should not appear for date-based deletion")

        // Configure toggles: only cookies
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: false, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })

        // Burn
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify History view still open
        XCTAssertTrue(historyWebView.exists, "History view should still be open")

        // Navigate to "today" section to verify it still has history
        let todayButton = historyWebView.buttons["Show history for today"]
        todayButton.click()
        XCTAssertTrue(historyWebView.links[todaySiteTitle].exists, "Today's site should still be in history (history toggle was off)")

        // Navigate to the week day section to verify it still has history (history toggle was off)
        foundWeekDayButton!.click()

        let emptyHistoryText = historyWebView.staticTexts["No browsing history yet."]
        XCTAssertFalse(emptyHistoryText.exists, "\(foundDay) section should NOT be empty when history toggle was off")

        // Refresh history (Cmd+R)
        app.typeKey("r", modifierFlags: [.command])
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should still exist after refresh")

        // Verify today's site still preserved after refresh
        todayButton.click()
        XCTAssertTrue(historyWebView.links[todaySiteTitle].exists, "Today's site should still be in history after refresh")

        // Verify week day still has history after refresh (history toggle was off)
        foundWeekDayButton!.click()
        XCTAssertFalse(emptyHistoryText.exists, "\(foundDay) section should still NOT be empty after refresh when history toggle was off")

        // Verify storage was cleared (cookies toggle was on)
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyInitialCountersSet()
    }

    func test_historyView_deleteOlder_historyAndCookies() throws {
        // Populate fake history from debug menu to ensure we have older history
        populateFakeHistoryFromDebugMenu()

        let storageURL = URL(string: "https://privacy-test-pages.site/features/local-storage.html")!

        // Visit sites and set storage today
        app.openURL(storageURL)
        setStorageAndCookies()
        verifyCountersSet()

        let todaySiteTitle = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: todaySiteTitle)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Verify older section exists
        let olderButton = historyWebView.buttons["Show older history"]
        XCTAssertTrue(olderButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Older button should exist")

        // Hover "Older" section button to reveal delete button
        olderButton.hover()

        // Click delete button for older
        let deleteOlderButton = historyWebView.buttons["Delete older history"]
        XCTAssertTrue(deleteOlderButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Delete older button should appear on hover")
        deleteOlderButton.click()

        // Verify Fire dialog opens
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fire dialog should open")

        // Verify no scope pill appears
        XCTAssertFalse(app.fireDialogSegmentedControl.exists, "Scope pill should not appear for date deletion")

        // Verify no Close tabs toggle
        XCTAssertFalse(fireDialogTabsToggle.exists, "Tabs toggle should not appear for date-based deletion")

        // Configure toggles: history + cookies
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })

        // Burn
        fireDialogBurnButton.click()
        waitForFireAnimationToComplete()

        // Verify History view still open
        XCTAssertTrue(historyWebView.exists, "History view should still be open")

        // Navigate to "today" section to verify it still has history
        let todayButton = historyWebView.buttons["Show history for today"]
        todayButton.click()
        XCTAssertTrue(historyWebView.links[todaySiteTitle].exists, "Today's site should still be in history")

        // Verify "older" section no longer exists (it disappears when empty)
        XCTAssertFalse(olderButton.exists, "Older section should not exist after deletion")

        // Refresh history (Cmd+R)
        app.typeKey("r", modifierFlags: [.command])
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should still exist after refresh")

        // Verify today's site still preserved after refresh
        todayButton.click()
        XCTAssertTrue(historyWebView.links[todaySiteTitle].exists, "Today's site should still be in history after refresh")

        // Verify older section still doesn't exist after refresh
        XCTAssertFalse(olderButton.exists, "Older section should still not exist after refresh")

        // Storage cleared for older history, but today's storage is new so we verify it was cleared
        app.activateAddressBar()
        app.openURL(storageURL)
        verifyInitialCountersSet()
    }

}
