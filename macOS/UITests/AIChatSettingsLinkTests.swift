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
    func test_openDuckAiSettingsLink_opensDuckAiAndShowsSettings() {
        // Navigate to AI Features settings
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)

        // Click the new link
        let settingsLink = app.windows.firstMatch.buttons[Identifiers.duckAiSettingsLink]
        XCTAssertTrue(settingsLink.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "'Open Duck.ai Settings' link should be visible when the feature flag is on and Duck.ai is enabled")
        settingsLink.click()

        // A new tab should open on duck.ai — the URL is the first signal that the click was
        // routed through AIChatTabOpener and a tab was created. Page navigation isn't instant,
        // so poll the address bar value until it reflects duck.ai (or the navigation timeout).
        let addressBar = app.addressBar
        XCTAssertTrue(addressBar.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let urlContainsDuckAi = NSPredicate(format: "self CONTAINS[c] %@", "duck.ai")
        let started = Date()
        while !urlContainsDuckAi.evaluate(with: addressBar.value as? String ?? "") {
            if Date().timeIntervalSince(started) > UITests.Timeouts.navigation { break }
            usleep(200_000)
        }
        XCTAssertTrue(urlContainsDuckAi.evaluate(with: addressBar.value as? String ?? ""),
                      "Expected the new tab to load duck.ai; address bar value: \(addressBar.value ?? "<nil>")")

        // Duck.ai's Settings modal should be visible inside the WebView. The modal is opened
        // by the FE in response to the `submitOpenSettingsAction` push from the two-phase
        // handshake — so its presence proves the end-to-end wiring works.
        // The predicate matches a stable header label inside the modal. If Duck.ai's modal
        // a11y labels evolve, adjust the string here.
        let modalElement = app.webViews.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Settings"))
            .firstMatch
        XCTAssertTrue(modalElement.waitForExistence(timeout: UITests.Timeouts.navigation),
                      "Duck.ai Settings modal should be visible after clicking the link")
    }
}
