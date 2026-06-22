//
//  YouTubeAdBlockingUITests.swift
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

final class YouTubeAdBlockingUITests: UITestCase {

    private let sidebarButtonIdentifier = "PreferencesSidebar.youTubeAdBlockingButton"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Settings sidebar visibility

    func testSettingsEntryVisible_whenFullyEnabled() throws {
        try skipIfUnsupported()
        app = XCUIApplication.setUp(featureFlags: [
            "webExtensions": true,
            "adBlockingExtension": true
        ])
        app.openPreferencesWindow()
        let sidebarButton = app.buttons[sidebarButtonIdentifier]
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "YouTube Ad Blocking sidebar entry should be visible when fully enabled")
    }

    func testSettingsEntryHidden_whenWebExtensionsOff() throws {
        try skipIfUnsupported()
        app = XCUIApplication.setUp(featureFlags: [
            "webExtensions": false
        ])
        app.openPreferencesWindow()
        let generalButton = app.buttons[XCUIApplication.AccessibilityIdentifiers.preferencesGeneralButton]
        XCTAssertTrue(generalButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Preferences sidebar did not load")
        XCTAssertFalse(app.buttons[sidebarButtonIdentifier].exists,
                       "YouTube Ad Blocking sidebar entry should be hidden when webExtensions is off")
    }

    func testSettingsEntryVisibleWithContingencyMessage_whenRemotelyDisabled() throws {
        try skipIfUnsupported()
        app = XCUIApplication.setUp(featureFlags: [
            "webExtensions": true,
            "adBlockingExtension": false
        ])
        app.openPreferencesWindow()
        let sidebarButton = app.buttons[sidebarButtonIdentifier]
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "YouTube Ad Blocking sidebar entry should still be visible when remotely disabled")
        sidebarButton.click()
        let contingencyMessage = app.descendants(matching: .any)["Preferences.YouTubeAdBlocking.unavailableMessage"]
        XCTAssertTrue(contingencyMessage.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Contingency message should be shown in YouTube Ad Blocking pane when remotely disabled")
    }

    // MARK: - Settings toggle default state

    func testSettingsToggleDefault_reflectsEnabledByDefaultFlag() throws {
        try skipIfUnsupported()

        try clearYouTubeAdBlockingEnabledDefault()
        app = XCUIApplication.setUp(featureFlags: [
            "webExtensions": true,
            "adBlockingExtension": true,
            "adBlockingExtensionEnabledByDefault": true
        ])
        var toggle = openYouTubeAdBlockingPreferencePane(app)

        XCTAssertEqual(toggle.value as? Int, 1,
                       "Toggle should be on when adBlockingExtensionEnabledByDefault=true")

        app.terminate()
        try clearYouTubeAdBlockingEnabledDefault()
        app = XCUIApplication.setUp(featureFlags: [
            "webExtensions": true,
            "adBlockingExtension": true,
            "adBlockingExtensionEnabledByDefault": false
        ])
        toggle = openYouTubeAdBlockingPreferencePane(app)
        XCTAssertEqual(toggle.value as? Int, 0,
                       "Toggle should be off when adBlockingExtensionEnabledByDefault=false")
    }

    // MARK: - Address-bar YouTube ad block button

    private let youTubeAdBlockButtonIdentifier = "AddressBarButtonsViewController.youTubeAdBlockButton"

    func testYouTubeAdBlockButtonAndPillAppear_onYouTubeVideo_whenEnabled() throws {
        try skipFlakyTest()
        try skipIfUnsupported()
        try clearYouTubeAdBlockingEnabledDefault()
        app = XCUIApplication.setUp(featureFlags: [
            "webExtensions": true,
            "adBlockingExtension": true,
            "adBlockingExtensionEnabledByDefault": true
        ])
        app.enforceSingleWindow()
        app.navigateToYouTubeVideo("dQw4w9WgXcQ")
        let pill = app.descendants(matching: .any)["NavigationBar.youTubeAdBlockOnNotification"]
        XCTAssertTrue(pill.waitForExistence(timeout: UITests.Timeouts.navigation),
                      "Animated YouTube Ad Block On pill should appear after navigating to a YouTube video")
        XCTAssertTrue(pill.waitForNonExistence(timeout: UITests.Timeouts.fireAnimation),
                      "Animated YouTube Ad Block On pill should disappear after the animation completes")
        let youTubeAdBlockButton = app.buttons[youTubeAdBlockButtonIdentifier]
        XCTAssertTrue(youTubeAdBlockButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "YouTube ad block button should appear on a YouTube video URL when feature is enabled")
    }

    func testYouTubeAdBlockButtonShowsContingencyMessage_whenRemotelyDisabled() throws {
        try skipIfUnsupported()
        app = XCUIApplication.setUp(featureFlags: [
            "webExtensions": true,
            "adBlockingExtension": false
        ])
        app.enforceSingleWindow()
        app.navigateToYouTubeVideo("dQw4w9WgXcQ")
        let youTubeAdBlockButton = app.buttons[youTubeAdBlockButtonIdentifier]
        XCTAssertTrue(youTubeAdBlockButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "YouTube ad block button should still appear when remotely disabled")
        youTubeAdBlockButton.click()
        let contingencyMessage = app.descendants(matching: .any)["YouTubeAdBlockPopover.unavailableMessage"]
        XCTAssertTrue(contingencyMessage.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Popover should show the contingency message when feature is remotely disabled")
    }

    func testYouTubeAdBlockButtonAbsent_onNonYouTubeURL_whenEnabled() throws {
        try skipIfUnsupported()
        app = XCUIApplication.setUp(featureFlags: [
            "webExtensions": true,
            "adBlockingExtension": true
        ])
        app.enforceSingleWindow()
        XCTAssertTrue(app.addressBar.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        app.addressBar.typeURL(URL(string: "https://example.com")!)
        XCTAssertTrue(app.windows.webViews["Example Domain"].waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "example.com page did not load")
        XCTAssertFalse(app.buttons[youTubeAdBlockButtonIdentifier].exists,
                       "YouTube ad block button should not appear on non-YouTube URLs")
    }

    // MARK: - Popover items

    func testPopoverShowsExpectedItems_whenYouTubeAdBlockButtonTapped() throws {
        try skipFlakyTest()
        try skipIfUnsupported()
        try clearYouTubeAdBlockingEnabledDefault()
        app = XCUIApplication.setUp(featureFlags: [
            "webExtensions": true,
            "adBlockingExtension": true,
            "adBlockingExtensionEnabledByDefault": true
        ])
        app.enforceSingleWindow()
        app.navigateToYouTubeVideo("dQw4w9WgXcQ")
        let pill = app.descendants(matching: .any)["NavigationBar.youTubeAdBlockOnNotification"]
        XCTAssertTrue(pill.waitForExistence(timeout: UITests.Timeouts.navigation),
                      "Animated YouTube Ad Block On pill should appear after navigating to a YouTube video")
        XCTAssertTrue(pill.waitForNonExistence(timeout: UITests.Timeouts.fireAnimation),
                      "Animated YouTube Ad Block On pill should disappear after the animation completes")
        let youTubeAdBlockButton = app.buttons[youTubeAdBlockButtonIdentifier]
        XCTAssertTrue(youTubeAdBlockButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "YouTube ad block button did not appear")
        youTubeAdBlockButton.click()

        let popoverRowTitle = app.descendants(matching: .any)["YouTubeAdBlockPopover.rowTitle"]
        let popoverModePicker = app.descendants(matching: .any)["YouTubeAdBlockPopover.modePicker"]
        let popoverSendReportButton = app.descendants(matching: .any)["YouTubeAdBlockPopover.sendReportButton"]

        XCTAssertTrue(popoverRowTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Popover row title not found")
        XCTAssertTrue(popoverModePicker.exists, "Popover mode picker not found")
        XCTAssertFalse(popoverSendReportButton.exists,
                       "Popover Send Report button should not appear while ad blocking is enabled")

        popoverModePicker.click()
        app.menuItems["Always Off"].click()

        XCTAssertTrue(popoverSendReportButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Popover Send Report button should appear after disabling ad blocking")
    }

    // MARK: - Helpers

    private func openYouTubeAdBlockingPreferencePane(_ app: XCUIApplication) -> XCUIElement {
        app.openPreferencesWindow()
        let sidebarButton = app.buttons[sidebarButtonIdentifier]
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "YouTube Ad Blocking sidebar entry not found")
        sidebarButton.click()
        let toggle = app.checkBoxes["Preferences.YouTubeAdBlocking.enabledToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "YouTube ad blocking toggle not found in preference pane")
        return toggle
    }

    private func clearYouTubeAdBlockingEnabledDefault() throws {
        let bundleID = try XCTUnwrap(XCUIApplication().bundleID)
        UserDefaults(suiteName: bundleID)?.removeObject(forKey: "preferences_youtube-ad-blocking_enabled")
    }

    private func skipIfUnsupported() throws {
        guard #available(macOS 15.4, *) else {
            throw XCTSkip("YouTube ad blocking requires macOS 15.4+")
        }
    }

    // Temporarily disabled: these assertions depend on live YouTube navigation and the animated
    // ad-block "on" pill appearing within a timeout, which is flaky on CI. Re-enable once stabilised.
    private func skipFlakyTest() throws {
        throw XCTSkip("Flaky: relies on live YouTube navigation and ad-block pill animation timing, currently failing in CI")
    }
}
