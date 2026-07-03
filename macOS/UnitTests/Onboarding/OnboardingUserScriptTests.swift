//
//  OnboardingUserScriptTests.swift
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

import BrowserServicesKitTestsUtils
import Combine
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class OnboardingUserScriptTests: XCTestCase {
    var script: OnboardingUserScript!
    var mockManager: CapturingOnboardingActionsManager!

    override func setUp() {
        super.setUp()
        mockManager = CapturingOnboardingActionsManager()
        script = OnboardingUserScript(onboardingActionsManager: mockManager)
    }

    override func tearDown() {
        mockManager = nil
        script = nil
        super.tearDown()
    }

    @MainActor
    func testSetInit_ReturnsExpectedParameters() async throws {
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "init"))

        let result = try await handler([""], WKScriptMessage.mock())
        XCTAssertEqual(result as? OnboardingConfiguration, mockManager.configuration)
        XCTAssertTrue(mockManager.onboardingStartedCalled)
    }

    @MainActor
    func testReportPageException_CallsGoToAddressBar() async throws {
        let params = ["sabrina": "awesome"]
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "reportPageException"))

        let result = try await handler(params, WKScriptMessage.mock())
        XCTAssertTrue(mockManager.reportExceptionCalled)
        XCTAssertEqual(mockManager.exceptionParams, params)
        XCTAssertNil(result)
    }

    @MainActor
    func testDismissToAddressBar_CallsGoToAddressBar() async throws {
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "dismissToAddressBar"))

        let result = try await handler([""], WKScriptMessage.mock())
        XCTAssertTrue(mockManager.goToAddressBarCalled)
        XCTAssertNil(result)
    }

    @MainActor
    func testDismissToSettings_CallsGoToSettings() async throws {
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "dismissToSettings"))

        let result = try await handler([""], WKScriptMessage.mock())
        XCTAssertTrue(mockManager.goToSettingsCalled)
        XCTAssertNil(result)
    }

    @MainActor
    func testRequestDockOptIn_CallsAddToDock() async throws {
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "requestDockOptIn"))

        let result = try await handler([""], WKScriptMessage.mock())
        XCTAssertTrue(mockManager.addToDockCalled)
        XCTAssertNotNil(result)
    }

    @MainActor
    func testRequestImport_CallsImportData() async throws {
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "requestImport"))

        let result = try await handler([""], WKScriptMessage.mock())
        XCTAssertTrue(mockManager.importDataCalled)
        XCTAssertNotNil(result)
    }

    @MainActor
    func testRequestSetAsDefault_CallsSetAsDefault() async throws {
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "requestSetAsDefault"))

        let result = try await handler([""], WKScriptMessage.mock())
        XCTAssertTrue(mockManager.setAsDefaultCalled)
        XCTAssertNotNil(result)
    }

    // MARK: - onSetAsDefaultComplete push

    @MainActor
    func testSetInit_CapturesWebView_ForLaterPush() async throws {
        let webView = WKWebView()
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "init"))

        _ = try await handler([""], WKScriptMessage.mock(webView: webView))

        XCTAssertTrue(script.webView === webView)
    }

    @MainActor
    func testPushSetAsDefaultComplete_DoesNothing_WhenInitHasNotCapturedAWebView() {
        // Given: "init" has never been handled, so no webView has been captured.
        XCTAssertNil(script.webView)

        // Then: the guard on `webView` must prevent any push attempt (no crash, no-op).
        script.pushSetAsDefaultComplete()
    }

    @MainActor
    func testPushSetAsDefaultComplete_DoesNothing_WhenWebViewCapturedButNoBrokerAttached() async throws {
        // Given: "init" captured a webView, but `with(broker:)` was never called.
        let webView = WKWebView()
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "init"))
        _ = try await handler([""], WKScriptMessage.mock(webView: webView))
        XCTAssertNil(script.broker)

        // Then: `broker?.push` is a safe no-op without a broker.
        script.pushSetAsDefaultComplete()
    }

    @MainActor
    func testRequestChromeExtensionInstall_CallsInstallChromeExtension() async throws {
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "requestChromeExtensionInstall"))

        let result = try await handler([""], WKScriptMessage.mock())
        XCTAssertTrue(mockManager.installChromeExtensionCalled)
        XCTAssertNil(result)
    }

    @MainActor
    func testSetBookmarksBar_CallsSetBookmarkBar() async throws {
        let randomBool = Bool.random()
        let params = ["enabled": randomBool]
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "setBookmarksBar"))

        let result = try await handler(params, WKScriptMessage.mock())
        XCTAssertTrue(mockManager.setBookmarkBarCalled)
        XCTAssertEqual(mockManager.bookmarkBarVisible, randomBool)
        XCTAssertNil(result)
    }

    @MainActor
    func testSetSessionRestore_CallsSetSessionRestore() async throws {
        let randomBool = Bool.random()
        let params = ["enabled": randomBool]
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "setSessionRestore"))

        let result = try? await handler(params, WKScriptMessage.mock())
        XCTAssertTrue(mockManager.setSessionRestoreCalled)
        XCTAssertEqual(mockManager.sessionRestoreEnabled, randomBool)
        XCTAssertNil(result)
    }

    @MainActor
    func testSetShowHome_CallsSetShowHomeButtonLeft() async throws {
        let randomBool = Bool.random()
        let params = ["enabled": randomBool]
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "setShowHomeButton"))

        let result = try await handler(params, WKScriptMessage.mock())
        XCTAssertTrue(mockManager.setHomeButtonPositionCalled)
        XCTAssertEqual(mockManager.homeButtonVisible, randomBool)
        XCTAssertNil(result)
    }

    @MainActor
    func testStepCompleted_CallsStepCompleted() async throws {
        let randomStep = OnboardingSteps.allCases.randomElement()!
        let params = ["id": randomStep.rawValue]
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "stepCompleted"))

        let result = try await handler(params, WKScriptMessage.mock())
        XCTAssertEqual(mockManager.completedStep, randomStep)
        XCTAssertNil(result)
    }

    @MainActor
    func testStepCompleted_CallsStepShown_ForNextStep() async throws {
        let randomStep = OnboardingSteps.allCases.randomElement()!
        let params = ["next": randomStep.rawValue]
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "stepCompleted"))

        let result = try await handler(params, WKScriptMessage.mock())
        XCTAssertEqual(mockManager.shownStep, randomStep)
        XCTAssertNil(result)
    }

    @MainActor
    func testRowShownTelemetryEvent_CallsReportTelemetryEvent_WithExpectedEvent() async throws {
        let rowShown = OnboardingRow.dataImport
        let params = [
            "attributes": [
                "name": "row_shown",
                "value": rowShown.rawValue
            ]
        ]
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "telemetryEvent"))

        let result = try await handler(params, WKScriptMessage.mock())
        XCTAssertEqual(mockManager.reportedTelemetryEvent, .rowShown(rowShown))
        XCTAssertNil(result)
    }

    @MainActor
    func testRowSkippedTelemetryEvent_CallsReportTelemetryEvent_WithExpectedEvent() async throws {
        let rowSkipped = OnboardingRow.dataImport
        let params = [
            "attributes": [
                "name": "row_skipped",
                "value": rowSkipped.rawValue
            ]
        ]
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "telemetryEvent"))

        let result = try await handler(params, WKScriptMessage.mock())
        XCTAssertEqual(mockManager.reportedTelemetryEvent, .rowSkipped(rowSkipped))
        XCTAssertNil(result)
    }

    @MainActor
    func testDockInstructionsShownTelemetryEvent_CallsReportTelemetryEvent_WithExpectedEvent() async throws {
        let params = [
            "attributes": [
                "name": "dock_instructions_shown"
            ]
        ]
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "telemetryEvent"))

        let result = try await handler(params, WKScriptMessage.mock())
        XCTAssertEqual(mockManager.reportedTelemetryEvent, .dockInstructionsShown)
        XCTAssertNil(result)
    }

    @MainActor
    func testDuckPlayerToggledTelemetryEvent_CallsReportTelemetryEvent_WithExpectedEvent() async throws {
        let params = [
            "attributes": [
                "name": "duck_player_toggled"
            ]
        ]
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "telemetryEvent"))

        let result = try await handler(params, WKScriptMessage.mock())
        XCTAssertEqual(mockManager.reportedTelemetryEvent, .duckPlayerToggled)
        XCTAssertNil(result)
    }

}
