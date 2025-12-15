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
        addressBarTextField.typeURLAfterExistenceTestSucceeds(permissionsSiteURL)

        let cameraButton = app.webViews.buttons["Camera"]
        cameraButton.clickAfterExistenceTestSucceeds()

        // Wait for and handle TCC system dialog
        XCTAssert(
            notificationCenter.buttons.firstMatch.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The notification center didn't appear. This can happen because the TCC setting at the start of the test wasn't correct – check the app.resetPermissions behavior."
        )
        let allowButtonIndex = try XCTUnwrap(notificationCenter.indexOfSystemModelDialogButtonOnElement(
            titled: "Allow",
            "OK"
        ))
        let allowButton = notificationCenter.buttons.element(boundBy: allowButtonIndex)
        allowButton.clickAfterExistenceTestSucceeds() // Click system camera permissions dialog

        // Handle the new SwiftUI permission authorization popover
        let permissionsPopoverAllowButton = app.popovers.buttons["PermissionAuthorizationSwiftUIView.allowButton"]
        permissionsPopoverAllowButton.clickAfterExistenceTestSucceeds()

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
