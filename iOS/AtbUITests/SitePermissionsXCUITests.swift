//
//  SitePermissionsXCUITests.swift
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

private extension XCUIElement {
    func waitForHittable(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND isHittable == true")
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: self)], timeout: timeout) == .completed
    }
}

/// Use the "iOS ATB UI Tests" scheme and select AtbUITests/SitePermissionsXCUITests.
/// The fixture results come from the real WebKit getUserMedia implementation.
final class SitePermissionsXCUITests: XCTestCase {
    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let server = HttpServer()
    private let timeout: TimeInterval = 20
    private var port = 0

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.resetAuthorizationStatus(for: .camera)
        server["/camera"] = { _ in .ok(.html(Self.cameraHTML)) }
        server["/atb.js"] = { _ in .ok(.json(["version": "v1-1", "majorVersion": 1, "minorVersion": 1])) }
        server["/exti/"] = { _ in .accepted }
        server["/t/:pixelName"] = { _ in .accepted }
        try server.start(0, forceIPv4: true, priority: .userInitiated)
        port = try server.port()
    }

    override func tearDownWithError() throws {
        app.terminate()
        server.stop()
        try super.tearDownWithError()
    }

    func testWhenFlagIsOffThenWebKitPromptsAndPermissionManagementIsHidden() {
        // Existing records must stay hidden after rollback too.
        launchApp(flagEnabled: false, seedPermissions: "{ \"127.0.0.1\" = { camera = allow; }; }")
        openCameraPage()
        requestCamera()

        let webKitAlert = app.alerts.containing(NSPredicate(format: "label CONTAINS[c] %@", "127.0.0.1")).firstMatch
        XCTAssertTrue(webKitAlert.waitForExistence(timeout: timeout), app.debugDescription)
        XCTAssertTrue(webKitAlert.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'camera'")).firstMatch.exists)
        XCTAssertFalse(element("SitePermissions.Dialog").exists)
        webKitAlert.buttons["Don’t Allow"].tap()

        openMenu()
        XCTAssertFalse(element("BrowsingMenu.SitePermissions").exists)
        tap(app.buttons["Settings"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: timeout))
        // Settings uses lazy list cells; inspect each viewport instead of only the initial screen.
        for _ in 0..<6 {
            XCTAssertFalse(element("Settings.SitePermissions").exists)
            app.swipeUp()
        }
        XCTAssertFalse(element("Settings.SitePermissions").exists)
    }

    func testWhenCameraIsAllowedThenSiteDialogPrecedesSystemPromptAndDecisionPersists() {
        launchApp()
        openCameraPage()
        requestCamera()
        assertSiteDialog()
        assertNoSystemAlert()

        tap(element("SitePermissions.Dialog.AllowWhileUsingSite"))
        answerSystemCameraAlert(allow: true)
        assertResult("success 1")
        openPermissionsSheet()
        XCTAssertTrue((element("SitePermissions.Sheet.Camera").value as? String)?.contains("Always Allow") == true)
        tap(element("SitePermissions.Sheet.Close"))
        openPermissionSettings()
        XCTAssertTrue(element("Settings.SitePermissions.Site.127.0.0.1").exists)
        closeSettings()

        reloadCameraPage()
        requestCamera()
        assertResult("success 1")
        assertNoPermissionPrompt()
    }

    func testWhenNeverAllowIsSavedThenRequestsAreDeniedUntilResetInSheet() {
        launchApp()
        openCameraPage()
        requestCamera()
        tap(element("SitePermissions.Dialog.NeverAllow"))
        assertResult("NotAllowedError 1")

        reloadCameraPage()
        requestCamera()
        assertResult("NotAllowedError 1")
        assertNoPermissionPrompt()
        openPermissionsSheet()
        tap(element("SitePermissions.Sheet.Camera"))
        tap(element("SitePermissions.Sheet.Camera.askEachTime"))
        XCTAssertTrue(element("SitePermissions.Sheet.ReloadCaption").waitForExistence(timeout: timeout))
        tap(element("SitePermissions.Sheet.Close"))
        reloadCameraPage()
        requestCamera()
        assertSiteDialog()
    }

    func testWhenAllowOnceIsChosenThenGrantEndsOnReloadAndSiteIsNotListed() {
        launchApp()
        openCameraPage()
        requestCamera()
        tap(element("SitePermissions.Dialog.AllowOnce"))
        answerSystemCameraAlert(allow: true)
        assertResult("success 1")

        // Begin a fresh browsing session with camera already authorized by iOS.
        app.terminate()
        launchApp()
        openCameraPage()
        requestCamera()
        tap(element("SitePermissions.Dialog.AllowOnce"))
        assertResult("success 1")
        assertNoSystemAlert()
        requestCamera()
        assertResult("success 2")
        assertNoPermissionPrompt()
        reloadCameraPage()
        requestCamera()
        assertSiteDialog()
        tap(element("SitePermissions.Dialog.AllowOnce"))
        assertResult("success 1")
        assertNoSystemAlert()
        openPermissionSettings()
        XCTAssertFalse(element("Settings.SitePermissions.Site.127.0.0.1").exists)
    }

    func testWhenSystemCameraIsDeniedThenReminderAppearsAndSiteAllowIsKept() {
        launchApp()
        openCameraPage()
        requestCamera()
        tap(element("SitePermissions.Dialog.AllowOnce"))
        answerSystemCameraAlert(allow: false)
        assertResult("NotAllowedError 1")
        reloadCameraPage()

        requestCamera()
        tap(element("SitePermissions.Dialog.AllowWhileUsingSite"))
        XCTAssertTrue(element("SitePermissions.Reminder").waitForExistence(timeout: timeout))
        XCTAssertTrue(element("SitePermissions.Reminder.ChangePermissions").exists)
        XCTAssertTrue(element("SitePermissions.Reminder.Cancel").exists)
        assertNoSystemAlert()
        tap(element("SitePermissions.Reminder.Cancel"))
        assertResult("NotAllowedError 1")
        openPermissionsSheet()
        XCTAssertTrue(element("SitePermissions.Sheet.Reminder").exists)
        XCTAssertTrue(element("SitePermissions.Sheet.GoToSystemSettings").exists)
        XCTAssertTrue((element("SitePermissions.Sheet.Camera").value as? String)?.contains("Always Allow") == true)
    }

    func testWhenFireClearsDataThenFireproofPermissionsAndGlobalDefaultsAreKept() {
        // These public DNS aliases resolve to loopback; all page content comes from our server.
        // For fully offline runs, map fireproof.lvh.me and clear.localtest.me to 127.0.0.1 in /etc/hosts.
        // ponytail: seed Fire setup; creating these decisions via prompts requires trusted local HTTPS.
        // Camera prompting and persistence are exercised separately without seeded state.
        let fireproofHost = "fireproof.lvh.me"
        let clearedHost = "clear.localtest.me"
        launchApp(seedPermissions: "{ \"\(fireproofHost)\" = { camera = allow; }; \"\(clearedHost)\" = { camera = allow; }; }")
        openCameraPage(host: fireproofHost)
        openMenu()
        let fireproofButton = app.buttons["Fireproof This Site"]
        scrollTo(fireproofButton)
        tap(fireproofButton)
        tap(app.sheets.buttons["Fireproof"])
        openPermissionSettings()
        XCTAssertTrue(element("Settings.SitePermissions.Site.\(fireproofHost)").waitForExistence(timeout: timeout))
        XCTAssertTrue(element("Settings.SitePermissions.Site.\(clearedHost)").exists)
        // SwiftUI exposes a row-wide button, but only the trailing Menu label accepts taps.
        let cameraMenu = element("Settings.SitePermissions.Global.camera").buttons.firstMatch
        XCTAssertTrue(cameraMenu.waitForExistence(timeout: timeout))
        cameraMenu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        tap(element("Settings.SitePermissions.Global.camera.deny"))
        XCTAssertEqual(element("Settings.SitePermissions.Global.camera").value as? String, "Never Allow")
        closeSettings()

        tap(element("Browser.Toolbar.Button.Fire"))
        let confirm = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier IN %@", ["alert.forget-data.confirm", "Fire.Confirmation.Button.Delete"])).firstMatch
        tap(confirm)
        XCTAssertTrue(confirm.waitForNonExistence(timeout: timeout))
        tap(element("UnifiedToggleInput.Button.Dismiss"))
        openPermissionSettings()
        XCTAssertTrue(element("Settings.SitePermissions.Site.\(fireproofHost)").exists)
        XCTAssertFalse(element("Settings.SitePermissions.Site.\(clearedHost)").exists)
        XCTAssertEqual(element("Settings.SitePermissions.Global.camera").value as? String, "Never Allow")
    }

    private func launchApp(flagEnabled: Bool = true, seedPermissions: String? = nil) {
        app.launchArguments = [
            "-clearAllDefaults", "isRunningUITests",
            "-isOnboardingCompleted", "true", "-isInternalUser", "true",
            "-ff.sitePermissions", String(flagEnabled),
            "-ff.floatingUIAugust2026", "true",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_GB"
        ]
        if let seedPermissions {
            app.launchArguments += ["-sitePermissionsTestSeed", seedPermissions]
        }
        app.launchEnvironment = [
            "UITEST_MODE": "1", "BASE_URL": "http://127.0.0.1:\(port)", "PIXEL_BASE_URL": "http://127.0.0.1:\(port)"
        ]
        app.launch()
        XCTAssertTrue(element("searchEntry").waitForHittable(timeout: timeout))
    }

    private func openCameraPage(host: String = "127.0.0.1") {
        tap(element("searchEntry"))
        let searchField = app.textFields.matching(identifier: "searchEntry").firstMatch
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
        searchField.typeText("http://\(host):\(port)/camera\r")
        XCTAssertTrue(app.staticTexts["Camera fixture"].waitForExistence(timeout: timeout), app.debugDescription)
        assertResult("ready")
    }

    private func reloadCameraPage() {
        tap(app.webViews.buttons["Reload fixture"])
        assertResult("ready")
    }

    private func requestCamera() {
        tap(app.webViews.buttons["Request camera"])
    }

    private func assertResult(_ result: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.webViews.staticTexts[result].waitForExistence(timeout: timeout), app.debugDescription, file: file, line: line)
    }

    private func assertSiteDialog(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element("SitePermissions.Dialog").waitForExistence(timeout: timeout), file: file, line: line)
        for action in ["AllowOnce", "AllowWhileUsingSite", "NeverAllow"] {
            XCTAssertTrue(element("SitePermissions.Dialog.\(action)").exists, file: file, line: line)
        }
    }

    private func answerSystemCameraAlert(allow: Bool) {
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: timeout), springboard.debugDescription)
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'camera'")).firstMatch.exists)
        let button = allow ? alert.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "OK"])).firstMatch
            : alert.buttons.matching(NSPredicate(format: "label IN %@", ["Don’t Allow", "Don\'t Allow"])).firstMatch
        tap(button)
        XCTAssertTrue(alert.waitForNonExistence(timeout: timeout))
    }

    private func assertNoSystemAlert(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(springboard.alerts.firstMatch.exists, file: file, line: line)
    }

    private func assertNoPermissionPrompt(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(element("SitePermissions.Dialog").exists, file: file, line: line)
        XCTAssertFalse(app.alerts.firstMatch.exists, file: file, line: line)
        assertNoSystemAlert(file: file, line: line)
    }

    private func openMenu() {
        tap(element("Browser.Toolbar.Button.Menu"))
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: timeout))
    }

    private func openPermissionsSheet() {
        openMenu()
        tap(element("BrowsingMenu.SitePermissions"))
        XCTAssertTrue(element("SitePermissions.Sheet.Camera").waitForExistence(timeout: timeout))
    }

    private func openPermissionSettings() {
        openMenu()
        tap(app.buttons["Settings"])
        openSitePermissionSettingsEntry()
        XCTAssertTrue(element("Settings.SitePermissions.Global.camera").waitForExistence(timeout: timeout))
    }

    private func openSitePermissionSettingsEntry() {
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: timeout))
        let entry = element("Settings.SitePermissions")
        scrollTo(entry)
        tap(entry)
    }

    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<6 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }

    private func closeSettings() {
        tap(app.navigationBars.buttons["Settings"])
        tap(app.buttons["Done"])
        XCTAssertTrue(element("searchEntry").waitForHittable(timeout: timeout))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForHittable(timeout: timeout), app.debugDescription, file: file, line: line)
        element.tap()
    }

    private static let cameraHTML = """
    <!doctype html>
    <html lang="en">
    <head><meta name="viewport" content="width=device-width, initial-scale=1"><title>Camera fixture</title></head>
    <body>
      <h1>Camera fixture</h1>
      <button onclick="requestCamera()">Request camera</button>
      <button onclick="location.reload()">Reload fixture</button>
      <p id="result" role="status">ready</p>
      <script>
        let requestCount = 0;
        const streams = [];
        async function requestCamera() {
          const count = ++requestCount;
          const result = document.getElementById('result');
          result.textContent = 'pending ' + count;
          try {
            const stream = await navigator.mediaDevices.getUserMedia({video: true});
            // Keep capture active for same-page Allow Once reuse; reload ends these streams.
            streams.push(stream);
            result.textContent = 'success ' + count;
          } catch (error) {
            result.textContent = error.name + ' ' + count;
          }
        }
      </script>
    </body>
    </html>
    """
}
