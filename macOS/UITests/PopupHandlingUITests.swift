//
//  PopupHandlingUITests.swift
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

final class PopupHandlingUITests: UITestCase {

    // MARK: - Constants

    /// User-initiated popup timeout threshold (reduced to 2s for faster testing)
    /// Production default is 6s, but tests override to 2s in setUp
    private enum PopupTimeout {
        static let testingThreshold: TimeInterval = 2.0
    }

    private enum AccessibilityIdentifiers {
        static let popupsButton = "AddressBarButtonsViewController.popupsButton"
        static let alwaysAllow = "PermissionContextMenu.alwaysAllow"
        static let alwaysAsk = "PermissionContextMenu.alwaysAsk"  // "Notify" for popups
        static let allowPopupsForPage = "PermissionContextMenu.allowPopupsForPage"  // "Only allow pop-ups for this visit"
    }

    private var addressBarTextField: XCUIElement!
    private var serviceNowURL: URL!
    private var popupDelayedURL: URL!
    private var popupLinksURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        // Enable all popup blocking features and set reduced timeout for faster testing
        app = XCUIApplication.setUp(
            environment: [
                "POPUP_TIMEOUT_OVERRIDE": String(PopupTimeout.testingThreshold)  // Reduce from 6s to 2s for faster tests
            ],
            featureFlags: [
                "popupBlocking": true,
                "extendedUserInitiatedPopupTimeout": true,
                "suppressEmptyPopUpsOnApproval": true,
                "allowPopupsForCurrentPage": true,
                "popupPermissionButtonPersistence": true
            ]
        )

        // Load test HTML files from HTTP test server (not file:// URLs)
        serviceNowURL = URL.testsServer.appendingPathComponent("popup-servicenow.html")
        popupDelayedURL = URL.testsServer.appendingPathComponent("popup-delayed.html")
        popupLinksURL = URL.testsServer.appendingPathComponent("popup-links.html")

        addressBarTextField = app.addressBar
        app.enforceSingleWindow()
    }

    override func tearDown() {
        // Burn all data to clear permissions between tests
        app.fireButton.click()
        app.fireDialogSegmentedControl.buttons["Everything"].click()
        app.fireDialogTabsToggle.toggleCheckboxIfNeeded(to: true, ensureHittable: { _ in })
        app.fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, ensureHittable: { _ in })
        app.fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, ensureHittable: { _ in })
        app.fireDialogBurnButton.click()

        // Wait for fire animation to complete
        _ = app.fakeFireButton.waitForNonExistence(timeout: UITests.Timeouts.fireAnimation)

        super.tearDown()
    }

    // MARK: - Tests

    // MARK: User-Initiated Popup Behavior

    /// Tests that user-initiated popups (triggered immediately on button click) open without requiring permission
    func testUserClickOpensPopupsWithoutPermission() throws {
        // Load test page
        addressBarTextField.pasteURL(popupDelayedURL, pressingEnter: true)
        let webView = app.webViews["Popup Delayed Test"]

        // Click button (user-initiated) - should open without permission
        let button = webView.links["Open Popup (Immediate)"]
        XCTAssertTrue(button.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        button.click()

        // Wait for popup window to appear and verify content
        let popupWindow = app.windows["Immediate Popup"]
        XCTAssertTrue(
            popupWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Popup should open without permission prompt"
        )

        // Verify popup content loaded correctly
        let popupContent = popupWindow.staticTexts["User-Initiated Popup Opened"]
        XCTAssertTrue(
            popupContent.exists,
            "Popup content should be visible, verifying no breakage"
        )

        // Verify no popup blocked button appears
        verifyNoPopupBlockedButton()
    }

    /// Tests that popups delayed within the user interaction timeout window (1s < 2s threshold) are allowed without permission
    func testExtendedTimeoutWindowAllowsDelayedPopups() throws {
        // Load test page
        addressBarTextField.pasteURL(popupDelayedURL, pressingEnter: true)
        let webView = app.webViews["Popup Delayed Test"]

        // Click on page to establish user interaction
        webView.click()

        // Click button for popup within timeout window
        let button = webView.links["Open Popup (Within Timeout)"]
        XCTAssertTrue(button.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        button.click()

        // Wait for popup window to appear (should open within threshold)
        let popupWindow = app.windows["Delayed User Popup"]
        XCTAssertTrue(
            popupWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Popup should open without permission within \(PopupTimeout.testingThreshold)s timeout window"
        )

        // Verify popup content loaded correctly
        let popupContent = popupWindow.staticTexts["Delayed User-Initiated Popup"]
        XCTAssertTrue(
            popupContent.exists,
            "Popup content should be visible, verifying no breakage"
        )

        // Verify no permission prompt appeared
        verifyNoPopupBlockedButton()
    }

    /// Tests that popups delayed beyond the timeout (3s > 2s threshold) are blocked and must be manually opened from the menu
    /// Verifies both empty (about:blank) and cross-domain popups, where empty URLs don't appear in the menu
    func testExpiredTimeoutRequiresPermissionAndManualOpen() throws {
        // Load test page
        addressBarTextField.pasteURL(popupDelayedURL, pressingEnter: true)
        let webView = app.webViews["Popup Delayed Test"]

        // First: Trigger blocked about:blank popup (3s delay)
        let blankButton = webView.links["Trigger Blocked about:blank"]
        XCTAssertTrue(blankButton.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        blankButton.click()

        // Validate first popup blocked button appears (wait for 3s delay + block to happen)
        // about:blank blocked - empty URLs don't appear in menu
        verifyPopupBlockedButton(count: 1, expectedOpenItems: 0, timeout: UITests.Timeouts.elementExistence)

        // Second: Click delayed cross-domain popup button (also 3s delay)
        let beyondButton = webView.links["Open Popup (Beyond Timeout)"]
        XCTAssertTrue(beyondButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        beyondButton.click()

        // Wait for status to change again (indicating second popup was blocked)
        let secondBlockedStatus = webView.staticTexts["Blocked"]
        XCTAssertTrue(
            secondBlockedStatus.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Status should show second popup was blocked"
        )

        // Verify 2 blocked popups (1 about:blank + 1 example.com)
        // Only example.com should have a menu item (about:blank suppressed)
        verifyPopupBlockedButton(count: 2, expectedOpenItems: 1, closeMenu: false)

        // Choose example.com (cross-domain popup) from the menu
        let blockedPopupMenuItem = app.menuItems.containing(\.title, containing: "example.com").firstMatch
        XCTAssertTrue(
            blockedPopupMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Blocked cross-domain popup (example.com) should appear in menu"
        )
        blockedPopupMenuItem.click()

        // Validate popup opened with content
        let popupWindow = app.windows["Example Domain"]
        XCTAssertTrue(
            popupWindow.waitForExistence(timeout: UITests.Timeouts.navigation),
            "Cross-domain popup should open when selected from menu"
        )

        // Verify popup navigated to cross-domain URL and loaded content
        let popupWebView = popupWindow.webViews["Example Domain"]
        XCTAssertTrue(
            popupWebView.waitForExistence(timeout: UITests.Timeouts.navigation),
            "Cross-domain popup content should load successfully"
        )

        // Verify window count: main + manually opened example.com (about:blank was blocked, not opened)
        XCTAssertEqual(app.windows.count, 2, "Should have main window + manually opened popup")
    }

    // MARK: Permission Persistence Across Tabs

    /// Tests that popup permissions ("Always Allow", "Notify") persist across tabs and app restarts
    /// Verifies that the popup blocked button remains visible (per PR #2641) and shows the correct permission state
    func testAlwaysAllowPersistsAcrossTabs() throws {
        // Tab 1: Load page and trigger blocked popup (beyond timeout)
        addressBarTextField.pasteURL(popupDelayedURL, pressingEnter: true)
        let webView = app.webViews["Popup Delayed Test"]

        let button = webView.links["Open Popup (Beyond Timeout)"]
        XCTAssertTrue(button.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        button.click()

        verifyPopupBlockedButton(count: 1, expectedOpenItems: 1, closeMenu: false)

        // Select "Always Allow" - this immediately opens the blocked popup
        app.menuItems[AccessibilityIdentifiers.alwaysAllow].click()

        // Verify the blocked popup opened immediately after granting permission
        let popupWindow = app.windows["Example Domain"]
        XCTAssertTrue(
            popupWindow.waitForExistence(timeout: UITests.Timeouts.navigation),
            "Blocked popup should open immediately after 'Always Allow'"
        )
        XCTAssertEqual(app.windows.count, 2, "Exactly one popup should have opened")

        // Close it
        popupWindow.buttons[XCUIIdentifierCloseWindow].click()

        // Tab 2: Open new tab and load same page
        app.openNewTab()
        addressBarTextField.pasteURL(popupDelayedURL, pressingEnter: true)

        // Verify button is NOT visible initially in new tab (no blocked popups yet)
        verifyNoPopupBlockedButton()

        // Click button - popup should now open (permission already granted)
        XCTAssertTrue(button.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        button.click()

        // Wait for popup window to open
        XCTAssertTrue(
            popupWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Popup should open (permission already granted)"
        )
        XCTAssertEqual(app.windows.count, 2, "Exactly one popup should have opened – 2")

        // Close popup window so it doesn't cover the popup blocked button
        popupWindow.buttons[XCUIIdentifierCloseWindow].click()

        // The popup button from Tab 1 should still be visible (button persists per PR #2641)
        // Open its menu to change permission back to Notify
        verifyPopupBlockedButton(count: 0, closeMenu: false)

        // Verify "Always Allow" is checked (persisted from Tab 1)
        let alwaysAllowMenuItem = app.menuItems[AccessibilityIdentifiers.alwaysAllow]
        XCTAssertEqual(alwaysAllowMenuItem.value as? String, "selected", "Always Allow should be selected in Tab 2")

        // Change to "Notify"
        app.menuItems[AccessibilityIdentifiers.alwaysAsk].click()

        // Try opening another popup in Tab 2 - should be blocked now
        button.click()

        let blockedStatus = webView.staticTexts.containing(\.value, containing: "Blocked").firstMatch
        XCTAssertTrue(
            blockedStatus.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Popup should be blocked in Tab 2 after changing to Notify"
        )

        verifyPopupBlockedButton(count: 1, expectedOpenItems: 1)
        try app.closeTab()

        // Open Tab 3 and verify Notify persists across tabs
        app.openNewTab()
        addressBarTextField.pasteURL(popupDelayedURL, pressingEnter: true)

        XCTAssertTrue(button.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        button.click()

        // Wait for popup to be blocked
        XCTAssertTrue(
            blockedStatus.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Popup should be blocked (Notify permission persisted across tabs)"
        )

        verifyPopupBlockedButton(count: 1, expectedOpenItems: 1, closeMenu: false)

        // Verify "Notify" is checked (persisted from Tab 2)
        let notifyMenuItem = app.menuItems[AccessibilityIdentifiers.alwaysAsk]
        XCTAssertEqual(notifyMenuItem.value as? String, "selected", "Notify should be selected in Tab 3")

        // Set "Always Allow" again - this immediately opens the blocked popup
        app.menuItems[AccessibilityIdentifiers.alwaysAllow].click()

        // Verify the blocked popup opened immediately
        XCTAssertTrue(
            popupWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Blocked popup should open immediately after 'Always Allow'"
        )
        XCTAssertEqual(app.windows.count, 2, "Exactly one popup should have opened – 3")

        // Close it before restart
        popupWindow.buttons[XCUIIdentifierCloseWindow].click()

        // Restart app: Verify permission persists after restart
        app.terminate()
        app.launch()

        addressBarTextField = app.addressBar
        app.enforceSingleWindow()

        addressBarTextField.pasteURL(popupDelayedURL, pressingEnter: true)

        XCTAssertTrue(button.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        button.click()

        // Wait for popup window to open again
        XCTAssertTrue(
            popupWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Popup should still open (permission persisted after restart)"
        )
        XCTAssertEqual(app.windows.count, 2, "Exactly one popup should have opened – 4")

        // Close popup and verify permission menu still accessible
        popupWindow.buttons[XCUIIdentifierCloseWindow].click()

        verifyPopupBlockedButton(count: 0, closeMenu: false)

        // Verify "Always Allow" is still checked after restart
        let alwaysAllowAfterRestart = app.menuItems[AccessibilityIdentifiers.alwaysAllow]
        XCTAssertEqual(alwaysAllowAfterRestart.value as? String, "selected", "Always Allow should still be selected after restart")

        // Close menu
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: Popup Button State

    /// Tests that the popup blocked button appears only for page-initiated blocked popups, not for user-initiated actions
    /// Validates page-initiated popups (where first consumes interaction, second is blocked) vs Cmd+click link navigation
    func testPopupButtonAppearsOnlyForPageInitiatedPopups() throws {
        // Load page and trigger page-initiated popup (first consumes interaction, second blocked)
        addressBarTextField.pasteURL(popupDelayedURL, pressingEnter: true)
        let webView = app.webViews["Popup Delayed Test"]

        // Trigger page popup: opens 2 popups (first allowed, second blocked)
        let button = webView.links["Trigger 2 Page Popups (1st Allowed, 2nd Blocked)"]
        XCTAssertTrue(button.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        button.click()

        // Verify first popup opened
        let popupWindow = app.windows["First Popup Allowed"]
        XCTAssertTrue(
            popupWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "First popup should exist"
        )
        XCTAssertEqual(app.windows.count, 2, "Exactly one popup should have opened (main + 1)")

        let popupContent = popupWindow.staticTexts["First Popup Allowed"]
        XCTAssertTrue(
            popupContent.exists,
            "First popup content should be visible, verifying no breakage"
        )

        // Close popup window before navigating
        popupWindow.buttons[XCUIIdentifierCloseWindow].click()

        // Only 1 popup should be blocked (first one consumes user interaction)
        // Blocked popup is about:blank - empty URLs don't appear in menu
        verifyPopupBlockedButton(count: 1, expectedOpenItems: 0)

        // Now test user-initiated popup
        app.activateAddressBar()
        app.openURL(popupLinksURL, waitForWebViewAccessibilityLabel: "Popup Links Test")
        let linksWebView = app.webViews["Popup Links Test"]

        // ⌘-click link (user-initiated)
        let link = linksWebView.links["Normal Link to Example"]
        XCUIElement.perform(withKeyModifiers: [.command]) {
            link.click()
        }

        // Wait for tab to open
        let newTab = app.tabs["Example Domain"]
        XCTAssertTrue(
            newTab.waitForExistence(timeout: UITests.Timeouts.navigation),
            "New tab should open"
        )

        // Button should NOT appear for user-initiated
        verifyNoPopupBlockedButton(webViewTitle: "Popup Links Test")
    }

    /// Tests that the popup blocked button correctly accumulates and displays the count of multiple blocked popups
    func testPopupButtonCountAccumulatesMultipleBlockedPopups() throws {
        addressBarTextField.pasteURL(popupDelayedURL, pressingEnter: true)
        let webView = app.webViews["Popup Delayed Test"]

        // Trigger 6 popups: first opens (consumes interaction), remaining 5 blocked
        let button = webView.links["Trigger 6 Page Popups (1st Allowed, 5 Blocked)"]
        XCTAssertTrue(button.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        button.click()

        // Verify first popup opened
        let popupWindow = app.windows["First of Multiple"]
        XCTAssertTrue(
            popupWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "First popup should exist"
        )
        XCTAssertEqual(app.windows.count, 2, "Exactly one popup should have opened (main + 1)")

        let popupContent = popupWindow.staticTexts["First Popup Allowed"]
        XCTAssertTrue(
            popupContent.exists,
            "First popup content should be visible, verifying no breakage"
        )

        // Close popup window
        popupWindow.buttons[XCUIIdentifierCloseWindow].click()

        // Verify button shows count of 5 blocked (first popup consumes interaction)
        // All 5 are empty URLs - don't appear in menu
        verifyPopupBlockedButton(count: 5, expectedOpenItems: 0)
    }

    /// Tests that the popup blocked button clears when navigating to a different page
    func testPopupButtonClearsOnNavigation() throws {
        // Block popup and verify button appears
        addressBarTextField.pasteURL(popupDelayedURL, pressingEnter: true)
        let webView = app.webViews["Popup Delayed Test"]

        let button = webView.links["Open Popup (Beyond Timeout)"]
        XCTAssertTrue(button.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        button.click()

        let blockedStatus = webView.staticTexts.containing(\.value, containing: "Blocked").firstMatch
        XCTAssertTrue(
            blockedStatus.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Popup should be blocked"
        )

        verifyPopupBlockedButton(count: 1, expectedOpenItems: 1)

        // Navigate to different page
        app.activateAddressBar()
        app.openURL(URL(string: "https://example.com")!, waitForWebViewAccessibilityLabel: "Example Domain")

        // Button should clear
        verifyNoPopupBlockedButton(webViewTitle: "Example Domain")
    }

    // MARK: Empty/About:blank URL Suppression

    /// Tests that empty/about:blank blocked popups don't appear in the menu and are suppressed from the blocked list
    /// Verifies that after "Always Allow", empty popups are suppressed while normal popups open correctly
    func testEmptyURLsSuppressedAfterPermissionApproval() throws {
        addressBarTextField.pasteURL(popupDelayedURL, pressingEnter: true)
        let webView = app.webViews["Popup Delayed Test"]

        // Click button that opens about:blank (blocked because beyond timeout)
        let blockedButton = webView.links["Trigger Blocked about:blank"]
        XCTAssertTrue(blockedButton.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        blockedButton.click()

        // about:blank blocked - empty URLs don't appear in menu
        verifyPopupBlockedButton(count: 1, expectedOpenItems: 0, closeMenu: false)

        // Grant "Always Allow" permission (shouldn't open empty popup since empty URLs are suppressed)
        app.menuItems[AccessibilityIdentifiers.alwaysAllow].click()

        // Verify no popup opened (empty URL suppressed)
        XCTAssertEqual(app.windows.count, 1, "Empty popup should be suppressed")

        // Click button that opens about:blank with "Expected to be opened" - should be allowed
        let expectedButton = webView.links["Open about:blank (Expected to be opened)"]
        expectedButton.click()

        // Popup should open (permission granted)
        let expectedPopup = app.windows["Expected Popup"]
        XCTAssertTrue(
            expectedPopup.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "about:blank popup should open (permission granted)"
        )
        XCTAssertEqual(app.windows.count, 2, "Exactly one popup should have opened")

        // Close popup
        expectedPopup.buttons[XCUIIdentifierCloseWindow].click()

        // Popups allowed - blocked count cleared
        verifyPopupBlockedButton(count: 0, expectedOpenItems: 0)
    }

    /// Tests that temporary popup allowance ("Only allow pop-ups for this visit") clears on reload, navigation, and back/forward navigation
    /// Verifies allowance is cleared on: page reload, forward/back navigation, and navigating to a different page
    func testTemporaryAllowanceClearsOnNavigation() throws {
        addressBarTextField.pasteURL(popupDelayedURL, pressingEnter: true)
        let webView = app.webViews["Popup Delayed Test"]

        let button = webView.links["Trigger Blocked about:blank"]
        XCTAssertTrue(button.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        button.click()

        verifyPopupBlockedButton(count: 1, expectedOpenItems: 0, closeMenu: false)

        // Select "Only allow pop-ups for this visit" (temporary)
        app.menuItems[AccessibilityIdentifiers.allowPopupsForPage].click()

        // Click button that opens popup that should be allowed
        let expectedButton = webView.links["Open about:blank (Expected to be opened)"]
        expectedButton.click()

        let popupWindow = app.windows["Expected Popup"]
        XCTAssertTrue(
            popupWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "about:blank popup should open (temporary allowance active)"
        )

        // Close popup
        popupWindow.buttons[XCUIIdentifierCloseWindow].click()

        // Reload page - temporary allowance should be cleared
        app.reloadButton.click()

        // Click again after reload - popup should be blocked (temporary allowance cleared on reload)
        XCTAssertTrue(button.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        button.click()

        let blockedStatus = webView.staticTexts.containing(\.value, containing: "Blocked").firstMatch
        XCTAssertTrue(
            blockedStatus.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Popup should be blocked (temporary allowance cleared after reload)"
        )

        verifyPopupBlockedButton(count: 1, expectedOpenItems: 0)

        // Navigate away
        app.activateAddressBar()
        app.openURL(URL(string: "https://example.com")!, waitForWebViewAccessibilityLabel: "Example Domain")

        // Navigate back
        app.activateAddressBar()
        addressBarTextField.pasteURL(popupDelayedURL, pressingEnter: true)

        // Popup should be blocked again (temporary allowance cleared on navigation)
        XCTAssertTrue(button.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        button.click()

        XCTAssertTrue(
            blockedStatus.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Popup should be blocked (temporary allowance cleared)"
        )

        verifyPopupBlockedButton(count: 1, expectedOpenItems: 0)

        // Navigate back twice (double-back)
        app.backButton.click()
        app.backButton.click()

        // Click after double-back - should still be blocked
        XCTAssertTrue(button.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        button.click()

        XCTAssertTrue(
            blockedStatus.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Popup should be blocked after double-back navigation"
        )

        verifyPopupBlockedButton(count: 1, expectedOpenItems: 0)

        // Navigate forward twice (double-forward)
        app.forwardButton.click()
        app.forwardButton.click()

        // Click after double-forward - should still be blocked
        XCTAssertTrue(button.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        button.click()

        XCTAssertTrue(
            blockedStatus.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Popup should be blocked after double-forward navigation"
        )

        verifyPopupBlockedButton(count: 1, expectedOpenItems: 0)
    }

    // MARK: Popup Without Window Features (Opens as Tab)

    /// Tests that blocked popups opened via window.open() without window features (width/height)
    /// are properly blocked and, when manually opened from the menu, open as tabs instead of popup windows
    func testDelayedPopupWithoutWindowFeaturesOpensAsTab() throws {
        addressBarTextField.pasteURL(popupDelayedURL, pressingEnter: true)
        let webView = app.webViews["Popup Delayed Test"]

        // Click button that opens popup without window features (should open as tab, not window)
        let button = webView.links["Open Popup as Tab (Beyond Timeout)"]
        XCTAssertTrue(button.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        button.click()

        let blockedStatus = webView.staticTexts.containing(\.value, containing: "Blocked").firstMatch
        XCTAssertTrue(
            blockedStatus.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Popup without window features should be blocked"
        )

        // Verify blocked popup appears in menu (cross-domain)
        verifyPopupBlockedButton(count: 1, expectedOpenItems: 1, closeMenu: false)

        // Open the blocked popup
        let blockedPopupMenuItem = app.menuItems.containing(\.title, containing: "example.com").firstMatch
        XCTAssertTrue(
            blockedPopupMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Blocked popup should appear in menu"
        )
        blockedPopupMenuItem.click()

        // Verify it opened as a tab, not a window
        let newTab = app.tabs["Example Domain"]
        XCTAssertTrue(
            newTab.waitForExistence(timeout: UITests.Timeouts.navigation),
            "Popup without window features should open as tab"
        )

        XCTAssertEqual(app.windows.count, 1, "Should have only 1 window (no popup window created)")
        XCTAssertEqual(app.tabs.count, 2, "Should have 2 tabs (original + opened)")
    }

    // MARK: Multiple Cross-Domain Blocked Popups

    /// Tests that multiple blocked popups from different cross-domain sources (example.com, duckduckgo.com)
    /// are tracked separately, appear as individual menu items, can be opened independently,
    /// and the blocked count decrements properly until the menu is empty
    func testMultipleCrossDomainBlockedPopups() throws {
        addressBarTextField.pasteURL(popupDelayedURL, pressingEnter: true)
        let webView = app.webViews["Popup Delayed Test"]

        // Block first popup (example.com)
        let exampleButton = webView.links["Open Popup (Beyond Timeout)"]
        XCTAssertTrue(exampleButton.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        exampleButton.click()

        let blockedStatus = webView.staticTexts.containing(\.value, containing: "Blocked").firstMatch
        XCTAssertTrue(
            blockedStatus.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "First popup (example.com) should be blocked"
        )

        verifyPopupBlockedButton(count: 1, expectedOpenItems: 1)

        // Block second popup (duckduckgo.com)
        let duckduckgoButton = webView.links["Open Popup Alt Domain (Beyond Timeout)"]
        XCTAssertTrue(duckduckgoButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        duckduckgoButton.click()

        XCTAssertTrue(
            blockedStatus.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Second popup (duckduckgo.com) should be blocked"
        )

        // Verify 2 blocked popups, both with menu items
        verifyPopupBlockedButton(count: 2, expectedOpenItems: 2, closeMenu: false)

        // Open first blocked popup (example.com)
        let exampleComItem = app.menuItems.containing(\.title, containing: "example.com").firstMatch
        XCTAssertTrue(
            exampleComItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "example.com menu item should exist"
        )
        exampleComItem.click()

        let examplePopup = app.windows["Example Domain"]
        XCTAssertTrue(
            examplePopup.waitForExistence(timeout: UITests.Timeouts.navigation),
            "example.com popup should open"
        )
        XCTAssertEqual(app.windows.count, 2, "Should have main window + 1 popup")

        // Close example.com popup
        examplePopup.buttons[XCUIIdentifierCloseWindow].click()

        // Verify count decremented to 1
        verifyPopupBlockedButton(count: 1, expectedOpenItems: 1, closeMenu: false)

        // Open second blocked popup (duckduckgo.com)
        let duckduckgoItem = app.menuItems.containing(\.title, containing: "duckduckgo.com").firstMatch
        XCTAssertTrue(
            duckduckgoItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "duckduckgo.com menu item should exist"
        )
        duckduckgoItem.click()

        let duckduckgoPopup = app.windows.element(matching: \.title, containing: "DuckDuckGo")
        XCTAssertTrue(
            duckduckgoPopup.waitForExistence(timeout: UITests.Timeouts.navigation),
            "duckduckgo.com popup should open"
        )
        XCTAssertEqual(app.windows.count, 2, "Should have main window + 1 popup")

        // Close duckduckgo.com popup
        duckduckgoPopup.buttons[XCUIIdentifierCloseWindow].click()

        // Verify button shows count 0 with no menu items (both popups opened)
        verifyPopupBlockedButton(count: 0, expectedOpenItems: 0)
    }

    // MARK: Multiple Windows with Blocked Popups

    /// Tests that blocked popup state is maintained independently per window:
    /// - Blocked popups in one window don't affect other windows
    /// - Opening a blocked popup in one window doesn't affect the other window's blocked list
    /// - Each window has its own popup blocked button with its own state
    func testBlockedPopupsInMultipleWindows() throws {
        // Window 1: Block popup
        addressBarTextField.pasteURL(popupDelayedURL, pressingEnter: true)
        let webView1 = app.webViews["Popup Delayed Test"]

        let button = webView1.links["Open Popup (Beyond Timeout)"]
        XCTAssertTrue(button.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        button.click()

        // Open second window immediately after clicking (while popup is being delayed)
        app.openNewWindow()

        // Wait for window count to become 2
        XCTAssertTrue(
            app.windows.wait(for: \.count, equals: 2, timeout: UITests.Timeouts.elementExistence),
            "Window count should become 2"
        )

        let blockedStatus = webView1.staticTexts.containing(\.value, containing: "Blocked").firstMatch
        XCTAssertTrue(
            blockedStatus.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Popup should be blocked in window 1"
        )

        // Verify no button in the new (second) window yet
        verifyNoPopupBlockedButton(webViewTitle: "New Tab")

        // Focus back to the first window
        app.typeKey("`", modifierFlags: [.command])

        verifyPopupBlockedButton(count: 1, expectedOpenItems: 1, closeMenu: false)

        // Open the blocked popup
        let exampleComItem = app.menuItems.containing(\.title, containing: "example.com").firstMatch
        exampleComItem.click()

        let popup = app.windows.element(matching: \.title, containing: "Example Domain")
        XCTAssertTrue(
            popup.waitForExistence(timeout: UITests.Timeouts.navigation),
            "Popup should open"
        )

        // Close popup
        popup.buttons[XCUIIdentifierCloseWindow].click()

        // Verify button state changed in window 1 (count 0)
        verifyPopupBlockedButton(count: 0, expectedOpenItems: 0)

        // Switch to window 2 and verify no button there
        app.typeKey("`", modifierFlags: [.command])
        verifyNoPopupBlockedButton(webViewTitle: "New Tab")

        // Window 2: Load same page and block popup
        let addressBar2 = app.addressBar
        addressBar2.pasteURL(popupDelayedURL, pressingEnter: true)
        let webView2 = app.webViews["Popup Delayed Test"].firstMatch

        let button2 = webView2.links["Open Popup (Beyond Timeout)"]
        XCTAssertTrue(button2.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        button2.click()

        XCTAssertTrue(
            blockedStatus.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Popup should be blocked in window 2"
        )

        // Verify button in window 2 shows blocked popup
        verifyPopupBlockedButton(count: 1, expectedOpenItems: 1)

        // Switch back to window 1 and verify its button still shows blocked popup
        app.typeKey("`", modifierFlags: [.command])
        verifyPopupBlockedButton(count: 0, expectedOpenItems: 0)
    }

    // MARK: ServiceNow Scenarios

    /// Tests ServiceNow-like scenario where Cmd+click on a link that also triggers window.open() calls
    /// Verifies that only one tab opens (event consumption prevents extra tabs) and extra window.open() calls are blocked
    func testServiceNowCommandClickOnlyOpensOneTab() throws {
        addressBarTextField.pasteURL(serviceNowURL, pressingEnter: true)
        let webView = app.webViews["Simulate ServiceNow Cmd+Click Bug"]

        // ⌘-click first link (with extra tabs)
        let link = webView.links["Incident INC001 (with extra tabs)"]
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.localTestServer))

        XCUIElement.perform(withKeyModifiers: [.command]) {
            link.click()
        }

        // Wait for new tab
        let newTab = app.tabs["Example Domain"]
        XCTAssertTrue(
            newTab.waitForExistence(timeout: UITests.Timeouts.navigation),
            "Only one new tab should open"
        )

        // Verify only 2 tabs total (original + 1 new)
        XCTAssertEqual(
            app.tabs.count,
            2,
            "Should have exactly 2 tabs (original + 1 new), event consumption prevented extra tabs"
        )

        // Verify popup button shows 2 blocked (the 2 window.open() calls)
        // Both are empty URLs - don't appear in menu
        verifyPopupBlockedButton(count: 2, webViewTitle: "Simulate ServiceNow Cmd+Click Bug", expectedOpenItems: 0)
    }

    /// Tests that middle-clicking a ServiceNow-like link bypasses the JavaScript handler entirely,
    /// opening only the intended tab without triggering or blocking any window.open() calls
    func testServiceNowMiddleClickOnlyOpensOneTab() throws {
        guard #available(macOS 15, *) else { throw XCTSkip("WebKit issue fixed in macOS 15, matches Safari behavior") }

        addressBarTextField.pasteURL(serviceNowURL, pressingEnter: true)
        let webView = app.webViews["Simulate ServiceNow Cmd+Click Bug"]

        // Middle-click first link (bypasses JavaScript handler)
        let link = webView.links["Incident INC001 (with extra tabs)"]
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        link.middleClick()

        // Wait for new tab
        let newTab = app.tabs["Example Domain"]
        XCTAssertTrue(
            newTab.waitForExistence(timeout: UITests.Timeouts.navigation),
            "New tab did not open"
        )

        // Verify only 2 tabs total
        XCTAssertEqual(
            app.tabs.count,
            2,
            "Should have exactly 2 tabs"
        )

        // Middle-click bypasses JavaScript, so no popups are triggered
        verifyNoPopupBlockedButton(webViewTitle: "Simulate ServiceNow Cmd+Click Bug")
    }

    /// Tests that using "Open Link in New Tab" from the context menu bypasses the JavaScript handler,
    /// opening only the intended tab without triggering or blocking any window.open() calls
    func testServiceNowContextMenuOpenInNewTab() throws {
        addressBarTextField.pasteURL(serviceNowURL, pressingEnter: true)
        let webView = app.webViews["Simulate ServiceNow Cmd+Click Bug"]

        // Right-click and select "Open Link in New Tab" (bypasses JavaScript handler)
        let link = webView.links["Incident INC001 (with extra tabs)"]
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        link.rightClick()

        app.menuItems["Open Link in New Tab"].click()

        // Wait for new tab
        let newTab = app.tabs["Example Domain"]
        XCTAssertTrue(
            newTab.waitForExistence(timeout: UITests.Timeouts.navigation),
            "Only one new tab should open"
        )

        // Verify only 2 tabs total
        XCTAssertEqual(
            app.tabs.count,
            2,
            "Should have exactly 2 tabs"
        )

        // Context menu bypasses JavaScript, so no popups are triggered
        verifyNoPopupBlockedButton(webViewTitle: "Simulate ServiceNow Cmd+Click Bug")
    }

    /// Tests that Cmd+clicking a clean link (without extra window.open() calls) opens normally without any blocked popups
    func testServiceNowCleanLinkOpensNormally() throws {
        addressBarTextField.pasteURL(serviceNowURL, pressingEnter: true)
        let webView = app.webViews["Simulate ServiceNow Cmd+Click Bug"]

        // ⌘-click clean link (no extra window.open() calls)
        let link = webView.links["Incident INC002 (clean)"]
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.localTestServer))

        XCUIElement.perform(withKeyModifiers: [.command]) {
            link.click()
        }

        // Wait for new tab
        let newTab = app.tabs["Example Domain"]
        XCTAssertTrue(
            newTab.waitForExistence(timeout: UITests.Timeouts.navigation),
            "New tab should open normally"
        )

        // Verify 2 tabs total
        XCTAssertEqual(app.tabs.count, 2, "Should have 2 tabs")

        // No popup button should appear (clean link has no extra popups)
        verifyNoPopupBlockedButton(webViewTitle: "Simulate ServiceNow Cmd+Click Bug")
    }

    // MARK: - Helpers

    private func mainWindow(titled webViewTitle: String) -> XCUIElement {
        // Find main window by its webview content (test page title)
        // Popup windows don't have these test pages
        app.windows.element(matching: \.title, equalTo: webViewTitle).firstMatch
    }

    private func popupBlockedButton(inWindowWith webViewTitle: String = "Popup Delayed Test") -> XCUIElement {
        // Get button from main window with specified webview title
        let mainWindow = mainWindow(titled: webViewTitle)
        XCTAssertTrue(
            mainWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "mainWindow should be available"
        )

        return mainWindow.buttons[AccessibilityIdentifiers.popupsButton]
    }

    private func verifyPopupBlockedButton(count: Int, webViewTitle: String = "Popup Delayed Test", expectedOpenItems: Int? = nil, timeout: TimeInterval = UITests.Timeouts.elementExistence, closeMenu: Bool = true, file: StaticString = #file, line: UInt = #line) {
        let button = popupBlockedButton(inWindowWith: webViewTitle)
        XCTAssertTrue(
            button.waitForExistence(timeout: timeout),
            "Popup blocked button should appear",
            file: file,
            line: line
        )

        // Click button to open context menu and verify count
        button.click()

        // Get the context menu
        let contextMenu = button.children(matching: .menu).firstMatch

        // Only check for "Blocked X pop-ups" header if count > 0
        if count > 0 {
            let expectedText = "Blocked \(count) pop-up"
            let menuItem = contextMenu.menuItems.containing(\.title, containing: expectedText).firstMatch
            XCTAssertTrue(
                menuItem.exists,
                "Menu should show '\(expectedText)s', but menu item not found",
                file: file,
                line: line
            )

            // Verify the number of "Open..." menu items if specified
            if let expectedOpenItems = expectedOpenItems {
                // Count menu items for blocked popups (empty/about:blank are suppressed and won't appear)
                let openItems = contextMenu.menuItems.containing(
                    .keyPath(\.isEnabled, equalTo: true)
                    .and(.or(.keyPath(\.title, contains: "\""),
                             .keyPath(\.title, contains: "“"),
                             .keyPath(\.title, contains: "about:blank")
                    ))
                ).allElementsBoundByIndex

                XCTAssertEqual(
                    openItems.count,
                    expectedOpenItems,
                    "Should have exactly \(expectedOpenItems) 'Open...' menu item(s) for blocked popups, but found \(openItems)",
                    file: file,
                    line: line
                )
            }
        } else {
            // When count is 0, verify no "Blocked" header
            let blockedHeader = contextMenu.menuItems.containing(\.title, containing: "Blocked").firstMatch
            XCTAssertFalse(
                blockedHeader.exists,
                "Should not show 'Blocked X pop-ups' header when count is 0",
                file: file,
                line: line
            )
        }

        // Close menu by pressing Escape (unless told to keep it open)
        if closeMenu {
            app.typeKey(.escape, modifierFlags: [])
        }
    }

    private func verifyNoPopupBlockedButton(webViewTitle: String = "Popup Delayed Test", file: StaticString = #file, line: UInt = #line) {
        XCTAssertFalse(
            popupBlockedButton(inWindowWith: webViewTitle).exists,
            "Popup blocked button should not appear for user-initiated popups",
            file: file,
            line: line
        )
    }

}
