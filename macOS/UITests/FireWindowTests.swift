//
//  FireWindowTests.swift
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

class FireWindowTests: UITestCase {

    private var settingsGeneralButton: XCUIElement!
    private var reopenAllWindowsFromLastSessionPreference: XCUIElement!

    override func setUpWithError() throws {
        try super.setUpWithError()
        app = XCUIApplication.setUp()

        settingsGeneralButton = app.buttons["PreferencesSidebar.generalButton"]
        reopenAllWindowsFromLastSessionPreference = app.radioButtons["PreferencesGeneralView.stateRestorePicker.reopenAllWindowsFromLastSession"]

        app.enforceSingleWindow()
    }

    func testFireWindowDoesNotStoreHistory() {
        app.openFireWindow()
        app.openSite(pageTitle: "Some site")
        app.openNewWindow()
        assertSiteIsNotShowingInNormalWindowHistory()
    }

    func testFireWindowStateIsNotSavedAfterRestart() {
        app.openNewWindow()
        // Open settings and enable session restore using helper
        app.openPreferencesWindow()
        app.preferencesSetRestorePreviousSession(to: .restoreLastSession)
        app.closePreferencesWindow()

        openThreeSitesOnNormalWindow()
        app.openFireWindow()
        openThreeSitesOnFireWindow()

        app.restart(forceTerminate: true)

        assertSitesOpenedInNormalWindowAreRestored()
        assertSitesOpenedOnFireWindowAreNotRestored()
    }

    func testFireWindowDoNotShowPinnedTabs() {
        app.openNewWindow()
        app.openSite(pageTitle: "Page #1")
        app.pinCurrentTab()

        app.openNewTab()
        app.openSite(pageTitle: "Page #2")
        app.pinCurrentTab()

        app.openFireWindow()
        assertFireWindowDoesNotHavePinnedTabs()
    }

    func testFireWindowTabsCannotBeDragged() {
        app.openFireWindow()
        app.openSite(pageTitle: "Page #1")

        app.openNewTab()
        app.openSite(pageTitle: "Page #2")

        dragFirstTabOutsideOfFireWindow()

        /// Assert that Page #1 is still on the fire window after the drag
        app.typeKey("]", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["Sample text for Page #2"].exists)
        app.typeKey("[", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["Sample text for Page #1"].exists)
    }

    func testFireWindowsSignInDoesNotShowCredentialsPopup() {
        app.openFireWindow()
        hoverMouseOutsideTabSoPreviewIsNotShown()
        app.openAutofillTestPage(.signUp)
        app.fillSignUpForm(email: "test@duck.com", password: "pa$$word")
        app.submitSignUpForm()
        assertSavePasswordPopupIsNotShown()
    }

    func testCrendentialsAreAutoFilledInFireWindows() {
        let email = "\(UITests.randomPageTitle(length: 8).lowercased())@duck.com"
        app.resetAutofillData()
        app.openNewWindow()
        hoverMouseOutsideTabSoPreviewIsNotShown()
        app.openAutofillTestPage(.login)
        app.signIn(email: email, password: "pa$$word")
        app.saveCredentialsFromPopover()

        /// Here we start the same flow but in the fire window, but we use the autofill credentials saved in the step before.
        app.openFireWindow()
        hoverMouseOutsideTabSoPreviewIsNotShown()
        app.openAutofillTestPage(.login)
        app.fillLoginUsingAutofill(email: email)
    }

    func testCookiesSetInRegularWindowAreNotVisibleInFireWindow() {
        let cookieName = "regular\(UITests.randomPageTitle(length: 8))"
        setCookie(named: cookieName)
        assertCookie(named: cookieName, isVisible: true)

        app.openFireWindow()
        assertCookie(named: cookieName, isVisible: false)
    }

    func testCookiesSetInFireWindowAreNotVisibleInRegularWindow() {
        let cookieName = "fire\(UITests.randomPageTitle(length: 8))"
        app.openFireWindow()
        setCookie(named: cookieName)
        assertCookie(named: cookieName, isVisible: true)

        app.openNewWindow()
        assertCookie(named: cookieName, isVisible: false)
    }

    func testDevelopMenuIsDisabledInNewFireWindow() {
        app.openFireWindow()
        assertDeveloperToolsEnabled(false)
    }

    func testDevelopMenuIsEnabledInFireWindowAfterNavigation() {
        app.openFireWindow()
        app.openSite(pageTitle: "Some site")
        assertDeveloperToolsEnabled(true)
    }

    // MARK: - Utilities

    private func hoverMouseOutsideTabSoPreviewIsNotShown() {
        let window = app.windows.firstMatch
        let coordinate = window.coordinate(withNormalizedOffset: CGVector(dx: -100, dy: -100))
        coordinate.hover()
    }

    private func assertSavePasswordPopupIsNotShown() {
        XCTAssertFalse(app.savePasswordPopoverTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                       "Fire windows shouldn't offer to save passwords.")
    }

    /// Cookies are per host and port, so every tests-server page shares them; the cookie name keeps tests apart.
    private func setCookie(named name: String) {
        let page = UITests.simpleServedPage(titled: "Cookie setter", body: """
            <script>document.cookie = "\(name)=1; max-age=3600; path=/";</script>
            <p>Cookie set</p>
            """)
        app.activateAddressBar()
        app.openURL(page, waitForWebViewAccessibilityLabel: "Cookie setter")
    }

    /// The reader page reports in its title whether it can see the cookie, which the web view exposes as its label.
    private func assertCookie(named name: String, isVisible: Bool) {
        let page = UITests.simpleServedPage(titled: "Cookie reader", body: """
            <script>
            document.title = document.cookie.split("; ").includes("\(name)=1") ? "Cookie present" : "Cookie absent";
            </script>
            """)
        app.activateAddressBar()
        app.openURL(page, waitForWebViewAccessibilityLabel: isVisible ? "Cookie present" : "Cookie absent")
    }

    private func dragFirstTabOutsideOfFireWindow() {
        let toolbar = app.toolbars.firstMatch
        let toolbarCoordinate = toolbar.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let startPoint = toolbarCoordinate.withOffset(CGVector(dx: 120, dy: -15))
        let endPoint = toolbarCoordinate.withOffset(CGVector(dx: -100, dy: -100))
        startPoint.click(forDuration: 0.5, thenDragTo: endPoint)
    }

    private func assertFireWindowDoesNotHavePinnedTabs() {
        let staticTexts = app.windows.firstMatch.staticTexts.element(boundBy: 0)
        XCTAssertTrue(staticTexts.waitForExistence(timeout: UITests.Timeouts.elementExistence), "No static texts were found in the app")

        // After confirming static texts are available, iterate through them
        for staticText in app.staticTexts.allElementsBoundByIndex where staticText.exists {
            XCTAssertFalse(staticText.label.contains("Page #1"), "Unwanted string found in static text: \(staticText.label)")
            XCTAssertFalse(staticText.label.contains("Page #2"), "Unwanted string found in static text: \(staticText.label)")
        }
    }

    private func assertSitesOpenedInNormalWindowAreRestored() {
        XCTAssertTrue(app.staticTexts["Sample text for Page #3"].waitForExistence(timeout: UITests.Timeouts.localTestServer), "Page #3 should exist.")
        app.typeKey("[", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["Sample text for Page #2"].waitForExistence(timeout: UITests.Timeouts.localTestServer), "Page #2 should exist.")
        app.typeKey("[", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["Sample text for Page #1"].waitForExistence(timeout: UITests.Timeouts.localTestServer), "Page #1 should exist.")
    }

    private func assertSitesOpenedOnFireWindowAreNotRestored() {
        let staticTexts = app.windows.firstMatch.staticTexts.element(boundBy: 0)
        XCTAssertTrue(staticTexts.waitForExistence(timeout: UITests.Timeouts.elementExistence), "No static texts were found in the app")

        // After confirming static texts are available, iterate through them
        for staticText in app.staticTexts.allElementsBoundByIndex where staticText.exists {
            XCTAssertFalse(staticText.label.contains("Page #4"), "Unwanted string found in static text: \(staticText.label)")
            XCTAssertFalse(staticText.label.contains("Page #5"), "Unwanted string found in static text: \(staticText.label)")
            XCTAssertFalse(staticText.label.contains("Page #6"), "Unwanted string found in static text: \(staticText.label)")
        }
    }

    private func openThreeSitesOnNormalWindow() {
        app.openNewTab()
        app.openSite(pageTitle: "Page #1")
        app.openNewTab()
        app.openSite(pageTitle: "Page #2")
        app.openNewTab()
        app.openSite(pageTitle: "Page #3")
    }

    private func openThreeSitesOnFireWindow() {
        app.openSite(pageTitle: "Page #4")
        app.openNewTab()
        app.openSite(pageTitle: "Page #5")
        app.openNewTab()
        app.openSite(pageTitle: "Page #6")
    }

    private func assertSiteIsNotShowingInNormalWindowHistory() {
        let siteMenuItemInHistory = app.menuItems["Some site"]
        XCTAssertFalse(siteMenuItemInHistory.exists, "Menu item should not exist because it was not stored in history.")
    }

    private func assertDeveloperToolsEnabled(_ shouldBeEnabled: Bool) {
        let developerTools = app.menuItems["toggleDeveloperTools:"]

        if shouldBeEnabled {
            XCTAssertTrue(developerTools.isEnabled)
        } else {
            XCTAssertFalse(developerTools.isEnabled)
        }
    }
}
