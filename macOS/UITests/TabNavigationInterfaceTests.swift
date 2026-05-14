//
//  TabNavigationInterfaceTests.swift
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

import Common
import XCTest

final class TabNavigationInterfaceTests: UITestCase, TabNavigationTestHelpers {

    override class func setUp() {
        super.setUp()
        UITests.firstRun()
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp()
    }

    // MARK: - Link Navigation Tests

    func testCommandClickOpensBackgroundTab() {
        app.setSwitchToNewTab(enabled: false)

        openTestPage("Page #1") {
            "<a href='\(UITests.simpleServedPage(titled: "Opened Tab"))'>Open in new tab</a>"
        }
        let link = app.webViews["Page #1"].links["Open in new tab"]
        XCUIElement.perform(withKeyModifiers: [.command]) {
            link.click()
        }

        XCTAssertTrue(app.tabs["Opened Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Page #1"].exists)
        XCTAssertTrue(app.tabs["Page #1"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testMiddleClickOpensBackgroundTab() {
        app.setSwitchToNewTab(enabled: false)

        openTestPage("Page #2") {
            "<a href='\(UITests.simpleServedPage(titled: "Opened Tab"))'>Open in new tab</a>"
        }
        let link = app.webViews["Page #2"].links["Open in new tab"]
        link.middleClick()

        XCTAssertTrue(app.tabs["Opened Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Page #2"].exists)
        XCTAssertTrue(app.tabs["Page #2"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testCommandShiftClickOpensActiveTab() {
        app.setSwitchToNewTab(enabled: false)

        openTestPage("Page #3") {
            "<a href='\(UITests.simpleServedPage(titled: "Opened Tab"))'>Open in new tab</a>"
        }
        let link = app.webViews["Page #3"].links["Open in new tab"]
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            link.click()
        }

        XCTAssertTrue(app.webViews["Opened Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Page #3"].exists)
        XCTAssertTrue(app.tabs["Opened Tab"].exists)
        XCTAssertTrue(app.tabs["Page #3"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testMiddleShiftClickOpensActiveTab() {
        app.setSwitchToNewTab(enabled: false)

        openTestPage("Page #4") {
            "<a href='\(UITests.simpleServedPage(titled: "Opened Tab"))'>Open in new tab</a>"
        }
        let link = app.webViews["Page #4"].links["Open in new tab"]
        XCUIElement.perform(withKeyModifiers: [.shift]) {
            link.middleClick()
        }
        XCTAssertTrue(app.webViews["Opened Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Page #4"].exists)
        XCTAssertTrue(app.tabs["Opened Tab"].exists)
        XCTAssertTrue(app.tabs["Page #4"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testCommandOptionClickOpensBackgroundWindow() {
        app.setSwitchToNewTab(enabled: false)

        openTestPage("Page #5") {
            "<a href='\(UITests.simpleServedPage(titled: "New Window Page"))'>Open in new window</a>"
        }
        let link = app.webViews["Page #5"].links["Open in new window"]
        XCUIElement.perform(withKeyModifiers: [.command, .option]) {
            link.click()
        }

        let mainWindow = app.windows.firstMatch
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertTrue(backgroundWindow.webViews["New Window Page"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(mainWindow.webViews["New Window Page"].exists)

        XCTAssertTrue(mainWindow.webViews["Page #5"].exists)
        XCTAssertFalse(mainWindow.webViews["New Window Page"].exists)

        XCTAssertTrue(mainWindow.tabs["Page #5"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 1)

        XCTAssertTrue(backgroundWindow.tabs["New Window Page"].exists)
        XCTAssertEqual(backgroundWindow.tabs.count, 1)
    }

    func testMiddleOptionClickOpensBackgroundWindow() {
        app.setSwitchToNewTab(enabled: false)

        openTestPage("Page #6") {
            "<a href='\(UITests.simpleServedPage(titled: "New Window Page"))'>Open in new window</a>"
        }
        let link = app.webViews["Page #6"].links["Open in new window"]
        XCUIElement.perform(withKeyModifiers: [.option]) {
            link.middleClick()
        }

        let mainWindow = app.windows.firstMatch
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertTrue(backgroundWindow.webViews["New Window Page"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(mainWindow.webViews["New Window Page"].exists)

        XCTAssertTrue(mainWindow.webViews["Page #6"].exists)
        XCTAssertFalse(mainWindow.webViews["New Window Page"].exists)

        XCTAssertTrue(mainWindow.tabs["Page #6"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 1)

        XCTAssertTrue(backgroundWindow.tabs["New Window Page"].exists)
        XCTAssertEqual(backgroundWindow.tabs.count, 1)
    }

    func testCommandOptionShiftClickOpensActiveWindow() {
        app.setSwitchToNewTab(enabled: false)

        openTestPage("Page #7") {
            "<a href='\(UITests.simpleServedPage(titled: "New Window Page"))'>Open in new window</a>"
        }
        let link = app.webViews["Page #7"].links["Open in new window"]
        XCUIElement.perform(withKeyModifiers: [.command, .option, .shift]) {
            link.click()
        }

        let activeWindow = app.windows.firstMatch
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertTrue(activeWindow.webViews["New Window Page"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(activeWindow.webViews["Page #7"].exists)

        XCTAssertTrue(activeWindow.tabs["New Window Page"].exists)
        XCTAssertEqual(activeWindow.tabs.count, 1)
    }

    func testMiddleOptionShiftClickOpensActiveWindow() {
        app.setSwitchToNewTab(enabled: false)

        openTestPage("Page #8") {
            "<a href='\(UITests.simpleServedPage(titled: "New Window Page"))'>Open in new window</a>"
        }
        let link = app.webViews["Page #8"].links["Open in new window"]
        XCUIElement.perform(withKeyModifiers: [.option, .shift]) {
            link.middleClick()
        }

        let activeWindow = app.windows.firstMatch
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertTrue(activeWindow.webViews["New Window Page"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(activeWindow.webViews["Page #8"].exists)

        XCTAssertTrue(activeWindow.tabs["New Window Page"].exists)
        XCTAssertEqual(activeWindow.tabs.count, 1)
    }

    func _testOptionClickDownloadsContent() {
        openTestPage("Page #9") {
            "<a href='data:application/zip;base64,UEsDBBQAAAAIAA==' download='file.zip'>Download file</a>"
        }
        let link = app.webViews["Page #9"].links["Download file"]
        XCUIElement.perform(withKeyModifiers: [.option]) {
            link.click()
        }

        XCTAssertTrue(app.downloadsButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.staticTexts["Downloading file.zip"].exists)
        XCTAssertTrue(app.tabs["Page #9"].exists)
        XCTAssertEqual(app.tabs.count, 1)
    }

    // MARK: - Settings and Special Cases Tests

    func testSettingsImpactOnTabBehavior() {
        app.setSwitchToNewTab(enabled: true)

        // Test inverted behavior
        openTestPage("Page #10") {
            "<a href='\(UITests.simpleServedPage(titled: "Opened Tab"))'>Open in new tab</a>"
        }
        let link = app.webViews["Page #10"].links["Open in new tab"]
        XCUIElement.perform(withKeyModifiers: [.command]) {
            link.click()
        }

        XCTAssertTrue(app.webViews["Opened Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Page #10"].exists)
        XCTAssertTrue(app.tabs["Opened Tab"].exists)
        XCTAssertTrue(app.tabs["Page #10"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func _testPinnedTabsNavigation() {
        // Pin a tab
        openTestPage("Page #11") {
            "<a href='\(UITests.simpleServedPage(titled: "Opened Tab"))'>Open in new tab</a>"
        }
        app.mainMenuPinTabMenuItem.click()

        // Try to navigate in pinned tab
        let link = app.webViews["Page #11"].links["Open in new tab"]
        XCUIElement.perform(withKeyModifiers: [.command]) {
            link.click()
        }

        // Should open in new tab since pinned tabs can't navigate
        XCTAssertTrue(app.tabs["Opened Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Page #11"].exists)
        XCTAssertTrue(app.tabs["Page #11"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    // MARK: - Back/Forward Navigation Tests

    func testBackForwardCommandClickOpensBackgroundTab() {
        app.setSwitchToNewTab(enabled: false)

        // Create navigation history
        openTestPage("Page #17")
        app.activateAddressBar()
        openTestPage("Page #18")
        app.activateAddressBar()
        openTestPage("Page #19")

        // Go back to Page #18
        app.backButton.click()
        XCTAssertTrue(app.webViews["Page #18"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertEqual(app.tabs.count, 1)

        // Command click back button should open Page #17 in background tab
        XCUIElement.perform(withKeyModifiers: [.command]) {
            app.backButton.click()
        }

        XCTAssertTrue(app.tabs["Page #17"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Page #18"].exists)       // Original page still visible
        XCTAssertFalse(app.webViews["Page #17"].exists)      // Back page in background
        XCTAssertTrue(app.tabs["Page #17"].exists)
        XCTAssertTrue(app.tabs["Page #18"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testBackForwardCommandShiftClickOpensActiveTab() {
        app.setSwitchToNewTab(enabled: false)

        // Create navigation history
        openTestPage("Page #17")
        app.activateAddressBar()
        openTestPage("Page #18")
        app.activateAddressBar()
        openTestPage("Page #19")

        // Go back to Page #18
        app.backButton.click()
        XCTAssertTrue(app.webViews["Page #18"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertEqual(app.tabs.count, 1)

        // Command+Shift click back button should open Page #17 in foreground tab
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            app.backButton.click()
        }

        XCTAssertTrue(app.webViews["Page #17"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Page #18"].exists)      // Original page now in background
        XCTAssertTrue(app.tabs["Page #17"].exists)
        XCTAssertTrue(app.tabs["Page #18"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testBackForwardMiddleClickOpensBackgroundTab() {
        app.setSwitchToNewTab(enabled: false)

        // Create navigation history
        openTestPage("Page #17")
        app.activateAddressBar()
        openTestPage("Page #18")
        app.activateAddressBar()
        openTestPage("Page #19")

        // Go back to Page #18
        app.backButton.click()
        XCTAssertTrue(app.webViews["Page #18"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertEqual(app.tabs.count, 1)

        // Middle click back button should open Page #17 in background tab
        app.backButton.middleClick()

        XCTAssertTrue(app.tabs["Page #17"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Page #18"].exists)       // Original page still visible
        XCTAssertFalse(app.webViews["Page #17"].exists)      // Back page in background
        XCTAssertTrue(app.tabs["Page #17"].exists)
        XCTAssertTrue(app.tabs["Page #18"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testBackForwardMiddleShiftClickOpensActiveTab() {
        app.setSwitchToNewTab(enabled: false)

        // Create navigation history
        openTestPage("Page #17")
        app.activateAddressBar()
        openTestPage("Page #18")
        app.activateAddressBar()
        openTestPage("Page #19")

        // Go back to Page #18
        app.backButton.click()
        XCTAssertTrue(app.webViews["Page #18"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertEqual(app.tabs.count, 1)

        // Middle+Shift click back button should open Page #17 in foreground tab
        XCUIElement.perform(withKeyModifiers: [.shift]) {
            app.backButton.middleClick()
        }

        XCTAssertTrue(app.webViews["Page #17"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Page #18"].exists)      // Original page now in background
        XCTAssertTrue(app.tabs["Page #17"].exists)
        XCTAssertTrue(app.tabs["Page #18"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testForwardNavigationCommandClickOpensBackgroundTab() {
        app.setSwitchToNewTab(enabled: false)

        // Create navigation history and go back
        openTestPage("Page #17")
        app.activateAddressBar()
        openTestPage("Page #18")
        app.activateAddressBar()
        openTestPage("Page #19")

        // Go back twice to Page #17
        app.backButton.click()
        app.backButton.click()
        XCTAssertTrue(app.webViews["Page #17"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertEqual(app.tabs.count, 1)

        // Command click forward button should open Page #18 in background tab
        XCUIElement.perform(withKeyModifiers: [.command]) {
            app.forwardButton.click()
        }

        XCTAssertTrue(app.tabs["Page #18"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Page #17"].exists)       // Original page still visible
        XCTAssertFalse(app.webViews["Page #18"].exists)      // Forward page in background
        XCTAssertTrue(app.tabs["Page #17"].exists)
        XCTAssertTrue(app.tabs["Page #18"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testForwardNavigationCommandShiftClickOpensActiveTab() {
        app.setSwitchToNewTab(enabled: false)

        // Create navigation history and go back
        openTestPage("Page #17")
        app.activateAddressBar()
        openTestPage("Page #18")
        app.activateAddressBar()
        openTestPage("Page #19")

        // Go back twice to Page #17
        app.backButton.click()
        app.backButton.click()
        XCTAssertTrue(app.webViews["Page #17"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertEqual(app.tabs.count, 1)

        // Command+Shift click forward button should open Page #18 in foreground tab
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            app.forwardButton.click()
        }

        XCTAssertTrue(app.webViews["Page #18"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Page #17"].exists)      // Original page now in background
        XCTAssertTrue(app.tabs["Page #17"].exists)
        XCTAssertTrue(app.tabs["Page #18"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testForwardNavigationMiddleClickOpensBackgroundTab() {
        app.setSwitchToNewTab(enabled: false)

        // Create navigation history and go back
        openTestPage("Page #17")
        app.activateAddressBar()
        openTestPage("Page #18")
        app.activateAddressBar()
        openTestPage("Page #19")

        // Go back twice to Page #17
        app.backButton.click()
        app.backButton.click()
        XCTAssertTrue(app.webViews["Page #17"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertEqual(app.tabs.count, 1)

        // Middle click forward button should open Page #18 in background tab
        app.forwardButton.middleClick()

        XCTAssertTrue(app.tabs["Page #18"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Page #17"].exists)       // Original page still visible
        XCTAssertFalse(app.webViews["Page #18"].exists)      // Forward page in background
        XCTAssertTrue(app.tabs["Page #17"].exists)
        XCTAssertTrue(app.tabs["Page #18"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testForwardNavigationMiddleShiftClickOpensActiveTab() {
        app.setSwitchToNewTab(enabled: false)

        // Create navigation history and go back
        openTestPage("Page #17")
        app.activateAddressBar()
        openTestPage("Page #18")
        app.activateAddressBar()
        openTestPage("Page #19")

        // Go back twice to Page #17
        app.backButton.click()
        app.backButton.click()
        XCTAssertTrue(app.webViews["Page #17"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertEqual(app.tabs.count, 1)

        // Middle+Shift click forward button should open Page #18 in foreground tab
        XCUIElement.perform(withKeyModifiers: [.shift]) {
            app.forwardButton.middleClick()
        }

        XCTAssertTrue(app.webViews["Page #18"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Page #17"].exists)      // Original page now in background
        XCTAssertTrue(app.tabs["Page #17"].exists)
        XCTAssertTrue(app.tabs["Page #18"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    // MARK: - Address Bar and Context Menu Tests

    func testAddressBarSuggestionsNavigation() throws {
        app.setSwitchToNewTab(enabled: false)

        openTestPage("Bookmarked Page #20")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()
        app.enforceSingleWindow()

        // Type to get suggestions
        app.addressBar.typeText("Bookmarked Page #20")

        // Command click suggestion should open in background
        let suggestion = app.tables["SuggestionViewController.tableView"].cells.staticTexts["Bookmarked Page #20"].firstMatch // Get the first match to differentiate from Duck.ai suggestions
        XCTAssertTrue(suggestion.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        var coordinate = suggestion.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        coordinate.hover()
        XCUIElement.perform(withKeyModifiers: [.command]) {
            coordinate.click()
        }

        XCTAssertTrue(app.tabs["Bookmarked Page #20"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["New Tab Page"].exists)
        XCTAssertTrue(app.tabs["New Tab"].exists)
        XCTAssertEqual(app.tabs.count, 2)
        try app.tabs.element(boundBy: 1).closeTab()

        app.activateAddressBar()
        app.addressBar.typeText("Bookmarked Page #20")

        XCTAssertTrue(suggestion.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Command shift click suggestion should open in foreground
        coordinate = suggestion.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        coordinate.hover()
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            coordinate.click()
        }
        XCTAssertTrue(app.tabs["Bookmarked Page #20"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["New Tab Page"].exists)
        XCTAssertTrue(app.tabs["New Tab"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testContextMenuNavigation() {
        app.setSwitchToNewTab(enabled: false)

        openTestPage("Page #21") {
            "<a href='\(UITests.simpleServedPage(titled: "Page #22"))'>Open in new tab</a>"
        }
        let link = app.webViews["Page #21"].links["Open in new tab"]

        // Right click to show context menu
        link.rightClick()

        // Command click menu item should open in background
        let menuItem = app.menuItems["Open Link in New Tab"]
        XCTAssertTrue(menuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        menuItem.click()

        XCTAssertTrue(app.tabs["Page #22"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Page #21"].exists)
        XCTAssertFalse(app.webViews["Page #22"].exists)
        XCTAssertTrue(app.tabs["Page #21"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testContextMenuNavigationWithForegroundTabSetting() {
        // First enable "switch to new tab immediately" setting
        app.setSwitchToNewTab(enabled: true)

        // Open test page with link
        openTestPage("Page #23") {
            "<a href='\(UITests.simpleServedPage(titled: "Page #24"))'>Open in new tab</a>"
        }
        let link = app.webViews["Page #23"].links["Open in new tab"]

        // Right click to show context menu
        link.rightClick()

        // Regular click on "Open Link in New Tab" should now open in foreground
        let menuItem = app.menuItems["Open Link in New Tab"]
        XCTAssertTrue(menuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        menuItem.click()

        // Verify new tab opens in foreground (becomes active)
        XCTAssertTrue(app.webViews["Page #24"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Page #23"].exists) // Original page should be in background
        XCTAssertTrue(app.webViews["Page #24"].exists) // New tab should be in foreground
        XCTAssertTrue(app.tabs["Page #23"].exists)
        XCTAssertTrue(app.tabs["Page #24"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }
}
