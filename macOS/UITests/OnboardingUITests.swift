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

    private var app: XCUIApplication!
    private var welcomeWindow: XCUIElement!

    override func setUpWithError() throws {
        try super.setUpWithError()

        continueAfterFailure = false
        try resetApplicationData()

        app = XCUIApplication.setUp(environment: [
            "UITEST_MODE_ONBOARDING": "1"
        ])
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

        // Complete onboarding using robust helper
        completeOnboardingFlow()

        // Verify home page loaded
        let ddgLogo = app.windows.webViews.groups.containing(.image, identifier: "DuckDuckGo Logo").element
        XCTAssertTrue(ddgLogo.waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    func testOnboardingFlow_AllStepsComplete_ReachesHomePage() throws {
        // Verify welcome window opens
        XCTAssertTrue(welcomeWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Complete full onboarding flow
        completeOnboardingFlow()

        // Verify we reach the home page (robust to DOM changes): wait for DDG logo
        let ddgLogo = app.windows.webViews.groups.containing(.image, identifier: "DuckDuckGo Logo").element
        XCTAssertTrue(ddgLogo.waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    func testOnboardingFlow_SkipAllSteps_ReachesHomePage() throws {
        // Skip through onboarding quickly
        skipOnboardingFlow()

        // Verify we still reach the home page
        let ddgLogo = app.windows.webViews.groups.containing(.image, identifier: "DuckDuckGo Logo").element
        XCTAssertTrue(ddgLogo.waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    func testOnboardingFlow_ImportDataDialog_CanBeCancelled() throws {
        // Navigate to import step (more patient and deterministic)
        navigateToImportStep()

        // Trigger import dialog; do not skip — assert presence
        let importNowButton = welcomeWindow.webViews["Welcome"].buttons["Import Now"]
        XCTAssertTrue(importNowButton.waitForExistence(timeout: 5.0), "'Import Now' should be present on the import step")
        importNowButton.click()

        // Verify dialog appears and can be cancelled
        let cancelButton = welcomeWindow.sheets.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                     "Import dialog should appear with Cancel button")
        cancelButton.click()

        // Verify dialog closes
        let dialogClosed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: cancelButton
        )
        let result = XCTWaiter.wait(for: [dialogClosed], timeout: 5.0)
        XCTAssertEqual(result, .completed, "Import dialog should close after cancellation")
    }

    func testOnboardingFlow_OptionsButtonDisabled_UntilComplete() throws {
        let optionsButton = welcomeWindow.buttons["NavigationBarViewController.optionsButton"]
        XCTAssertTrue(optionsButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Options button should be disabled during onboarding
        XCTAssertFalse(optionsButton.isEnabled, "Options button should be disabled during onboarding")

        // Complete onboarding
        completeOnboardingFlow()

        // Ensure main UI is visible before checking options button state
        let ddgLogo = app.windows.webViews.groups.containing(.image, identifier: "DuckDuckGo Logo").element
        XCTAssertTrue(ddgLogo.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Options button should be present and interactable after onboarding
        let optionsButtonAfter = app.buttons["NavigationBarViewController.optionsButton"]
        XCTAssertTrue(optionsButtonAfter.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(optionsButtonAfter.isHittable, "Options button should be hittable after onboarding completion")
    }

    // MARK: - Helper Methods

    private func completeOnboardingFlow() {
        welcomeWindow.click()
        let webView = welcomeWindow.webViews["Welcome"]

        // Ensure first slide loaded
        let introText = webView.staticTexts["Ready for a faster browser that keeps you protected?"]
        XCTAssertTrue(introText.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Get Started
        let getStartedButton = webView.buttons["Let’s Do It!"]
        XCTAssertTrue(getStartedButton.waitForExistence(timeout: 20))
        // Use coordinate tap to avoid overlay/hittability quirks
        let centerCoordinate = getStartedButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        centerCoordinate.click()

        // Protections activated
        XCTAssertTrue(webView.staticTexts["Protections activated!"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Skip
        let skipButton = webView.buttons["Skip"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        skipButton.click()

        // Let’s get you set up!
        XCTAssertTrue(webView.staticTexts["Let’s get you set up!"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Skip
        XCTAssertTrue(skipButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        skipButton.click()

        // Import step: Next won't exist until we Skip the import
        let importNowButton = webView.buttons["Import Now"]
        XCTAssertTrue(importNowButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let importSkipButton = webView.buttons["Skip"]
        XCTAssertTrue(importSkipButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        importSkipButton.click()

        // Next (set up): re-query after DOM updates
        let nextButtonSetUp = webView.buttons["Next"]
        XCTAssertTrue(nextButtonSetUp.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let nextCoord = nextButtonSetUp.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        nextCoord.click()

        // Duck Player
        XCTAssertTrue(webView.staticTexts["Drowning in ads on YouTube? Not with Duck Player!"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let nextButtonDuckPlayer = webView.buttons["Next"]
        XCTAssertTrue(nextButtonDuckPlayer.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        nextButtonDuckPlayer.click()

        // Customize Experience
        XCTAssertTrue(webView.staticTexts["Let’s customize a few things…"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Session Restore: Skip → Enable Session Restore → Show Home Button
        XCTAssertTrue(skipButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        skipButton.click()
        let enableSessionRestoreButton = webView.buttons["Enable Session Restore"]
        XCTAssertTrue(enableSessionRestoreButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        enableSessionRestoreButton.click()
        let showHomeButton = webView.buttons["Show Home Button"]
        XCTAssertTrue(showHomeButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        showHomeButton.click()

        // Start Browsing
        let startBrowsingButton = webView.buttons["Start Browsing"]
        XCTAssertTrue(startBrowsingButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        startBrowsingButton.click()
    }

    private func skipOnboardingFlow() {
        welcomeWindow.click()
        let webView = welcomeWindow.webViews["Welcome"]

        // Ensure first slide loaded
        let introText = webView.staticTexts["Ready for a faster browser that keeps you protected?"]
        XCTAssertTrue(introText.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Get Started
        let getStartedButton = webView.buttons["Let’s Do It!"]
        XCTAssertTrue(getStartedButton.waitForExistence(timeout: 20))
        // Use coordinate tap to avoid overlay/hittability quirks
        let centerCoordinate = getStartedButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        centerCoordinate.click()

        // Protections activated
        XCTAssertTrue(webView.staticTexts["Protections activated!"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Skip to setup headline
        let skipButton = webView.buttons["Skip"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        skipButton.click()
        XCTAssertTrue(webView.staticTexts["Let’s get you set up!"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Skip to Import step
        XCTAssertTrue(skipButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        skipButton.click()
        let importNowButton = webView.buttons["Import Now"]
        XCTAssertTrue(importNowButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(skipButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        skipButton.click()

        // Next (setup)
        let nextButton = webView.buttons["Next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        nextButton.click()

        // Duck Player
        XCTAssertTrue(webView.staticTexts["Drowning in ads on YouTube? Not with Duck Player!"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(nextButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        nextButton.click()

        // Customize Experience
        XCTAssertTrue(webView.staticTexts["Let’s customize a few things…"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // 1) Show a bookmarks bar with your favorite sites → Skip
        XCTAssertTrue(webView.staticTexts["Show a bookmarks bar with your favorite sites"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(skipButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        skipButton.click()

        // 2) Restore previous websites on startup → Skip
        XCTAssertTrue(webView.staticTexts["Restore previous websites on startup"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(skipButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        skipButton.click()

        // 3) Add a shortcut to your homepage in the toolbar → Skip
        XCTAssertTrue(webView.staticTexts["Add a shortcut to your homepage in the toolbar"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(skipButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        skipButton.click()

        let startBrowsingButton = webView.buttons["Start Browsing"]
        XCTAssertTrue(startBrowsingButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        startBrowsingButton.click()
    }

    private func navigateToImportStep() {
        welcomeWindow.click()
        let webView = welcomeWindow.webViews["Welcome"]

        // Get Started
        let getStartedButton = webView.buttons["Let’s Do It!"]
        XCTAssertTrue(getStartedButton.waitForExistence(timeout: 20))

        let centerCoordinate = getStartedButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        centerCoordinate.click()

        // Protections activated
        XCTAssertTrue(webView.staticTexts["Protections activated!"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Skip to setup step
        let skipButton = webView.buttons["Skip"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        skipButton.click()

        // Ensure we are on the setup headline, then explicitly skip the Dock step
        XCTAssertTrue(webView.staticTexts["Let’s get you set up!"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(skipButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        skipButton.click()

        // Ensure Import Now present
        let importNow = webView.buttons["Import Now"]
        XCTAssertTrue(importNow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    func resetApplicationData() throws {
        let commands = [
            "/usr/bin/defaults delete com.duckduckgo.macos.browser.review",
            "/bin/rm -rf ~/Library/Containers/com.duckduckgo.macos.browser.review/Data",
            "/usr/bin/defaults write com.duckduckgo.macos.browser.review moveToApplicationsFolderAlertSuppress 1"
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
