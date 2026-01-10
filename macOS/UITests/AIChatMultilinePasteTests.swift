//
//  AIChatMultilinePasteTests.swift
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

class AIChatMultilinePasteTests: UITestCase {
    private var addressBarTextField: XCUIElement!

    private enum AccessibilityIdentifiers {
        static let showSearchAndDuckAIToggle = "Preferences.AIChat.showSearchAndDuckAIToggleToggle"
        static let aiChatOmnibarTextView = "AIChatOmnibarTextContainerViewController.textView"
        static let aiChatOmnibarContainerView = "AIChatOmnibarTextContainerViewController.view"
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp(featureFlags: ["aiChatOmnibarToggle": true])

        addressBarTextField = app.addressBar
        app.enforceSingleWindow()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        app = XCUIApplication.setUp(featureFlags: ["aiChatOmnibarToggle": false])
        app.terminate()
    }

    /// Tests that pasting multiline text into the address bar switches to Duck.ai mode when the toggle setting is ON
    func test_pasteMultilineText_withToggleSettingON_switchesToDuckAIMode() throws {
        throw XCTSkip("Temporarily disabled")

        // Navigate to AI Chat settings and enable the Search/Duck.ai toggle
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)

        let toggleSetting = app.checkBoxes[AccessibilityIdentifiers.showSearchAndDuckAIToggle]
        XCTAssertTrue(toggleSetting.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Search/Duck.ai toggle setting should exist")

        // Ensure the toggle is ON
        if toggleSetting.value as? Bool == false {
            toggleSetting.click()
        }
        XCTAssertEqual(toggleSetting.value as? Bool, true, "Search/Duck.ai toggle should be ON")

        // Close settings and go to a new tab
        app.typeKey("w", modifierFlags: .command)
        app.openNewTab()

        // Focus the address bar using keyboard shortcut to ensure it's in editing mode
        app.activateAddressBar()
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Copy multiline text to clipboard
        let multilineText = "Hello\nWorld\nThis is a test"
        copyTextToClipboard(multilineText)

        // Paste into address bar (Cmd+V)
        app.typeKey("v", modifierFlags: .command)

        // Verify the Duck.ai panel appeared by checking for the container view
        let aiChatContainerView = app.windows.firstMatch.descendants(matching: .any)[AccessibilityIdentifiers.aiChatOmnibarContainerView]
        XCTAssertTrue(
            aiChatContainerView.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Duck.ai container view should appear after pasting multiline text with toggle ON"
        )
    }

    /// Tests that pasting multiline text into the address bar does NOT switch to Duck.ai mode when the toggle setting is OFF
    func test_pasteMultilineText_withToggleSettingOFF_doesNotSwitchToDuckAIMode() throws {
        // Navigate to AI Chat settings and disable the Search/Duck.ai toggle
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)

        let toggleSetting = app.checkBoxes[AccessibilityIdentifiers.showSearchAndDuckAIToggle]
        XCTAssertTrue(toggleSetting.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Search/Duck.ai toggle setting should exist")

        // Ensure the toggle is OFF
        if toggleSetting.value as? Bool == true {
            toggleSetting.click()
        }
        XCTAssertEqual(toggleSetting.value as? Bool, false, "Search/Duck.ai toggle should be OFF")

        // Close settings and go to a new tab
        app.typeKey("w", modifierFlags: .command)
        app.openNewTab()

        // Focus the address bar using keyboard shortcut to ensure it's in editing mode
        app.activateAddressBar()
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Copy multiline text to clipboard
        let multilineText = "Hello\nWorld\nThis is a test"
        copyTextToClipboard(multilineText)

        // Paste into address bar (Cmd+V)
        app.typeKey("v", modifierFlags: .command)

        // Verify the Duck.ai panel did NOT appear
        let aiChatContainerView = app.windows.firstMatch.descendants(matching: .any)[AccessibilityIdentifiers.aiChatOmnibarContainerView]
        // Wait briefly to ensure no mode switch occurs
        let appeared = aiChatContainerView.waitForExistence(timeout: 0.5)
        XCTAssertFalse(
            appeared,
            "Duck.ai container view should NOT appear after pasting multiline text with toggle OFF"
        )

        // The text should be in the address bar (newlines replaced with spaces)
        let addressBarValue = addressBarTextField.value as? String ?? ""
        XCTAssertTrue(
            addressBarValue.contains("Hello") || addressBarValue.contains("World"),
            "Address bar should contain the pasted text when toggle is OFF"
        )
    }

    /// Tests that pasting single-line text does NOT trigger Duck.ai mode switch
    func test_pasteSingleLineText_doesNotSwitchToDuckAIMode() throws {
        // Navigate to AI Chat settings and enable the Search/Duck.ai toggle
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)

        let toggleSetting = app.checkBoxes[AccessibilityIdentifiers.showSearchAndDuckAIToggle]
        XCTAssertTrue(toggleSetting.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Search/Duck.ai toggle setting should exist")

        // Ensure the toggle is ON
        if toggleSetting.value as? Bool == false {
            toggleSetting.click()
        }

        // Close settings and go to a new tab
        app.typeKey("w", modifierFlags: .command)
        app.openNewTab()

        // Focus the address bar using keyboard shortcut to ensure it's in editing mode
        app.activateAddressBar()
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Copy single-line text to clipboard (no newlines)
        let singleLineText = "Hello World This is a test"
        copyTextToClipboard(singleLineText)

        // Paste into address bar (Cmd+V)
        app.typeKey("v", modifierFlags: .command)

        // Verify the Duck.ai panel did NOT appear
        let aiChatContainerView = app.windows.firstMatch.descendants(matching: .any)[AccessibilityIdentifiers.aiChatOmnibarContainerView]
        // Wait briefly to ensure no mode switch occurs
        let appeared = aiChatContainerView.waitForExistence(timeout: 0.5)
        XCTAssertFalse(
            appeared,
            "Duck.ai container view should NOT appear after pasting single-line text"
        )
    }

    /// Tests that pressing SHIFT + ENTER in the address bar toggles to Duck.ai mode when the aiChatOmnibarToggle feature flag is ON
    func test_shiftEnter_withToggleSettingON_togglesToDuckAIMode() throws {
        // Navigate to AI Chat settings and enable the Search/Duck.ai toggle
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)

        let toggleSetting = app.checkBoxes[AccessibilityIdentifiers.showSearchAndDuckAIToggle]
        XCTAssertTrue(toggleSetting.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Search/Duck.ai toggle setting should exist")

        // Ensure the toggle is ON
        if toggleSetting.value as? Bool == false {
            toggleSetting.click()
        }
        XCTAssertEqual(toggleSetting.value as? Bool, true, "Search/Duck.ai toggle should be ON")

        // Close settings and go to a new tab
        app.typeKey("w", modifierFlags: .command)
        app.openNewTab()

        // Focus the address bar using keyboard shortcut to ensure it's in editing mode
        app.activateAddressBar()
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Type some text in the address bar
        addressBarTextField.typeText("test query")

        // Press SHIFT + ENTER to toggle to Duck.ai mode
        app.typeKey(.return, modifierFlags: [.shift])

        // Verify the Duck.ai panel appeared by checking for the container view
        let aiChatContainerView = app.windows.firstMatch.descendants(matching: .any)[AccessibilityIdentifiers.aiChatOmnibarContainerView]
        XCTAssertTrue(
            aiChatContainerView.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Duck.ai container view should appear after pressing SHIFT + ENTER with toggle setting ON"
        )
    }

    // MARK: - Helper Methods

    private func copyTextToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
