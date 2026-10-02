//
//  AppOpenKeyboardXCUITests.swift
//  AtbUITests
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

import Swifter
import XCTest

/// Runs against the real app-open timer: the long-return cases deliberately wait 25 seconds.
final class AppOpenKeyboardXCUITests: XCTestCase {
    private let app = XCUIApplication()
    private let server = HttpServer()
    private let timeout: TimeInterval = 15
    private var baseURL = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        server["/atb.js"] = { _ in .ok(.json(["version": "v1-1", "majorVersion": 1, "minorVersion": 1])) }
        server["/exti/"] = { _ in .accepted }
        server["/t/:pixelName"] = { _ in .accepted }
        server["/page"] = { _ in .ok(.html("<html><head><title>Keyboard fixture</title></head><body><h1>Keyboard fixture</h1></body></html>")) }
        try server.start(0, forceIPv4: true, priority: .userInitiated)
        baseURL = "http://127.0.0.1:\(try server.port())"
    }

    override func tearDownWithError() throws {
        app.terminate()
        server.stop()
        try super.tearDownWithError()
    }

    func testColdLaunchRestoresNewTabWithFocusedKeyboard() {
        launchApp(flagOn: true)
        dismissKeyboard()
        relaunchPreservingState()
        assertKeyboard(up: true)
        app.typeText("keyboard probe")
        XCTAssertTrue(element("searchEntry").value as? String == "keyboard probe", app.debugDescription)
    }

    func testFlagOffColdLaunchKeepsKeyboardDown() {
        launchApp(flagOn: false)
        dismissKeyboard()
        relaunchPreservingState()
        assertKeyboard(up: false)
    }

    func testLongReturnRaisesKeyboardButShortReturnRespectsDismissal() {
        launchApp(flagOn: true)
        configureIdleReturn(lastUsedTab: false)
        backgroundAndReturn(long: true)
        assertKeyboard(up: true)
        dismissKeyboard()
        backgroundAndReturn(long: false)
        assertKeyboard(up: false)
    }

    func testFlagOffLongReturnKeepsKeyboardDown() {
        launchApp(flagOn: false)
        configureIdleReturn(lastUsedTab: false)
        backgroundAndReturn(long: true)
        assertKeyboard(up: false)
    }

    func testIdleReturnClosesSettingsWithOpenNewTab() {
        assertOverlayReturn(settings: true, lastUsedTab: false, flagOn: true)
    }

    func testShortIdleReturnClosesSettingsWithoutRaisingKeyboard() {
        assertOverlayReturn(settings: true, lastUsedTab: false, flagOn: true, long: false)
    }

    func testIdleReturnClosesSettingsWithOpenLastUsedTab() {
        assertOverlayReturn(settings: true, lastUsedTab: true, flagOn: true)
    }

    func testIdleReturnClosesTabManagerWithOpenNewTab() {
        assertOverlayReturn(settings: false, lastUsedTab: false, flagOn: true)
    }

    func testIdleReturnClosesTabManagerWithOpenLastUsedTab() {
        assertOverlayReturn(settings: false, lastUsedTab: true, flagOn: true)
    }

    func testFlagOffIdleReturnKeepsSettingsOpen() {
        assertOverlayReturn(settings: true, lastUsedTab: false, flagOn: false)
    }

    func testFlagOffIdleReturnKeepsTabManagerOpen() {
        assertOverlayReturn(settings: false, lastUsedTab: false, flagOn: false)
    }

    func testWebsiteIdleReturnCreatesFocusedNewTabEvenBeforeTwentySeconds() {
        launchApp(flagOn: true)
        configureIdleReturn(lastUsedTab: false)
        openWebsite()
        backgroundAndReturn(long: false)
        assertKeyboard(up: true)
        XCTAssertTrue(element("NewTabPage.escapeHatch.card").waitForExistence(timeout: timeout), app.debugDescription)
        XCTAssertFalse(app.webViews.staticTexts["Keyboard fixture"].exists, app.debugDescription)
        dismissKeyboard()
        openWebsite()
        backgroundAndReturn(long: true)
        assertKeyboard(up: true)
        XCTAssertTrue(element("NewTabPage.escapeHatch.card").waitForExistence(timeout: timeout), app.debugDescription)
        XCTAssertFalse(app.webViews.staticTexts["Keyboard fixture"].exists, app.debugDescription)
    }

    func testAppLaunchSettingAppliesToWebsiteButNotNewTab() {
        launchApp(flagOn: true, onNewTab: false, onAppLaunch: true)
        configureIdleReturn(lastUsedTab: true)
        backgroundAndReturn(long: true)
        assertKeyboard(up: false)
        openWebsite()
        backgroundAndReturn(long: true)
        assertKeyboard(up: true)
    }

    func testFirstSuccessfulUnlockAfterShortReturnStillRaisesKeyboard() {
        launchApp(flagOn: true, authenticationResults: "failure,success", waitForBrowser: false)
        XCTAssertTrue(element("AppLock.Retry").waitForHittable(timeout: timeout), app.debugDescription)
        assertKeyboard(up: false)
        backgroundAndReturn(long: false)
        XCTAssertTrue(element("AppLock.Screen").waitForNonExistence(timeout: timeout))
        assertKeyboard(up: true)
    }

    func testFailedUnlockKeepsKeyboardDownUntilSuccessfulRetry() {
        launchApp(flagOn: true, authenticationResults: "success,failure,success")
        dismissKeyboard()
        backgroundAndReturn(long: true)
        let retry = element("AppLock.Retry")
        XCTAssertTrue(retry.waitForHittable(timeout: timeout), app.debugDescription)
        assertKeyboard(up: false)
        tap(retry)
        XCTAssertTrue(element("AppLock.Screen").waitForNonExistence(timeout: timeout))
        assertKeyboard(up: true)
    }

    func testBackgroundWhileWaitingForUnlockDoesNotLeakKeyboardIntoNextLockScreen() {
        launchApp(flagOn: true, authenticationResults: "success,failure,failure,success")
        dismissKeyboard()
        backgroundAndReturn(long: true)
        let retry = element("AppLock.Retry")
        XCTAssertTrue(retry.waitForHittable(timeout: timeout), app.debugDescription)
        assertKeyboard(up: false)
        backgroundAndReturn(long: true)
        XCTAssertTrue(retry.waitForHittable(timeout: timeout), app.debugDescription)
        assertKeyboard(up: false)
        tap(retry)
        XCTAssertTrue(element("AppLock.Screen").waitForNonExistence(timeout: timeout))
        assertKeyboard(up: true)
    }

    func testInitialOnboardingDialogStaysAboveKeyboardOnLongReturn() {
        launchApp(flagOn: true, onboarding: true)
        completeLinearOnboarding()
        assertOnboardingSurvivesReturn(button: app.buttons["Surprise me!"].firstMatch)
    }

    func testFinalOnboardingDialogStaysAboveKeyboardAfterItMarksItselfSeen() {
        // Seed only completed preceding steps; the real final dialog marks itself seen on appearance.
        launchApp(flagOn: true, onboarding: true, finalOnboardingDialog: true)
        completeLinearOnboarding()
        assertOnboardingSurvivesReturn(button: app.buttons["High five!"].firstMatch)
    }

    private func completeLinearOnboarding() {
        tap(app.buttons["Let’s get started!"])
        tap(app.buttons["Skip"].firstMatch)
        tap(app.buttons["Skip"].firstMatch)
        tap(app.buttons["Next"].firstMatch)
        tap(app.buttons["Next"].firstMatch)
        tap(app.buttons["Search only"].firstMatch)
        tap(app.buttons["Next"].firstMatch)
    }

    private func assertOnboardingSurvivesReturn(button: XCUIElement) {
        XCTAssertTrue(button.waitForHittable(timeout: timeout), app.debugDescription)
        // Completing linear onboarding focuses the address bar independently of app-open handling.
        dismissKeyboard()
        XCTAssertTrue(button.isHittable, app.debugDescription)
        backgroundAndReturn(long: true)
        XCTAssertTrue(button.waitForHittable(timeout: timeout), app.debugDescription)
        assertKeyboard(up: false)
    }

    private func launchApp(flagOn: Bool, onNewTab: Bool = true, onAppLaunch: Bool = false,
                           onboarding: Bool = false, authenticationResults: String? = nil, finalOnboardingDialog: Bool = false,
                           waitForBrowser: Bool = true) {
        app.launchArguments = [
            "-clearAllDefaults", "isRunningUITests",
            "-ff.alwaysShowKeyboardOnNewTabPage", String(flagOn),
            "-ff.showNTPAfterIdleReturn", "true",
            "-ff.floatingUIiOS26", "true", "-ff.floatingUIiOS27", "true",
            "-ff.newTabPageRedesign", "false",
            "-ff.subscriptionPromoForExistingUsers", "false",
            "-ff.subscriptionPromoForReinstallers", "false",
            "-ff.privacyProOnboardingPromotion", "false",
            "-appOpenKeyboardTestSeed", "{ newTab = \(onNewTab); appLaunch = \(onAppLaunch); appLock = \(authenticationResults != nil); " +
                "fireEducation = \(finalOnboardingDialog); siteVisited = \(finalOnboardingDialog); }",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_GB"
        ]
        if !onboarding {
            app.launchArguments += ["-isOnboardingCompleted", "true"]
        }
        app.launchEnvironment = ["UITEST_MODE": "1", "BASE_URL": baseURL, "PIXEL_BASE_URL": baseURL]
        if let authenticationResults {
            app.launchEnvironment["UITEST_APP_LOCK_RESULTS"] = authenticationResults
        }
        app.launch()
        if !onboarding && waitForBrowser {
            XCTAssertTrue(element("searchEntry").waitForHittable(timeout: timeout), app.debugDescription)
        }
    }

    private func relaunchPreservingState() {
        app.terminate()
        app.launchArguments.removeAll { $0 == "-clearAllDefaults" }
        app.launch()
        XCTAssertTrue(element("searchEntry").waitForHittable(timeout: timeout), app.debugDescription)
    }

    private func backgroundAndReturn(long: Bool) {
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        let backgroundStart = Date()
        if long {
            // This measures the production >20-second rule, not a test override or a readiness delay.
            Thread.sleep(forTimeInterval: 25)
        }
        app.activate()
        if !long {
            XCTAssertLessThan(Date().timeIntervalSince(backgroundStart), 20, "A slow activation must not silently turn a short-return case into a long one.")
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: timeout))
    }

    private func configureIdleReturn(lastUsedTab: Bool) {
        dismissKeyboard()
        openSettings()
        let general = app.staticTexts["General"].firstMatch
        for _ in 0..<8 {
            if general.exists && general.isHittable && app.frame.contains(general.frame) { break }
            app.swipeUp(velocity: .slow)
        }
        tap(general)
        selectSetting("After Inactivity", option: "Open New Tab")
        selectSetting("Inactivity Timer", option: "None")
        if lastUsedTab {
            selectSetting("After Inactivity", option: "Open Last Used Tab")
        }
        tap(app.navigationBars.buttons["Settings"])
        tap(app.buttons["Done"])
        assertKeyboard(up: false)
    }

    private func selectSetting(_ title: String, option: String) {
        let setting = app.cells.containing(.staticText, identifier: title).buttons.firstMatch
        XCTAssertTrue(setting.waitForHittable(timeout: timeout), app.debugDescription)
        guard setting.label != option else { return }
        tap(setting)
        tap(app.buttons[option].firstMatch)
        XCTAssertEqual(setting.label, option)
    }

    private func assertOverlayReturn(settings: Bool, lastUsedTab: Bool, flagOn: Bool, long: Bool = true) {
        launchApp(flagOn: flagOn)
        configureIdleReturn(lastUsedTab: lastUsedTab)
        if settings {
            openSettings()
        } else {
            tap(element("Browser.Toolbar.Button.TabSwitcher"))
        }
        let overlay = settings ? app.navigationBars["Settings"] : app.buttons["Done"]
        XCTAssertTrue(overlay.waitForExistence(timeout: timeout), app.debugDescription)
        backgroundAndReturn(long: long)
        if flagOn {
            XCTAssertTrue(overlay.waitForNonExistence(timeout: timeout), app.debugDescription)
        } else {
            XCTAssertTrue(overlay.exists, app.debugDescription)
        }
        assertKeyboard(up: flagOn && long)
    }

    private func openSettings() {
        tap(element("Browser.Toolbar.Button.Menu"))
        tap(app.buttons["Settings"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: timeout))
    }

    private func openWebsite() {
        tap(element("searchEntry"))
        app.typeText(baseURL + "/page\r")
        XCTAssertTrue(app.webViews.staticTexts["Keyboard fixture"].waitForExistence(timeout: timeout), app.debugDescription)
        assertKeyboard(up: false)
    }

    private func dismissKeyboard() {
        if app.keyboards.firstMatch.waitForExistence(timeout: 1) {
            tap(element("UnifiedToggleInput.Button.Dismiss"))
        }
        assertKeyboard(up: false)
    }

    private func assertKeyboard(up: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let keyboard = app.keyboards.firstMatch
        if up {
            XCTAssertTrue(keyboard.waitForExistence(timeout: timeout), app.debugDescription, file: file, line: line)
        } else {
            XCTAssertTrue(keyboard.waitForNonExistence(timeout: timeout), app.debugDescription, file: file, line: line)
            XCTAssertFalse(keyboard.waitForExistence(timeout: 2), "A delayed keyboard appeared.", file: file, line: line)
        }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForHittable(timeout: timeout), app.debugDescription, file: file, line: line)
        element.tap()
    }
}
