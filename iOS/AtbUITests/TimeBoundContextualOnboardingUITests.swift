//
//  TimeBoundContextualOnboardingUITests.swift
//  DuckDuckGo
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
import UITestingSupport

final class TimeBoundContextualOnboardingUITests: XCTestCase {

    private let app = XCUIApplication()
    private let timeout = UITestTimeouts.navigation
    private let trackerPage = "https://privacy-test-pages.site/tracker-reporting/1major-via-script.html"
    private let secondTrackerPage = "https://privacy-test-pages.site/tracker-reporting/1major-via-img.html"
    private let searchDialogTitle = "That’s DuckDuckGo Search!"

    override func setUpWithError() throws {
        try super.setUpWithError()
        // These tests walk the iPhone linear onboarding, which iPad does not show.
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        continueAfterFailure = false
        executionTimeAllowance = 180
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        app.terminate()
        try super.tearDownWithError()
    }

    func testAppOpensLimitSuppressesSearchSiteAndNewTabDialogs() {
        launch(maxAppOpens: 1)
        finishLinearOnboarding()
        relaunchPreservingOnboardingState()
        assertNoContextualDialog()

        search()
        assertNoContextualDialog()
        openTrackerFreePage()
        assertNoContextualDialog()

        dismissInputIfNeeded()
        let tabSwitcher = app.buttons["Browser.Toolbar.Button.TabSwitcher"]
        XCTAssertTrue(tabSwitcher.staticTexts["1"].waitForExistence(timeout: timeout))
        tap(app.buttons["Browser.Toolbar.Button.Menu"])
        tapButton("New Tab")
        waitForBrowser()
        dismissInputIfNeeded()
        XCTAssertTrue(tabSwitcher.staticTexts["2"].waitForExistence(timeout: timeout))
        assertNoContextualDialog()
        attachScreenshot(named: "New tab after the limit")
    }

    func testDaysLimitSuppressesSearchAndTrackerFreeSiteDialogs() {
        launch(daysSinceStart: 8)
        finishLinearOnboarding()
        assertNoContextualDialog()

        search()
        assertNoContextualDialog()
        openTrackerFreePage()
        assertNoContextualDialog()
    }

    func testAfterLimitShowsTrackersOnceWithoutFireFollowUp() {
        launch(daysSinceStart: 8)
        finishLinearOnboarding()
        openTrackerPage()
        XCTAssertTrue(trackersMessage.waitForExistence(timeout: timeout))
        attachScreenshot(named: "Final trackers exception")

        let acknowledge = app.buttons["Got it!"].firstMatch
        XCTAssertTrue(acknowledge.waitForExistence(timeout: timeout))
        XCTAssertTrue(acknowledge.isEnabled)
        // XCTest reports this visible SwiftUI overlay button as non-hittable.
        acknowledge.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(trackersMessage.waitForNonExistence(timeout: timeout))
        assertNoContextualDialog()
        attachScreenshot(named: "Trackers exception dismissed without fire education")

        openSecondTrackerSite()
        assertNoContextualDialog()
        assertCurrentPageHasBlockedTrackers()
        assertNoContextualDialog()
    }

    func testTrackersSeenBeforeLimitSuppressesTheException() {
        launch(maxAppOpens: 1)
        finishLinearOnboarding()
        openTrackerPage()
        XCTAssertTrue(trackersMessage.waitForExistence(timeout: timeout))

        relaunchPreservingOnboardingState()
        openSecondTrackerSite()
        assertNoContextualDialog()
        assertCurrentPageHasBlockedTrackers()
        assertNoContextualDialog()
    }

    func testSkippedOnboardingSuppressesTrackersAfterLimit() {
        launch(daysSinceStart: 8, returningUser: true)
        tapButton("I’ve been here before")
        tapButton("Start Browsing")
        waitForBrowser()

        openTrackerPage()
        assertNoContextualDialog()
        assertCurrentPageHasBlockedTrackers()
        assertNoContextualDialog()
    }

    func testWarmReturnPastLimitRemovesAnAlreadyVisibleSearchDialog() {
        launch(maxAppOpens: 1)
        finishLinearOnboarding()
        let searchDialog = app.staticTexts[searchDialogTitle]
        XCTAssertTrue(searchDialog.waitForExistence(timeout: timeout))

        XCUIDevice.shared.press(.home)
        XCTAssertNotEqual(app.state, .notRunning, "This check must preserve the running app.")
        app.activate()

        waitForBrowser()
        XCTAssertTrue(searchDialog.waitForNonExistence(timeout: timeout))
        assertNoContextualDialog()
        attachScreenshot(named: "Visible search dialog removed after warm-return expiry")
    }

    private func launch(maxAppOpens: Int = 1000, daysSinceStart: Int = 0, returningUser: Bool = false) {
        app.launchArguments = [
            "-clearAllDefaults",
            "isRunningUITests",
            "-isOnboardingCompleted", "false",
            "-setDaxNotDismissed",
            "-isInternalUser", "true",
            "-currentAppVariant", returningUser ? "ru" : "mh",
            "-ff.contextualOnboardingTimeLimit", "true",
            "-ff.onboardingDuckAIFlow", "false",
            "-ff.newTabPageRedesign", "true",
            "-ff.alwaysShowKeyboardOnNewTabPage", "false",
            "-ff.slideToDelete", "false",
            "-contextualOnboardingMaxDays", "7",
            "-contextualOnboardingMaxAppOpens", String(maxAppOpens),
            "-contextualOnboardingStartDate", String(Date().addingTimeInterval(-Double(daysSinceStart) * 86_400).timeIntervalSince1970),
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launchEnvironment = ["UITEST_MODE": "1"]
        app.launch()
    }

    /// Completes the iPhone linear onboarding by searching from its last step, which lands on the search results page.
    private func finishLinearOnboarding() {
        tapButton("Let’s get started!")
        waitForText("Set things up your way")
        tap(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Search and")).firstMatch)
        tapButton("Next")

        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Protections activated")).firstMatch
            .waitForExistence(timeout: timeout))
        tapButton("Skip")
        waitForText("Want easy access to private AI chat in the address bar?")
        tap(app.staticTexts["Search only"])
        tapButton("Next")
        waitForText("Where should I put your address bar?")
        tapButton("Next")

        let dock = app.staticTexts["Add me to your Dock!"]
        let icon = app.staticTexts["Which color looks best on me?"]
        XCTAssertTrue(app.wait(for: NSPredicate { _, _ in dock.exists || icon.exists }, timeout: timeout))
        if dock.exists {
            tapButton("Skip")
        }
        waitForText("Which color looks best on me?")
        tapButton("Next")

        waitForText("Now, try a private search!")
        // The step focuses its search field and shows the keyboard on its own.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: timeout))
        app.typeText("timebound dax onboarding\n")
        waitForPageText("All")
    }

    private func relaunchPreservingOnboardingState() {
        app.terminate()
        // A repeated false override would restart linear onboarding instead of testing a real app open.
        if let index = app.launchArguments.firstIndex(of: "-isOnboardingCompleted") {
            app.launchArguments.removeSubrange(index...index + 1)
        }
        app.launchArguments.removeAll { ["-clearAllDefaults", "-setDaxNotDismissed"].contains($0) }
        app.launch()
        waitForBrowser()
    }

    private func search() {
        navigate(to: "timebound dax onboarding")
        waitForPageText("All")
    }

    private func openTrackerFreePage() {
        navigate(to: "https://example.com")
        waitForPageText("Example Domain")
    }

    private func openTrackerPage() {
        navigate(to: trackerPage)
        waitForPageText("1 major tracker loaded via script src")
    }

    private func openSecondTrackerSite() {
        navigate(to: secondTrackerPage)
        waitForPageText("1 major tracker loaded via img src")
    }

    private func navigate(to text: String) {
        tap(app.descendants(matching: .any)["searchEntry"].firstMatch)
        let field = app.textFields["searchEntry"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        // The keyboard introduction can animate in with or just after the keyboard, so give it a moment once the keyboard is up.
        let keyboardIntroduction = app.buttons["Continue"]
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(app.wait(for: NSPredicate { _, _ in keyboardIntroduction.exists || keyboard.exists }, timeout: timeout))
        if keyboardIntroduction.waitForExistence(timeout: 1) {
            tap(keyboardIntroduction)
        }
        if let value = field.value as? String, !value.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        field.typeText(text + "\n")
    }

    private func waitForPageLoad() {
        XCTAssertTrue(app.buttons["Stop Loading"].waitForNonExistence(timeout: timeout))
    }

    private func waitForPageText(_ label: String) {
        let text = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: timeout), "Expected page content did not load: \(label)")
        waitForPageLoad()
    }

    private var trackersMessage: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "trying to track you here")).firstMatch
    }

    private func assertCurrentPageHasBlockedTrackers() {
        let icon = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier IN %@ OR label == %@", ["PrivacyIcon", "privacy-icon-shield.button"], "Privacy Icon"
        )).firstMatch
        tap(icon)
        let blocked = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "We blocked")).firstMatch
        XCTAssertTrue(blocked.waitForExistence(timeout: timeout), "The fixture must actually block trackers.")
        tapButton("Done")
        waitForBrowser()
    }

    /// Browsing dialogs appear about half a second after tracker info settles, so watch for any of them for several seconds.
    private func assertNoContextualDialog(file: StaticString = #filePath, line: UInt = #line) {
        let dialog = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ OR label CONTAINS %@ OR label CONTAINS %@ OR label == %@ OR label == %@",
            "onboardingDialogDismissButton", "Give it a try!", "trying to track you here", "You’ve got this!", searchDialogTitle
        )).firstMatch
        XCTAssertFalse(dialog.waitForExistence(timeout: UITestTimeouts.elementExistence), "A contextual onboarding dialog appeared", file: file, line: line)
    }

    private func waitForBrowser() {
        XCTAssertTrue(app.descendants(matching: .any)["searchEntry"].firstMatch.waitForExistence(timeout: timeout))
    }

    private func waitForText(_ text: String) {
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: timeout))
    }

    private func tapButton(_ label: String) {
        tap(app.buttons[label].firstMatch)
    }

    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.wait(for: NSPredicate { _, _ in element.isHittable }, timeout: timeout))
        element.tap()
    }

    /// Waits until either the toolbar or an active input's dismiss button is available, then closes the input.
    private func dismissInputIfNeeded() {
        let menu = app.buttons["Browser.Toolbar.Button.Menu"]
        let dismissButtons = ["UnifiedToggleInput.Button.Dismiss", "Browser.OmniBar.Button.Dismiss"].map { app.buttons[$0] }
        XCTAssertTrue(app.wait(for: NSPredicate { _, _ in menu.isHittable || dismissButtons.contains { $0.isHittable } }, timeout: timeout))
        dismissButtons.first { $0.isHittable }?.tap()
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
