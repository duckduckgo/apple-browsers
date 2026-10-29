//
//  JSAlertUITests.swift
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

/// A JS dialog blocks its page until it's answered. These tests leave a dialog unanswered and check
/// that closing the tab, navigating away or closing the window gets rid of it without breaking the browser.
class JSAlertUITests: UITestCase {

    private enum Dialog: String {
        case alert = "Alert"
        case confirm = "Confirm"
        case prompt = "Prompt"
    }

    private static let dialogsPageTitle = "JS Dialogs"
    private static let dialogsPageBody = """
        <button onclick="alert('Alert message')">Alert</button>
        <button onclick="confirm('Confirm message')">Confirm</button>
        <button onclick="prompt('Prompt message', 'Default answer')">Prompt</button>
        """
    private static let nextPageTitle = "After the dialog"

    override func setUpWithError() throws {
        try super.setUpWithError()
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()
    }

    func testAlertIsDismissedWhenTabIsClosed() {
        assertDialogIsDismissedWhenTabIsClosed(.alert)
    }

    func testConfirmIsDismissedWhenTabIsClosed() {
        assertDialogIsDismissedWhenTabIsClosed(.confirm)
    }

    func testPromptIsDismissedWhenTabIsClosed() {
        assertDialogIsDismissedWhenTabIsClosed(.prompt)
    }

    func testAlertIsDismissedWhenNavigatingAway() {
        assertDialogIsDismissedWhenNavigatingAway(.alert)
    }

    func testConfirmIsDismissedWhenNavigatingAway() {
        assertDialogIsDismissedWhenNavigatingAway(.confirm)
    }

    func testPromptIsDismissedWhenNavigatingAway() {
        assertDialogIsDismissedWhenNavigatingAway(.prompt)
    }

    func testAlertIsDismissedWhenWindowIsClosed() {
        assertDialogIsDismissedWhenWindowIsClosed(.alert)
    }

    func testConfirmIsDismissedWhenWindowIsClosed() {
        assertDialogIsDismissedWhenWindowIsClosed(.confirm)
    }

    func testPromptIsDismissedWhenWindowIsClosed() {
        assertDialogIsDismissedWhenWindowIsClosed(.prompt)
    }

    // MARK: - Utilities

    /// The dialog is drawn inside the tab and has no identifiers; its title reads "A message from <host>".
    /// AppKit labels expose their text as the value; a block predicate skips values that aren't strings.
    private var dialogTitle: XCUIElement {
        app.windows.firstMatch.staticTexts.matching(NSPredicate { element, _ in
            ["label", "value"].contains { ((element as? NSObject)?.value(forKey: $0) as? String)?.hasPrefix("A message from") == true }
        }).firstMatch
    }

    private func assertDialogIsDismissedWhenTabIsClosed(_ dialog: Dialog) {
        app.openNewTab()
        showDialog(dialog)
        let tabCount = app.tabs.count

        app.closeCurrentTab()

        XCTAssertTrue(app.wait(for: .keyPath(\.tabs.count, equalTo: tabCount - 1), timeout: UITests.Timeouts.elementExistence),
                      "Cmd+W should close the tab showing the \(dialog) dialog")
        assertDialogIsGone(dialog)
        app.activateAddressBar()
        app.openSite(pageTitle: Self.nextPageTitle)
    }

    private func assertDialogIsDismissedWhenNavigatingAway(_ dialog: Dialog) {
        showDialog(dialog)

        app.activateAddressBar()
        app.openSite(pageTitle: Self.nextPageTitle)

        assertDialogIsGone(dialog)
    }

    private func assertDialogIsDismissedWhenWindowIsClosed(_ dialog: Dialog) {
        showDialog(dialog)

        app.closeWindow()
        XCTAssertTrue(app.windows.firstMatch.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
                      "The window with the \(dialog) dialog didn't close.")

        app.openNewWindow()
        assertDialogIsGone(dialog)
        app.openSite(pageTitle: Self.nextPageTitle)
    }

    private func showDialog(_ dialog: Dialog) {
        let url = UITests.simpleServedPage(titled: Self.dialogsPageTitle, body: Self.dialogsPageBody)
        app.openURL(url, waitForWebViewAccessibilityLabel: Self.dialogsPageTitle)
        app.windows.firstMatch.webViews[Self.dialogsPageTitle].buttons[dialog.rawValue].click()
        XCTAssertTrue(dialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "The \(dialog) dialog didn't appear.")
    }

    private func assertDialogIsGone(_ dialog: Dialog) {
        XCTAssertTrue(dialogTitle.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "The \(dialog) dialog is still shown.")
    }
}
