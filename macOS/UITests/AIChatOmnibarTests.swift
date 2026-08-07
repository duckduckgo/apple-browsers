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

/// UI tests for the Duck.ai address-bar mode (the per-tab Search ↔ Duck.ai toggle). Covers the
/// high-traffic state transitions: tab-switch draft preservation, Cmd+T from Duck.ai, two-step ESC,
/// and refocus from the unfocused Duck.ai state.
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
        app = XCUIApplication.setUp()

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

    /// Waits until `addressBarTextField.value` satisfies the given predicate format. Necessary because
    /// XCUI's keyboard and tab-switch operations are non-blocking with respect to the app processing
    /// them — without an explicit wait, an assertion can read a stale or partial value (we hit this
    /// repeatedly across tests, where 3 runs would pass and the 4th would fail with `value: ''`).
    /// Failure of the wait is itself an assertion failure with a descriptive message; callers can still
    /// follow up with their own assertions on the now-stable value.
    private func waitForAddressBarValue(
        matching format: String,
        timeout: TimeInterval = UITests.Timeouts.elementExistence,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: format)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: addressBarTextField)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed,
                       "Address bar value did not match predicate '\(format)' within \(timeout)s",
                       file: file, line: line)
    }

    /// Switches to the previous tab via Cmd+Shift+[. Wrapped so future hardening (focus resets, sync
    /// points, etc.) can be applied in one place if these tests start to flake again.
    private func switchToPreviousTab() {
        app.typeKey("[", modifierFlags: [.command, .shift])
    }

    /// Switches to the next tab via Cmd+Shift+].
    private func switchToNextTab() {
        app.typeKey("]", modifierFlags: [.command, .shift])
    }

    // MARK: - Tier 1 tests

    /// Regression guard: the Duck.ai draft on the originating tab must NOT leak onto a sibling tab,
    /// even after a back-and-forth tab switch sequence. Reproduces a bug where switching back to a
    /// fresh tab a second time would show the Duck.ai-tab's prompt.
    func test_tabSwitch_DuckAIDraft_DoesNotLeakBetweenTabs() throws {
        // Tab 1: enter Duck.ai mode with a draft prompt.
        enterDuckAIModeWithPrompt("hello")

        // Tab 2: open a fresh NTP (Cmd+T). Wait for the bar to drop tab1's draft before the next
        // keystroke so Cmd+Shift+[ doesn't race with tab2's settle.
        app.openNewTab()
        waitForAddressBarValue(matching: "NOT (value CONTAINS 'hello')")

        // Switch back to Tab 1 (Cmd+Shift+[). Tab-switch-back into Duck.ai lands in `.inactiveWithAIChat`
        // by design (panel hidden, draft visible in the bar via the active text field), so we assert on
        // `addressBarTextField.value` rather than the panel's text view.
        switchToPreviousTab()
        waitForAddressBarValue(matching: "value CONTAINS 'hello'")

        // Switch forward to Tab 2 — the bar must NOT show Tab 1's prompt.
        switchToNextTab()
        waitForAddressBarValue(matching: "NOT (value CONTAINS 'hello')")

        // Reproduce the leak: switch back to Tab 1, then forward to Tab 2 a second time.
        switchToPreviousTab()
        waitForAddressBarValue(matching: "value CONTAINS 'hello'")
        switchToNextTab()
        waitForAddressBarValue(matching: "NOT (value CONTAINS 'hello')")
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
        waitForAddressBarValue(matching: "value CONTAINS 'typed-on-new-tab'")
    }

    /// Regression guard: two Duck.ai tabs with different drafts must keep their prompts isolated
    /// across repeated tab switches. Stresses the per-tab `sharedTextState` + `lastAddressBarTextFieldValue`
    /// snapshot/restore loop with two Duck.ai-mode tabs (the harder variant of the leak test).
    func test_twoDuckAITabs_PromptsStayIsolated() throws {
        // Tab 1: enter Duck.ai with "first prompt".
        enterDuckAIModeWithPrompt("first prompt")

        // Tab 2: open a fresh NTP and enter Duck.ai with "second prompt".
        app.openNewTab()
        waitForAddressBarValue(matching: "NOT (value CONTAINS 'first prompt')")
        enterDuckAIModeWithPrompt("second prompt")

        // Back to Tab 1 — bar must show tab 1's prompt, not tab 2's.
        switchToPreviousTab()
        waitForAddressBarValue(matching: "value CONTAINS 'first prompt'")
        let tab1AfterFirstReturn = (addressBarTextField.value as? String) ?? ""
        XCTAssertFalse(tab1AfterFirstReturn.contains("second prompt"),
                       "Tab 1 must not inherit Tab 2's Duck.ai draft, got: '\(tab1AfterFirstReturn)'")

        // Forward to Tab 2 — bar must show tab 2's prompt, not tab 1's.
        switchToNextTab()
        waitForAddressBarValue(matching: "value CONTAINS 'second prompt'")
        let tab2AfterReturn = (addressBarTextField.value as? String) ?? ""
        XCTAssertFalse(tab2AfterReturn.contains("first prompt"),
                       "Tab 2 must not inherit Tab 1's Duck.ai draft, got: '\(tab2AfterReturn)'")

        // One more round-trip to make sure repeated switches don't drift.
        switchToPreviousTab()
        waitForAddressBarValue(matching: "value CONTAINS 'first prompt'")
        switchToNextTab()
        waitForAddressBarValue(matching: "value CONTAINS 'second prompt'")
    }

    /// Regression guard: closing the active Duck.ai tab via Cmd+W must not leak its Duck.ai panel
    /// or draft onto the neighboring tab that becomes selected.
    func test_closeDuckAITab_NeighborStateUnaffected() throws {
        // Tab 1: a plain NTP in Search mode. The setUp left us on a fresh NTP, so just stay here.
        // Tab 2: open a fresh NTP and enter Duck.ai with a draft.
        app.openNewTab()
        enterDuckAIModeWithPrompt("about to close")

        // Close Tab 2 (Cmd+W) — Tab 1 should become selected.
        app.typeKey("w", modifierFlags: .command)

        // The Duck.ai panel must NOT be up on Tab 1.
        let panelAppeared = duckAIPanelContainer.waitForExistence(timeout: 1)
        XCTAssertFalse(panelAppeared,
                       "Tab 1 (Search mode) should not show the Duck.ai panel after closing the Duck.ai neighbor")

        // The bar must NOT show Tab 2's draft.
        waitForAddressBarValue(matching: "NOT (value CONTAINS 'about to close')")
    }

    /// Regression guard: clicking the Search↔Duck.ai toggle mid-typing preserves the bar text across
    /// the mode switch (the toggle is a UX shortcut for what Shift+Enter does, just without submit).
    func test_toggleClick_PreservesBarTextAcrossModeSwitches() throws {
        // Type a draft into the bar in Search mode.
        app.activateAddressBar()
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        addressBarTextField.typeText("preserved across toggle")
        waitForAddressBarValue(matching: "value CONTAINS 'preserved across toggle'")

        let toggle = app.windows.firstMatch.descendants(matching: .any)[Identifiers.searchModeToggleControl]
        XCTAssertTrue(toggle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Search/Duck.ai toggle should be visible")
        let toggleCenter = toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))

        // Click toggle → Duck.ai mode. Whether the panel auto-opens depends on focus state and isn't
        // the contract under test here — what matters is that the typed text survives the mode flip.
        toggleCenter.click()
        waitForAddressBarValue(matching: "value CONTAINS 'preserved across toggle'")

        // Click toggle → back to Search. Text must still be there.
        toggleCenter.click()
        waitForAddressBarValue(matching: "value CONTAINS 'preserved across toggle'")
    }

    /// Regression guard for the search-mode draft preservation case. Was previously deleted as flaky —
    /// the underlying flake (a `.suggestion(.askAIChat)` snapshot path that race-cleared the typed text)
    /// is sidestepped now that `lastAddressBarTextFieldValue` is mirrored live per keystroke from
    /// `handleTextDidChange`, always as the canonical `.text(typedText, userTyped: true)` shape.
    func test_tabSwitch_SearchModeDraft_PreservedAcrossSwitchBack() throws {
        // Tab 1: type a draft into the address bar in plain Search mode (no Duck.ai).
        app.activateAddressBar()
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Address bar should be reachable for typing the search draft")
        addressBarTextField.typeText("hello")
        waitForAddressBarValue(matching: "value CONTAINS 'hello'")

        // Tab 2: open a fresh NTP. Wait for the bar to clear before issuing the next keystroke so
        // Cmd+Shift+[ doesn't race with tab2's settle.
        app.openNewTab()
        waitForAddressBarValue(matching: "NOT (value CONTAINS 'hello')")

        // Switch back to Tab 1 — the search-mode draft must still be there.
        switchToPreviousTab()
        waitForAddressBarValue(matching: "value CONTAINS 'hello'")
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
        waitForAddressBarValue(matching: "value == ''")
    }

}
