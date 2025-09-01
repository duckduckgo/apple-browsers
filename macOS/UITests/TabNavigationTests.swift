//
//  TabNavigationTests.swift
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

import Common
import XCTest

class TabNavigationTests: UITestCase {

    private static var isSwitchToNewTabEnabled: Bool?

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
        setSwitchToNewTab(enabled: false)

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
        setSwitchToNewTab(enabled: false)

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
        setSwitchToNewTab(enabled: false)

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
        setSwitchToNewTab(enabled: false)

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
        setSwitchToNewTab(enabled: false)

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
        setSwitchToNewTab(enabled: false)

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
        setSwitchToNewTab(enabled: false)

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
        setSwitchToNewTab(enabled: false)

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
        setSwitchToNewTab(enabled: true)

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

    func testPopupWindowsNavigation() {
        setSwitchToNewTab(enabled: false)

        // Open a popup window
        let popupHTML = """
        <a href='\(UITests.simpleServedPage(titled: "New Tab"))' target='_blank'>Open in new tab</a>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let mainWindow = app.windows.containing(NSPredicate(format: "title == 'Page #12'")).firstMatch
        let popupLink = mainWindow.webViews["Page #12"].links["Open popup"]
        popupLink.click()

        // Try to navigate in popup
        let popupWindow = app.windows.containing(NSPredicate(format: "title == 'Popup Page'")).firstMatch
        let link = popupWindow.webViews["Popup Page"].links["Open in new tab"]
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        link.click()

        // Should open in new tab of the original window
        XCTAssertEqual(app.windows.count, 2)
        XCTAssertTrue(mainWindow.webViews["New Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(mainWindow.tabs["Page #12"].exists)
        XCTAssertTrue(mainWindow.tabs["New Tab"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 2)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify main window is frontmost
        XCTAssertEqual(app.windows.firstMatch.title, mainWindow.title, "Main window should be frontmost after popup navigation")
        XCTAssertNotEqual(app.windows.firstMatch.title, popupWindow.title, "Main window should be frontmost after popup navigation")
    }

    func testPopupCommandClickOpensBackgroundTab() {
        setSwitchToNewTab(enabled: false)

        // Open a popup window
        let popupHTML = """
        <a href='\(UITests.simpleServedPage(titled: "Page #13"))'>Open Page #13</a>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let mainWindow = app.windows.containing(NSPredicate(format: "title == 'Page #12'")).firstMatch
        let popupLink = mainWindow.webViews["Page #12"].links["Open popup"]
        popupLink.click()

        // Command click in popup - should open in background tab in main window
        let popupWindow = app.windows.containing(NSPredicate(format: "title == 'Popup Page'")).firstMatch
        let link = popupWindow.webViews["Popup Page"].links["Open Page #13"]
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command]) {
            link.click()
        }

        // Should open in background tab in main window, popup remains frontmost
        XCTAssertTrue(mainWindow.tabs["Page #13"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)
        XCTAssertTrue(mainWindow.webViews["Page #12"].exists)
        XCTAssertFalse(mainWindow.webViews["Page #13"].exists) // Original page still in foreground
        XCTAssertTrue(mainWindow.tabs["Page #12"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 2)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify popup window remains frontmost (background operation)
        XCTAssertEqual(app.windows.firstMatch.title, popupWindow.title, "Popup window should remain frontmost for background operations")
    }

    func testPopupCommandShiftClickOpensForegroundTab() {
        setSwitchToNewTab(enabled: false)

        // Open a popup window
        let popupHTML = """
        <a href='\(UITests.simpleServedPage(titled: "Page #14"))'>Open Page #14</a>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let mainWindow = app.windows.containing(NSPredicate(format: "title == 'Page #12'")).firstMatch
        let popupLink = mainWindow.webViews["Page #12"].links["Open popup"]
        popupLink.click()

        // Command shift click in popup - should open in foreground tab in main window
        let popupWindow = app.windows.containing(NSPredicate(format: "title == 'Popup Page'")).firstMatch
        let link = popupWindow.webViews["Popup Page"].links["Open Page #14"]
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            link.click()
        }

        // Should open in foreground tab in main window
        XCTAssertEqual(app.windows.count, 2) // Main window + popup window
        XCTAssertTrue(mainWindow.webViews["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(mainWindow.webViews["Page #12"].exists) // Original page now in background
        XCTAssertTrue(mainWindow.tabs["Page #12"].exists)
        XCTAssertTrue(mainWindow.tabs["Page #14"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 2)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify main window is frontmost
        XCTAssertEqual(app.windows.firstMatch.title, mainWindow.title, "Main window should be frontmost after popup navigation")
    }

    func testPopupCommandOptionClickOpensBackgroundWindow() {
        setSwitchToNewTab(enabled: false)

        // Open a popup window
        let popupHTML = """
        <a href='\(UITests.simpleServedPage(titled: "Page #15"))'>Open Page #15</a>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let mainWindow = app.windows.containing(NSPredicate(format: "title == 'Page #12'")).firstMatch
        let popupLink = mainWindow.webViews["Page #12"].links["Open popup"]
        popupLink.click()

        // Command option click in popup - should open in background window
        let popupWindow = app.windows.containing(NSPredicate(format: "title == 'Popup Page'")).firstMatch
        let link = popupWindow.webViews["Popup Page"].links["Open Page #15"]
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command, .option]) {
            link.click()
        }

        // Should open in background window, popup remains frontmost
        let backgroundWindow = app.windows.element(boundBy: 2) // Now third window (main, popup, background)
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(backgroundWindow.webViews["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 3)

        XCTAssertTrue(mainWindow.webViews["Page #12"].exists)
        XCTAssertFalse(mainWindow.webViews["Page #15"].exists)
        XCTAssertTrue(mainWindow.tabs["Page #12"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 1)

        XCTAssertTrue(backgroundWindow.tabs["Page #15"].exists)
        XCTAssertEqual(backgroundWindow.tabs.count, 1)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify popup window remains frontmost (background window operation)
        XCTAssertEqual(app.windows.firstMatch.title, popupWindow.title, "Popup window should remain frontmost for background operations")
    }

    func testPopupCommandOptionShiftClickOpensForegroundWindow() {
        setSwitchToNewTab(enabled: false)

        // Open a popup window
        let popupHTML = """
        <a href='\(UITests.simpleServedPage(titled: "Page #16"))'>Open Page #16</a>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let mainWindow = app.windows.containing(NSPredicate(format: "title == 'Page #12'")).firstMatch
        let popupLink = mainWindow.webViews["Page #12"].links["Open popup"]
        popupLink.click()

        // Command option shift click in popup - should open in foreground window
        let popupWindow = app.windows.containing(NSPredicate(format: "title == 'Popup Page'")).firstMatch
        let link = popupWindow.webViews["Popup Page"].links["Open Page #16"]
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command, .option, .shift]) {
            link.click()
        }

        // Should open in foreground window
        let activeWindow = app.windows.firstMatch
        XCTAssertTrue(activeWindow.webViews["Page #16"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 3) // Main window + popup window + new foreground window

        XCTAssertFalse(activeWindow.webViews["Page #12"].exists)
        XCTAssertTrue(activeWindow.tabs["Page #16"].exists)
        XCTAssertEqual(activeWindow.tabs.count, 1)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify new window is frontmost (foreground window operation)
        let foregroundWindow = app.windows.containing(NSPredicate(format: "title == 'Page #16'")).firstMatch
        XCTAssertEqual(app.windows.firstMatch.title, foregroundWindow.title, "New window should be frontmost when opened in foreground")
    }

    // MARK: - Fire Window Popup Navigation Tests

    func testFireWindowPopupCommandClickOpensBackgroundTab() {
        setSwitchToNewTab(enabled: false)

        app.closeWindow()
        // Open Fire window
        app.openFireWindow()

        // Open a popup window from Fire window
        let popupHTML = """
        <a href='\(UITests.simpleServedPage(titled: "Page #13"))'>Open Page #13</a>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Fire Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let fireWindow = app.windows.containing(NSPredicate(format: "title == 'Fire Page #12'")).firstMatch
        let popupLink = fireWindow.webViews["Fire Page #12"].links["Open popup"]
        popupLink.click()

        // Command click in popup - should open in background tab in Fire window
        let popupWindow = app.windows.containing(.link, identifier: "Open Page #13").firstMatch
        let link = popupWindow.links["Open Page #13"]
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command]) {
            link.click()
        }

        // Should open in background tab in Fire window, popup remains frontmost
        XCTAssertEqual(app.windows.count, 2)
        XCTAssertTrue(fireWindow.tabs["Page #13"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(fireWindow.tabs["Fire Page #12"].exists)
        XCTAssertTrue(fireWindow.webViews["Fire Page #12"].exists) // Original Fire page still in foreground
        XCTAssertEqual(fireWindow.tabs.count, 2)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify popup link still available
        XCTAssertTrue(link.exists, "Popup link should still be available after navigation")

        // Verify popup window remains frontmost (background operation)
        XCTAssertEqual(app.windows.firstMatch.title, popupWindow.title, "Popup window should remain frontmost for background operations")
    }

    func testFireWindowPopupBackgroundAndForegroundTab() {
        setSwitchToNewTab(enabled: false)

        app.closeWindow()
        // Open Fire window
        app.openFireWindow()

        // Open a popup window from Fire window
        let popupHTML = """
        <a href='\(UITests.simpleServedPage(titled: "Page #14"))' id='link14'>Open Page #14</a>
        <a href='\(UITests.simpleServedPage(titled: "Page #15"))' id='link15'>Open Page #15</a>
        <a href='\(UITests.simpleServedPage(titled: "Page #16"))' id='link16'>Open Page #16</a>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Fire Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let fireWindow = app.windows.containing(NSPredicate(format: "title == 'Fire Page #12'")).firstMatch
        let popupLink = fireWindow.webViews["Fire Page #12"].links["Open popup"]
        popupLink.click()

        let popupWindow = app.windows.containing(.link, identifier: "Open Page #15").firstMatch
        XCTAssertTrue(popupWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Test 1: Command+Option click - should open in background Fire window
        let link15 = popupWindow.links["Open Page #15"]
        XCTAssertTrue(link15.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command, .option]) {
            link15.click()
        }

        // Should open in background Fire window
        let backgroundFireWindow = app.windows.element(boundBy: 2) // Main Fire, popup, background Fire
        XCTAssertTrue(backgroundFireWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(backgroundFireWindow.tabs["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(backgroundFireWindow.webViews["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 3)

        XCTAssertEqual(backgroundFireWindow.tabs.count, 1)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify popup link still available
        XCTAssertTrue(link15.exists, "Popup link should still be available after navigation")

        // Verify popup window remains frontmost (background Fire window operation)
        XCTAssertEqual(app.windows.firstMatch.title, popupWindow.title, "Popup window should remain frontmost for background Fire window operations")

        // Test 2: Command+Shift click - should open in foreground tab in Fire window (end test after this)
        let link14 = popupWindow.links["Open Page #14"]
        XCTAssertTrue(link14.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            link14.click()
        }

        // Should open in foreground tab in Fire window
        XCTAssertEqual(app.windows.count, 3) // Main Fire + popup + background Fire
        XCTAssertTrue(fireWindow.tabs["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(fireWindow.webViews["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(fireWindow.webViews["Fire Page #12"].exists) // Original page now in background
        XCTAssertTrue(fireWindow.tabs["Fire Page #12"].exists)
        XCTAssertEqual(fireWindow.tabs.count, 2)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify Fire window is frontmost (foreground tab operation ends test)
        XCTAssertEqual(app.windows.firstMatch.title, fireWindow.title, "Fire window should be frontmost after popup navigation")
    }

    func testFireWindowPopupForegroundWindow() {
        setSwitchToNewTab(enabled: false)

        app.closeWindow()
        // Open Fire window
        app.openFireWindow()

        // Open a popup window from Fire window
        let popupHTML = """
        <a href='\(UITests.simpleServedPage(titled: "Page #16"))' id='link16'>Open Page #16</a>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Fire Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let fireWindow = app.windows.containing(NSPredicate(format: "title == 'Fire Page #12'")).firstMatch
        let popupLink = fireWindow.webViews["Fire Page #12"].links["Open popup"]
        popupLink.click()

        let popupWindow = app.windows.containing(.link, identifier: "Open Page #16").firstMatch
        XCTAssertTrue(popupWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Command+Option+Shift click - should open in foreground Fire window
        let link16 = popupWindow.links["Open Page #16"]
        XCTAssertTrue(link16.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command, .option, .shift]) {
            link16.click()
        }

        // Should open in foreground Fire window
        let foregroundFireWindow = app.windows.firstMatch
        XCTAssertTrue(foregroundFireWindow.tabs["Page #16"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(foregroundFireWindow.webViews["Page #16"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 3) // Original Fire + popup + foreground Fire

        XCTAssertEqual(foregroundFireWindow.tabs.count, 1)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify new Fire window is frontmost (foreground Fire window operation)
        let newFireWindow = app.windows.containing(NSPredicate(format: "title == 'Page #16'")).firstMatch
        XCTAssertEqual(app.windows.firstMatch.title, newFireWindow.title, "New Fire window should be frontmost when opened in foreground")
    }

    func testFireWindowPopupAfterOriginalFireWindowClosed() {
        setSwitchToNewTab(enabled: false)

        app.closeWindow()
        // Open Fire window
        app.openFireWindow()

        // Open a popup window from Fire window
        let popupHTML = """
        <a href='\(UITests.simpleServedPage(titled: "Page #17"))' id='link17'>Open Page #17</a>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Fire Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let fireWindow = app.windows.containing(NSPredicate(format: "title == 'Fire Page #12'")).firstMatch
        let popupLink = fireWindow.webViews["Fire Page #12"].links["Open popup"]
        popupLink.click()

        // Close the original Fire window
        fireWindow.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(fireWindow.webViews["Fire Page #12"].waitForNonExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1) // Only popup window remains

        // Click link in popup - should open new Fire window
        let popupWindow = app.windows.containing(.link, identifier: "Open Page #17").firstMatch
        XCTAssertTrue(popupWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let link17 = popupWindow.links["Open Page #17"]
        XCTAssertTrue(link17.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            link17.click()
        }

        // Should open new Fire window
        XCTAssertEqual(app.windows.count, 2) // Popup + new Fire window
        let newFireWindow = app.windows.containing(NSPredicate(format: "title == 'Page #17'")).firstMatch
        XCTAssertTrue(newFireWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(newFireWindow.tabs["Page #17"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(newFireWindow.webViews["Page #17"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(newFireWindow.tabs.count, 1)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify popup link still available
        XCTAssertTrue(link17.exists, "Popup link should still be available after navigation")

        // Verify new Fire window is frontmost
        XCTAssertEqual(app.windows.firstMatch.title, newFireWindow.title, "New Fire window should be frontmost after popup navigation")
    }

    func testFireWindowPopupBookmarkCommandClick() {
        setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add a bookmark for Page #18
        openTestPage("Page #18")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()

        app.closeWindow()
        // Open Fire window
        app.openFireWindow()

        // Open a popup window from Fire window
        let popupHTML = """
        <p>Popup content with bookmarks access</p>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Fire Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let fireWindow = app.windows.containing(NSPredicate(format: "title == 'Fire Page #12'")).firstMatch
        let popupLink = fireWindow.webViews["Fire Page #12"].links["Open popup"]
        popupLink.click()

        let popupWindow = app.windows.containing(.staticText, identifier: "Popup content with bookmarks access").firstMatch
        XCTAssertTrue(popupWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Command click bookmark from popup - should open in background tab in Fire window
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Page #18"]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.command]) {
            bookmarkItem.click()
        }

        // Should open in background tab in Fire window, popup remains frontmost
        XCTAssertEqual(app.windows.count, 2)
        XCTAssertTrue(fireWindow.tabs["Page #18"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(fireWindow.webViews["Fire Page #12"].exists) // Original Fire page still in foreground
        XCTAssertFalse(fireWindow.webViews["Page #18"].exists) // Bookmark page in background
        XCTAssertTrue(fireWindow.tabs["Fire Page #12"].exists)
        XCTAssertEqual(fireWindow.tabs.count, 2)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify popup window remains frontmost (background operation)
        XCTAssertEqual(app.windows.firstMatch.title, popupWindow.title, "Popup window should remain frontmost for background operations")
    }

    func testFireWindowPopupBookmarkCommandShiftClick() {
        setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add a bookmark for Page #19
        openTestPage("Page #19")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()

        app.closeWindow()
        // Open Fire window
        app.openFireWindow()

        // Open a popup window from Fire window
        let popupHTML = """
        <p>Popup content with bookmarks access</p>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Fire Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let fireWindow = app.windows.containing(NSPredicate(format: "title == 'Fire Page #12'")).firstMatch
        let popupLink = fireWindow.webViews["Fire Page #12"].links["Open popup"]
        popupLink.click()

        let popupWindow = app.windows.containing(.staticText, identifier: "Popup content with bookmarks access").firstMatch
        XCTAssertTrue(popupWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Command+Shift click bookmark from popup - should open in foreground tab in Fire window
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Page #19"]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            bookmarkItem.click()
        }

        // Should open in foreground tab in Fire window
        XCTAssertEqual(app.windows.count, 2)
        XCTAssertTrue(fireWindow.tabs["Page #19"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(fireWindow.webViews["Page #19"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(fireWindow.webViews["Fire Page #12"].exists) // Original Fire page now in background
        XCTAssertTrue(fireWindow.tabs["Fire Page #12"].exists)
        XCTAssertEqual(fireWindow.tabs.count, 2)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify Fire window is frontmost (foreground tab operation)
        XCTAssertEqual(app.windows.firstMatch.title, fireWindow.title, "Fire window should be frontmost after popup bookmark navigation")
    }

    func testFireWindowPopupNavigation() {
        setSwitchToNewTab(enabled: false)

        app.closeWindow()
        // Open Fire window
        app.openFireWindow()

        // Open a popup window from Fire window
        let popupHTML = """
        <a href='\(UITests.simpleServedPage(titled: "New Tab"))' target='_blank'>Open in new tab</a>
        """

        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Page", body: popupHTML)
            .absoluteString.escapedJavaScriptString()
        openTestPage("Fire Page #12") {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
        let fireWindow = app.windows.containing(NSPredicate(format: "title == 'Fire Page #12'")).firstMatch
        let popupLink = fireWindow.webViews["Fire Page #12"].links["Open popup"]
        popupLink.click()

        // Try to navigate in popup
        let popupWindow = app.windows.containing(.link, identifier: "Open in new tab").firstMatch
        let link = popupWindow.links["Open in new tab"]
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        link.click()

        // Should open in new tab of the Fire window
        XCTAssertEqual(app.windows.count, 2)
        XCTAssertTrue(fireWindow.tabs["New Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(fireWindow.webViews["New Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(fireWindow.tabs["Fire Page #12"].exists)
        XCTAssertEqual(fireWindow.tabs.count, 2)

        // Verify popup window and its webView still exist
        XCTAssertTrue(popupWindow.webViews["Popup Page"].exists, "Popup window webView should still exist")

        // Verify popup link still available
        XCTAssertTrue(link.exists, "Popup link should still be available after navigation")

        // Verify Fire window is frontmost
        XCTAssertEqual(app.windows.firstMatch.title, fireWindow.title, "Fire window should be frontmost after popup navigation")
    }

    // MARK: - Bookmark Navigation Tests

    func testBookmarkCommandClickOpensBackgroundTab() {
        setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()

        // Navigate to different page
        app.activateAddressBar()
        openTestPage("Other Page")

        // Command click bookmark should open in background tab
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Page #13"]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.command]) {
            bookmarkItem.click()
        }

        XCTAssertTrue(app.tabs["Page #13"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Other Page"].exists)    // Original page still visible
        XCTAssertFalse(app.webViews["Page #13"].exists)     // Bookmark page in background
        XCTAssertTrue(app.tabs["Page #13"].exists)
        XCTAssertTrue(app.tabs["Other Page"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testBookmarkCommandShiftClickOpensActiveTab() {
        setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()

        // Navigate to different page
        app.activateAddressBar()
        openTestPage("Other Page")

        // Command+Shift click bookmark should open in foreground tab
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Page #13"]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            bookmarkItem.click()
        }

        XCTAssertTrue(app.webViews["Page #13"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Other Page"].exists)   // Original page now in background
        XCTAssertTrue(app.tabs["Page #13"].exists)
        XCTAssertTrue(app.tabs["Other Page"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testBookmarkCommandOptionClickOpensBackgroundWindow() {
        setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()

        // Navigate to different page
        app.activateAddressBar()
        openTestPage("Other Page")

        // Command+Option click bookmark should open in background window
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Page #13"]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.command, .option]) {
            bookmarkItem.click()
        }

        let mainWindow = app.windows.firstMatch
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(backgroundWindow.webViews["Page #13"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertTrue(mainWindow.webViews["Other Page"].exists)     // Original page still visible in main window
        XCTAssertFalse(mainWindow.webViews["Page #13"].exists)     // Bookmark not in main window
        XCTAssertTrue(mainWindow.tabs["Other Page"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 1)

        XCTAssertTrue(backgroundWindow.tabs["Page #13"].exists)
        XCTAssertEqual(backgroundWindow.tabs.count, 1)
    }

    func testBookmarkCommandOptionShiftClickOpensActiveWindow() {
        setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()

        // Navigate to different page
        app.activateAddressBar()
        openTestPage("Other Page")

        // Command+Option+Shift click bookmark should open in foreground window
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Page #13"]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.command, .option, .shift]) {
            bookmarkItem.click()
        }

        let activeWindow = app.windows.firstMatch
        XCTAssertTrue(activeWindow.webViews["Page #13"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertFalse(activeWindow.webViews["Other Page"].exists) // Original page now in background window
        XCTAssertTrue(activeWindow.tabs["Page #13"].exists)
        XCTAssertEqual(activeWindow.tabs.count, 1)
    }

    func testBookmarkMiddleClickOpensBackgroundTab() {
        setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()

        // Navigate to different page
        app.activateAddressBar()
        openTestPage("Other Page")

        // Middle click bookmark should open in background tab
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Page #13"]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        bookmarkItem.middleClick()

        XCTAssertTrue(app.tabs["Page #13"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Other Page"].exists)    // Original page still visible
        XCTAssertFalse(app.webViews["Page #13"].exists)     // Bookmark page in background
        XCTAssertTrue(app.tabs["Page #13"].exists)
        XCTAssertTrue(app.tabs["Other Page"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testBookmarkMiddleShiftClickOpensActiveTab() {
        setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()

        // Navigate to different page
        app.activateAddressBar()
        openTestPage("Other Page")

        // Middle+Shift click bookmark should open in foreground tab
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Page #13"]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.shift]) {
            bookmarkItem.middleClick()
        }

        XCTAssertTrue(app.webViews["Page #13"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Other Page"].exists)   // Original page now in background
        XCTAssertTrue(app.tabs["Page #13"].exists)
        XCTAssertTrue(app.tabs["Other Page"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testBookmarkMiddleOptionClickOpensBackgroundWindow() {
        setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()

        // Navigate to different page
        app.activateAddressBar()
        openTestPage("Other Page")

        // Middle+Option click bookmark should open in background window
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Page #13"]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.option]) {
            bookmarkItem.middleClick()
        }

        let mainWindow = app.windows.firstMatch
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(backgroundWindow.webViews["Page #13"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertTrue(mainWindow.webViews["Other Page"].exists)     // Original page still visible in main window
        XCTAssertFalse(mainWindow.webViews["Page #13"].exists)     // Bookmark not in main window
        XCTAssertTrue(mainWindow.tabs["Other Page"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 1)

        XCTAssertTrue(backgroundWindow.tabs["Page #13"].exists)
        XCTAssertEqual(backgroundWindow.tabs.count, 1)
    }

    func testBookmarkMiddleOptionShiftClickOpensActiveWindow() {
        setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add a bookmark for Page #13
        openTestPage("Page #13")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()

        // Navigate to different page
        app.activateAddressBar()
        openTestPage("Other Page")

        // Middle+Option+Shift click bookmark should open in foreground window
        app.bookmarksMenu.click()
        let bookmarkItem = app.bookmarksMenu.menuItems["Page #13"]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.option, .shift]) {
            bookmarkItem.middleClick()
        }

        let activeWindow = app.windows.firstMatch
        XCTAssertTrue(activeWindow.webViews["Page #13"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertFalse(activeWindow.webViews["Other Page"].exists) // Original page now in background window
        XCTAssertTrue(activeWindow.tabs["Page #13"].exists)
        XCTAssertEqual(activeWindow.tabs.count, 1)
    }

    // MARK: - History Navigation Tests

    func testHistoryCommandClickOpensBackgroundTab() {
        setSwitchToNewTab(enabled: false)

        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.activateAddressBar()
        openTestPage("Other Page")

        // Command click history item should open in background tab
        app.historyMenu.click()
        let historyItem = app.menuItems["Page #14"]
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.command]) {
            historyItem.click()
        }

        XCTAssertTrue(app.tabs["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Other Page"].exists)    // Original page still visible
        XCTAssertFalse(app.webViews["Page #14"].exists)     // History page in background
        XCTAssertTrue(app.tabs["Page #14"].exists)
        XCTAssertTrue(app.tabs["Other Page"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testHistoryCommandShiftClickOpensActiveTab() {
        setSwitchToNewTab(enabled: false)

        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.activateAddressBar()
        openTestPage("Other Page")

        // Command+Shift click history item should open in foreground tab
        app.historyMenu.click()
        let historyItem = app.menuItems["Page #14"]
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            historyItem.click()
        }

        XCTAssertTrue(app.webViews["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Other Page"].exists)   // Original page now in background
        XCTAssertTrue(app.tabs["Page #14"].exists)
        XCTAssertTrue(app.tabs["Other Page"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testHistoryMiddleClickOpensBackgroundTab() {
        setSwitchToNewTab(enabled: false)

        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.activateAddressBar()
        openTestPage("Other Page")

        // Middle click history item should open in background tab
        app.historyMenu.click()
        let historyItem = app.menuItems["Page #14"]
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        historyItem.middleClick()

        XCTAssertTrue(app.tabs["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Other Page"].exists)    // Original page still visible
        XCTAssertFalse(app.webViews["Page #14"].exists)     // History page in background
        XCTAssertTrue(app.tabs["Page #14"].exists)
        XCTAssertTrue(app.tabs["Other Page"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testHistoryMiddleShiftClickOpensActiveTab() {
        setSwitchToNewTab(enabled: false)

        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.activateAddressBar()
        openTestPage("Other Page")

        // Middle+Shift click history item should open in foreground tab
        app.historyMenu.click()
        let historyItem = app.menuItems["Page #14"]
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.shift]) {
            historyItem.middleClick()
        }

        XCTAssertTrue(app.webViews["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Other Page"].exists)   // Original page now in background
        XCTAssertTrue(app.tabs["Page #14"].exists)
        XCTAssertTrue(app.tabs["Other Page"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testHistoryCommandOptionClickOpensBackgroundWindow() {
        setSwitchToNewTab(enabled: false)

        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.activateAddressBar()
        openTestPage("Other Page")

        // Command+Option click history item should open in background window
        app.historyMenu.click()
        let historyItem = app.menuItems["Page #14"]
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.command, .option]) {
            historyItem.click()
        }

        let mainWindow = app.windows.firstMatch
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(backgroundWindow.webViews["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertTrue(mainWindow.webViews["Other Page"].exists)     // Original page still visible in main window
        XCTAssertFalse(mainWindow.webViews["Page #14"].exists)     // History not in main window
        XCTAssertTrue(mainWindow.tabs["Other Page"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 1)

        XCTAssertTrue(backgroundWindow.tabs["Page #14"].exists)
        XCTAssertEqual(backgroundWindow.tabs.count, 1)
    }

    func testHistoryCommandOptionShiftClickOpensActiveWindow() {
        setSwitchToNewTab(enabled: false)

        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.activateAddressBar()
        openTestPage("Other Page")

        // Command+Option+Shift click history item should open in foreground window
        app.historyMenu.click()
        let historyItem = app.menuItems["Page #14"]
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.command, .option, .shift]) {
            historyItem.click()
        }

        let activeWindow = app.windows.firstMatch
        XCTAssertTrue(activeWindow.webViews["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertFalse(activeWindow.webViews["Other Page"].exists) // Original page now in background window
        XCTAssertTrue(activeWindow.tabs["Page #14"].exists)
        XCTAssertEqual(activeWindow.tabs.count, 1)
    }

    func testHistoryMiddleOptionClickOpensBackgroundWindow() {
        setSwitchToNewTab(enabled: false)

        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.activateAddressBar()
        app.activateAddressBar()
        openTestPage("Other Page")

        // Middle+Option click history item should open in background window
        app.historyMenu.click()
        let historyItem = app.menuItems["Page #14"]
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.option]) {
            historyItem.middleClick()
        }

        let mainWindow = app.windows.firstMatch
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(backgroundWindow.webViews["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertTrue(mainWindow.webViews["Other Page"].exists)     // Original page still visible in main window
        XCTAssertFalse(mainWindow.webViews["Page #14"].exists)     // History not in main window
        XCTAssertTrue(mainWindow.tabs["Other Page"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 1)

        XCTAssertTrue(backgroundWindow.tabs["Page #14"].exists)
        XCTAssertEqual(backgroundWindow.tabs.count, 1)
    }

    func testHistoryMiddleOptionShiftClickOpensActiveWindow() {
        setSwitchToNewTab(enabled: false)

        // Visit a page to add to history
        openTestPage("Page #14")

        // Navigate to different page
        app.activateAddressBar()
        openTestPage("Other Page")

        // Middle+Option+Shift click history item should open in foreground window
        app.historyMenu.click()
        let historyItem = app.menuItems["Page #14"]
        XCTAssertTrue(historyItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCUIElement.perform(withKeyModifiers: [.option, .shift]) {
            historyItem.middleClick()
        }

        let activeWindow = app.windows.firstMatch
        XCTAssertTrue(activeWindow.webViews["Page #14"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertFalse(activeWindow.webViews["Other Page"].exists) // Original page now in background window
        XCTAssertTrue(activeWindow.tabs["Page #14"].exists)
        XCTAssertEqual(activeWindow.tabs.count, 1)
    }

    // MARK: - Favorites Navigation Tests

    func testFavoritesRegularClickOpensSameTab() {
        setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add to favorites
        openTestPage("Page #15")
        app.mainMenuAddBookmarkMenuItem.click()
        app.bookmarksDialogAddToFavoritesCheckbox.click()
        app.addBookmarkAlertAddButton.click()

        app.closeAllWindows()
        app.openNewWindow()

        // Find the favorite item by its title
        let favoriteItem = app.links["Page #15"]
        XCTAssertTrue(favoriteItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Regular click should open in same tab
        favoriteItem.click()
        XCTAssertTrue(app.webViews["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["New Tab Page"].exists)
        XCTAssertTrue(app.tabs["Page #15"].exists)
        XCTAssertEqual(app.tabs.count, 1)
    }

    func testFavoritesCommandClickOpensBackgroundTab() {
        setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add to favorites
        openTestPage("Page #15")
        app.mainMenuAddBookmarkMenuItem.click()
        app.bookmarksDialogAddToFavoritesCheckbox.click()
        app.addBookmarkAlertAddButton.click()

        app.closeAllWindows()
        app.openNewWindow()

        // Find the favorite item by its title
        let favoriteItem = app.links["Page #15"]
        XCTAssertTrue(favoriteItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Command click should open in background tab
        XCUIElement.perform(withKeyModifiers: [.command]) {
            favoriteItem.click()
        }
        XCTAssertTrue(app.tabs["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["New Tab Page"].exists)
        XCTAssertFalse(app.webViews["Page #15"].exists)      // Favorites in background
        XCTAssertTrue(app.tabs["Page #15"].exists)
        XCTAssertTrue(app.tabs["New Tab"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testFavoritesCommandShiftClickOpensActiveTab() {
        setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add to favorites
        openTestPage("Page #15")
        app.mainMenuAddBookmarkMenuItem.click()
        app.bookmarksDialogAddToFavoritesCheckbox.click()
        app.addBookmarkAlertAddButton.click()

        app.closeAllWindows()
        app.openNewWindow()

        // Find the favorite item by its title
        let favoriteItem = app.links["Page #15"]
        XCTAssertTrue(favoriteItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Command shift click should open in foreground tab
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            favoriteItem.click()
        }
        XCTAssertTrue(app.webViews["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["New Tab Page"].exists) // New Tab now in background
        XCTAssertTrue(app.tabs["Page #15"].exists)
        XCTAssertTrue(app.tabs["New Tab"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testFavoritesCommandOptionClickOpensBackgroundWindow() {
        setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add to favorites
        openTestPage("Page #15")
        app.mainMenuAddBookmarkMenuItem.click()
        app.bookmarksDialogAddToFavoritesCheckbox.click()
        app.addBookmarkAlertAddButton.click()

        app.closeAllWindows()
        app.openNewWindow()

        // Find the favorite item by its title
        let favoriteItem = app.links["Page #15"]
        XCTAssertTrue(favoriteItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Command option click should open in background window
        XCUIElement.perform(withKeyModifiers: [.command, .option]) {
            favoriteItem.click()
        }
        let mainWindow = app.windows.firstMatch
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(backgroundWindow.webViews["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertTrue(mainWindow.webViews["New Tab Page"].exists)
        XCTAssertFalse(mainWindow.webViews["Page #15"].exists)
        XCTAssertTrue(mainWindow.tabs["New Tab"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 1)

        XCTAssertTrue(backgroundWindow.tabs["Page #15"].exists)
        XCTAssertEqual(backgroundWindow.tabs.count, 1)
    }

    func testFavoritesCommandOptionShiftClickOpensActiveWindow() {
        setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add to favorites
        openTestPage("Page #15")
        app.mainMenuAddBookmarkMenuItem.click()
        app.bookmarksDialogAddToFavoritesCheckbox.click()
        app.addBookmarkAlertAddButton.click()

        app.closeAllWindows()
        app.openNewWindow()

        // Find the favorite item by its title
        let favoriteItem = app.links["Page #15"]
        XCTAssertTrue(favoriteItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Command option shift click should open in foreground window
        XCUIElement.perform(withKeyModifiers: [.command, .option, .shift]) {
            favoriteItem.click()
        }
        let activeWindow = app.windows.firstMatch
        XCTAssertTrue(activeWindow.webViews["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertFalse(activeWindow.webViews["New Tab Page"].exists)
        XCTAssertTrue(activeWindow.tabs["Page #15"].exists)
        XCTAssertEqual(activeWindow.tabs.count, 1)
    }

    func testFavoritesMiddleClickOpensBackgroundTab() {
        setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add to favorites
        openTestPage("Page #15")
        app.mainMenuAddBookmarkMenuItem.click()
        app.bookmarksDialogAddToFavoritesCheckbox.click()
        app.addBookmarkAlertAddButton.click()

        app.closeAllWindows()
        app.openNewWindow()

        // Find the favorite item by its title
        let favoriteItem = app.links["Page #15"]
        XCTAssertTrue(favoriteItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Middle click should open in background tab
        favoriteItem.middleClick()

        XCTAssertTrue(app.tabs["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["New Tab Page"].exists)
        XCTAssertFalse(app.webViews["Page #15"].exists)      // Favorite in background
        XCTAssertTrue(app.tabs["Page #15"].exists)
        XCTAssertTrue(app.tabs["New Tab"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testFavoritesMiddleShiftClickOpensActiveTab() {
        setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add to favorites
        openTestPage("Page #15")
        app.mainMenuAddBookmarkMenuItem.click()
        app.bookmarksDialogAddToFavoritesCheckbox.click()
        app.addBookmarkAlertAddButton.click()

        app.closeAllWindows()
        app.openNewWindow()

        // Find the favorite item by its title
        let favoriteItem = app.links["Page #15"]
        XCTAssertTrue(favoriteItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Middle+Shift click should open in foreground tab
        XCUIElement.perform(withKeyModifiers: [.shift]) {
            favoriteItem.middleClick()
        }

        XCTAssertTrue(app.webViews["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["New Tab Page"].exists) // New Tab now in background
        XCTAssertTrue(app.tabs["Page #15"].exists)
        XCTAssertTrue(app.tabs["New Tab"].exists)
        XCTAssertEqual(app.tabs.count, 2)
    }

    func testFavoritesMiddleOptionClickOpensBackgroundWindow() {
        setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add to favorites
        openTestPage("Page #15")
        app.mainMenuAddBookmarkMenuItem.click()
        app.bookmarksDialogAddToFavoritesCheckbox.click()
        app.addBookmarkAlertAddButton.click()

        app.closeAllWindows()
        app.openNewWindow()

        // Find the favorite item by its title
        let favoriteItem = app.links["Page #15"]
        XCTAssertTrue(favoriteItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Middle+Option click should open in background window
        XCUIElement.perform(withKeyModifiers: [.option]) {
            favoriteItem.middleClick()
        }

        let mainWindow = app.windows.firstMatch
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(backgroundWindow.webViews["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertTrue(mainWindow.webViews["New Tab Page"].exists)
        XCTAssertFalse(mainWindow.webViews["Page #15"].exists)
        XCTAssertTrue(mainWindow.tabs["New Tab"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 1)

        XCTAssertTrue(backgroundWindow.tabs["Page #15"].exists)
        XCTAssertEqual(backgroundWindow.tabs.count, 1)
    }

    func testFavoritesMiddleOptionShiftClickOpensActiveWindow() {
        setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add to favorites
        openTestPage("Page #15")
        app.mainMenuAddBookmarkMenuItem.click()
        app.bookmarksDialogAddToFavoritesCheckbox.click()
        app.addBookmarkAlertAddButton.click()

        app.closeAllWindows()
        app.openNewWindow()

        // Find the favorite item by its title
        let favoriteItem = app.links["Page #15"]
        XCTAssertTrue(favoriteItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Middle+Option+Shift click should open in foreground window
        XCUIElement.perform(withKeyModifiers: [.option, .shift]) {
            favoriteItem.middleClick()
        }

        let activeWindow = app.windows.firstMatch
        XCTAssertTrue(activeWindow.webViews["Page #15"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertFalse(activeWindow.webViews["New Tab Page"].exists)
        XCTAssertTrue(activeWindow.tabs["Page #15"].exists)
        XCTAssertEqual(activeWindow.tabs.count, 1)
    }

    // MARK: - Other Navigation Tests

    func testBookmarksBarNavigation() throws {
        setSwitchToNewTab(enabled: false)
        app.resetBookmarks()

        // Add to bookmarks bar
        openTestPage("Page #16")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()
        if !app.bookmarksBar.exists {
            app.mainMenuToggleBookmarksBarMenuItem.click()
        }

        app.activateAddressBar()
        openTestPage("Page #17")

        // Open bookmark with different modifiers
        // Access bookmark item from bookmarks bar (using pattern from BookmarksAndFavoritesTests)
        let bookmarkItem = app.bookmarksBar.groups.firstMatch
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Command click should open in background
        XCUIElement.perform(withKeyModifiers: [.command]) {
            bookmarkItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }
        XCTAssertTrue(app.tabs["Page #16"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(app.tabs["Page #17"].exists)
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.webViews["Page #17"].exists)
        XCTAssertFalse(app.webViews["Page #16"].exists) // Should open in background
        XCTAssertEqual(app.tabs.count, 2)
        try app.tabs.element(boundBy: 1).closeTab()

        // Command shift click should open in foreground
        XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
            bookmarkItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }
        XCTAssertTrue(app.webViews["Page #16"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertFalse(app.webViews["Page #17"].exists)
        XCTAssertTrue(app.tabs["Page #16"].exists)
        XCTAssertTrue(app.tabs["Page #17"].exists)
        XCTAssertEqual(app.tabs.count, 2)
        app.closeCurrentTab()

        // Command+Option click should open in background window
        XCUIElement.perform(withKeyModifiers: [.command, .option]) {
            bookmarkItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }

        let mainWindow = app.windows.firstMatch
        let backgroundWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(backgroundWindow.webViews["Page #16"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(backgroundWindow.tabs.count, 1)
        XCTAssertEqual(app.windows.count, 2)

        XCTAssertTrue(mainWindow.webViews["Page #17"].exists)     // Original page still visible in main window
        XCTAssertTrue(mainWindow.tabs["Page #17"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 1)

        XCTAssertTrue(backgroundWindow.tabs["Page #16"].exists)
        XCTAssertEqual(backgroundWindow.tabs.count, 1)

        // Command+Option+Shift click should open in foreground window
        XCUIElement.perform(withKeyModifiers: [.command, .option, .shift]) {
            bookmarkItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }

        XCTAssertTrue(mainWindow.webViews["Page #16"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(app.windows.count, 3)

        XCTAssertTrue(mainWindow.tabs["Page #16"].exists)
        XCTAssertEqual(mainWindow.tabs.count, 1)
    }

    func testBackForwardCommandClickOpensBackgroundTab() {
        setSwitchToNewTab(enabled: false)

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
        setSwitchToNewTab(enabled: false)

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
        setSwitchToNewTab(enabled: false)

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
        setSwitchToNewTab(enabled: false)

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
        setSwitchToNewTab(enabled: false)

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
        setSwitchToNewTab(enabled: false)

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
        setSwitchToNewTab(enabled: false)

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
        setSwitchToNewTab(enabled: false)

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

    func testAddressBarSuggestionsNavigation() throws {
        setSwitchToNewTab(enabled: false)

        openTestPage("Bookmarked Page #20")
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()
        app.enforceSingleWindow()

        // Type to get suggestions
        app.addressBar.typeText("Bookmarked Page #20")

        // Command click suggestion should open in background
        let suggestion = app.tables["SuggestionViewController.tableView"].cells.staticTexts["Bookmarked Page #20"]
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
        setSwitchToNewTab(enabled: false)

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
        setSwitchToNewTab(enabled: true)

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

    // MARK: - Test Utilities

    private func openTestPage(_ title: String, body: (() -> String)? = nil) {
        let url = UITests.simpleServedPage(titled: title, body: body?() ?? "<p>Sample text for \(title)</p>")
        XCTAssertTrue(
            app.addressBar.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The address bar text field didn't become available in a reasonable timeframe."
        )
        app.addressBar.pasteURL(url)
        XCTAssertTrue(
            app.windows.firstMatch.webViews[title].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Visited site didn't load with the expected title in a reasonable timeframe."
        )
    }

    private func setSwitchToNewTab(enabled: Bool) {
        defer {
            app.enforceSingleWindow()
        }
        guard Self.isSwitchToNewTabEnabled != enabled else { return }

        app.openPreferencesWindow()
        app.preferencesGoToGeneralPane()
        app.setSwitchToNewTabWhenOpened(enabled: enabled)
        Self.isSwitchToNewTabEnabled = enabled
    }

}
