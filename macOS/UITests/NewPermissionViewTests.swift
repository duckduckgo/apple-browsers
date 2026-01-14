//
//  NewPermissionViewTests.swift
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

import AppKitExtensions
import XCTest

/// UI Tests for the new permission authorization view and permission center (behind the newPermissionView feature flag).
/// These tests verify the SwiftUI-based permission UI that replaces the legacy storyboard-based permission UI.
/// Note: Restricted to macOS 26+ due to differences in system permission dialogs across macOS versions.
class NewPermissionViewTests: UITestCase {

    private var notificationCenter: XCUIApplication!
    private var addressBarTextField: XCUIElement!
    private var permissionsSiteURL: URL!

    // Fire Dialog Element Accessors
    private var fireDialogTitle: XCUIElement { app.fireDialogTitle }
    private var fireDialogHistoryToggle: XCUIElement { app.fireDialogHistoryToggle }
    private var fireDialogCookiesToggle: XCUIElement { app.fireDialogCookiesToggle }
    private var fireDialogTabsToggle: XCUIElement { app.fireDialogTabsToggle }
    private var fireDialogBurnButton: XCUIElement { app.fireDialogBurnButton }

    override func setUpWithError() throws {
        // Skip tests on macOS versions below 26 due to differences in system permission dialogs
        if #unavailable(macOS 26) {
            throw XCTSkip("NewPermissionViewTests require macOS 26 or later due to system permission dialog differences")
        }

        try super.setUpWithError()
        continueAfterFailure = false

        permissionsSiteURL = try XCTUnwrap(URL(string: "https://permission.site"), "It wasn't possible to unwrap a URL that the tests depend on.")
        notificationCenter = XCUIApplication(bundleIdentifier: "com.apple.UserNotificationCenter")

        // Reset permissions BEFORE app launch - this is critical for TCC dialogs to appear
        app = XCUIApplication()
        app.resetAuthorizationStatus(for: .camera)
        app.resetAuthorizationStatus(for: .microphone)

        // Now set up and launch the app with the newPermissionView feature flag enabled
        app = XCUIApplication.setUp(featureFlags: ["newPermissionView": true])
        addressBarTextField = app.addressBar
        app.enforceSingleWindow()

        // Clear history using Fire Dialog
        XCTAssertTrue(
            app.historyMenu.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "History menu bar item didn't appear in a reasonable timeframe."
        )
        app.historyMenu.click()

        XCTAssertTrue(
            app.clearAllHistoryMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Clear all history item didn't appear in a reasonable timeframe."
        )
        app.clearAllHistoryMenuItem.click()

        // Fire Dialog should appear instead of old alert
        XCTAssertTrue(
            fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Fire dialog didn't appear in a reasonable timeframe."
        )

        // Select "Everything" scope to clear all history
        app.fireDialogSegmentedControl.buttons["Everything"].click()

        // Ensure toggles are enabled
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, ensureHittable: { _ in })
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: true, ensureHittable: { _ in })

        // Click burn button to clear history
        fireDialogBurnButton.click()

        // Wait for fire animation to complete
        XCTAssertTrue(
            app.fakeFireButton.waitForNonExistence(timeout: UITests.Timeouts.fireAnimation),
            "Fire animation didn't finish and cease existing in a reasonable timeframe."
        )

        XCTAssertTrue(
            addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The address bar text field didn't become available in a reasonable timeframe before starting the test."
        )
    }

    // MARK: - Camera Permission Tests

    func test_cameraPermissions_withAcceptedTCCChallenge_showCorrectStateInBrowser() throws {
        throw XCTSkip("Test disabled due to TCC permission dialog issues on CI")

        addressBarTextField.typeURLAfterExistenceTestSucceeds(permissionsSiteURL)

        let cameraButton = app.webViews.buttons["Camera"]
        cameraButton.clickAfterExistenceTestSucceeds()

        // TCC system dialog appears FIRST for camera/microphone
        XCTAssert(
            notificationCenter.buttons.firstMatch.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The notification center didn't appear. This can happen because the TCC setting at the start of the test wasn't correct – check the app.resetPermissions behavior."
        )
        let allowButtonIndex = try XCTUnwrap(notificationCenter.indexOfSystemModelDialogButtonOnElement(
            titled: "Allow",
            "OK"
        ))
        let allowButton = notificationCenter.buttons.element(boundBy: allowButtonIndex)
        allowButton.clickAfterExistenceTestSucceeds()

        // THEN browser's SwiftUI permission authorization popover appears
        let permissionsPopoverAllowButton = app.popovers.buttons["PermissionAuthorizationSwiftUIView.allowButton"]
        permissionsPopoverAllowButton.clickAfterExistenceTestSucceeds() // Click system camera permissions dialog

        // Wait for website button to turn green
        var websitePermissionsColorIsGreen = false
        for _ in 1 ... 4 { // permission.site updates this color a bit slowly and we have no control over it, so we try a few times.
            websitePermissionsColorIsGreen = try websitePermissionsButtonIsExpectedColor(cameraButton, is: .green)
            if websitePermissionsColorIsGreen {
                break
            }
            usleep(500_000)
        }
        XCTAssertTrue(
            websitePermissionsColorIsGreen,
            "After a few attempts to wait for permissions.site to update their button animation after the TCC dialog, their button has to be green."
        )

        // Click the permission center button (new UI)
        let permissionCenterButton = app.buttons["AddressBarButtonsViewController.permissionCenterButton"]
        permissionCenterButton.clickAfterExistenceTestSucceeds()

        // Verify the permission center popover appears with the camera permission
        // The permission center shows permission rows with dropdowns
        let permissionCenterPopover = app.popovers.firstMatch
        XCTAssertTrue(
            permissionCenterPopover.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Permission center popover didn't appear in a reasonable timeframe."
        )

        // Find the camera permission dropdown and verify "Always ask" is the current selection
        // The dropdown is an NSPopUpButton which appears as a PopUpButton in the accessibility hierarchy
        let cameraDecisionDropdown = permissionCenterPopover.popUpButtons.firstMatch
        XCTAssertTrue(
            cameraDecisionDropdown.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Camera permission dropdown didn't appear in the permission center."
        )

        // Verify the dropdown shows "Always ask" (the default for one-time allow)
        let dropdownValue = cameraDecisionDropdown.value as? String ?? ""
        XCTAssertEqual(
            dropdownValue,
            "Always ask",
            "The camera permission should be set to 'Always ask' after a one-time allow."
        )
    }

    func test_cameraPermissions_withDeniedTCCChallenge_showCorrectStateInBrowser() throws {
        throw XCTSkip("Test disabled due to TCC permission dialog issues on CI")

        addressBarTextField.typeURLAfterExistenceTestSucceeds(permissionsSiteURL)

        let cameraButton = app.webViews.buttons["Camera"]
        cameraButton.clickAfterExistenceTestSucceeds()

        // TCC system dialog appears FIRST for camera/microphone - deny this time
        XCTAssert(
            notificationCenter.buttons.firstMatch.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The notification center didn't appear. This can happen because the TCC setting at the start of the test wasn't correct – check the app.resetPermissions behavior."
        )
        // Use the more robust deny button finder that looks for the button that's NOT an allow button
        let denyButtonIndex = try XCTUnwrap(
            notificationCenter.indexOfDenyButtonOnSystemDialog(),
            "Could not find deny button in TCC dialog. Available buttons: \(notificationCenter.buttons.allElementsBoundByIndex.map { $0.title })"
        )
        let denyButton = notificationCenter.buttons.element(boundBy: denyButtonIndex)
        denyButton.clickAfterExistenceTestSucceeds() // Click system camera permissions dialog to deny

        // Browser's permission popover should not appear when TCC is denied
        let permissionsPopoverAllowButton = app.popovers.buttons["PermissionAuthorizationSwiftUIView.allowButton"]
        XCTAssertTrue(
            permissionsPopoverAllowButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "The permissions popover in the browser should not appear when camera permission has been denied at system level."
        )

        // Wait for website button to turn red
        var websitePermissionsColorIsRed = false
        for _ in 1 ... 4 {
            websitePermissionsColorIsRed = try websitePermissionsButtonIsExpectedColor(cameraButton, is: .red)
            if websitePermissionsColorIsRed {
                break
            }
            usleep(500_000)
        }
        XCTAssertTrue(
            websitePermissionsColorIsRed,
            "After a few attempts to wait for permissions.site to update their button animation after the TCC dialog, their button has to be red."
        )

        // The permission center button should not appear when system permission is denied
        let permissionCenterButton = app.buttons["AddressBarButtonsViewController.permissionCenterButton"]
        XCTAssertTrue(
            permissionCenterButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "The permission center button should not appear when camera permission has been denied at system level."
        )
    }

    func test_cameraPermissions_withAcceptedTCCChallenge_whereNeverAllowIsSelected_alwaysDenies() throws {
        throw XCTSkip("Test disabled due to TCC permission dialog issues on CI")

        addressBarTextField.typeURLAfterExistenceTestSucceeds(permissionsSiteURL)

        let cameraButton = app.webViews.buttons["Camera"]
        cameraButton.clickAfterExistenceTestSucceeds()

        // TCC system dialog appears FIRST for camera/microphone
        XCTAssert(
            notificationCenter.buttons.firstMatch.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The notification center didn't appear. This can happen because the TCC setting at the start of the test wasn't correct – check the app.resetPermissions behavior."
        )
        let allowButtonIndex = try XCTUnwrap(notificationCenter.indexOfSystemModelDialogButtonOnElement(
            titled: "Allow",
            "OK"
        ))
        let allowButton = notificationCenter.buttons.element(boundBy: allowButtonIndex)
        allowButton.clickAfterExistenceTestSucceeds()

        // THEN browser's SwiftUI permission authorization popover appears
        let permissionsPopoverAllowButton = app.popovers.buttons["PermissionAuthorizationSwiftUIView.allowButton"]
        permissionsPopoverAllowButton.clickAfterExistenceTestSucceeds()

        // Wait for website button to turn green
        var websitePermissionsColorIsGreen = false
        for _ in 1 ... 4 {
            websitePermissionsColorIsGreen = try websitePermissionsButtonIsExpectedColor(cameraButton, is: .green)
            if websitePermissionsColorIsGreen {
                break
            }
            usleep(500_000)
        }
        XCTAssertTrue(
            websitePermissionsColorIsGreen,
            "After a few attempts to wait for permissions.site to update their button animation after the TCC dialog, their button has to be green."
        )

        // Click the permission center button and change to "Never allow"
        let permissionCenterButton = app.buttons["AddressBarButtonsViewController.permissionCenterButton"]
        permissionCenterButton.clickAfterExistenceTestSucceeds()

        let permissionCenterPopover = app.popovers.firstMatch
        XCTAssertTrue(
            permissionCenterPopover.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Permission center popover didn't appear in a reasonable timeframe."
        )

        // Find and click the dropdown to change to "Never allow"
        let cameraDecisionDropdown = permissionCenterPopover.popUpButtons.firstMatch
        XCTAssertTrue(
            cameraDecisionDropdown.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Camera permission dropdown didn't appear in the permission center."
        )
        cameraDecisionDropdown.click()

        // Select "Never allow" from the dropdown menu
        let neverAllowMenuItem = app.menuItems["Never allow"]
        neverAllowMenuItem.clickAfterExistenceTestSucceeds()

        // Close the popover by clicking elsewhere or pressing Escape
        app.typeKey(.escape, modifierFlags: [])

        // Navigate to the site again and try to use camera
        app.enforceSingleWindow()
        addressBarTextField.typeURL(permissionsSiteURL)

        // Try clicking camera button multiple times - should stay red
        for _ in 1 ... 4 {
            cameraButton.clickAfterExistenceTestSucceeds()
        }

        XCTAssertTrue(
            try websitePermissionsButtonIsExpectedColor(cameraButton, is: .red),
            "Even if we click the button for the denied resource many times, when we have set 'Never allow' for the resource, the permission button will remain red"
        )

        // TCC dialog should not appear
        XCTAssert(
            notificationCenter.buttons.firstMatch.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "Even if we click the button for the denied resource many times, when we have set 'Never allow' for the resource, the TCC dialog permission alert will not be on the screen"
        )

        // Permission popover should not appear
        XCTAssert(
            permissionsPopoverAllowButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "Even if we click the button for the denied resource many times, when we have set 'Never allow' for the resource, the permission popover will not be on the screen"
        )
    }

    // MARK: - Microphone Permission Tests

    func test_microphonePermissions_withAcceptedTCCChallenge_showCorrectStateInBrowser() throws {
        throw XCTSkip("Test disabled due to TCC permission dialog issues on CI")

        addressBarTextField.typeURLAfterExistenceTestSucceeds(permissionsSiteURL)

        let microphoneButton = app.webViews.buttons["Microphone"]
        microphoneButton.clickAfterExistenceTestSucceeds()

        // TCC system dialog appears FIRST for camera/microphone
        XCTAssert(
            notificationCenter.buttons.firstMatch.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The notification center didn't appear. This can happen because the TCC setting at the start of the test wasn't correct – check the app.resetPermissions behavior."
        )
        let allowButtonIndex = try XCTUnwrap(notificationCenter.indexOfSystemModelDialogButtonOnElement(
            titled: "Allow",
            "OK"
        ))
        let allowButton = notificationCenter.buttons.element(boundBy: allowButtonIndex)
        allowButton.clickAfterExistenceTestSucceeds()

        // THEN browser's SwiftUI permission authorization popover appears
        let permissionsPopoverAllowButton = app.popovers.buttons["PermissionAuthorizationSwiftUIView.allowButton"]
        permissionsPopoverAllowButton.clickAfterExistenceTestSucceeds()

        // Wait for website button to turn green
        var websitePermissionsColorIsGreen = false
        for _ in 1 ... 4 {
            websitePermissionsColorIsGreen = try websitePermissionsButtonIsExpectedColor(microphoneButton, is: .green)
            if websitePermissionsColorIsGreen {
                break
            }
            usleep(500_000)
        }
        XCTAssertTrue(
            websitePermissionsColorIsGreen,
            "After a few attempts to wait for permissions.site to update their button animation after the TCC dialog, their button has to be green."
        )

        // Click the permission center button
        let permissionCenterButton = app.buttons["AddressBarButtonsViewController.permissionCenterButton"]
        permissionCenterButton.clickAfterExistenceTestSucceeds()

        // Verify the permission center popover appears
        let permissionCenterPopover = app.popovers.firstMatch
        XCTAssertTrue(
            permissionCenterPopover.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Permission center popover didn't appear in a reasonable timeframe."
        )

        // Find the microphone permission dropdown and verify "Always ask" is the current selection
        let microphoneDecisionDropdown = permissionCenterPopover.popUpButtons.firstMatch
        XCTAssertTrue(
            microphoneDecisionDropdown.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Microphone permission dropdown didn't appear in the permission center."
        )

        let dropdownValue = microphoneDecisionDropdown.value as? String ?? ""
        XCTAssertEqual(
            dropdownValue,
            "Always ask",
            "The microphone permission should be set to 'Always ask' after a one-time allow."
        )
    }

    func test_microphonePermissions_withDeniedTCCChallenge_showCorrectStateInBrowser() throws {
        throw XCTSkip("Test disabled due to TCC permission dialog issues on CI")

        addressBarTextField.typeURLAfterExistenceTestSucceeds(permissionsSiteURL)

        let microphoneButton = app.webViews.buttons["Microphone"]
        microphoneButton.clickAfterExistenceTestSucceeds()

        // TCC system dialog appears FIRST for camera/microphone - deny this time
        XCTAssert(
            notificationCenter.buttons.firstMatch.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The notification center didn't appear. This can happen because the TCC setting at the start of the test wasn't correct – check the app.resetPermissions behavior."
        )
        // Use the more robust deny button finder that looks for the button that's NOT an allow button
        let denyButtonIndex = try XCTUnwrap(
            notificationCenter.indexOfDenyButtonOnSystemDialog(),
            "Could not find deny button in TCC dialog. Available buttons: \(notificationCenter.buttons.allElementsBoundByIndex.map { $0.title })"
        )
        let denyButton = notificationCenter.buttons.element(boundBy: denyButtonIndex)
        denyButton.clickAfterExistenceTestSucceeds()

        // Browser's permission popover should not appear when TCC is denied
        let permissionsPopoverAllowButton = app.popovers.buttons["PermissionAuthorizationSwiftUIView.allowButton"]
        XCTAssertTrue(
            permissionsPopoverAllowButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "The permissions popover in the browser should not appear when microphone permission has been denied at system level."
        )

        // Wait for website button to turn red
        var websitePermissionsColorIsRed = false
        for _ in 1 ... 4 {
            websitePermissionsColorIsRed = try websitePermissionsButtonIsExpectedColor(microphoneButton, is: .red)
            if websitePermissionsColorIsRed {
                break
            }
            usleep(500_000)
        }
        XCTAssertTrue(
            websitePermissionsColorIsRed,
            "After between one and four attempts to wait for permissions.site to update their button animation after the TCC dialog, their button has to be red."
        )

        // The permission center button should not appear when system permission is denied
        let permissionCenterButton = app.buttons["AddressBarButtonsViewController.permissionCenterButton"]
        XCTAssertTrue(
            permissionCenterButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "The permission center button should not appear when microphone permission has been denied at system level."
        )
    }

    func test_microphonePermissions_withAcceptedTCCChallenge_whereNeverAllowIsSelected_alwaysDenies() throws {
        throw XCTSkip("Test disabled due to TCC permission dialog issues on CI")

        addressBarTextField.typeURLAfterExistenceTestSucceeds(permissionsSiteURL)

        let microphoneButton = app.webViews.buttons["Microphone"]
        microphoneButton.clickAfterExistenceTestSucceeds()

        // TCC system dialog appears FIRST for camera/microphone
        XCTAssert(
            notificationCenter.buttons.firstMatch.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The notification center didn't appear. This can happen because the TCC setting at the start of the test wasn't correct – check the app.resetPermissions behavior."
        )
        let allowButtonIndex = try XCTUnwrap(notificationCenter.indexOfSystemModelDialogButtonOnElement(
            titled: "Allow",
            "OK"
        ))
        let allowButton = notificationCenter.buttons.element(boundBy: allowButtonIndex)
        allowButton.clickAfterExistenceTestSucceeds()

        // THEN browser's SwiftUI permission authorization popover appears
        let permissionsPopoverAllowButton = app.popovers.buttons["PermissionAuthorizationSwiftUIView.allowButton"]
        permissionsPopoverAllowButton.clickAfterExistenceTestSucceeds()

        // Wait for website button to turn green
        var websitePermissionsColorIsGreen = false
        for _ in 1 ... 4 {
            websitePermissionsColorIsGreen = try websitePermissionsButtonIsExpectedColor(microphoneButton, is: .green)
            if websitePermissionsColorIsGreen {
                break
            }
            usleep(500_000)
        }
        XCTAssertTrue(
            websitePermissionsColorIsGreen,
            "After a few attempts to wait for permissions.site to update their button animation after the TCC dialog, their button has to be green."
        )

        // Click the permission center button and change to "Never allow"
        let permissionCenterButton = app.buttons["AddressBarButtonsViewController.permissionCenterButton"]
        permissionCenterButton.clickAfterExistenceTestSucceeds()

        let permissionCenterPopover = app.popovers.firstMatch
        XCTAssertTrue(
            permissionCenterPopover.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Permission center popover didn't appear in a reasonable timeframe."
        )

        // Find and click the dropdown to change to "Never allow"
        let microphoneDecisionDropdown = permissionCenterPopover.popUpButtons.firstMatch
        XCTAssertTrue(
            microphoneDecisionDropdown.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Microphone permission dropdown didn't appear in the permission center."
        )
        microphoneDecisionDropdown.click()

        // Select "Never allow" from the dropdown menu
        let neverAllowMenuItem = app.menuItems["Never allow"]
        neverAllowMenuItem.clickAfterExistenceTestSucceeds()

        // Close the popover
        app.typeKey(.escape, modifierFlags: [])

        // Navigate to the site again and try to use microphone
        app.enforceSingleWindow()
        addressBarTextField.typeURL(permissionsSiteURL)

        // Try clicking microphone button multiple times - should stay red
        for _ in 1 ... 4 {
            microphoneButton.clickAfterExistenceTestSucceeds()
        }

        XCTAssertTrue(
            try websitePermissionsButtonIsExpectedColor(microphoneButton, is: .red),
            "Even if we click the button for the denied resource many times, when we have set 'Never allow' for the resource, the permission button will remain red"
        )

        // TCC dialog should not appear
        XCTAssert(
            notificationCenter.buttons.firstMatch.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "Even if we click the button for the denied resource many times, when we have set 'Never allow' for the resource, the TCC dialog permission alert will not be on the screen"
        )

        // Permission popover should not appear
        XCTAssert(
            permissionsPopoverAllowButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "Even if we click the button for the denied resource many times, when we have set 'Never allow' for the resource, the permission popover will not be on the screen"
        )
    }

    // MARK: - Location Permission Tests

    func test_locationPermissions_whenAccepted_showCorrectStateInBrowser() throws {
        addressBarTextField.typeURLAfterExistenceTestSucceeds(permissionsSiteURL)

        let locationButton = app.webViews.buttons["Location"]
        locationButton.clickAfterExistenceTestSucceeds()

        // Location uses the new two-step authorization flow in the SwiftUI view
        // Handle the permission authorization popover
        let permissionsPopoverAllowButton = app.popovers.buttons["PermissionAuthorizationSwiftUIView.allowButton"]
        permissionsPopoverAllowButton.clickAfterExistenceTestSucceeds()

        // Wait for website button to turn green (location button often doesn't turn green reliably on permission.site)
        var websitePermissionsColorIsGreen = false
        for _ in 1 ... 4 {
            websitePermissionsColorIsGreen = try websitePermissionsButtonIsExpectedColor(locationButton, is: .green)
            if websitePermissionsColorIsGreen {
                break
            }
            usleep(500_000)
        }
        // We would like to be able to test here that the permission.site "Location" button turns green here, but it frequently doesn't turn green
        // when location permissions are granted.

        // Click the permission center button
        let permissionCenterButton = app.buttons["AddressBarButtonsViewController.permissionCenterButton"]
        permissionCenterButton.clickAfterExistenceTestSucceeds()

        // Verify the permission center popover appears
        let permissionCenterPopover = app.popovers.firstMatch
        XCTAssertTrue(
            permissionCenterPopover.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Permission center popover didn't appear in a reasonable timeframe."
        )

        // Find the location permission dropdown and verify "Always ask" is the current selection
        let locationDecisionDropdown = permissionCenterPopover.popUpButtons.firstMatch
        XCTAssertTrue(
            locationDecisionDropdown.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Location permission dropdown didn't appear in the permission center."
        )

        let dropdownValue = locationDecisionDropdown.value as? String ?? ""
        XCTAssertEqual(
            dropdownValue,
            "Always ask",
            "The location permission should be set to 'Always ask' after a one-time allow."
        )
    }

    func test_locationPermissions_whenNeverAllowIsSelected_alwaysDenies() throws {
        addressBarTextField.typeURLAfterExistenceTestSucceeds(permissionsSiteURL)

        let locationButton = app.webViews.buttons["Location"]
        locationButton.clickAfterExistenceTestSucceeds()

        // Handle the permission authorization popover
        let permissionsPopoverAllowButton = app.popovers.buttons["PermissionAuthorizationSwiftUIView.allowButton"]
        permissionsPopoverAllowButton.clickAfterExistenceTestSucceeds()

        // Wait for website button to turn green
        var websitePermissionsColorIsGreen = false
        for _ in 1 ... 4 {
            websitePermissionsColorIsGreen = try websitePermissionsButtonIsExpectedColor(locationButton, is: .green)
            if websitePermissionsColorIsGreen {
                break
            }
            usleep(500_000)
        }
        // We would like to be able to test here that the permission.site "Location" button turns green here, but it frequently doesn't turn green
        // when location permissions are granted.

        // Click the permission center button and change to "Never allow"
        let permissionCenterButton = app.buttons["AddressBarButtonsViewController.permissionCenterButton"]
        permissionCenterButton.clickAfterExistenceTestSucceeds()

        let permissionCenterPopover = app.popovers.firstMatch
        XCTAssertTrue(
            permissionCenterPopover.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Permission center popover didn't appear in a reasonable timeframe."
        )

        // Find and click the dropdown to change to "Never allow"
        let locationDecisionDropdown = permissionCenterPopover.popUpButtons.firstMatch
        XCTAssertTrue(
            locationDecisionDropdown.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Location permission dropdown didn't appear in the permission center."
        )
        locationDecisionDropdown.click()

        // Select "Never allow" from the dropdown menu
        let neverAllowMenuItem = app.menuItems["Never allow"]
        neverAllowMenuItem.clickAfterExistenceTestSucceeds()

        // Close the popover
        app.typeKey(.escape, modifierFlags: [])

        // Navigate to the site again and try to use location
        app.enforceSingleWindow()
        addressBarTextField.typeURL(permissionsSiteURL)

        // Try clicking location button multiple times - should stay red
        for _ in 1 ... 4 {
            locationButton.clickAfterExistenceTestSucceeds()
        }

        XCTAssertTrue( // Location does turn red when permission is denied
            try websitePermissionsButtonIsExpectedColor(locationButton, is: .red),
            "Even if we click the button for the denied resource many times, when we have set 'Never allow' for the resource, the permission button will remain red"
        )

        // Permission popover should not appear
        XCTAssert(
            permissionsPopoverAllowButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "Even if we click the button for the denied resource many times, when we have set 'Never allow' for the resource, the permission popover will not be on the screen"
        )
    }

    // MARK: - External Scheme Permission Tests

    func test_externalSchemePermissions_whenDenied_doesNotOpenExternalApp() throws {
        // Navigate to the w3schools mailto test page
        let mailtoTestURL = URL(string: "https://www.w3schools.com/tags/tryit.asp?filename=tryhtml_link_mailto")!
        addressBarTextField.typeURLAfterExistenceTestSucceeds(mailtoTestURL)

        // Wait for the page to load - the "Send email" link is inside an iframe
        // The iframe has id "iframeResult" and the link is inside it
        let webView = app.webViews.firstMatch
        XCTAssertTrue(
            webView.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Web view didn't appear in a reasonable timeframe."
        )

        // Give the page time to fully load including the iframe
        sleep(3)

        // Find and click the "Send email" link - it's in the iframe result area
        // The link text is "Send email"
        let sendEmailLink = webView.links["Send email"]
        if sendEmailLink.waitForExistence(timeout: UITests.Timeouts.elementExistence) {
            sendEmailLink.click()
        } else {
            // Try finding it as a static text or other element type
            let sendEmailText = webView.staticTexts["Send email"]
            if sendEmailText.waitForExistence(timeout: UITests.Timeouts.elementExistence) {
                sendEmailText.click()
            } else {
                XCTFail("Could not find 'Send email' link on the page")
                return
            }
        }

        // The browser's permission authorization popover should appear for external scheme (mailto:)
        let permissionsPopoverDenyButton = app.popovers.buttons["PermissionAuthorizationSwiftUIView.denyButton"]
        XCTAssertTrue(
            permissionsPopoverDenyButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The external scheme permission popover didn't appear after clicking mailto link."
        )

        // Click Deny to prevent opening the Mail app
        permissionsPopoverDenyButton.click()

        // Verify the popover is dismissed
        XCTAssertTrue(
            permissionsPopoverDenyButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "The permission popover should be dismissed after clicking Deny."
        )

        // The permission center button should appear (since we interacted with a permission)
        let permissionCenterButton = app.buttons["AddressBarButtonsViewController.permissionCenterButton"]
        XCTAssertTrue(
            permissionCenterButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The permission center button should appear after denying external scheme permission."
        )

        // Open permission center and verify the external scheme permission is shown
        permissionCenterButton.click()

        let permissionCenterPopover = app.popovers.firstMatch
        XCTAssertTrue(
            permissionCenterPopover.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Permission center popover didn't appear in a reasonable timeframe."
        )

        // Verify the external apps permission dropdown exists and shows "Always ask"
        let externalAppsDropdown = permissionCenterPopover.popUpButtons.firstMatch
        XCTAssertTrue(
            externalAppsDropdown.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "External apps permission dropdown didn't appear in the permission center."
        )

        let dropdownValue = externalAppsDropdown.value as? String ?? ""
        XCTAssertEqual(
            dropdownValue,
            "Always ask",
            "The external apps permission should be set to 'Always ask' after denying once."
        )
    }

}

// MARK: - Popup Permission Tests with New Permission View

/// Tests for popup blocking with the new permission view enabled.
/// These tests require additional popup-related feature flags.
final class NewPermissionViewPopupTests: UITestCase {

    private enum PopupTimeout {
        static let testingThreshold: TimeInterval = 2.0
    }

    private var addressBarTextField: XCUIElement!
    private var popupDelayedURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        // Enable newPermissionView AND popup blocking features with reduced timeout
        app = XCUIApplication.setUp(
            environment: [
                "POPUP_TIMEOUT_OVERRIDE": String(PopupTimeout.testingThreshold)
            ],
            featureFlags: [
                "newPermissionView": true,
                "popupBlocking": true,
                "extendedUserInitiatedPopupTimeout": true,
                "suppressEmptyPopUpsOnApproval": true,
                "allowPopupsForCurrentPage": true,
                "popupPermissionButtonPersistence": true
            ]
        )

        popupDelayedURL = URL.testsServer.appendingPathComponent("popup-delayed.html")
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

    /// Tests that the new popup blocked SwiftUI popover appears automatically when a popup is blocked
    func test_popupPermissions_blockedPopupShowsSwiftUIPopover() throws {
        addressBarTextField.pasteURL(popupDelayedURL, pressingEnter: true)

        let webView = app.webViews["Popup Delayed Test"]
        XCTAssertTrue(
            webView.waitForExistence(timeout: UITests.Timeouts.localTestServer),
            "Web view didn't appear in a reasonable timeframe."
        )

        // Click button that triggers a popup beyond the timeout (will be blocked)
        let beyondTimeoutButton = webView.links["Open Popup (Beyond Timeout)"]
        XCTAssertTrue(
            beyondTimeoutButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Beyond timeout button didn't appear."
        )
        beyondTimeoutButton.click()

        // The popup blocked popover should appear AUTOMATICALLY with the SwiftUI view
        let popover = app.popovers.firstMatch
        XCTAssertTrue(
            popover.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Popup blocked popover should appear automatically when popup is blocked."
        )

        // Verify the popover contains the "Pop-Up Blocked" text
        let blockedText = popover.staticTexts.containing(\.value, containing: "Pop-Up Blocked").firstMatch
        XCTAssertTrue(
            blockedText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Pop-Up Blocked text should appear in the popover."
        )

        // Verify the "Open" button exists in the SwiftUI popover
        let openButton = popover.buttons["Open"]
        XCTAssertTrue(
            openButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Open button should appear in the popup blocked popover."
        )
    }

    /// Tests that clicking "Open" in the popup blocked popover opens the blocked popup
    func test_popupPermissions_openButtonOpensBlockedPopup() throws {
        addressBarTextField.pasteURL(popupDelayedURL, pressingEnter: true)

        let webView = app.webViews["Popup Delayed Test"]
        XCTAssertTrue(
            webView.waitForExistence(timeout: UITests.Timeouts.localTestServer),
            "Web view didn't appear in a reasonable timeframe."
        )

        // Click button that triggers a popup beyond the timeout (will be blocked)
        let beyondTimeoutButton = webView.links["Open Popup (Beyond Timeout)"]
        XCTAssertTrue(
            beyondTimeoutButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Beyond timeout button didn't appear."
        )
        beyondTimeoutButton.click()

        // The popup blocked popover should appear AUTOMATICALLY
        let popover = app.popovers.firstMatch
        XCTAssertTrue(
            popover.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Popup blocked popover should appear automatically when popup is blocked."
        )

        // Click the "Open" button to open the blocked popup
        let openButton = popover.buttons["Open"]
        XCTAssertTrue(
            openButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Open button should appear in the popup blocked popover."
        )
        openButton.click()

        // Verify popup window opened
        let popupWindow = app.windows["Example Domain"]
        XCTAssertTrue(
            popupWindow.waitForExistence(timeout: UITests.Timeouts.navigation),
            "Popup should open after clicking 'Open' button."
        )

        // Verify we now have 2 windows (main + popup)
        XCTAssertEqual(
            app.windows.count, 2,
            "Should have main window + opened popup window."
        )
    }
}

// MARK: - Private Helpers

private extension NewPermissionViewTests {
    func websitePermissionsButtonIsExpectedColor(_ button: XCUIElement, is expectedColor: PredominantColor) throws -> Bool {
        let buttonScreenshot = button.screenshot().image
        let trimmedButton = buttonScreenshot.trim(to: CGRect(
            x: 10,
            y: 10,
            width: 20,
            height: 20
        )) // A sample of the button that we are going to analyze for its predominant color tone.
        let predominantColor = try XCTUnwrap(
            trimmedButton.ciImage(with: nil).predominantColor(),
            "It wasn't possible to unwrap the predominant color of the website button screenshot sample"
        )
        return predominantColor == expectedColor
    }
}

private extension XCUIElement {
    /// We don't have as much control over what is going to appear on a modal dialogue, and it feels fragile to use Apple's accessibility IDs since I
    /// don't think there is any contract for that, but we can plan some flexibility in title matching for the button names, since the button names
    /// are in the test description.
    /// - Parameter titled: The title or titles (if they vary across macOS versions) of a button whose index on the element we'd like to know,
    /// variadic
    /// - Returns: An optional Int representing the button index on the element, if a button with this title was found.
    func indexOfSystemModelDialogButtonOnElement(titled: String...) -> Int? {
        for buttonIndex in 0 ... 4 { // It feels unlikely that a system modal dialog will have more than five buttons
            let button = self.buttons.element(boundBy: buttonIndex)
            if button.exists, titled.contains(button.title) {
                return buttonIndex
            }
        }
        return nil
    }

    /// Finds the deny/cancel button in a system dialog by looking for common deny button patterns.
    /// This is more robust than matching exact deny button titles which can vary across macOS versions and locales.
    /// - Returns: An optional Int representing the button index of the deny button, if found.
    func indexOfDenyButtonOnSystemDialog() -> Int? {
        // First, try to find a button with a deny-like title
        let denyTitles = ["Don't Allow", "Deny", "Cancel", "No", "Not Now", "Later"]

        for buttonIndex in 0 ... 4 {
            let button = self.buttons.element(boundBy: buttonIndex)
            if button.exists {
                let title = button.title
                // Check if this is a deny button by title
                for denyTitle in denyTitles where title.localizedCaseInsensitiveCompare(denyTitle) == .orderedSame {
                    return buttonIndex
                }
                // Also check if title contains "Don" and "Allow" (handles various apostrophe encodings)
                if title.lowercased().contains("don") && title.lowercased().contains("allow") {
                    return buttonIndex
                }
            }
        }

        // Fallback: find a button that's not Allow/OK and not a single character (like "?")
        let allowTitles = ["Allow", "OK", "Allow Once", "Allow While Using App"]
        for buttonIndex in 0 ... 4 {
            let button = self.buttons.element(boundBy: buttonIndex)
            if button.exists {
                let title = button.title
                let isAllowButton = allowTitles.contains { title.localizedCaseInsensitiveContains($0) }
                let isHelpButton = title.count <= 1 // Skip single-char buttons like "?"
                if !isAllowButton && !isHelpButton {
                    return buttonIndex
                }
            }
        }
        return nil
    }
}

/// Understand whether a webpage button is greenish or reddish when we expect one or the other, or states where we need to retry or fail
private enum PredominantColor {
    case red
    case green
    case neither
}

private extension NSImage {
    /// Trim NSImage to sample
    /// - Parameter rect: the sample size to trim to
    /// - Returns: The trimmed NSImage
    func trim(to rect: CGRect) -> NSImage {
        let result = NSImage(size: rect.size)
        result.lockFocus()

        let destRect = CGRect(origin: .zero, size: result.size)
        self.draw(in: destRect, from: rect, operation: .copy, fraction: 1.0)

        result.unlockFocus()
        return result
    }
}

private extension CIImage {
    /// Evaluate a sample of a webpage button to see what its predominant color tone is. Assumes it is being run on a button that is expected to be
    /// either green or red (otherwise we are starting to think into `https://permission.site`'s potential implementation errors or surprise cases,
    /// which I don't think should be part of this test case scope which tests UIs from three responsible organizations in which the tested UIs, in
    /// order of importance, should be: this browser, macOS, permission.site)).
    /// - Returns: .red, .green, .neither if we get a result but it isn't helpful, or nil in the event of an error (but it will always verbosely fail
    /// the test before returning nil, so in practice, if the test is still in progress, it has returned a case.)
    func predominantColor() throws -> PredominantColor? {
        var redValueOfSample = 0.0
        var greenValueOfSample = 0.0

        for channel in 0 ... 1 { // We are only checking the first two channels
            let extentVector = CIVector(
                x: self.extent.origin.x,
                y: self.extent.origin.y,
                z: self.extent.size.width,
                w: self.extent.size.height
            )

            guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: self, kCIInputExtentKey: extentVector])
            else { XCTFail("It wasn't possible to set the CIFilter for the predominant color channel check")
                return nil
            }
            guard let outputImage = filter.outputImage
            else { XCTFail("It wasn't possible to set the output image for the predominant color channel check")
                return nil
            }

            var outputBitmap = [UInt8](repeating: 0, count: 4)
            let nullSingletonInstance = try XCTUnwrap(kCFNull, "Could not unwrap singleton null instance")
            let outputRenderContext = CIContext(options: [.workingColorSpace: nullSingletonInstance])
            outputRenderContext.render(
                outputImage,
                toBitmap: &outputBitmap,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: nil
            )
            if channel == 0 {
                redValueOfSample = Double(outputBitmap[channel]) / Double(255)
            } else if channel == 1 {
                greenValueOfSample = Double(outputBitmap[channel]) / Double(255)
            }
        }

        let tooSimilar = abs(redValueOfSample - greenValueOfSample) < 0.05 // This isn't a huge difference because these are both very light colors
        if tooSimilar {
            print(
                "It wasn't possible to get a predominant color of the button because the two channel values of red (\(redValueOfSample)) and green (\(greenValueOfSample)) were \(redValueOfSample == greenValueOfSample ? "the same." : "too close in value.")"
            )
            return .neither
        }

        return max(redValueOfSample, greenValueOfSample) == redValueOfSample ? .red : .green
    }
}
