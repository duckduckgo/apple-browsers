//
//  SubscriptionEntryPointsTests.swift
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

/// Checks that each way into the subscription purchase flow opens the purchase page. Buying stays a manual check.
class SubscriptionEntryPointsTests: UITestCase {

    private static let purchasePageURLPrefix = "https://duckduckgo.com/subscriptions"

    override func setUpWithError() throws {
        try super.setUpWithError()
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()
    }

    func testMoreOptionsMenuOpensPurchasePageInNewTab() {
        let tabCount = app.windows.firstMatch.tabs.count

        app.optionsButton.click()
        // While the free trial badge shows, the menu item draws its title in a custom view and has none of its own
        app.menuItems["openSubscriptionPurchasePage:"].clickAfterExistenceTestSucceeds()

        assertPurchasePageIsOpenInNewTab(previousTabCount: tabCount)
    }

    func testSettingsPurchaseButtonOpensPurchasePageInNewTab() {
        app.openSettings()
        app.preferencesGoToPrivacyProPane()
        let tabCount = app.windows.firstMatch.tabs.count

        app.preferencesWindow.buttons["PreferencesPurchaseSubscriptionView.purchaseButton"].clickAfterExistenceTestSucceeds()

        assertPurchasePageIsOpenInNewTab(previousTabCount: tabCount)
    }

    func testProURLLoadsPurchasePage() {
        XCTAssertTrue(app.addressBar.waitForExistence(timeout: UITests.Timeouts.elementExistence), "The address bar should be editable")
        // The app redirects /pro to the purchase page, so `openURL`, which expects the typed URL, doesn't fit here
        app.addressBar.pasteURL(URL(string: "https://duckduckgo.com/pro")!, pressingEnter: true)

        assertSelectedTabShowsPurchasePage()
    }

    // MARK: - Utilities

    private func assertPurchasePageIsOpenInNewTab(previousTabCount: Int, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.wait(for: .keyPath(\.tabs.count, equalTo: previousTabCount + 1), timeout: UITests.Timeouts.elementExistence),
                      "The purchase page should open in a new tab", file: file, line: line)
        assertSelectedTabShowsPurchasePage(file: file, line: line)
    }

    private func assertSelectedTabShowsPurchasePage(file: StaticString = #filePath, line: UInt = #line) {
        let selectedTab = app.windows.firstMatch.tabs.element(matching: \.isSelected, equalTo: true)
        let showsPurchasePage = NSPredicate { element, _ in
            (element as? XCUIElement)?.url?.hasPrefix(Self.purchasePageURLPrefix) == true
        }
        XCTAssertTrue(selectedTab.wait(for: showsPurchasePage, timeout: UITests.Timeouts.navigation),
                      "The selected tab should show the purchase page (current URL: \(selectedTab.url ?? "<nil>"))", file: file, line: line)
        XCTAssertTrue(app.windows.firstMatch.webViews.firstMatch.waitForExistence(timeout: UITests.Timeouts.navigation),
                      "The purchase page should load", file: file, line: line)
    }
}
