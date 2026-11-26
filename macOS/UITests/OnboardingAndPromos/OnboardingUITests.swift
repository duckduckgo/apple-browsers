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

        try resetApplicationData()

        launchOnboarding()
    }

    /// Launches the app into the onboarding flow.
    private func launchOnboarding(featureFlags: [String: Bool] = [:]) {
        app = XCUIApplication.setUp(
            environment: [
                "UITEST_MODE_ONBOARDING": "1"
            ],
            featureFlags: featureFlags
        )
        app.enforceSingleWindow()
        welcomeWindow = app.windows["Welcome"]
    }

    override func tearDownWithError() throws {
        try resetApplicationData()
        try super.tearDownWithError()
    }

    func testOnboardingToBrowsing() throws {
        // The flow without the search or AI chat step, which the remote config can still turn off.
        app.terminate()
        launchOnboarding(featureFlags: ["onboardingSearchOrChat": false])

        goToAIChatStep()

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

    func testSearchOnlyToSearch() throws {
        goToAIChatStep()
        welcomeButton(titled: "Search Only").click()
        welcomeButton(titled: "Next").click()

        XCTAssertTrue(welcomeText(containing: "Now, try a private search!").waitForExistence(timeout: UITests.Timeouts.elementExistence))
        welcomeButton(titled: "in spanish").click()

        assertAddressBar(contains: "duckduckgo.com")
    }

    func testSearchAndDuckAIToSearch() throws {
        goToAIChatStep()
        welcomeButton(titled: "Next").click()

        // Search is selected by default.
        XCTAssertTrue(welcomeText(containing: "Ready to get started?").waitForExistence(timeout: UITests.Timeouts.elementExistence))
        welcomeButton(titled: "in spanish").click()

        assertAddressBar(contains: "duckduckgo.com")
    }

    func testSearchAndDuckAIToDuckAI() throws {
        goToAIChatStep()
        welcomeButton(titled: "Next").click()

        XCTAssertTrue(welcomeText(containing: "Ready to get started?").waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // The mode toggle is a tab, not a button.
        let askAITab = welcomeWindow.webViews["Welcome"].descendants(matching: .any)
            .matching(NSPredicate(format: "title ==[c] %@ OR label ==[c] %@", "Ask AI", "Ask AI"))
            .firstMatch
        XCTAssertTrue(askAITab.waitForExistence(timeout: UITests.Timeouts.elementExistence), "No \"Ask AI\" toggle")
        askAITab.click()
        welcomeButton(titled: "Plan a perfect day in London").click()

        // Contextual onboarding is off in this test mode, so the Duck.ai path's lock and dialogs aren't checked here.
        assertAddressBar(contains: "Duck.ai")
    }

    private func welcomeButton(titled title: String) -> XCUIElement {
        let button = welcomeWindow.webViews["Welcome"].buttons
            .matching(NSPredicate(format: "title CONTAINS[c] %@", title))
            .firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: UITests.Timeouts.elementExistence), "No \"\(title)\" button")
        return button
    }

    private func welcomeText(containing text: String) -> XCUIElement {
        welcomeWindow.webViews["Welcome"].staticTexts
            .matching(NSPredicate(format: "value CONTAINS[c] %@", text))
            .firstMatch
    }

    private func assertAddressBar(contains text: String, file: StaticString = #filePath, line: UInt = #line) {
        let addressBar = app.windows.firstMatch.staticTexts[XCUIApplication.AccessibilityIdentifiers.addressBarPassiveTextField]
        let predicate = NSPredicate(format: "value CONTAINS[c] %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: addressBar)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: UITests.Timeouts.navigation), .completed,
                       "Address bar shows \"\(addressBar.value as? String ?? "")\"", file: file, line: line)
    }

    /// Goes through the welcome steps up to the AI Chat step.
    private func goToAIChatStep() {
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
