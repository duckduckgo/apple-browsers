//
//  AutoconsentMessageProtocolTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import BrowserServicesKitTestsUtils
import Common
import EventHub
import FeatureFlags_macOS
import FoundationExtensions
import History
import HistoryView
@_spi(Testing) import Persistence
import PixelKit
import PrivacyConfig
import PrivacyConfigTestsUtils
import PrivacyDashboard
import WebExtensions
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

class AutoconsentMessageProtocolTests: XCTestCase {

    var userScript: AutoconsentUserScript!
    var config: MockPrivacyConfiguration!
    var preferences: CookiePopupProtectionPreferences!

    @MainActor
    override func setUp() async throws{
        try await super.setUp()

        config = MockPrivacyConfiguration()
        preferences = CookiePopupProtectionPreferences(persistor: MockCookiePopupProtectionPreferencesPersistor(), windowControllersManager: WindowControllersManagerMock())
        preferences.isAutoconsentEnabled = true

        userScript = AutoconsentUserScript(
            config: config,
            management: AutoconsentManagement(),
            preferences: preferences,
            featureFlagger: MockFeatureFlagger()
        )
    }

    override func tearDown() {
        userScript = nil
        config = nil
        preferences = nil
    }

    func replyToJson(msg: Any) -> String {
        let jsonData = try? JSONSerialization.data(withJSONObject: msg, options: .sortedKeys)
        return String(data: jsonData!, encoding: .ascii)!
    }

    @MainActor
    func testInitIgnoresNonHttp() {
        let expect = expectation(description: "tt")
        let message = WKScriptMessage.mock(name: "init", body: [
            "type": "init",
            "url": "file://helicopter"
        ])
        userScript.handleMessage(
            replyHandler: {(msg: Any?, _: String?) in
                expect.fulfill()
                XCTAssertEqual(self.replyToJson(msg: msg!), """
                {"type":"ok"}
                """)
            },
            message: message
        )
        waitForExpectations(timeout: 1.0)
    }

    @MainActor
    func testInitResponds() {
        let expect = expectation(description: "tt")
        let message = WKScriptMessage.mock(name: "init", body: [
            "type": "init",
            "url": "https://example.com"
        ])
        userScript.handleMessage(
            replyHandler: {(msg: Any?, _: String?) in
                expect.fulfill()
                guard let jsonData = try? JSONSerialization.data(withJSONObject: msg!, options: .sortedKeys),
                      let json = try? JSONSerialization.jsonObject(with: jsonData, options: []),
                      let dict = json as? [String: Any],
                      let config = dict["config"] as? [String: Any]
                else {
                    XCTFail("Could not parse init response")
                    return
                }

                XCTAssertEqual(dict["type"] as? String, "initResp")
                XCTAssertEqual(config["autoAction"] as? String, "optOut")
            },
            message: message
        )
        waitForExpectations(timeout: 1.0)
    }

    @MainActor
    func testWhenNativeAutoconsentPixelFiresThenHeuristicModeMatchesInitConfiguration() {
        let cases: [(preference: CookiePopupPreference, heuristicEnabled: Bool, expectedMode: String)] = [
            (.default, true, "tier1"),
            (.max, true, "tier2"),
            (.default, false, "off"),
        ]

        for testCase in cases {
            assertHeuristicMode(
                preference: testCase.preference,
                heuristicEnabled: testCase.heuristicEnabled,
                expectedMode: testCase.expectedMode
            )
        }
    }

    @MainActor
    func testWhenNativeAutoconsentPixelsFireThenTheyAreCountedPerSiteRank() {
        let management = AutoconsentManagement()
        userScript = AutoconsentUserScript(
            config: config,
            management: management,
            preferences: preferences,
            featureFlagger: MockFeatureFlagger()
        )

        _ = sendInit(url: "https://www.google.com/")
        _ = sendInit(url: "https://example.com/")

        XCTAssertEqual(management.pixelCounter, [CPMSiteRank.top10k: ["init": 1], CPMSiteRank.other: ["init": 1]])
    }

    @MainActor
    func testWhenSummaryPixelsFireThenCPMCoverageIsReportedToEventHub() {
        let eventHub = RecordingEventHub()
        let management = AutoconsentManagement()
        management.eventHub = eventHub
        management.pixelCounter = [
            CPMSiteRank.top10k: ["init": 2, "detected-by-patterns": 2, "detected-by-both": 1],
            CPMSiteRank.other: ["init": 3, "detected-by-patterns": 1, "detected-by-both": 3],
        ]

        management.fireSummaryPixels(additionalParameters: [:])

        XCTAssertEqual(eventHub.nativeEventCounts, [
            "autoconsent_page": 5, "autoconsent_page_top10k": 2,
            "autoconsent_unhandled": 1, "autoconsent_unhandled_top10k": 1,
        ])
        XCTAssertTrue(management.pixelCounter.isEmpty)
    }

    func testWhenEmbeddedExtensionSendsSummaryThenCPMCoverageIsReportedToEventHub() throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Embedded extension requires macOS 15.4") }
        let eventHub = RecordingEventHub()
        let delegate = MacOSAutoconsentMessageHandlerDelegate(eventHub: eventHub)

        delegate.sendPixel(PixelInfo(name: "autoconsent_init", type: "daily"))
        delegate.sendPixel(PixelInfo(name: "autoconsent_summary", type: "standard", params: [
            "init": "4", "detected-by-patterns": 3, "detected-by-both": "1", "siteRank": "top10k",
        ]))
        // Older extension versions don't send siteRank
        delegate.sendPixel(PixelInfo(name: "autoconsent_summary", type: "standard", params: ["init": 1, "detected-by-patterns": 1]))

        XCTAssertEqual(eventHub.nativeEventCounts, [
            "autoconsent_page": 5, "autoconsent_page_top10k": 4,
            "autoconsent_unhandled": 3, "autoconsent_unhandled_top10k": 2,
        ])
    }

    @MainActor
    func testEval() {
        let webView = WKWebView()
        let message = WKScriptMessage.mock(name: "eval", body: [
            "type": "eval",
            "id": "some id",
            "code": "1+1==2"
        ], webView: webView)

        let expect = expectation(description: "testEval")
        userScript.handleMessage(
            replyHandler: {(msg: Any?, _: String?) in
                expect.fulfill()
                XCTAssertEqual(self.replyToJson(msg: msg!), """
                {"id":"some id","result":true,"type":"evalResp"}
                """)
            },
            message: message
        )
        waitForExpectations(timeout: 5.0)
    }

    @MainActor
    func testPopupFoundNoPromptIfEnabled() {
        let expect = expectation(description: "tt")
        let message = WKScriptMessage.mock(name: "popupFound", body: [
            "type": "popupFound",
            "cmp": "some cmp",
            "url": "https://example.com"
        ])
        userScript.handleMessage(
            replyHandler: {(msg: Any?, _: String?) in
                expect.fulfill()
                XCTAssertEqual(self.replyToJson(msg: msg!), """
                {"type":"ok"}
                """)
            },
            message: message
        )
        waitForExpectations(timeout: 1.0)
    }

    @MainActor
    func testWhenInitAcceptedThenPublishesLegacyCPMDiagnostics() throws {
        let delegate = MockAutoconsentUserScriptDelegate()
        userScript.delegate = delegate

        _ = sendInit(url: "https://example.com")

        let cookieConsentInfo = try cookieConsentInfoDictionary(from: delegate.receivedConsentStatuses.last)
        XCTAssertEqual(cookieConsentInfo["consentManaged"] as? Bool, false)
        XCTAssertEqual(cookieConsentInfo["cpmDashboardState"] as? String, "applied")
        XCTAssertEqual(cookieConsentInfo["cpmStage"] as? String, "init_received")
        XCTAssertEqual(cookieConsentInfo["cpmQueueSize"] as? Int, 0)
        XCTAssertEqual(cookieConsentInfo["cpmExtensionDroppedCallbacks"] as? Int, 0)
        XCTAssertEqual(cookieConsentInfo["cpmExtensionLoaded"] as? Bool, false)
        XCTAssertEqual(cookieConsentInfo["cpmConfigVersion"] as? String, "123456789")
    }

    @MainActor
    func testWhenAutoconsentDisabledByUserThenPublishesSettingDisabledCPMDiagnostics() throws {
        let delegate = MockAutoconsentUserScriptDelegate()
        userScript.delegate = delegate
        preferences.isAutoconsentEnabled = false

        _ = sendInit(url: "https://example.com")

        let cookieConsentInfo = try cookieConsentInfoDictionary(from: delegate.receivedConsentStatuses.last)
        XCTAssertEqual(cookieConsentInfo["consentManaged"] as? Bool, false)
        XCTAssertEqual(cookieConsentInfo["cpmDashboardState"] as? String, "applied")
        XCTAssertEqual(cookieConsentInfo["cpmStage"] as? String, "setting_disabled")
        XCTAssertEqual(cookieConsentInfo["cpmQueueSize"] as? Int, 0)
        XCTAssertEqual(cookieConsentInfo["cpmExtensionDroppedCallbacks"] as? Int, 0)
        XCTAssertEqual(cookieConsentInfo["cpmExtensionLoaded"] as? Bool, false)
        XCTAssertEqual(cookieConsentInfo["cpmConfigVersion"] as? String, "123456789")
    }

    @MainActor
    func testWhenAutoconsentDisabledForSiteThenPublishesSiteDisabledCPMDiagnostics() throws {
        let delegate = MockAutoconsentUserScriptDelegate()
        userScript.delegate = delegate
        config.isFeatureEnabledForDomainCheck = { _, _ in false }

        _ = sendInit(url: "https://example.com")

        let cookieConsentInfo = try cookieConsentInfoDictionary(from: delegate.receivedConsentStatuses.last)
        XCTAssertEqual(cookieConsentInfo["consentManaged"] as? Bool, false)
        XCTAssertEqual(cookieConsentInfo["cpmDashboardState"] as? String, "applied")
        XCTAssertEqual(cookieConsentInfo["cpmStage"] as? String, "site_disabled")
        XCTAssertEqual(cookieConsentInfo["cpmQueueSize"] as? Int, 0)
        XCTAssertEqual(cookieConsentInfo["cpmExtensionDroppedCallbacks"] as? Int, 0)
        XCTAssertEqual(cookieConsentInfo["cpmExtensionLoaded"] as? Bool, false)
        XCTAssertEqual(cookieConsentInfo["cpmConfigVersion"] as? String, "123456789")
    }

    @MainActor
    func testWhenLegacyLifecycleProgressesThenPublishesCPMStagesAndErrors() throws {
        let delegate = MockAutoconsentUserScriptDelegate()
        userScript.delegate = delegate

        _ = sendInit(url: "https://example.com")
        sendPopupFound(cmp: "TestCMP", url: "https://example.com")
        var cookieConsentInfo = try cookieConsentInfoDictionary(from: delegate.receivedConsentStatuses.last)
        XCTAssertEqual(cookieConsentInfo["cpmStage"] as? String, "popup_found")

        sendOptOutResult(cmp: "TestCMP", result: false, url: "https://example.com")
        cookieConsentInfo = try cookieConsentInfoDictionary(from: delegate.receivedConsentStatuses.last)
        XCTAssertEqual(cookieConsentInfo["cpmStage"] as? String, "optout_failed")
        XCTAssertEqual(cookieConsentInfo["optoutFailed"] as? Bool, true)

        sendAutoconsentError()
        cookieConsentInfo = try cookieConsentInfoDictionary(from: delegate.receivedConsentStatuses.last)
        XCTAssertEqual(cookieConsentInfo["cpmErrors"] as? String, "multiple_cmps")
        XCTAssertEqual(cookieConsentInfo["optoutFailed"] as? Bool, true)

        sendAutoconsentDone(cmp: "TestCMP", url: "https://example.com", isCosmetic: false)
        cookieConsentInfo = try cookieConsentInfoDictionary(from: delegate.receivedConsentStatuses.last)
        XCTAssertEqual(cookieConsentInfo["cpmStage"] as? String, "done")
    }

    @MainActor
    func testWhenSamePopupFoundAfterAutoconsentDoneThenDashboardReportsReloadLoop() throws {
        let delegate = MockAutoconsentUserScriptDelegate()
        userScript.delegate = delegate

        _ = sendInit(url: "https://example.com")
        sendPopupFound(cmp: "TestCMP", url: "https://example.com")
        sendAutoconsentDone(cmp: "TestCMP", url: "https://example.com", isCosmetic: false)
        sendPopupFound(cmp: "TestCMP", url: "https://example.com")

        let cookieConsentInfo = try cookieConsentInfoDictionary(from: delegate.receivedConsentStatuses.last)
        XCTAssertEqual(cookieConsentInfo["consentReloadLoop"] as? Bool, true)
    }

    @MainActor
    @discardableResult
    private func sendInit(url: String) -> [String: Any]? {
        sendMessage(name: "init", body: [
            "type": "init",
            "url": url
        ])
    }

    @MainActor
    private func sendPopupFound(cmp: String, url: String) {
        _ = sendMessage(name: "popupFound", body: [
            "type": "popupFound",
            "cmp": cmp,
            "url": url
        ])
    }

    @MainActor
    private func sendOptOutResult(cmp: String, result: Bool, url: String) {
        _ = sendMessage(name: "optOutResult", body: [
            "type": "optOutResult",
            "cmp": cmp,
            "result": result,
            "scheduleSelfTest": false,
            "url": url
        ])
    }

    @MainActor
    private func sendAutoconsentDone(cmp: String, url: String, isCosmetic: Bool) {
        _ = sendMessage(name: "autoconsentDone", body: [
            "type": "autoconsentDone",
            "cmp": cmp,
            "url": url,
            "isCosmetic": isCosmetic,
            "duration": 42,
            "totalClicks": 1
        ])
    }

    @MainActor
    private func sendAutoconsentError() {
        _ = sendMessage(name: "autoconsentError", body: [
            "type": "autoconsentError"
        ])
    }

    @MainActor
    private func sendMessage(name: String, body: [String: Any]) -> [String: Any]? {
        let expect = expectation(description: "reply for \(name)")
        var receivedReply: [String: Any]?
        let message = WKScriptMessage.mock(name: name, body: body)
        userScript.handleMessage(
            replyHandler: { (msg: Any?, _: String?) in
                if let msg,
                   let data = try? JSONSerialization.data(withJSONObject: msg, options: .sortedKeys),
                   let json = try? JSONSerialization.jsonObject(with: data, options: []),
                   let dict = json as? [String: Any] {
                    receivedReply = dict
                }
                expect.fulfill()
            },
            message: message
        )
        waitForExpectations(timeout: 1.0)
        return receivedReply
    }

    @MainActor
    private func assertHeuristicMode(preference: CookiePopupPreference,
                                     heuristicEnabled: Bool,
                                     expectedMode: String) {
        config = MockPrivacyConfiguration()
        preferences = CookiePopupProtectionPreferences(
            persistor: MockCookiePopupProtectionPreferencesPersistor(),
            windowControllersManager: WindowControllersManagerMock()
        )
        preferences.cookiePopupPreference = preference

        let cohort: FeatureFlag.HeuristicActionCohort = heuristicEnabled ? .treatment : .control
        userScript = AutoconsentUserScript(
            config: config,
            management: AutoconsentManagement(),
            preferences: preferences,
            featureFlagger: MockFeatureFlagger(resolveCohortStub: cohort)
        )

        var firedParameters: [String: String]?
        PixelKit.setUp(
            dryRun: false,
            appVersion: "1.0.0",
            session: "test",
            defaultHeaders: [:],
            defaults: UserDefaults(suiteName: "test_\(UUID().uuidString)")!
        ) { _, _, parameters, _, _, completion in
            firedParameters = parameters
            completion(true, nil)
        }
        defer { PixelKit.tearDown() }

        let response = sendInit(url: "https://example.com")
        let initConfig = response?["config"] as? [String: Any]

        XCTAssertEqual(initConfig?["heuristicMode"] as? String, expectedMode)
        XCTAssertEqual(firedParameters?["consentHeuristicEnabled"], expectedMode)
    }

    private func cookieConsentInfoDictionary(from cookieConsentInfo: CookieConsentInfo?) throws -> [String: Any] {
        let cookieConsentInfo = try XCTUnwrap(cookieConsentInfo)
        let data = try JSONEncoder().encode(cookieConsentInfo)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class RecordingEventHub: EventHubManaging {
    private(set) var nativeEventCounts: [String: Int] = [:]

    func handleWebEvent(_ webEventData: [String: Any], tabID: EventHubTabID) {}
    func handleNativeEvent(_ type: String, data: Encodable?) {
        nativeEventCounts[type, default: 0] += 1
    }
    func onNavigationStarted(tabID: EventHubTabID, url: String) {}
    func onTabClosed(tabID: EventHubTabID) {}
    func onConfigChanged() {}
    func onAppForegrounded() {}
    func onAppBackgrounded() {}
}

final class MockAutoconsentUserScriptDelegate: AutoconsentUserScriptDelegate {
    private(set) var receivedConsentStatuses: [CookieConsentInfo] = []

    func autoconsentUserScript(consentStatus: CookieConsentInfo) {
        receivedConsentStatuses.append(consentStatus)
    }
}
