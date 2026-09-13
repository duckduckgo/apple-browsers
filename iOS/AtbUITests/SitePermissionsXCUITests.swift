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

import CoreLocation
import Swifter
import XCTest

private extension XCUIElement {
    func waitForHittable(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND isHittable == true")
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: self)], timeout: timeout) == .completed
    }
}

/// Use the "iOS ATB UI Tests" scheme and select AtbUITests/SitePermissionsXCUITests.
/// The local fixture uses real WebKit media capture and the app's geolocation bridge.
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
        app.resetAuthorizationStatus(for: .microphone)
        app.resetAuthorizationStatus(for: .location)
        server["/camera"] = { _ in .ok(.html(Self.permissionsHTML)) }
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
        openPermissionPage()
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
        openPermissionPage()
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

        reloadPermissionPage()
        requestCamera()
        assertResult("success 1")
        assertNoPermissionPrompt()
    }

    func testWhenNeverAllowIsSavedThenRequestsAreDeniedUntilResetInSheet() {
        launchApp()
        openPermissionPage()
        requestCamera()
        tap(element("SitePermissions.Dialog.NeverAllow"))
        assertResult("NotAllowedError 1")

        reloadPermissionPage()
        requestCamera()
        assertResult("NotAllowedError 1")
        assertNoPermissionPrompt()
        openPermissionsSheet()
        tap(element("SitePermissions.Sheet.Camera"))
        tap(element("SitePermissions.Sheet.Camera.askEachTime"))
        XCTAssertTrue(element("SitePermissions.Sheet.ReloadCaption").waitForExistence(timeout: timeout))
        tap(element("SitePermissions.Sheet.Close"))
        reloadPermissionPage()
        requestCamera()
        assertSiteDialog()
    }

    func testWhenAllowOnceIsChosenThenGrantEndsOnReloadAndSiteIsNotListed() {
        launchApp()
        openPermissionPage()
        requestCamera()
        tap(element("SitePermissions.Dialog.AllowOnce"))
        answerSystemCameraAlert(allow: true)
        assertResult("success 1")

        // Begin a fresh browsing session with camera already authorized by iOS.
        app.terminate()
        launchApp()
        openPermissionPage()
        requestCamera()
        tap(element("SitePermissions.Dialog.AllowOnce"))
        assertResult("success 1")
        assertNoSystemAlert()
        requestCamera()
        assertResult("success 2")
        assertNoPermissionPrompt()
        reloadPermissionPage()
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
        openPermissionPage()
        requestCamera()
        tap(element("SitePermissions.Dialog.AllowOnce"))
        answerSystemCameraAlert(allow: false)
        assertResult("NotAllowedError 1")
        reloadPermissionPage()

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

    func testWhenMicrophoneIsAllowedThenSiteDialogPrecedesSystemPromptAndOnlyAudioIsGranted() {
        launchApp()
        openPermissionPage()
        requestMedia("microphone")
        assertSiteDialog(permission: "microphone")
        assertNoSystemAlert()
        tap(element("SitePermissions.Dialog.AllowWhileUsingSite"))
        answerSystemAlert(for: "microphone", allow: true)
        assertResult("success 1")
        assertResult("tracks video=0 audio=1")
        openPermissionsSheet()
        assertSheetDecision("Microphone", contains: "Always Allow")
        XCTAssertFalse(element("SitePermissions.Sheet.Camera").exists)
        tap(element("SitePermissions.Sheet.Close"))

        reloadPermissionPage()
        requestMedia("microphone")
        assertResult("success 1")
        assertResult("tracks video=0 audio=1")
        assertNoPermissionPrompt()
        requestCamera()
        assertSiteDialog(permission: "camera")
        assertNoSystemAlert()
        tap(element("SitePermissions.Dialog.AllowOnce"))
        answerSystemCameraAlert(allow: true)
        assertResult("success 2")
        assertResult("tracks video=1 audio=0")
    }

    func testWhenSystemMicrophoneIsDeniedThenReminderKeepsSiteAllowAndCameraStillWorks() {
        launchApp()
        openPermissionPage()
        requestMedia("microphone")
        tap(element("SitePermissions.Dialog.AllowOnce"))
        answerSystemAlert(for: "microphone", allow: false)
        assertResult("NotAllowedError 1")
        reloadPermissionPage()

        requestMedia("microphone")
        tap(element("SitePermissions.Dialog.AllowWhileUsingSite"))
        dismissReminder(for: "microphone")
        assertResult("NotAllowedError 1")
        openPermissionsSheet()
        assertSheetDecision("Microphone", contains: "Always Allow")
        XCTAssertFalse(element("SitePermissions.Sheet.Camera").exists)
        tap(element("SitePermissions.Sheet.Close"))
        requestCamera()
        assertSiteDialog(permission: "camera")
        tap(element("SitePermissions.Dialog.AllowOnce"))
        answerSystemCameraAlert(allow: true)
        assertResult("success 2")
        assertResult("tracks video=1 audio=0")
    }

    func testWhenCombinedMediaIsAllowedThenBothSystemPromptsAppearAndBothDecisionsPersist() {
        launchApp()
        openPermissionPage()
        requestMedia("camera and microphone")
        assertSiteDialog(permission: "camera and microphone")
        assertNoSystemAlert()
        tap(element("SitePermissions.Dialog.AllowWhileUsingSite"))
        answerSystemCameraAlert(allow: true)
        answerSystemAlert(for: "microphone", allow: true)
        assertResult("success 1")
        assertResult("tracks video=1 audio=1")
        openPermissionsSheet()
        assertSheetDecision("Camera", contains: "Always Allow")
        assertSheetDecision("Microphone", contains: "Always Allow")
        tap(element("SitePermissions.Sheet.Close"))

        reloadPermissionPage()
        requestMedia("camera and microphone")
        assertResult("success 1")
        assertResult("tracks video=1 audio=1")
        assertNoPermissionPrompt()
    }

    func testWhenCombinedMediaHasSystemMicrophoneDenialThenNeitherTrackIsGrantedAndCameraWorksIndependently() {
        launchApp()
        openPermissionPage()
        requestMedia("camera and microphone")
        tap(element("SitePermissions.Dialog.AllowWhileUsingSite"))
        answerSystemCameraAlert(allow: true)
        answerSystemAlert(for: "microphone", allow: false)
        assertResult("NotAllowedError 1")
        assertResult("tracks video=0 audio=0")
        reloadPermissionPage()

        requestMedia("camera and microphone")
        dismissReminder(for: "microphone")
        assertResult("NotAllowedError 1")
        openPermissionsSheet()
        assertSheetDecision("Camera", contains: "Always Allow")
        assertSheetDecision("Microphone", contains: "Always Allow")
        tap(element("SitePermissions.Sheet.Close"))
        requestCamera()
        assertResult("success 2")
        assertResult("tracks video=1 audio=0")
        assertNoPermissionPrompt()
    }

    func testWhenLocationIsAllowedThenSiteDialogPrecedesSystemPromptAndCoordinatesSurviveReload() throws {
        try simulateLocation(latitude: 37.3317, longitude: -122.0301)
        launchApp()
        openPermissionPage()
        requestLocation()
        assertSiteDialog(permission: "location")
        assertNoSystemAlert()
        tap(element("SitePermissions.Dialog.AllowWhileUsingSite"))
        answerSystemAlert(for: "location", allow: true)
        // maximumAge: 0 needs a fix timestamped after authorization and acquisition begin.
        try simulateLocation(latitude: 37.3317, longitude: -122.0301)
        assertResult("location success 1 37.3317,-122.0301")
        openPermissionsSheet()
        assertSheetDecision("Geolocation", contains: "Always Allow")
        tap(element("SitePermissions.Sheet.Close"))

        requestLocation()
        try simulateLocation(latitude: 37.3317, longitude: -122.0301)
        assertResult("location success 2 37.3317,-122.0301")
        assertNoPermissionPrompt()
        reloadPermissionPage()
        requestLocation()
        try simulateLocation(latitude: 37.3317, longitude: -122.0301)
        assertResult("location success 1 37.3317,-122.0301")
        assertNoPermissionPrompt()
    }

    func testWhenSystemLocationIsDeniedThenReminderKeepsSavedSiteAllow() {
        launchApp()
        openPermissionPage()
        requestLocation()
        tap(element("SitePermissions.Dialog.AllowOnce"))
        answerSystemAlert(for: "location", allow: false)
        assertResult("location error 1 1")
        reloadPermissionPage()

        requestLocation()
        tap(element("SitePermissions.Dialog.AllowWhileUsingSite"))
        dismissReminder(for: "location")
        assertResult("location error 1 1")
        openPermissionsSheet()
        assertSheetDecision("Geolocation", contains: "Always Allow")
        XCTAssertTrue(element("SitePermissions.Sheet.GoToSystemSettings").exists)
    }

    func testWhenActiveLocationWatchIsDeniedThenItStopsAndReallowDoesNotRestartIt() throws {
        try simulateLocation(latitude: 37.3317, longitude: -122.0301)
        launchApp()
        openPermissionPage()
        tap(app.webViews.buttons["Watch location"])
        tap(element("SitePermissions.Dialog.AllowWhileUsingSite"))
        answerSystemAlert(for: "location", allow: true)
        try simulateLocation(latitude: 37.3317, longitude: -122.0301)
        assertResult("watch success 37.3317,-122.0301")

        openPermissionsSheet()
        tap(element("SitePermissions.Sheet.Geolocation"))
        tap(element("SitePermissions.Sheet.Geolocation.neverAllow"))
        tap(element("SitePermissions.Sheet.Close"))
        assertResult("watch error 1")
        openPermissionsSheet()
        tap(element("SitePermissions.Sheet.Geolocation"))
        tap(element("SitePermissions.Sheet.Geolocation.alwaysAllow"))
        tap(element("SitePermissions.Sheet.Close"))
        requestLocation()
        try simulateLocation(latitude: 51.5007, longitude: -0.1246)
        assertResult("location success 1 51.5007,-0.1246")
        assertNoPermissionPrompt()
        // A new request proves delivery resumed; the old watch must remain terminated.
        let restartedWatch = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true"),
            object: app.webViews.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'watch success'")).firstMatch)
        restartedWatch.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [restartedWatch], timeout: 2), .completed)
        assertResult("watch error 1")
    }

    func testWhenCameraSettingsChangeThenMicrophoneAndLocationSettingsAreUnchanged() {
        launchApp(seedPermissions: "{ \"127.0.0.1\" = { camera = allow; microphone = deny; geolocation = allow; }; }")
        openPermissionPage()
        openPermissionsSheet()
        for option in ["neverAllow", "askEachTime"] {
            tap(element("SitePermissions.Sheet.Camera"))
            tap(element("SitePermissions.Sheet.Camera.\(option)"))
            assertSheetDecision("Camera", contains: option == "neverAllow" ? "Never Allow" : "Ask Each Time")
            assertSheetDecision("Microphone", contains: "Never Allow")
            assertSheetDecision("Geolocation", contains: "Always Allow")
        }
        tap(element("SitePermissions.Sheet.Close"))
        openPermissionSettings()
        for decision in ["deny", "ask"] {
            setGlobalDefault("camera", decision: decision)
            XCTAssertEqual(element("Settings.SitePermissions.Global.camera").value as? String,
                           decision == "deny" ? "Never Allow" : "Ask Each Time")
            XCTAssertEqual(element("Settings.SitePermissions.Global.microphone").value as? String, "Ask Each Time")
            XCTAssertEqual(element("Settings.SitePermissions.Global.geolocation").value as? String, "Ask Each Time")
        }
    }

    func testWhenFlagIsOffThenMicrophoneUsesWebKitDespiteSavedDenial() {
        assertWebKitMediaRollback(permission: "microphone")
    }

    func testWhenFlagIsOffThenCombinedMediaUsesWebKitDespiteSavedDenials() {
        assertWebKitMediaRollback(permission: "camera and microphone")
    }

    func testWhenFlagIsOffThenLocationUsesWebKitDespiteSavedDenial() throws {
        try simulateLocation(latitude: 37.3317, longitude: -122.0301)
        launchApp()
        openPermissionPage()
        requestLocation()
        tap(element("SitePermissions.Dialog.AllowWhileUsingSite"))
        answerSystemAlert(for: "location", allow: true)
        try simulateLocation(latitude: 37.3317, longitude: -122.0301)
        assertResult("location success 1 37.3317,-122.0301")

        // Establish OS authorization first so this checks the native site prompt independently.
        app.terminate()
        launchApp(flagEnabled: false, seedPermissions: "{ \"127.0.0.1\" = { geolocation = deny; }; }")
        openPermissionPage()
        requestLocation()
        let alert = app.alerts.containing(NSPredicate(format: "label CONTAINS[c] %@", "127.0.0.1")).firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: timeout), app.debugDescription)
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'location'")).firstMatch.exists)
        XCTAssertFalse(element("SitePermissions.Dialog").exists)
        tap(alert.buttons.matching(NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow"])).firstMatch)
        assertResult("location error 1 1")
        assertNoPermissionPrompt()
    }

    func testWhenFireClearsDataThenFireproofPermissionsAndGlobalDefaultsAreKept() {
        // These public DNS aliases resolve to loopback; all page content comes from our server.
        // For fully offline runs, map fireproof.lvh.me and clear.localtest.me to 127.0.0.1 in /etc/hosts.
        // ponytail: seed Fire setup; creating these decisions via prompts requires trusted local HTTPS.
        // Camera prompting and persistence are exercised separately without seeded state.
        let fireproofHost = "fireproof.lvh.me"
        let clearedHost = "clear.localtest.me"
        let decisions = "{ camera = allow; microphone = deny; geolocation = allow; }"
        launchApp(seedPermissions: "{ \"\(fireproofHost)\" = \(decisions); \"\(clearedHost)\" = \(decisions); }")
        openPermissionPage(host: fireproofHost)
        openMenu()
        let fireproofButton = app.buttons["Fireproof This Site"]
        scrollTo(fireproofButton)
        tap(fireproofButton)
        tap(app.sheets.buttons["Fireproof"])
        openPermissionSettings()
        XCTAssertTrue(element("Settings.SitePermissions.Site.\(fireproofHost)").waitForExistence(timeout: timeout))
        XCTAssertTrue(element("Settings.SitePermissions.Site.\(clearedHost)").exists)
        setGlobalDefault("camera", decision: "deny")
        setGlobalDefault("geolocation", decision: "deny")
        XCTAssertEqual(element("Settings.SitePermissions.Global.camera").value as? String, "Never Allow")
        closeSettings()

        tap(element("Browser.Toolbar.Button.Fire"))
        let confirm = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier IN %@", ["alert.forget-data.confirm", "Fire.Confirmation.Button.Delete"])).firstMatch
        tap(confirm)
        XCTAssertTrue(confirm.waitForNonExistence(timeout: timeout))
        // Fire does not always focus the search field; enter editing before dismissing it.
        tap(element("searchEntry"))
        tap(element("UnifiedToggleInput.Button.Dismiss"))
        openPermissionSettings()
        XCTAssertTrue(element("Settings.SitePermissions.Site.\(fireproofHost)").exists)
        XCTAssertFalse(element("Settings.SitePermissions.Site.\(clearedHost)").exists)
        XCTAssertEqual(element("Settings.SitePermissions.Global.camera").value as? String, "Never Allow")
        XCTAssertEqual(element("Settings.SitePermissions.Global.microphone").value as? String, "Ask Each Time")
        XCTAssertEqual(element("Settings.SitePermissions.Global.geolocation").value as? String, "Never Allow")
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

    private func openPermissionPage(host: String = "127.0.0.1") {
        tap(element("searchEntry"))
        let searchField = app.textFields.matching(identifier: "searchEntry").firstMatch
        XCTAssertTrue(searchField.waitForHittable(timeout: timeout))
        searchField.typeText("http://\(host):\(port)/camera\r")
        XCTAssertTrue(app.staticTexts["Permissions fixture"].waitForExistence(timeout: timeout), app.debugDescription)
        assertResult("ready")
    }

    private func reloadPermissionPage() {
        tap(app.webViews.buttons["Reload fixture"])
        assertResult("ready")
    }

    private func requestCamera() {
        requestMedia("camera")
    }

    private func requestMedia(_ permission: String) {
        tap(app.webViews.buttons["Request \(permission)"])
    }

    private func requestLocation() {
        tap(app.webViews.buttons["Request location"])
    }

    private func simulateLocation(latitude: Double, longitude: Double) throws {
        guard #available(iOS 16.4, *) else {
            throw XCTSkip("Deterministic device location requires iOS 16.4 or later")
        }
        let originalLocation = XCUIDevice.shared.location
        addTeardownBlock { XCUIDevice.shared.location = originalLocation }
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: latitude, longitude: longitude))
    }

    private func assertResult(_ result: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.webViews.staticTexts[result].waitForExistence(timeout: timeout), app.debugDescription, file: file, line: line)
    }

    private func assertSiteDialog(permission: String = "camera", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element("SitePermissions.Dialog").waitForExistence(timeout: timeout), file: file, line: line)
        XCTAssertEqual(element("SitePermissions.Dialog.Title").label, "“127.0.0.1” website wants to access your \(permission)",
                       file: file, line: line)
        for action in ["AllowOnce", "AllowWhileUsingSite", "NeverAllow"] {
            XCTAssertTrue(element("SitePermissions.Dialog.\(action)").exists, file: file, line: line)
        }
    }

    private func answerSystemCameraAlert(allow: Bool) {
        answerSystemAlert(for: "camera", allow: allow)
    }

    private func answerSystemAlert(for permission: String, allow: Bool) {
        // Match the permission so consecutive camera/microphone prompts do not share an element query.
        let systemAlert = springboard.alerts.containing(NSPredicate(format: "label CONTAINS[c] %@", permission)).firstMatch
        XCTAssertTrue(systemAlert.waitForExistence(timeout: timeout), springboard.debugDescription)
        let allowLabels = permission == "location" ? ["Allow While Using App", "Allow While Using the App"] : ["Allow", "OK"]
        let button = systemAlert.buttons.matching(NSPredicate(
            format: "label IN %@", allow ? allowLabels : ["Don’t Allow", "Don't Allow"])).firstMatch
        tap(button)
        XCTAssertTrue(systemAlert.waitForNonExistence(timeout: timeout))
    }

    private func dismissReminder(for permission: String) {
        XCTAssertTrue(element("SitePermissions.Reminder").waitForExistence(timeout: timeout))
        XCTAssertEqual(element("SitePermissions.Reminder.Title").label, "DuckDuckGo needs to access your \(permission)")
        XCTAssertTrue(element("SitePermissions.Reminder.ChangePermissions").exists)
        assertNoSystemAlert()
        tap(element("SitePermissions.Reminder.Cancel"))
    }

    private func assertSheetDecision(_ permission: String, contains value: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue((element("SitePermissions.Sheet.\(permission)").value as? String)?.contains(value) == true,
                      app.debugDescription, file: file, line: line)
    }

    private func setGlobalDefault(_ permission: String, decision: String) {
        // SwiftUI exposes a row-wide button, but only the trailing Menu label accepts taps.
        let menu = element("Settings.SitePermissions.Global.\(permission)").buttons.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: timeout))
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        tap(element("Settings.SitePermissions.Global.\(permission).\(decision)"))
    }

    private func assertWebKitMediaRollback(permission: String) {
        launchApp(flagEnabled: false, seedPermissions: "{ \"127.0.0.1\" = { camera = deny; microphone = deny; geolocation = deny; }; }")
        openPermissionPage()
        requestMedia(permission)
        let alert = app.alerts.containing(NSPredicate(format: "label CONTAINS[c] %@", "127.0.0.1")).firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: timeout), springboard.debugDescription)
        for name in permission.components(separatedBy: " and ") {
            XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch.exists)
        }
        XCTAssertFalse(element("SitePermissions.Dialog").exists)
        tap(alert.buttons.matching(NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow"])).firstMatch)
        assertResult("NotAllowedError 1")
        assertResult("tracks video=0 audio=0")
        assertNoPermissionPrompt()
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
        XCTAssertTrue(element("SitePermissions.Sheet").waitForExistence(timeout: timeout))
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
            // A clipped row can be hittable even when its tap target is offscreen.
            if element.isHittable && app.frame.contains(element.frame) { return }
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

    private static let permissionsHTML = """
    <!doctype html>
    <html lang="en">
    <head><meta name="viewport" content="width=device-width, initial-scale=1"><title>Permissions fixture</title></head>
    <body>
      <h1>Permissions fixture</h1>
      <button onclick="requestMedia({video: true})">Request camera</button>
      <button onclick="requestMedia({audio: true})">Request microphone</button>
      <button onclick="requestMedia({video: true, audio: true})">Request camera and microphone</button>
      <button onclick="requestLocation()">Request location</button>
      <button onclick="watchLocation()">Watch location</button>
      <button onclick="location.reload()">Reload fixture</button>
      <p id="result" role="status">ready</p>
      <p id="tracks" role="status">tracks video=0 audio=0</p>
      <p id="locationResult" role="status">location ready</p>
      <p id="watchResult" role="status">watch ready</p>
      <script>
        let requestCount = 0;
        let locationRequestCount = 0;
        const streams = [];
        async function requestMedia(constraints) {
          const count = ++requestCount;
          const result = document.getElementById('result');
          const tracks = document.getElementById('tracks');
          tracks.textContent = 'tracks video=0 audio=0';
          result.textContent = 'pending ' + count;
          try {
            const stream = await navigator.mediaDevices.getUserMedia(constraints);
            // Keep capture active for same-page Allow Once reuse; reload ends these streams.
            streams.push(stream);
            tracks.textContent = 'tracks video=' + stream.getVideoTracks().length + ' audio=' + stream.getAudioTracks().length;
            result.textContent = 'success ' + count;
          } catch (error) {
            result.textContent = error.name + ' ' + count;
          }
        }
        function coordinates(position) {
          return position.coords.latitude.toFixed(4) + ',' + position.coords.longitude.toFixed(4);
        }
        function requestLocation() {
          const count = ++locationRequestCount;
          const result = document.getElementById('locationResult');
          result.textContent = 'location pending ' + count;
          navigator.geolocation.getCurrentPosition(
            position => result.textContent = 'location success ' + count + ' ' + coordinates(position),
            error => result.textContent = 'location error ' + count + ' ' + error.code,
            {maximumAge: 0, timeout: 15000, enableHighAccuracy: true});
        }
        function watchLocation() {
          const result = document.getElementById('watchResult');
          result.textContent = 'watch pending';
          navigator.geolocation.watchPosition(
            position => result.textContent = 'watch success ' + coordinates(position),
            error => result.textContent = 'watch error ' + error.code,
            {maximumAge: 0, enableHighAccuracy: true});
        }
      </script>
    </body>
    </html>
    """
}
