//
//  TabNavigationTestHelpers.swift
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

enum TabNavigationTestState {
    static var isSwitchToNewTabEnabled: Bool?
}

protocol TabNavigationTestHelpers: UITestCase {}

extension TabNavigationTestHelpers {

    func openTestPage(_ title: String, body: (() -> String)? = nil) {
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

    func setupPopupWindowForBookmarkMainMenu(targetTitle: String, sourceTitle: String) -> (XCUIElement, XCUIElement) {
        // Open test page and bookmark it.
        app.resetBookmarks()
        openTestPage(targetTitle)
        app.mainMenuAddBookmarkMenuItem.click()
        app.addBookmarkAlertAddButton.click()
        app.dismissBookmarksBarPopover()

        // Navigate to source page and open popup.
        app.activateAddressBar()
        openPopupSourcePage(sourceTitle: sourceTitle)

        let mainWindow = app.windows.containing(.keyPath(\.title, equalTo: sourceTitle)).firstMatch
        let popupLink = mainWindow.webViews[sourceTitle].links["Open popup"]
        popupLink.click()

        let popupWindow = app.windows.containing(.staticText, identifier: "Popup menu actions").firstMatch
        XCTAssertTrue(popupWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        return (mainWindow, popupWindow)
    }

    func setupPopupWindowForHistoryMainMenu(targetTitle: String, sourceTitle: String) -> (XCUIElement, XCUIElement) {
        // Create history entry and navigate to source page.
        openTestPage(targetTitle)
        app.activateAddressBar()
        openPopupSourcePage(sourceTitle: sourceTitle)

        let mainWindow = app.windows.containing(.keyPath(\.title, equalTo: sourceTitle)).firstMatch
        let popupLink = mainWindow.webViews[sourceTitle].links["Open popup"]
        popupLink.click()

        let popupWindow = app.windows.containing(.staticText, identifier: "Popup menu actions").firstMatch
        XCTAssertTrue(popupWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        return (mainWindow, popupWindow)
    }

    func openPopupSourcePage(sourceTitle: String) {
        // Open a page that can launch a popup window.
        let popupWindowURL = UITests.simpleServedPage(titled: "Popup Menu Page", body: "<p>Popup menu actions</p>")
            .absoluteString.escapedJavaScriptString()
        openTestPage(sourceTitle) {
            """
            <script>
            var popupUrl = "\(popupWindowURL)";
            </script>
            <a href='javascript:window.open(popupUrl, "popup", "width=400,height=300")'>Open popup</a>
            """
        }
    }
}

extension XCUIApplication {
    func setSwitchToNewTab(enabled: Bool) {
        defer {
            enforceSingleWindow()
        }
        guard TabNavigationTestState.isSwitchToNewTabEnabled != enabled else {
            Logger.log("Checkbox value from last run should be already set to \(enabled), skipping")
            return
        }

        openPreferencesWindow()
        preferencesGoToGeneralPane()
        setSwitchToNewTabWhenOpened(enabled: enabled)
        TabNavigationTestState.isSwitchToNewTabEnabled = enabled
    }
}
