//
//  OnboardingUITests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

final class OnboardingUITests: UITestCase {

    private var welcomeWindow: XCUIElement!

    override func setUpWithError() throws {
        try super.setUpWithError()

        continueAfterFailure = false
        try resetApplicationData()

        launchOnboarding()
    }

    /// Launches the app into the onboarding flow.
    private func launchOnboarding() {
        app = XCUIApplication.setUp(
            environment: [
                "UITEST_MODE_ONBOARDING": "1"
            ]
        )
        app.enforceSingleWindow()
        welcomeWindow = app.windows["Welcome"]
    }

    override func tearDownWithError() throws {
        try resetApplicationData()
        try super.tearDownWithError()
    }

    func testOnboardingToBrowsing() throws {
        // Options button initially disabled on welcome
        let optionsButton = welcomeWindow.buttons["NavigationBarViewController.optionsButton"]
        XCTAssertTrue(optionsButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(optionsButton.isEnabled)

        // Get Started
        XCTAssertTrue(welcomeWindow.webViews["Welcome"].staticTexts["Hi there."].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // The onboarding buttons have no aria-label/identifier, so WebKit exposes their text via `title` rather than `label`.
        let getStartedButton = welcomeWindow.webViews["Welcome"].buttons
            .matching(NSPredicate(format: "title ==[c] %@", "Let’s get started!"))
            .firstMatch
        XCTAssertTrue(getStartedButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Use coordinate tap to avoid overlay/hittability quirks
        let centerCoordinate = getStartedButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        centerCoordinate.click()

        // Protections activated
        XCTAssertTrue(welcomeWindow.webViews["Welcome"].staticTexts["Protections activated!"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Skip making DuckDuckGo the default browser
        let skipButton = welcomeWindow.webViews["Welcome"].buttons
            .matching(NSPredicate(format: "title ==[c] %@", "Skip"))
            .firstMatch
        XCTAssertTrue(skipButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        skipButton.click()

        // Let’s get you set up
        XCTAssertTrue(welcomeWindow.webViews["Welcome"].staticTexts["Let’s get you set up!"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Skip the dock and import rows
        XCTAssertTrue(skipButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        skipButton.click()

        XCTAssertTrue(skipButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        skipButton.click()

        let nextButtonSetUp = welcomeWindow.webViews["Welcome"].buttons
            .matching(NSPredicate(format: "title ==[c] %@", "Next"))
            .firstMatch
        XCTAssertTrue(nextButtonSetUp.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        nextButtonSetUp.click()

        // Customize Experience
        XCTAssertTrue(welcomeWindow.webViews["Welcome"].staticTexts["Let’s customize a few things…"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Skip the bookmarks, session restore, and home shortcut rows
        XCTAssertTrue(skipButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        skipButton.click()

        XCTAssertTrue(skipButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        skipButton.click()

        XCTAssertTrue(skipButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        skipButton.click()

        let nextButtonCustomize = welcomeWindow.webViews["Welcome"].buttons
            .matching(NSPredicate(format: "title ==[c] %@", "Next"))
            .firstMatch
        XCTAssertTrue(nextButtonCustomize.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        nextButtonCustomize.click()

        // AI Chat
        XCTAssertTrue(welcomeWindow.webViews["Welcome"].staticTexts["Want easy access to private AI Chat?"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Start Browsing
        let startBrowsingButton = welcomeWindow.webViews["Welcome"].buttons
            .matching(NSPredicate(format: "title ==[c] %@", "Start Browsing"))
            .firstMatch
        XCTAssertTrue(startBrowsingButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        startBrowsingButton.click()

        // AfterOnboarding
        let ddgLogo = app.windows.webViews.groups.containing(.image, identifier: "DuckDuckGo Logo").element
        let tooltip = app.windows.webViews.groups.containing(.staticText, identifier: "Toggle between search and AI chat").element
        XCTAssertTrue(ddgLogo.waitForExistence(timeout: UITests.Timeouts.elementExistence) || tooltip.waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    func testDuckAIIsUnavailableDuringOnboarding() throws {
        let button = app.windows.buttons[XCUIApplication.AccessibilityIdentifiers.aiChatButton]

        XCTAssertFalse(button.exists, "AIChat Button should NOT be visible during onboarding")
    }

    func testPassiveAddressBarShowsWelcomeMessage() throws {
        let passiveTextField = app.staticTexts[XCUIApplication.AccessibilityIdentifiers.addressBarPassiveTextField]

        XCTAssertTrue(passiveTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence), "(Passive) AddressBar TextField should be visible")
        XCTAssertEqual(passiveTextField.value as? String, "Welcome")
    }

    func resetApplicationData() throws {
        let bundleID = try XCTUnwrap(XCUIApplication().bundleID)
        let commands = [
            "/usr/bin/defaults delete \(bundleID)",
            "/bin/rm -rf ~/Library/Containers/\(bundleID)/Data/* || true",
            "/usr/bin/defaults write \(bundleID) moveToApplicationsFolderAlertSuppress 1"
        ]

        for command in commands {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                throw NSError(domain: "ProcessErrorDomain", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Command failed: \(command)"])
            }
        }
    }
}
