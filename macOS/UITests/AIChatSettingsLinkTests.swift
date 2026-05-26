//
//  AIChatSettingsLinkTests.swift
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

class AIChatSettingsLinkTests: UITestCase {
    private var addressBarTextField: XCUIElement!

    private enum Identifiers {
        static let duckAiSettingsLink = "Preferences.AIChat.duckAiSettingsLink"
        static let duckAiConsentAgreeButton = "Agree and Continue"
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp(featureFlags: ["aiChatSettingsLinkInAiFeatures": true])
        addressBarTextField = app.addressBar
        app.enforceSingleWindow()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        app.terminate()
    }

    /// Happy path: with the sub-feature flag on, clicking "Open Duck.ai Settings" from
    /// Settings → AI Features should open duck.ai in a new tab AND surface the Duck.ai
    /// Settings modal via the two-phase `submitOpenSettingsAction` push.
    func test_openDuckAiSettingsLink_opensDuckAiAndShowsSettings() throws {
        // duck.ai loads too slowly on the macOS 14 CI runner for the two-phase handshake to
        // reliably observe the Settings modal within UI-test timeouts. Skip there until we
        // can make the test resilient to that environment.
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        try XCTSkipIf(osVersion.majorVersion == 14, "Disabled on macOS 14: duck.ai is too slow to load for this test to be reliable.")

        // Navigate to AI Features settings
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)

        // Click the new link
        let settingsLink = app.windows.firstMatch.buttons[Identifiers.duckAiSettingsLink]
        XCTAssertTrue(settingsLink.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "'Open Duck.ai Settings' link should be visible when the feature flag is on and Duck.ai is enabled")

        settingsLink.click()

        // Dismiss duck.ai's first-run consent dialog if it appears. It's gated by WebKit storage
        // and only shows on runners with a clean profile (e.g. macOS 14 CI), where it would otherwise
        // sit on top of and block accessibility access to the Settings modal underneath.
        let agreeButton = app.webViews.buttons[Identifiers.duckAiConsentAgreeButton]
        if agreeButton.waitForExistence(timeout: UITests.Timeouts.elementExistence) {
            agreeButton.click()
        }

        // Duck.ai's Settings modal should be visible inside the WebView. The modal is opened
        // by the FE in response to the `submitOpenSettingsAction` push from the two-phase
        // handshake — so its presence proves the end-to-end wiring works.
        //
        // Two checks for resilience:
        //
        // 1. The modal's "close dialog" button. `.buttons` deterministically maps from
        //    AXButton across macOS versions, the label is unique inside this WebView,
        //    and the button only exists while the modal is open.
        //
        // 2. The modal container itself, labeled "Duck.ai Settings". The dialog is an
        //    AXGroup with AXApplicationDialog subrole — XCUI surfaces it under `.groups`
        //    on current macOS. If a future macOS or WebKit revision moves it to
        //    `.otherElements`, swap `.groups` for `.otherElements` below.
        let closeDialogButton = app.webViews.buttons["close dialog"]
        XCTAssertTrue(closeDialogButton.waitForExistence(timeout: UITests.Timeouts.navigation),
                      "Duck.ai Settings modal's close button should be visible after clicking the link")

        let settingsModal = app.webViews.groups["Duck.ai Settings"]
        XCTAssertTrue(settingsModal.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Duck.ai Settings modal container labeled 'Duck.ai Settings' should be visible")
    }
}
