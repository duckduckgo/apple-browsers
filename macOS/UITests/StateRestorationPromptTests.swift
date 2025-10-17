//
//  StateRestorationPromptTests.swift
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

class StateRestorationPromptTests: UITestCase {

    private var pageTitle: String!
    private var urlForBookmarksBar: URL!
    private let titleStringLength = 12
    private var addressBarTextField: XCUIElement!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp(arguments: ["CRASH_RESTORE_TEST"])
        pageTitle = UITests.randomPageTitle(length: titleStringLength)
        urlForBookmarksBar = UITests.simpleServedPage(titled: pageTitle)
        addressBarTextField = app.addressBar

        app.enforceSingleWindow()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        app.terminate()
    }

    func test_sessionCanBeRestored_whenSessionRestoreDisabled_andAppRelaunchesAfterCrash() throws {
        // Open settings and disable session restore using helper
        app.openPreferencesWindow()
        app.preferencesSetRestorePreviousSession(to: .newWindow)
        app.closePreferencesWindow()
        app.enforceSingleWindow()
        XCTAssertTrue(
            addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The address bar text field didn't become available in a reasonable timeframe."
        )
        addressBarTextField.pasteURL(urlForBookmarksBar)
        XCTAssertTrue(
            app.windows.webViews[pageTitle].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Site didn't load with the expected title in a reasonable timeframe."
        )

        sleep(1) // Give some time for the session to be saved

        app.terminate()
        app.launch()
        app.openNewWindow()

        app.acceptSessionRestore()

        XCTAssertTrue(
            app.windows.webViews[pageTitle].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Visited site wasn't found in a webview with the expected title in a reasonable timeframe."
        )

        XCTAssertTrue(
            app.sessionRestoreAcceptButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "Session restore reject button should not be in any webview after restore is accepted."
        )
    }

    func test_sessionRestorePromptCanBeClosed_whenSessionRestoreDisabled_andAppRelaunchesAfterCrash() throws {
        // Open settings and disable session restore using helper
        app.openPreferencesWindow()
        app.preferencesSetRestorePreviousSession(to: .newWindow)
        app.closePreferencesWindow()
        app.enforceSingleWindow()
        XCTAssertTrue(
            addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The address bar text field didn't become available in a reasonable timeframe."
        )
        addressBarTextField.pasteURL(urlForBookmarksBar)
        XCTAssertTrue(
            app.windows.webViews[pageTitle].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Site didn't load with the expected title in a reasonable timeframe."
        )

        sleep(1) // Give some time for the session to be saved

        app.terminate()
        app.launch()
        app.openNewWindow()

        app.rejectSessionRestore()

        XCTAssertTrue(
            app.windows.webViews[pageTitle].waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "Visited site should not be in any webview after restore is rejected."
        )

        XCTAssertTrue(
            app.sessionRestoreRejectButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "Session restore reject button should not be in any webview after restore is rejected."
        )
    }
}

internal extension XCUIApplication {
    var sessionRestoreAcceptButton: XCUIElement {
        buttons["session.restore.prompt.accept"]
    }

    var sessionRestoreRejectButton: XCUIElement {
        buttons["session.restore.prompt.reject"]
    }

    func acceptSessionRestore() {
        if sessionRestoreAcceptButton.waitForExistence(timeout: UITests.Timeouts.elementExistence) {
            sessionRestoreAcceptButton.click()
        } else {
            XCTFail("Session restore accept button did not appear in a reasonable timeframe.")
        }
    }

    func rejectSessionRestore() {
        if sessionRestoreRejectButton.waitForExistence(timeout: UITests.Timeouts.elementExistence) {
            sessionRestoreRejectButton.click()
        } else {
            XCTFail("Session restore reject button did not appear in a reasonable timeframe.")
        }
    }
}
