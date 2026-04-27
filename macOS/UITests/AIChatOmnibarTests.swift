//
//  AIChatOmnibarTests.swift
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

/// UI tests for the Duck.ai address-bar mode (the per-tab Search ↔ Duck.ai toggle introduced by the
/// `aiChatOmnibarToggle` feature). Covers the high-traffic state transitions: tab-switch draft
/// preservation, Cmd+T from Duck.ai, two-step ESC, and refocus from the unfocused Duck.ai state.
class AIChatOmnibarTests: UITestCase {

    private var addressBarTextField: XCUIElement!

    private enum Identifiers {
        static let searchModeToggleControl = "AddressBarButtonsViewController.searchModeToggleControl"
        static let showSearchAndDuckAIToggleToggle = "Preferences.AIChat.showSearchAndDuckAIToggleToggle"
        static let aiChatOmnibarTextView = "AIChatOmnibarTextContainerViewController.textView"
        static let aiChatOmnibarContainerView = "AIChatOmnibarTextContainerViewController.view"
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp(featureFlags: ["aiChatOmnibarToggle": true])

        addressBarTextField = app.addressBar
        app.enforceSingleWindow()

        // The Search/Duck.ai segmented toggle is gated behind a user setting; without it on, Shift+Enter
        // doesn't switch into Duck.ai and the per-tab Duck.ai state machine isn't exercised.
        ensureSearchAndDuckAIToggleSettingIsOn()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        app.terminate()
    }

    // MARK: - Helpers

    /// Navigates to the AI Chat settings, enables `showSearchAndDuckAIToggle` if it's off, closes the
    /// settings tab, and opens a fresh NTP so the test starts in a clean state. Mirrors the proven
    /// flow from `test_shiftEnter_withToggleSettingON_togglesToDuckAIMode` in `AIChatMultilinePasteTests`.
    private func ensureSearchAndDuckAIToggleSettingIsOn() {
        addressBarTextField.typeURL(URL(string: "duck://settings/aichat")!)
        let toggleSetting = app.checkBoxes[Identifiers.showSearchAndDuckAIToggleToggle]
        XCTAssertTrue(toggleSetting.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Search/Duck.ai toggle setting should be reachable from settings")
        if toggleSetting.value as? Bool == false {
            toggleSetting.click()
        }
        XCTAssertEqual(toggleSetting.value as? Bool, true,
                       "Search/Duck.ai toggle setting should now be ON")
        app.typeKey("w", modifierFlags: .command)
        app.openNewTab()
    }

    /// Switches the active tab into focused Duck.ai mode by typing the prompt in the address bar and
    /// pressing Shift+Enter. Returns the panel's text view element for further assertions. The
    /// existence check is on the container view rather than the text view because that's the
    /// reliably-queryable element under XCUI (matches the assertion in
    /// `AIChatMultilinePasteTests.test_shiftEnter_withToggleSettingON_togglesToDuckAIMode`).
    @discardableResult
    private func enterDuckAIModeWithPrompt(_ prompt: String) -> XCUIElement {
        app.activateAddressBar()
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Address bar should be reachable for typing the seed prompt")
        addressBarTextField.typeText(prompt)
        app.typeKey(.return, modifierFlags: [.shift])
        XCTAssertTrue(duckAIPanelContainer.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Duck.ai panel container should appear after Shift+Enter")
        return duckAITextView
    }

    private var duckAITextView: XCUIElement {
        app.windows.firstMatch.descendants(matching: .any)[Identifiers.aiChatOmnibarTextView]
    }

    private var duckAIPanelContainer: XCUIElement {
        app.windows.firstMatch.descendants(matching: .any)[Identifiers.aiChatOmnibarContainerView]
    }

    // MARK: - Tier 1 tests

    /// Regression guard: the Duck.ai draft on the originating tab must NOT leak onto a sibling tab,
    /// even after a back-and-forth tab switch sequence. Reproduces a bug where switching back to a
    /// fresh tab a second time would show the Duck.ai-tab's prompt.
    func test_tabSwitch_DuckAIDraft_DoesNotLeakBetweenTabs() throws {
        // Tab 1: enter Duck.ai mode with a draft prompt.
        enterDuckAIModeWithPrompt("hello")

        // Tab 2: open a fresh NTP (Cmd+T).
        app.openNewTab()

        // Switch back to Tab 1 (Cmd+Shift+[). Tab-switch-back into Duck.ai lands in `.inactiveWithAIChat`
        // by design (panel hidden, draft visible in the bar via the active text field), so we assert on
        // `addressBarTextField.value` rather than the panel's text view.
        app.typeKey("[", modifierFlags: [.command, .shift])
        let tab1BarValue = (addressBarTextField.value as? String) ?? ""
        XCTAssertTrue(tab1BarValue.contains("hello"),
                      "Tab 1's Duck.ai prompt should be restored in the bar after returning")

        // Switch forward to Tab 2 — the bar must NOT show Tab 1's prompt.
        app.typeKey("]", modifierFlags: [.command, .shift])
        let tab2BarValue = (addressBarTextField.value as? String) ?? ""
        XCTAssertFalse(tab2BarValue.contains("hello"),
                       "Tab 2 should not inherit Tab 1's Duck.ai draft on first visit-back, got: '\(tab2BarValue)'")

        // Reproduce the leak: switch back to Tab 1, then forward to Tab 2 a second time.
        app.typeKey("[", modifierFlags: [.command, .shift])
        app.typeKey("]", modifierFlags: [.command, .shift])
        let tab2BarValueAgain = (addressBarTextField.value as? String) ?? ""
        XCTAssertFalse(tab2BarValueAgain.contains("hello"),
                       "Tab 2 must still be empty on a second return — no draft leak, got: '\(tab2BarValueAgain)'")
    }

    /// Regression guard: opening a new tab via Cmd+T while Tab 1 is in Duck.ai mode should land the
    /// new tab in focused search (no Duck.ai panel, address bar takes typed input).
    func test_cmdT_FromDuckAITab_LandsFocusedInSearch() throws {
        enterDuckAIModeWithPrompt("input isn't submitted")

        // Cmd+T — open a fresh NTP.
        app.openNewTab()

        // The new tab should NOT have the Duck.ai panel up.
        let panelAppeared = duckAIPanelContainer.waitForExistence(timeout: 1)
        XCTAssertFalse(panelAppeared,
                       "New NTP from Cmd+T should not show the Duck.ai panel")

        // The address bar should be focused — typing should land in it without any extra click.
        addressBarTextField.typeText("typed-on-new-tab")
        let value = (addressBarTextField.value as? String) ?? ""
        XCTAssertTrue(value.contains("typed-on-new-tab"),
                      "New NTP's address bar should be focused (typing lands in the bar)")
    }

    /// Regression guard for the search-mode draft preservation case. An earlier attempt to fix the
    /// Duck.ai leak (commit 370851b12e) snapshotted the outgoing tab's bar value at the wrong time
    /// and ended up wiping plain search-mode drafts on tab-switch-back. This test pins the contract:
    /// typing in the bar (no Shift+Enter, plain Search mode), opening a fresh tab, and switching
    /// back must restore the draft on the originating tab.
    func test_tabSwitch_SearchModeDraft_PreservedAcrossSwitchBack() throws {
        // Tab 1: type a draft into the address bar in plain Search mode (no Duck.ai).
        app.activateAddressBar()
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Address bar should be reachable for typing the search draft")
        addressBarTextField.typeText("hello")

        // Tab 2: open a fresh NTP (Cmd+T).
        app.openNewTab()

        // Switch back to Tab 1 (Cmd+Shift+[) — the search-mode draft must still be there.
        app.typeKey("[", modifierFlags: [.command, .shift])
        let tab1BarValue = (addressBarTextField.value as? String) ?? ""
        XCTAssertTrue(tab1BarValue.contains("hello"),
                      "Tab 1's search-mode draft should be preserved after switching back, got: '\(tab1BarValue)'")
    }

    /// First ESC unfocuses Duck.ai (panel hidden, draft preserved). Second ESC fully exits Duck.ai
    /// (draft cleared, toggle back to Search).
    func test_twoStepEscape_UnfocusesThenExitsDuckAI() throws {
        enterDuckAIModeWithPrompt("hello")

        // First Escape: panel collapses to a single-line bar.
        app.typeKey(.escape, modifierFlags: [])
        let panelStillVisible = duckAIPanelContainer.waitForExistence(timeout: 1)
        XCTAssertFalse(panelStillVisible,
                       "Duck.ai panel container should hide after the first ESC")

        // Second Escape: fully exits Duck.ai. Re-activate the bar to inspect its value.
        app.typeKey(.escape, modifierFlags: [])
        app.activateAddressBar()
        let valueAfterSecondEsc = (addressBarTextField.value as? String) ?? ""
        XCTAssertEqual(valueAfterSecondEsc, "",
                       "Bar should be empty after the second ESC fully exits Duck.ai")
    }

}
