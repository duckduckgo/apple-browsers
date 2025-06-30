//
//  AIChatTests.swift
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

class AIChatTests: UITestCase {
    private var addressBarTextField: XCUIElement!
    private var app: XCUIApplication!

    override class func setUp() {
        super.setUp()
        UITests.firstRun()
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp()

        addressBarTextField = app.windows.textFields["AddressBarViewController.addressBarTextField"]
        app.typeKey("w", modifierFlags: [.command, .option, .shift]) // Let's enforce a single window
        app.typeKey("n", modifierFlags: .command)
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    func test_availableAIChatInOmnibarDefaultSettings() throws {
        let button = app.windows.buttons["AddressBarButtonsViewController.aiChatButton"]
        XCTAssertTrue(button.exists, "AIChat Button should exist")
    }

    func test_disableAIChatOmnibarFromSettings_buttonIsRemovedFromOmnibar() throws {
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)
        let toggle = app.checkBoxes["Preferences.AIChat.showInAddressBarToggle"]

        let button = app.windows.buttons["AddressBarButtonsViewController.aiChatButton"]
        XCTAssertTrue(button.waitForExistence(timeout: UITests.Timeouts.elementExistence), "AIChat Button should exist by default")

        toggle.click()

        XCTAssertFalse(button.exists, "AIChat Button should not exist after being disabled")

        toggle.click()

        XCTAssertTrue(button.exists, "AIChat Button should exist after being enabled")
    }
}
