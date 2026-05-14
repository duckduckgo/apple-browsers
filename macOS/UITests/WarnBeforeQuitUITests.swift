//
//  WarnBeforeQuitUITests.swift
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

import Carbon
import XCTest

class WarnBeforeQuitUITests: UITestCase {

    var featureFlags: [String: Bool] {
        [
            "warnBeforeQuit": true,
            "firstTimeQuitSurvey": false
        ]
    }

    private var quitOverlay: XCUIElement {
        app.staticTexts["Hold or press again to quit"]
    }

    private var closeOverlay: XCUIElement {
        app.staticTexts["Hold or press again to close"]
    }

    private var dontShowAgainButton: XCUIElement {
        app.staticTexts[XCUIApplication.AccessibilityIdentifiers.warnBeforeQuitDontShowAgainButton]
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication.setUp(featureFlags: featureFlags)
        while app.pinnedTabs.count > 0 {
            app.menuItems["Close Tab"].click()
        }
        app.enforceSingleWindow()
        XCTAssertEqual(app.pinnedTabs.count, 0, "Should have no pinned tabs open")
        XCTAssertEqual(app.tabs.count, 1)
    }

    override func tearDown() {
        super.tearDown()
        if app.exists {
            app.closeAllWindows()
        }
    }

    // MARK: - Quit Confirmation Tests

    /// Verifies quit without window quits immediately (no overlay)
    func testQuitWithoutWindowQuitsImmediately() {
        app.enableWarnBeforeQuitting()
        app.closeAllWindows()

        // Given - no windows open
        XCTAssertEqual(app.windows.count, 0, "No windows should be open")

        // When - press Cmd+Q
        app.typeKey("q", modifierFlags: [.command])

        // Then - app should quit immediately without showing overlay
        XCTAssertTrue(
            app.wait(for: .keyPath(\.exists, equalTo: false), timeout: UITests.Timeouts.elementExistence),
            "App should quit immediately when no windows are open"
        )
    }

    /// Verifies overlay auto-dismisses after timeout, then double-press quits
    func testOverlayTimeoutThenDoublePress() {
        app.enableWarnBeforeQuitting()

        // Given - window is open
        app.openNewWindow()

        // Hover over tab bar to prevent hover-pause of timer
        app.tabs.firstMatch.hoverCoordinate()

        // When - press Cmd+Q once and let it timeout
        app.typeKey("q", modifierFlags: [.command])
        XCTAssertTrue(
            quitOverlay.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Overlay should appear"
        )

        // Then - overlay should auto-dismiss after timeout (4 seconds + buffer)
        XCTAssertTrue(
            quitOverlay.waitForNonExistence(timeout: 6.0),
            "Overlay should auto-dismiss after timeout"
        )

        // When - press Cmd+Q twice to quit
        app.typeKey("q", modifierFlags: [.command])
        XCTAssertTrue(
            quitOverlay.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Overlay should appear after first Cmd+Q"
        )

        app.typeKey("q", modifierFlags: [.command])

        // Then - app should quit
        XCTAssertTrue(
            app.wait(for: .keyPath(\.exists, equalTo: false), timeout: UITests.Timeouts.elementExistence),
            "App should quit after double Cmd+Q"
        )
    }

    /// Verifies pressing Escape cancels the quit confirmation
    func testPressingEscapeCancelsQuitConfirmation() {
        app.enableWarnBeforeQuitting()

        // Given - window is open
        app.openNewWindow()

        // Hover over tab bar to ensure overlay is not paused
        app.tabs.firstMatch.hoverCoordinate()

        // When - press Cmd+Q to show overlay
        app.typeKey("q", modifierFlags: [.command])

        XCTAssertTrue(
            quitOverlay.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Overlay should appear"
        )

        // When - press Escape
        app.typeKey(.escape, modifierFlags: [])

        // Then - overlay should disappear immediately
        XCTAssertTrue(
            quitOverlay.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "Overlay should disappear immediately after Escape"
        )

        // And - app should still be running
        XCTAssertTrue(app.exists)
    }

    /// Verifies pressing Cmd+Q twice quickly quits app
    func testPressingCmdQTwiceQuitsApp() {
        app.enableWarnBeforeQuitting()

        // Given - window is open
        app.openNewWindow()

        // When - press Cmd+Q twice
        app.typeKey("q", modifierFlags: [.command])
        app.typeKey("q", modifierFlags: [.command])

        // Then - app should quit
        XCTAssertTrue(
            app.wait(for: .keyPath(\.exists, equalTo: false), timeout: UITests.Timeouts.elementExistence),
            "App should quit after double Cmd+Q"
        )
    }

    /// Verifies holding Cmd+Q quits app
    func testHoldingCmdQQuitsApp() {
        app.enableWarnBeforeQuitting()
        app.openNewWindow()

        // When - hold Cmd+Q for 0.7s (past 0.5s threshold)
        XCUIElement.perform(withKeyModifiers: [.command]) {
            app.keyDown(keyCode: kVK_ANSI_Q)
            RunLoop.current.run(until: Date().addingTimeInterval(0.7))
            app.keyUp(keyCode: kVK_ANSI_Q)
        }

        // Then - app should quit
        XCTAssertTrue(
            app.wait(for: .keyPath(\.exists, equalTo: false), timeout: UITests.Timeouts.elementExistence),
            "App should quit after holding Cmd+Q past threshold"
        )
    }

    /// Verifies early release (key or modifier) doesn't quit app
    func testEarlyReleaseDoesNotQuitApp() {
        app.enableWarnBeforeQuitting()

        // Test 1: Early key release (Q released before threshold while holding Cmd)
        app.openNewWindow()

        // Hover over tab bar to ensure overlay is not paused
        app.tabs.firstMatch.hoverCoordinate()

        XCUIElement.perform(withKeyModifiers: [.command]) {
            app.keyDown(keyCode: kVK_ANSI_Q)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            app.keyUp(keyCode: kVK_ANSI_Q)
            RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        }

        XCTAssertTrue(
            quitOverlay.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "Overlay should disappear after early key release"
        )
        XCTAssertTrue(app.exists, "App should still be running after early key release")

        // Test 2: Early modifier release (Cmd released before threshold while holding Q)
        XCUIElement.perform(withKeyModifiers: [.command]) {
            app.keyDown(keyCode: kVK_ANSI_Q)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        app.keyUp(keyCode: kVK_ANSI_Q)

        // Hover over tab bar to ensure overlay is not paused
        app.tabs.firstMatch.hoverCoordinate()

        XCTAssertTrue(
            quitOverlay.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "Overlay should disappear after early modifier release"
        )
        XCTAssertTrue(app.exists, "App should still be running after early modifier release")
    }

    // MARK: - Close Pinned Tab Tests

    /// Verifies warning appears when trying to close a pinned tab with Cmd+W
    func testClosePinnedTabWarningAppears() {
        app.enableWarnBeforeClosingPinnedTabs()

        // Given - a pinned tab
        app.openNewTab()
        app.pinCurrentTab()

        // When - press Cmd+W
        app.typeKey("w", modifierFlags: [.command])

        // Then - overlay should appear with close confirmation message
        XCTAssertTrue(
            closeOverlay.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Close pinned tab warning should appear after pressing Cmd+W"
        )

        // Verify don't show again button appears
        XCTAssertTrue(dontShowAgainButton.exists, "Don't Show Again button should be visible")
    }

    /// Verifies pressing Cmd+W twice closes a pinned tab
    func testPressingCmdWTwiceClosesPinnedTab() {
        app.enableWarnBeforeClosingPinnedTabs()

        // Given - a pinned tab
        app.pinCurrentTab()
        XCTAssertEqual(app.tabs.count, 0, "Should have no regular tabs open")
        XCTAssertTrue(
            app.wait(for: .keyPath(\.pinnedTabs.count, equalTo: 1), timeout: UITests.Timeouts.elementExistence),
            "Should have 1 pinned tab"
        )

        // When - press Cmd+W twice
        app.typeKey("w", modifierFlags: [.command])
        app.typeKey("w", modifierFlags: [.command])

        // Then - tab should be closed
        XCTAssertEqual(app.pinnedTabs.count, 0, "Pinned tab should be closed after double Cmd+W")
    }

    /// Verifies holding Cmd+W closes pinned tab
    func testHoldingCmdWClosesPinnedTab() {
        app.enableWarnBeforeClosingPinnedTabs()

        // Given - a pinned tab
        app.pinCurrentTab()
        XCTAssertEqual(app.tabs.count, 0, "Should have no regular tabs open")
        XCTAssertTrue(
            app.wait(for: .keyPath(\.pinnedTabs.count, equalTo: 1), timeout: UITests.Timeouts.elementExistence),
            "Should have 1 pinned tab"
        )

        // When - hold Cmd+W for 0.7s (past 0.5s threshold)
        XCUIElement.perform(withKeyModifiers: [.command]) {
            app.keyDown(keyCode: kVK_ANSI_W)
            RunLoop.current.run(until: Date().addingTimeInterval(0.7))
            app.keyUp(keyCode: kVK_ANSI_W)
        }

        // Then - tab should be closed
        XCTAssertEqual(app.pinnedTabs.count, 0, "Pinned tab should be closed after holding Cmd+W past threshold")
    }

    /// Verifies early release (key or modifier) doesn't close pinned tab
    func testEarlyReleaseDoesNotClosePinnedTab() {
        app.enableWarnBeforeClosingPinnedTabs()

        // Test 1: Early key release (W released before threshold while holding Cmd)
        app.pinCurrentTab()

        XCTAssertEqual(app.tabs.count, 0, "Should have no regular tabs open")
        XCTAssertTrue(
            app.wait(for: .keyPath(\.pinnedTabs.count, equalTo: 1), timeout: UITests.Timeouts.elementExistence),
            "Should have 1 pinned tab"
        )

        // Hover over pinned tab to ensure overlay is not paused
        app.pinnedTabs.firstMatch.hoverCoordinate()

        XCUIElement.perform(withKeyModifiers: [.command]) {
            app.keyDown(keyCode: kVK_ANSI_W)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            app.keyUp(keyCode: kVK_ANSI_W)
            RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        }

        XCTAssertTrue(
            closeOverlay.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "Overlay should disappear after early key release"
        )
        XCTAssertEqual(app.pinnedTabs.count, 1, "Pinned tab should still be open after early key release")

        // Test 2: Early modifier release (Cmd released before threshold while holding W)
        XCUIElement.perform(withKeyModifiers: [.command]) {
            app.keyDown(keyCode: kVK_ANSI_W)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        app.keyUp(keyCode: kVK_ANSI_W)

        XCTAssertTrue(
            closeOverlay.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "Overlay should disappear after early modifier release"
        )
        XCTAssertEqual(app.pinnedTabs.count, 1, "Pinned tab should still be open after early modifier release")
    }

    /// Verifies dialog doesn't appear for next pinned tab after holding to close first tab
    func testDialogDoesNotAppearForNextPinnedTabAfterHolding() throws {
        app.enableWarnBeforeClosingPinnedTabs()

        // Given - 2 pinned tabs and no regular tabs
        app.pinCurrentTab()
        app.openNewTab()
        app.pinCurrentTab()

        XCTAssertEqual(app.tabs.count, 0, "Should have no regular tabs open")
        XCTAssertTrue(
            app.wait(for: .keyPath(\.pinnedTabs.count, equalTo: 2), timeout: UITests.Timeouts.elementExistence),
            "Should have 1 pinned tab"
        )

        // When - close first tab with double-press
        app.typeKey("w", modifierFlags: [.command])

        closeOverlay.hoverCoordinate()
        XCTAssertTrue(closeOverlay.exists)

        // Then immediately press and hold Cmd+W to close first tab
        XCUIElement.perform(withKeyModifiers: [.command]) {
            app.keyDown(keyCode: kVK_ANSI_W)
            RunLoop.current.run(until: Date().addingTimeInterval(0.7))

            // Wait for overlay to disappear and first tab to close
            XCTAssertTrue(
                closeOverlay.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
                "Overlay should disappear after first tab closes"
            )
            XCTAssertEqual(app.pinnedTabs.count, 1, "First pinned tab should be closed")

            // Verify overlay doesn't appear for second tab
            XCTAssertFalse(
                closeOverlay.waitForExistence(timeout: 1),
                "Overlay should not appear for second tab"
            )
            app.keyUp(keyCode: kVK_ANSI_W)
        }

        // Then - only first tab should be closed, second tab remains
        XCTAssertEqual(app.pinnedTabs.count, 1, "Only first tab should be closed")
    }

    /// Verifies closing unpinned tabs doesn't show warning
    func testClosingUnpinnedTabDoesNotShowWarning() {
        app.enableWarnBeforeQuitting()

        // Given - an unpinned tab
        app.openNewTab()

        // Ensure it's not pinned
        XCTAssertTrue(app.currentTabCanBePinned(), "Tab should be unpinned")

        // When - press Cmd+W
        app.typeKey("w", modifierFlags: [.command])

        // Then - no overlay should appear, tab closes immediately
        XCTAssertFalse(
            closeOverlay.waitForExistence(timeout: 1),
            "Warning should not appear for unpinned tabs"
        )
    }

    // MARK: - Don't Show Again Tests

    /// Verifies hovering over the button keeps overlay visible
    func testHoveringOverButtonKeepsOverlayVisible() {
        app.enableWarnBeforeQuitting()

        // Given - window is open and quit warning is shown
        app.openNewWindow()
        app.typeKey("q", modifierFlags: [.command])

        // When - hover over the dialog
        quitOverlay.hoverCoordinate()

        RunLoop.current.run(until: Date().addingTimeInterval(5))
        // Then - overlay should remain visible while hovering
        XCTAssertTrue(
            quitOverlay.exists,
            "Overlay should remain visible while hovering over button"
        )
    }

    /// Verifies disabling close pinned tab warning in settings
    func testDisablingClosePinnedTabWarningInSettings() {
        // Given - warning disabled in settings
        app.disableWarnBeforeClosingPinnedTabs()

        // When - create and pin a tab, then try to close it
        XCTAssertEqual(app.pinnedTabs.count, 0, "Should have no pinned tabs initially")
        app.openNewTab()
        app.pinCurrentTab()
        XCTAssertTrue(
            app.wait(for: .keyPath(\.pinnedTabs.count, equalTo: 1), timeout: UITests.Timeouts.elementExistence),
            "Should have 1 pinned tab"
        )

        app.typeKey("w", modifierFlags: [.command])

        // Then - overlay should not appear
        XCTAssertFalse(
            closeOverlay.waitForExistence(timeout: 1),
            "Overlay should not appear when warning is disabled in settings"
        )

        // And - pinned tab should close immediately
        XCTAssertEqual(app.pinnedTabs.count, 0, "Pinned tab should close immediately when warning is disabled")
    }

    /// Verifies disabling quit warning in settings
    func testDisablingQuitWarningInSettings() {
        // Given - warning disabled in settings
        app.disableWarnBeforeQuitting()

        // When - press Cmd+Q
        app.typeKey("q", modifierFlags: [.command])

        // Then - app should quit immediately
        XCTAssertTrue(
            app.wait(for: .keyPath(\.exists, equalTo: false), timeout: UITests.Timeouts.elementExistence),
            "App should quit immediately when warning is disabled"
        )
    }

    /// Verifies "Don't Show Again" button syncs with quit warning settings checkbox
    func testDontShowAgainButtonSyncsWithQuitWarningSettings() {
        // Given - settings window open in background with warning enabled, new window in foreground
        app.enableWarnBeforeQuitting(closeSettings: false)
        app.openNewWindow()

        // When - in active window, show overlay and click "Don't Show Again"
        app.typeKey("q", modifierFlags: [.command])

        quitOverlay.hoverCoordinate()
        XCTAssertTrue(quitOverlay.exists)

        dontShowAgainButton.clickCoordinate()

        // Then - app should quit immediately
        XCTAssertTrue(
            app.wait(for: .keyPath(\.exists, equalTo: false), timeout: UITests.Timeouts.elementExistence),
            "App should quit immediately after clicking Don't Show Again"
        )

        // Restart app and verify checkbox stayed off, then re-enable and test
        app = XCUIApplication.setUp(featureFlags: featureFlags)

        // Open settings and verify checkbox is still off
        app.openGeneralPreferences()
        XCTAssertEqual(app.warnBeforeQuittingCheckbox.value as? Int, 0, "Checkbox should remain unchecked after app restart")

        // When - check the checkbox back on
        app.warnBeforeQuittingCheckbox.toggleCheckboxIfNeeded(to: true, ensureHittable: app.ensureHittable)

        // Then - verify dialog appears again
        app.typeKey("q", modifierFlags: [.command])
        XCTAssertTrue(
            quitOverlay.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Overlay should appear again after re-enabling in settings"
        )
    }

    /// Verifies "Don't Show Again" button syncs with pinned tab close warning settings checkbox
    func testDontShowAgainButtonSyncsWithPinnedTabCloseSettings() {
        // Given - settings window open in background with warning enabled, new window with pinned tab in foreground
        app.enableWarnBeforeClosingPinnedTabs(closeSettings: false)

        app.openNewWindow()
        app.openNewTab()
        app.pinCurrentTab()
        app.pinnedTabs.firstMatch.click()

        // When - in active window, show overlay and click "Don't Show Again"
        app.typeKey("w", modifierFlags: [.command])

        closeOverlay.hoverCoordinate()
        XCTAssertTrue(closeOverlay.exists)

        dontShowAgainButton.clickCoordinate()

        // Then - switch to settings window and verify checkbox is now off
        app.typeKey("`", modifierFlags: [.command])  // Cycle to settings window

        XCTAssertEqual(app.warnBeforeClosingPinnedTabsCheckbox.value as? Int, 0, "Checkbox should be unchecked after clicking Don't Show Again")

        // When - check the checkbox back on
        app.warnBeforeClosingPinnedTabsCheckbox.toggleCheckboxIfNeeded(to: true, ensureHittable: app.ensureHittable)

        // Switch back to main window
        app.typeKey("`", modifierFlags: [.command])

        // Create another pinned tab to test
        app.openNewTab()
        app.pinCurrentTab()
        app.pinnedTabs.firstMatch.click()

        // Then - verify dialog appears again
        app.typeKey("w", modifierFlags: [.command])
        XCTAssertTrue(
            closeOverlay.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Overlay should appear again after re-enabling in settings"
        )
    }

}

private extension XCUIElement {
    func hoverCoordinate() {
        let coordinate = self.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        coordinate.hover()
    }
    func clickCoordinate() {
        let coordinate = self.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        coordinate.click()
    }
}
