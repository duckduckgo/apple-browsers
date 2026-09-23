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

/// Run with the "iOS Site Permissions UI Tests" scheme; the "iOS ATB UI Tests" scheme skips this class.
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
        request("camera")
        denyWebKitPrompt(for: "camera")

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
        request("camera")
        assertSiteDialog()

        tap(element("SitePermissions.Dialog.AllowWhileUsingSite"))
        answerSystemAlert(for: "camera", allow: true)
        assertResult("success 1")
        openPermissionsSheet()
        XCTAssertTrue((element("SitePermissions.Sheet.Camera").value as? String)?.contains("Always Allow") == true)
        tap(element("SitePermissions.Sheet.Close"))
        openPermissionSettings()
        XCTAssertTrue(element("Settings.SitePermissions.Site.127.0.0.1").exists)
        closeSettings()

        reloadPermissionPage()
        request("camera")
        assertResult("success 1")
        assertNoPermissionPrompt()
    }

    func testWhenNeverAllowIsSavedThenRequestsAreDeniedUntilResetInSheet() {
        assertReloadCaptionAfterResettingPermission("camera", row: "Camera")
    }

    func testWhenMicrophoneChangesInSheetThenReloadCaptionAppearsAndReloadUsesNewDecision() {
        assertReloadCaptionAfterResettingPermission("microphone", row: "Microphone")
    }

    func testWhenLocationChangesInSheetThenReloadCaptionAppearsAndReloadUsesNewDecision() {
        assertReloadCaptionAfterResettingPermission("location", row: "Geolocation")
    }

    func testWhenAllowOnceIsChosenThenGrantEndsOnReloadAndSiteIsNotListed() {
        launchApp()
        openPermissionPage()
        request("camera")
        tap(element("SitePermissions.Dialog.AllowOnce"))
        answerSystemAlert(for: "camera", allow: true)
        assertResult("success 1")

        // Begin a fresh browsing session with camera already authorized by iOS.
        app.terminate()
        launchApp()
        openPermissionPage()
        request("camera")
        tap(element("SitePermissions.Dialog.AllowOnce"))
        assertResult("success 1")
        assertNoSystemAlert()
        request("camera")
        assertResult("success 2")
        assertNoPermissionPrompt()
        reloadPermissionPage()
        request("camera")
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
        request("camera")
        tap(element("SitePermissions.Dialog.AllowOnce"))
        answerSystemAlert(for: "camera", allow: false)
        assertResult("NotAllowedError 1")
        reloadPermissionPage()

        request("camera")
        tap(element("SitePermissions.Dialog.AllowWhileUsingSite"))
        dismissReminder(for: "camera")
        assertResult("NotAllowedError 1")
        openPermissionsSheet()
        XCTAssertTrue(element("SitePermissions.Sheet.Reminder").exists)
        XCTAssertTrue(element("SitePermissions.Sheet.GoToSystemSettings").exists)
        XCTAssertTrue((element("SitePermissions.Sheet.Camera").value as? String)?.contains("Always Allow") == true)
    }

    func testWhenMicrophoneIsAllowedThenSiteDialogPrecedesSystemPromptAndOnlyAudioIsGranted() {
        launchApp()
        openPermissionPage()
        request("microphone")
        assertSiteDialog(permission: "microphone")
        tap(element("SitePermissions.Dialog.AllowWhileUsingSite"))
        answerSystemAlert(for: "microphone", allow: true)
        assertResult("success 1")
        assertResult("tracks video=0 audio=1")
        openPermissionsSheet()
        assertSheetDecision("Microphone", contains: "Always Allow")
        XCTAssertFalse(element("SitePermissions.Sheet.Camera").exists)
        tap(element("SitePermissions.Sheet.Close"))

        reloadPermissionPage()
        request("microphone")
        assertResult("success 1")
        assertResult("tracks video=0 audio=1")
        assertNoPermissionPrompt()
        request("camera")
        assertSiteDialog(permission: "camera")
        tap(element("SitePermissions.Dialog.AllowOnce"))
        answerSystemAlert(for: "camera", allow: true)
        assertResult("success 2")
        assertResult("tracks video=1 audio=0")
    }

    func testWhenSystemMicrophoneIsDeniedThenReminderKeepsSiteAllowAndCameraStillWorks() {
        launchApp()
        openPermissionPage()
        request("microphone")
        tap(element("SitePermissions.Dialog.AllowOnce"))
        answerSystemAlert(for: "microphone", allow: false)
        assertResult("NotAllowedError 1")
        reloadPermissionPage()

        request("microphone")
        tap(element("SitePermissions.Dialog.AllowWhileUsingSite"))
        dismissReminder(for: "microphone")
        assertResult("NotAllowedError 1")
        openPermissionsSheet()
        assertSheetDecision("Microphone", contains: "Always Allow")
        XCTAssertFalse(element("SitePermissions.Sheet.Camera").exists)
        tap(element("SitePermissions.Sheet.Close"))
        request("camera")
        assertSiteDialog(permission: "camera")
        tap(element("SitePermissions.Dialog.AllowOnce"))
        answerSystemAlert(for: "camera", allow: true)
        assertResult("success 2")
        assertResult("tracks video=1 audio=0")
    }

    func testWhenPrivateVoiceSearchLosesMicrophoneAccessThenReminderCanCancelOrHideVoiceSearch() {
        showAndCancelVoicePermissionReminder(duckAI: false, isVoiceChat: false)
        tap(element("Browser.OmniBar.Button.VoiceSearch"))
        assertVoicePermissionReminder(isVoiceChat: false)
        tap(element("SitePermissions.Reminder.HideVoiceSearch"))
        XCTAssertTrue(element("SitePermissions.Reminder").waitForNonExistence(timeout: timeout))
        XCTAssertTrue(element("Browser.OmniBar.Button.VoiceSearch").waitForNonExistence(timeout: timeout))
        tap(element("UnifiedToggleInput.Button.Dismiss"))
        assertResult("tracks video=0 audio=0")
        openVoiceSearchSettings()
        XCTAssertEqual(voiceSearchSwitch.value as? String, "0")
    }

    func testWhenDuckAIDictationLosesMicrophoneAccessThenPrivateVoiceSearchReminderAppears() {
        showAndCancelVoicePermissionReminder(duckAI: true, isVoiceChat: false)
        tap(element("UnifiedToggleInput.Button.Dismiss"))
        assertResult("NotAllowedError 1")
        assertResult("tracks video=0 audio=0")
    }

    func testWhenDuckAIVoiceChatLosesMicrophoneAccessThenVoiceChatReminderAppearsWithoutOpeningChat() {
        showAndCancelVoicePermissionReminder(duckAI: true, isVoiceChat: true)
        tap(element("UnifiedToggleInput.Button.Dismiss"))
        assertResult("NotAllowedError 1")
        assertResult("tracks video=0 audio=0")
    }

    func testWhenCombinedMediaIsAllowedThenBothSystemPromptsAppearAndBothDecisionsPersist() {
        launchApp()
        openPermissionPage()
        request("camera and microphone")
        assertSiteDialog(permission: "camera and microphone")
        tap(element("SitePermissions.Dialog.AllowWhileUsingSite"))
        answerSystemAlert(for: "camera", allow: true)
        answerSystemAlert(for: "microphone", allow: true)
        assertResult("success 1")
        assertResult("tracks video=1 audio=1")
        openPermissionsSheet()
        assertSheetDecision("Camera", contains: "Always Allow")
        assertSheetDecision("Microphone", contains: "Always Allow")
        tap(element("SitePermissions.Sheet.Close"))

        reloadPermissionPage()
        request("camera and microphone")
        assertResult("success 1")
        assertResult("tracks video=1 audio=1")
        assertNoPermissionPrompt()
    }

    func testWhenCombinedMediaHasSystemCameraDenialThenNeitherTrackIsGrantedAndMicrophoneWorksIndependently() {
        assertCombinedMediaFailsAfterSystemDenial(of: "camera")
    }

    func testWhenCombinedMediaHasSystemMicrophoneDenialThenNeitherTrackIsGrantedAndCameraWorksIndependently() {
        assertCombinedMediaFailsAfterSystemDenial(of: "microphone")
    }

    func testWhenCombinedPromptIsNeverAllowedThenRunningAllowOnceCameraStops() {
        launchApp()
        openPermissionPage()
        request("camera")
        tap(element("SitePermissions.Dialog.AllowOnce"))
        answerSystemAlert(for: "camera", allow: true)
        assertResult("success 1")
        assertResult("live video=1 audio=0")

        // The running Allow Once camera passes the site check, so only the microphone asks, as a combined prompt.
        request("camera and microphone")
        assertSiteDialog(permission: "camera and microphone")
        tap(element("SitePermissions.Dialog.NeverAllow"))
        assertResult("NotAllowedError 2")
        assertResult("live video=0 audio=0")
        openPermissionsSheet()
        XCTAssertEqual(element("SitePermissions.Sheet.Camera").value as? String, "Never Allow")
        XCTAssertEqual(element("SitePermissions.Sheet.Microphone").value as? String, "Never Allow")
    }

    func testWhenLocationIsAllowedThenSiteDialogPrecedesSystemPromptAndCoordinatesSurviveReload() throws {
        try simulateLocation(latitude: 37.3317, longitude: -122.0301)
        launchApp()
        openPermissionPage()
        request("location")
        assertSiteDialog(permission: "location")
        tap(element("SitePermissions.Dialog.AllowWhileUsingSite"))
        answerSystemAlert(for: "location", allow: true)
        // maximumAge: 0 needs a fix timestamped after authorization and acquisition begin.
        try simulateLocation(latitude: 37.3317, longitude: -122.0301)
        assertResult("location success 1 37.3317,-122.0301")
        openPermissionsSheet()
        assertSheetDecision("Geolocation", contains: "Always Allow")
        tap(element("SitePermissions.Sheet.Close"))

        request("location")
        try simulateLocation(latitude: 37.3317, longitude: -122.0301)
        assertResult("location success 2 37.3317,-122.0301")
        assertNoPermissionPrompt()
        reloadPermissionPage()
        request("location")
        try simulateLocation(latitude: 37.3317, longitude: -122.0301)
        assertResult("location success 1 37.3317,-122.0301")
        assertNoPermissionPrompt()
    }

    func testWhenSystemLocationIsDeniedThenReminderKeepsSavedSiteAllow() {
        launchApp()
        openPermissionPage()
        request("location")
        tap(element("SitePermissions.Dialog.AllowOnce"))
        answerSystemAlert(for: "location", allow: false)
        assertResult("location error 1 1")
        reloadPermissionPage()

        request("location")
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
        tap(app.buttons["Never Allow"])
        tap(element("SitePermissions.Sheet.Close"))
        assertResult("watch error 1")
        openPermissionsSheet()
        tap(element("SitePermissions.Sheet.Geolocation"))
        tap(app.buttons["Always Allow"])
        tap(element("SitePermissions.Sheet.Close"))
        request("location")
        try simulateLocation(latitude: 51.5007, longitude: -0.1246)
        assertResult("location success 1 51.5007,-0.1246")
        assertNoPermissionPrompt()
        // A new request proves delivery resumed; the old watch must remain terminated.
        let restartedWatch = app.webViews.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'watch success'")).firstMatch
        XCTAssertFalse(restartedWatch.waitForExistence(timeout: 2))
        assertResult("watch error 1")
    }

    func testWhenCameraSettingsChangeThenMicrophoneAndLocationSettingsAreUnchanged() {
        launchApp(seedPermissions: "{ \"127.0.0.1\" = { camera = allow; microphone = deny; geolocation = allow; }; }")
        openPermissionPage()
        openPermissionsSheet()
        let sheetScreenshot = XCTAttachment(screenshot: app.screenshot())
        sheetScreenshot.name = "Permissions sheet"
        sheetScreenshot.lifetime = .keepAlways
        add(sheetScreenshot)
        var selectedOption = "Always Allow"
        for option in ["Never Allow", "Ask Each Time"] {
            tap(element("SitePermissions.Sheet.Camera"))
            XCTAssertTrue(app.buttons[selectedOption].waitForExistence(timeout: timeout))
            XCTAssertTrue(app.buttons[selectedOption].isSelected)
            let pickerScreenshot = XCTAttachment(screenshot: app.screenshot())
            pickerScreenshot.name = "Permission picker - \(selectedOption)"
            pickerScreenshot.lifetime = .keepAlways
            add(pickerScreenshot)
            tap(app.buttons[option])
            assertSheetDecision("Camera", contains: option)
            assertSheetDecision("Microphone", contains: "Never Allow")
            assertSheetDecision("Geolocation", contains: "Always Allow")
            selectedOption = option
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

    func testWhenRemovalIsUndoneThenPermissionsSheetReopensForTheSite() {
        launchApp(seedPermissions: "{ \"127.0.0.1\" = { camera = allow; microphone = deny; }; }")
        openPermissionPage()
        openPermissionsSheet()
        tap(element("SitePermissions.Sheet.RemovePermissions"))
        XCTAssertTrue(element("SitePermissions.Sheet").waitForNonExistence(timeout: timeout))

        tap(element("SitePermissions.Toast.Undo"))

        XCTAssertTrue(element("SitePermissions.Sheet").waitForExistence(timeout: timeout))
        XCTAssertEqual(element("SitePermissions.Sheet.Title").label, "Permissions for “127.0.0.1”")
        assertSheetDecision("Camera", contains: "Always Allow")
        assertSheetDecision("Microphone", contains: "Never Allow")
        tap(element("SitePermissions.Sheet.Close"))
        assertResult("tracks video=0 audio=0")
    }

    func testWhenSavedPermissionsAreResetToAskThenSettingsKeepsExplicitDecisions() {
        launchApp(seedPermissions: "{ \"127.0.0.1\" = { camera = allow; microphone = deny; }; }")
        openPermissionPage()
        openPermissionsSheet()
        assertSheetDecision("Camera", contains: "Always Allow")
        assertSheetDecision("Microphone", contains: "Never Allow")
        tap(element("SitePermissions.Sheet.Microphone"))
        tap(app.buttons["Ask Each Time"])
        assertSheetDecision("Microphone", contains: "Ask Each Time")
        tap(element("SitePermissions.Sheet.Close"))
        openPermissionSettings()
        tap(element("Settings.SitePermissions.Site.127.0.0.1"))

        XCTAssertTrue(element("Settings.SitePermissions.Site.camera").waitForExistence(timeout: timeout))
        XCTAssertEqual(element("Settings.SitePermissions.Site.camera").value as? String, "Always Allow")
        XCTAssertEqual(element("Settings.SitePermissions.Site.microphone").value as? String, "Ask Each Time")
        XCTAssertFalse(element("Settings.SitePermissions.Site.geolocation").exists)

        let cameraPicker = element("Settings.SitePermissions.Site.camera").buttons.firstMatch
        XCTAssertTrue(cameraPicker.waitForExistence(timeout: timeout))
        cameraPicker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        tap(app.buttons["Ask Each Time"])
        XCTAssertEqual(element("Settings.SitePermissions.Site.camera").value as? String, "Ask Each Time")
        tap(app.navigationBars.buttons["Site Permissions"])
        tap(element("Settings.SitePermissions.Site.127.0.0.1"))
        XCTAssertEqual(element("Settings.SitePermissions.Site.camera").value as? String, "Ask Each Time")
        XCTAssertEqual(element("Settings.SitePermissions.Site.microphone").value as? String, "Ask Each Time")
        XCTAssertFalse(element("Settings.SitePermissions.Site.geolocation").exists)
        tap(app.navigationBars.buttons["Site Permissions"])
        closeSettings()
        openPermissionsSheet()
        assertSheetDecision("Camera", contains: "Ask Each Time")
        assertSheetDecision("Microphone", contains: "Ask Each Time")
        XCTAssertFalse(element("SitePermissions.Sheet.Geolocation").exists)
    }

    func testWhenFlagIsOffThenCombinedMediaUsesWebKitDespiteSavedDenials() {
        assertWebKitMediaRollback(permission: "camera and microphone")
    }

    func testWhenFlagIsOffThenLocationUsesWebKitDespiteSavedDenial() throws {
        try simulateLocation(latitude: 37.3317, longitude: -122.0301)
        launchApp()
        openPermissionPage()
        request("location")
        tap(element("SitePermissions.Dialog.AllowWhileUsingSite"))
        answerSystemAlert(for: "location", allow: true)
        try simulateLocation(latitude: 37.3317, longitude: -122.0301)
        assertResult("location success 1 37.3317,-122.0301")

        // Establish OS authorization first so this checks the native site prompt independently.
        app.terminate()
        launchApp(flagEnabled: false, seedPermissions: "{ \"127.0.0.1\" = { geolocation = deny; }; }")
        openPermissionPage()
        request("location")
        denyWebKitPrompt(for: "location")
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

    func testWhenSettingsVoiceSearchMicrophoneIsDeniedThenReminderDismissesAndOpensSystemSettings() {
        launchApp()
        openVoiceSearchSettings()
        enablePrivateVoiceSearch()
        answerSystemAlert(for: "microphone", allow: false)

        let reminder = element("SitePermissions.Reminder")
        XCTAssertTrue(reminder.waitForExistence(timeout: timeout))
        XCTAssertEqual(element("SitePermissions.Reminder.Title").label, "DuckDuckGo needs to access your microphone")
        XCTAssertTrue(app.staticTexts["Microphone permissions are needed if you want to use our private voice features."].exists)
        XCTAssertFalse(element("SitePermissions.Reminder.HideVoiceSearch").exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        XCTAssertTrue(reminder.waitForNonExistence(timeout: timeout))

        enablePrivateVoiceSearch()
        tap(element("SitePermissions.Reminder.Cancel"))
        XCTAssertTrue(reminder.waitForNonExistence(timeout: timeout))
        assertNoSystemAlert()

        enablePrivateVoiceSearch()
        tap(element("SitePermissions.Reminder.ChangePermissions"))
        XCTAssertTrue(XCUIApplication(bundleIdentifier: "com.apple.Preferences").wait(for: .runningForeground, timeout: timeout))
    }

    func testWhenSettingsVoiceSearchMicrophoneIsDeniedWithFeatureOffThenLegacyAlertIsUsed() {
        launchApp(flagEnabled: false)
        openVoiceSearchSettings()
        enablePrivateVoiceSearch()
        answerSystemAlert(for: "microphone", allow: false)

        let alert = app.alerts["Microphone Access Required"]
        XCTAssertTrue(alert.waitForExistence(timeout: timeout))
        XCTAssertTrue(alert.staticTexts["Please allow Microphone access in iOS System Settings for DuckDuckGo to use voice features."].exists)
        XCTAssertEqual(alert.buttons.count, 1)
        XCTAssertFalse(element("SitePermissions.Reminder").exists)
        tap(alert.buttons["OK"])
        XCTAssertTrue(alert.waitForNonExistence(timeout: timeout))

        enablePrivateVoiceSearch()
        XCTAssertTrue(alert.waitForExistence(timeout: timeout))
        assertNoSystemAlert()
        tap(alert.buttons["OK"])
    }

    private func showAndCancelVoicePermissionReminder(duckAI: Bool, isVoiceChat: Bool) {
        prepareVoiceSearchWithDeniedMicrophone()
        openEmptyVoiceSearchInput(duckAI: duckAI)
        tap(element(isVoiceChat ? "AIChat.Toolbar.Button.Submit" : "Browser.OmniBar.Button.VoiceSearch"))
        assertVoicePermissionReminder(isVoiceChat: isVoiceChat)

        tap(element("SitePermissions.Reminder.Cancel"))
        XCTAssertTrue(element("SitePermissions.Reminder").waitForNonExistence(timeout: timeout))
        XCTAssertTrue(element("Browser.OmniBar.Button.VoiceSearch").waitForHittable(timeout: timeout))
        assertNoPermissionPrompt()
    }

    private func prepareVoiceSearchWithDeniedMicrophone() {
        launchApp(additionalArguments: ["-ff.utiDuckAIWarnings", "false"])
        enableDuckAIInput()
        openVoiceSearchSettings()
        XCTAssertEqual(voiceSearchSwitch.value as? String, "0")
        // iOS 26 reports the nested switch's frame away from the drawn toggle, so tap the toggle through its row.
        let voiceSearchRow = app.switches["Private Voice Search"].firstMatch
        XCTAssertTrue(voiceSearchRow.waitForHittable(timeout: timeout))
        voiceSearchRow.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        answerSystemAlert(for: "microphone", allow: true)
        let voiceSearchEnabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: voiceSearchSwitch)
        XCTAssertEqual(XCTWaiter.wait(for: [voiceSearchEnabled], timeout: timeout), .completed)
        closeSettings()

        // Keep the enabled preference while arranging the same iOS denial as revoking access in Settings.
        app.terminate()
        app.resetAuthorizationStatus(for: .microphone)
        app.launchArguments.removeAll { $0 == "-clearAllDefaults" }
        app.launch()
        XCTAssertTrue(element("searchEntry").waitForHittable(timeout: timeout))
        openPermissionPage()
        request("microphone")
        tap(element("SitePermissions.Dialog.AllowOnce"))
        answerSystemAlert(for: "microphone", allow: false)
        assertResult("NotAllowedError 1")
        assertResult("tracks video=0 audio=0")
        openVoiceSearchSettings()
        XCTAssertEqual(voiceSearchSwitch.value as? String, "1")
        closeSettings()
    }

    private func enableDuckAIInput() {
        openSettings()
        let aiFeatures = app.staticTexts["AI Features"]
        scrollTo(aiFeatures)
        tap(aiFeatures)
        XCTAssertTrue(app.navigationBars["AI Features"].waitForExistence(timeout: timeout))
        let enableToggle = element("Settings.AIFeatures.EnableToggle")
        scrollTo(enableToggle)
        XCTAssertTrue(enableToggle.waitForHittable(timeout: timeout))
        if enableToggle.value as? String == "0" {
            tap(enableToggle)
        }
        XCTAssertEqual(enableToggle.value as? String, "1")
        let searchAndDuckAI = element("Settings.AIFeatures.Picker.SearchAndDuckAI")
        scrollTo(searchAndDuckAI)
        tap(searchAndDuckAI)
        closeSettings()
        tap(element("searchEntry"))
        XCTAssertTrue(element("AddressBar.Button.DuckAI").waitForHittable(timeout: timeout))
        tap(element("UnifiedToggleInput.Button.Dismiss"))
    }

    private func openVoiceSearchSettings() {
        openSettings()
        let accessibility = app.buttons.matching(identifier: "Accessibility").firstMatch
        // Use overlapping viewports: a full-screen swipe can jump past this row near the top of Main Settings.
        for _ in 0..<12 {
            if accessibility.exists && accessibility.isHittable && app.frame.contains(accessibility.frame) { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        }
        tap(accessibility)
        XCTAssertTrue(app.navigationBars["Accessibility"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["Private Voice Search"].exists)
        XCTAssertTrue(voiceSearchSwitch.waitForHittable(timeout: timeout))
    }

    private func enablePrivateVoiceSearch() {
        let row = app.cells.containing(.staticText, identifier: "Private Voice Search").firstMatch
        XCTAssertTrue(row.waitForHittable(timeout: timeout), app.debugDescription)
        let toggle = row.switches.firstMatch
        XCTAssertTrue(toggle.waitForHittable(timeout: timeout), row.debugDescription)
        XCTAssertTrue(["0", "1"].contains(toggle.value as? String ?? ""), toggle.debugDescription)
        // SwiftUI can expose nested switch elements; tap the trailing control rather than the row's label.
        let switchControl = toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        if toggle.value as? String == "1" {
            switchControl.tap()
            XCTAssertEqual(toggle.value as? String, "0")
        }
        switchControl.tap()
    }

    private var voiceSearchSwitch: XCUIElement {
        // The labeled row also has the switch trait, but only its nested control handles taps.
        app.switches["Private Voice Search"].switches.firstMatch
    }

    private func openEmptyVoiceSearchInput(duckAI: Bool) {
        tap(element("searchEntry"))
        tap(element("Browser.OmniBar.Button.ClearText"))
        tap(element(duckAI ? "AddressBar.Button.DuckAI" : "AddressBar.Button.Search"))
        let placeholder = duckAI ? "Ask anything privately" : "Search or enter address"
        XCTAssertTrue(app.staticTexts[placeholder].waitForExistence(timeout: timeout))
        XCTAssertTrue(element("Browser.OmniBar.Button.VoiceSearch").waitForHittable(timeout: timeout))
    }

    private func assertVoicePermissionReminder(isVoiceChat: Bool) {
        XCTAssertTrue(element("SitePermissions.Reminder").waitForExistence(timeout: timeout))
        XCTAssertEqual(element("SitePermissions.Reminder.Title").label, "DuckDuckGo needs to access your microphone")
        let body = isVoiceChat
            ? "Microphone permissions are needed if you want to use Voice Chat in Duck.ai."
            : "Microphone permissions are needed if you want to use our Private Voice Search."
        XCTAssertTrue(app.staticTexts[body].exists)
        XCTAssertEqual(element("SitePermissions.Reminder.ChangePermissions").label, "Change Permissions")
        XCTAssertEqual(element("SitePermissions.Reminder.Cancel").label, "Cancel")
        if isVoiceChat {
            XCTAssertFalse(element("SitePermissions.Reminder.HideVoiceSearch").exists)
        } else {
            XCTAssertEqual(element("SitePermissions.Reminder.HideVoiceSearch").label, "Hide Voice Search")
        }
        assertNoPermissionPrompt()
    }

    private func launchApp(flagEnabled: Bool = true, seedPermissions: String? = nil, additionalArguments: [String] = []) {
        app.launchArguments = [
            "-clearAllDefaults", "isRunningUITests",
            "-isOnboardingCompleted", "true",
            "-ff.sitePermissions", String(flagEnabled),
            "-ff.floatingUIAugust2026", "true",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_GB"
        ]
        if ProcessInfo.processInfo.environment["INTERNAL_USER_MODE"] == "true" {
            app.launchArguments += ["-isInternalUser", "true"]
        }
        if let seedPermissions {
            app.launchArguments += ["-sitePermissionsTestSeed", seedPermissions]
        }
        app.launchArguments += additionalArguments
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

    private func assertReloadCaptionAfterResettingPermission(_ permission: String, row: String) {
        launchApp()
        openPermissionPage()
        let deniedResult = permission == "location" ? "location error 1 1" : "NotAllowedError 1"
        request(permission)
        assertSiteDialog(permission: permission)
        tap(element("SitePermissions.Dialog.NeverAllow"))
        assertResult(deniedResult)

        reloadPermissionPage()
        request(permission)
        assertResult(deniedResult)
        assertNoPermissionPrompt()
        openPermissionsSheet()
        let caption = element("SitePermissions.Sheet.ReloadCaption")
        XCTAssertFalse(caption.exists)
        assertSheetDecision(row, contains: "Never Allow")
        tap(element("SitePermissions.Sheet.\(row)"))
        tap(app.buttons["Never Allow"])
        XCTAssertFalse(caption.exists)

        tap(element("SitePermissions.Sheet.\(row)"))
        tap(app.buttons["Ask Each Time"])
        assertSheetDecision(row, contains: "Ask Each Time")
        XCTAssertTrue(caption.waitForExistence(timeout: timeout))
        XCTAssertEqual(caption.label, "Reload the page for changes to take effect.")
        tap(element("SitePermissions.Sheet.Close"))
        // Changing the saved choice does not automatically retry the old request.
        assertResult(deniedResult)
        assertNoPermissionPrompt()

        reloadPermissionPage()
        openPermissionsSheet()
        assertSheetDecision(row, contains: "Ask Each Time")
        XCTAssertFalse(caption.exists)
        tap(element("SitePermissions.Sheet.Close"))
        request(permission)
        assertSiteDialog(permission: permission)
        tap(element("SitePermissions.Dialog.NeverAllow"))
        assertResult(deniedResult)
        assertResult("tracks video=0 audio=0")
    }

    private func assertCombinedMediaFailsAfterSystemDenial(of deniedPermission: String) {
        let allowedPermission = deniedPermission == "camera" ? "microphone" : "camera"
        launchApp()
        openPermissionPage()
        request("camera and microphone")
        assertSiteDialog(permission: "camera and microphone")
        tap(element("SitePermissions.Dialog.AllowWhileUsingSite"))
        answerSystemAlert(for: "camera", allow: deniedPermission != "camera")
        // The toast hides after 3 seconds, so look for it before waiting for the system alert to dismiss.
        answerSystemAlert(for: "microphone", allow: deniedPermission != "microphone", waitForDismissal: false)
        XCTAssertTrue(element("SitePermissions.Toast").staticTexts[
            "DuckDuckGo couldn’t give \(deniedPermission) access to this site"].waitForExistence(timeout: timeout))
        XCTAssertTrue(springboard.alerts.firstMatch.waitForNonExistence(timeout: timeout))
        assertResult("NotAllowedError 1")
        assertResult("tracks video=0 audio=0")
        reloadPermissionPage()

        request("camera and microphone")
        dismissReminder(for: deniedPermission)
        assertResult("NotAllowedError 1")
        assertResult("tracks video=0 audio=0")
        openPermissionsSheet()
        assertSheetDecision("Camera", contains: "Always Allow")
        assertSheetDecision("Microphone", contains: "Always Allow")
        tap(element("SitePermissions.Sheet.Close"))
        request(allowedPermission)
        assertResult("success 2")
        assertResult(allowedPermission == "camera" ? "tracks video=1 audio=0" : "tracks video=0 audio=1")
        assertNoPermissionPrompt()
    }

    private func request(_ permission: String) {
        tap(app.webViews.buttons["Request \(permission)"])
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
        assertNoSystemAlert(file: file, line: line)
    }

    private func answerSystemAlert(for permission: String, allow: Bool, waitForDismissal: Bool = true) {
        // Match the permission so consecutive camera/microphone prompts do not share an element query.
        let systemAlert = springboard.alerts.containing(NSPredicate(format: "label CONTAINS[c] %@", permission)).firstMatch
        XCTAssertTrue(systemAlert.waitForExistence(timeout: timeout), springboard.debugDescription)
        let allowLabels = permission == "location" ? ["Allow While Using App", "Allow While Using the App"] : ["Allow", "OK"]
        let button = systemAlert.buttons.matching(NSPredicate(
            format: "label IN %@", allow ? allowLabels : Self.dontAllowLabels)).firstMatch
        tap(button)
        if waitForDismissal {
            XCTAssertTrue(systemAlert.waitForNonExistence(timeout: timeout))
        }
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
        // System menu options expose their labels without the SwiftUI identifiers on iOS 27.
        tap(app.buttons[decision == "deny" ? "Never Allow" : "Ask Each Time"])
    }

    private func assertWebKitMediaRollback(permission: String) {
        launchApp(flagEnabled: false, seedPermissions: "{ \"127.0.0.1\" = { camera = deny; microphone = deny; geolocation = deny; }; }")
        openPermissionPage()
        request(permission)
        denyWebKitPrompt(for: permission)
        assertResult("NotAllowedError 1")
        assertResult("tracks video=0 audio=0")
        assertNoPermissionPrompt()
    }

    private func denyWebKitPrompt(for permission: String) {
        let alert = app.alerts.containing(NSPredicate(format: "label CONTAINS[c] %@", "127.0.0.1")).firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: timeout), app.debugDescription)
        for name in permission.components(separatedBy: " and ") {
            XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch.exists)
        }
        XCTAssertFalse(element("SitePermissions.Dialog").exists)
        tap(alert.buttons.matching(NSPredicate(format: "label IN %@", Self.dontAllowLabels)).firstMatch)
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
        XCTAssertEqual(element("SitePermissions.Sheet.Title").label, "Permissions for “127.0.0.1”")
    }

    private func openSettings() {
        openMenu()
        tap(app.buttons["Settings"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: timeout))
    }

    private func openPermissionSettings() {
        openSettings()
        let entry = element("Settings.SitePermissions")
        scrollTo(entry)
        tap(entry)
        XCTAssertTrue(element("Settings.SitePermissions.Global.camera").waitForExistence(timeout: timeout))
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

    private static let dontAllowLabels = ["Don’t Allow", "Don't Allow"]

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
      <button onclick="document.getElementById('result').textContent = 'reloading'; location.reload()">Reload fixture</button>
      <p id="result" role="status">ready</p>
      <p id="tracks" role="status">tracks video=0 audio=0</p>
      <p id="liveTracks" role="status">live video=0 audio=0</p>
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
            stream.getTracks().forEach(track => track.addEventListener('ended', updateLiveTracks));
            updateLiveTracks();
            tracks.textContent = 'tracks video=' + stream.getVideoTracks().length + ' audio=' + stream.getAudioTracks().length;
            result.textContent = 'success ' + count;
          } catch (error) {
            result.textContent = error.name + ' ' + count;
          }
        }
        function updateLiveTracks() {
          const live = streams.flatMap(stream => stream.getTracks()).filter(track => track.readyState === 'live');
          document.getElementById('liveTracks').textContent = 'live video=' + live.filter(track => track.kind === 'video').length
            + ' audio=' + live.filter(track => track.kind === 'audio').length;
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
