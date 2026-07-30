//
//  AutoconsentMessageProtocolTests.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import WebExtensions
@testable import DuckDuckGo
@testable import Core
import BrowserServicesKitTestsUtils
import WebKit
import PrivacyConfig
import PrivacyConfigTestsUtils
import PrivacyDashboard

final class AutoconsentMessageProtocolTests: XCTestCase {

    var userScript: AutoconsentUserScript! = {
        let embeddedConfig =
        """
        {
            "features": {
                "autoconsent": {
                    "exceptions": [
                        {
                            "domain": "computerbild.de",
                            "reason": "Page renders but one cannot scroll (and no CMP is shown) for a few seconds."
                        },
                        {
                            "domain": "spiegel.de",
                            "reason": "CMP gets incorrectly handled, gets stuck in preferences dialogue."
                        },
                    ],
                    "settings": {
                        "disabledCMPs": [
                            "Sourcepoint-top"
                        ]
                    },
                    "state": "enabled",
                    "hash": "659eb19df598629f1eaecbe7fa2d7f00"
                }
            },
            "unprotectedTemporary": []
        }
        """.data(using: .utf8)!

        let mockEmbeddedData = MockEmbeddedDataProvider(data: embeddedConfig, etag: "embedded")


        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: PrivacyConfig.MockInternalUserDecider())
        return AutoconsentUserScript(config: manager.privacyConfig, preferences: MockAutoconsentPreferences())
    }()

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
        let cases: [(preference: CookiePopupPreference, preferenceSettingEnabled: Bool, heuristicEnabled: Bool, expectedMode: String)] = [
            (.default, false, true, "reject"),
            (.default, true, true, "tier1"),
            (.max, true, true, "tier2"),
            (.default, true, false, "off"),
        ]

        for testCase in cases {
            assertHeuristicMode(
                preference: testCase.preference,
                preferenceSettingEnabled: testCase.preferenceSettingEnabled,
                heuristicEnabled: testCase.heuristicEnabled,
                expectedMode: testCase.expectedMode
            )
        }
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
    }

    @MainActor
    func testWhenAutoconsentDisabledByUserThenPublishesSettingDisabledCPMDiagnostics() throws {
        let delegate = MockAutoconsentUserScriptDelegate()
        userScript.delegate = delegate
        userScript.preferences.cookiePopupPreference = .off

        _ = sendInit(url: "https://example.com")

        let cookieConsentInfo = try cookieConsentInfoDictionary(from: delegate.receivedConsentStatuses.last)
        XCTAssertEqual(cookieConsentInfo["consentManaged"] as? Bool, false)
        XCTAssertEqual(cookieConsentInfo["cpmDashboardState"] as? String, "applied")
        XCTAssertEqual(cookieConsentInfo["cpmStage"] as? String, "setting_disabled")
        XCTAssertEqual(cookieConsentInfo["cpmQueueSize"] as? Int, 0)
        XCTAssertEqual(cookieConsentInfo["cpmExtensionDroppedCallbacks"] as? Int, 0)
        XCTAssertEqual(cookieConsentInfo["cpmExtensionLoaded"] as? Bool, false)
    }

    @MainActor
    func testWhenAutoconsentDisabledForSiteThenPublishesSiteDisabledCPMDiagnostics() throws {
        let config = MockPrivacyConfiguration()
        config.isFeatureEnabledForDomainCheck = { _, _ in false }
        userScript = AutoconsentUserScript(config: config, preferences: MockAutoconsentPreferences())
        let delegate = MockAutoconsentUserScriptDelegate()
        userScript.delegate = delegate

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

    // Flaky test that fails often, to re-evaluate. See 15s timeout, something wrong here
    @MainActor
    func testEval() {
        let message = WKScriptMessage.mock(name: "eval", body: [
            "type": "eval",
            "id": "some id",
            "code": "1+1==2"
        ], webView: WKWebView())
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
        waitForExpectations(timeout: 15.0)
    }

    @MainActor
    func testPopupFoundNoPromptIfEnabled() {
        let expect = expectation(description: "tt")
        let message = WKScriptMessage.mock(name: "popupFound", body: [
            "type": "popupFound",
            "cmp": "some cmp",
            "url": "some url"
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

    // MARK: - Reload Loop Detection

    @MainActor
    func testWhenSamePopupFoundAfterAutoconsentDoneThenReloadLoopDisablesAutoAction() {
        _ = sendInit(url: "https://example.com")
        sendPopupFound(cmp: "TestCMP", url: "https://example.com")
        sendAutoconsentDone(cmp: "TestCMP", url: "https://example.com", isCosmetic: false)
        sendPopupFound(cmp: "TestCMP", url: "https://example.com")

        let config = sendInit(url: "https://example.com")?["config"] as? [String: Any]
        XCTAssertNotNil(config)
        XCTAssertNil(config?["autoAction"] as? String, "autoAction should be cleared after reload loop is detected")
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
    func testWhenCosmeticAutoconsentDoneThenReloadLoopStateIsClearedAndAutoActionRemains() {
        _ = sendInit(url: "https://example.com")
        sendPopupFound(cmp: "TestCMP", url: "https://example.com")
        sendAutoconsentDone(cmp: "TestCMP", url: "https://example.com", isCosmetic: true)
        sendPopupFound(cmp: "TestCMP", url: "https://example.com")

        let config = sendInit(url: "https://example.com")?["config"] as? [String: Any]
        XCTAssertEqual(config?["autoAction"] as? String, "optOut", "Cosmetic rules should not trigger reload loop detection")
    }

    @MainActor
    func testWhenDifferentCMPDetectedThenNoReloadLoop() {
        _ = sendInit(url: "https://example.com")
        sendPopupFound(cmp: "CMP_A", url: "https://example.com")
        sendAutoconsentDone(cmp: "CMP_A", url: "https://example.com", isCosmetic: false)
        sendPopupFound(cmp: "CMP_B", url: "https://example.com")

        let config = sendInit(url: "https://example.com")?["config"] as? [String: Any]
        XCTAssertEqual(config?["autoAction"] as? String, "optOut", "A different CMP should not trigger reload loop detection")
    }

    @MainActor
    func testWhenMainFrameURLChangesThenReloadLoopStateClears() {
        _ = sendInit(url: "https://example.com")
        sendPopupFound(cmp: "TestCMP", url: "https://example.com")
        sendAutoconsentDone(cmp: "TestCMP", url: "https://example.com", isCosmetic: false)
        sendPopupFound(cmp: "TestCMP", url: "https://example.com")

        let loopedConfig = sendInit(url: "https://example.com")?["config"] as? [String: Any]
        XCTAssertNil(loopedConfig?["autoAction"] as? String, "Reload loop should be detected on the same URL")

        let navigatedConfig = sendInit(url: "https://other.com")?["config"] as? [String: Any]
        XCTAssertEqual(navigatedConfig?["autoAction"] as? String, "optOut", "Navigating to a different URL should clear the reload loop state")
    }

    // MARK: - Helpers

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
    private func sendAutoconsentDone(cmp: String, url: String, isCosmetic: Bool) {
        _ = sendMessage(name: "autoconsentDone", body: [
            "type": "autoconsentDone",
            "cmp": cmp,
            "url": url,
            "isCosmetic": isCosmetic
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
                                     preferenceSettingEnabled: Bool,
                                     heuristicEnabled: Bool,
                                     expectedMode: String) {
        let config = MockPrivacyConfiguration()
        config.isSubfeatureKeyEnabled = { subfeature, _ in
            subfeature.rawValue == AutoconsentSubfeature.cookiePopupPreferenceSetting.rawValue && preferenceSettingEnabled
        }
        let preferences = MockAutoconsentPreferences()
        preferences.cookiePopupPreference = preference
        let enabledFeatureFlags: [FeatureFlag] = heuristicEnabled ? [.heuristicAction] : []
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: enabledFeatureFlags)
        let management = MockAutoconsentManagement()
        userScript = AutoconsentUserScript(
            config: config,
            preferences: preferences,
            featureFlagger: featureFlagger
        )
        userScript.management = management

        let response = sendInit(url: "https://example.com")
        let initConfig = response?["config"] as? [String: Any]

        XCTAssertEqual(initConfig?["heuristicMode"] as? String, expectedMode)
        XCTAssertEqual(management.lastAdditionalParameters?["consentHeuristicEnabled"], expectedMode)
    }

    private func cookieConsentInfoDictionary(from cookieConsentInfo: CookieConsentInfo?) throws -> [String: Any] {
        let cookieConsentInfo = try XCTUnwrap(cookieConsentInfo)
        let data = try JSONEncoder().encode(cookieConsentInfo)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

class MockAutoconsentPreferences: AutoconsentPreferences {
    var cookiePopupPreference: CookiePopupPreference = .default
}

final class MockAutoconsentUserScriptDelegate: AutoconsentUserScriptDelegate {
    private(set) var receivedConsentStatuses: [CookieConsentInfo] = []

    func autoconsentUserScript(consentStatus: CookieConsentInfo) {
        receivedConsentStatuses.append(consentStatus)
    }
}

final class AutoconsentDashboardStateRefreshTests: XCTestCase {

    func testWhenDashboardStateRefreshMatchesHostAndPathThenPrivacyInfoUpdates() throws {
        guard #available(iOS 18.4, *) else {
            throw XCTSkip("Web extension Autoconsent dashboard state refresh requires iOS 18.4")
        }

        let matchingPrivacyInfo = makePrivacyInfo(url: URL(string: "https://example.com/articles/one?tab=query")!)
        let consentStatus = ConsentStatusInfo(
            consentManaged: true,
            cosmetic: false,
            optoutFailed: true,
            selftestFailed: false,
            consentReloadLoop: true,
            consentRule: "test-rule",
            consentHeuristicEnabled: false,
            cpmStage: "popup_found",
            cpmErrors: "multiple_cmps,tab_refreshDashboardState",
            cpmQueueSize: 2,
            cpmConfigVersion: "123")
        let refreshURL = URL(string: "https://example.com/articles/one?refresh=query")!

        matchingPrivacyInfo.updateCookieConsentManagedForWebExtensionDashboardState(url: refreshURL, consentStatus: consentStatus)

        let cookieConsentInfo = try cookieConsentInfoDictionary(from: matchingPrivacyInfo)
        XCTAssertEqual(cookieConsentInfo["consentManaged"] as? Bool, true)
        XCTAssertEqual(cookieConsentInfo["cosmetic"] as? Bool, false)
        XCTAssertEqual(cookieConsentInfo["optoutFailed"] as? Bool, true)
        XCTAssertEqual(cookieConsentInfo["selftestFailed"] as? Bool, false)
        XCTAssertEqual(cookieConsentInfo["consentReloadLoop"] as? Bool, true)
        XCTAssertEqual(cookieConsentInfo["consentRule"] as? String, "test-rule")
        XCTAssertEqual(cookieConsentInfo["consentHeuristicEnabled"] as? Bool, false)
        XCTAssertEqual(cookieConsentInfo["cpmDashboardState"] as? String, "applied")
        XCTAssertEqual(cookieConsentInfo["cpmStage"] as? String, "popup_found")
        XCTAssertEqual(cookieConsentInfo["cpmErrors"] as? String, "multiple_cmps,tab_refreshDashboardState")
        XCTAssertEqual(cookieConsentInfo["cpmQueueSize"] as? Int, 2)
        XCTAssertEqual(cookieConsentInfo["cpmConfigVersion"] as? String, "123")
    }

    func testWhenDashboardStateRefreshMatchesHostButNotPathThenPrivacyInfoDoesNotUpdate() throws {
        guard #available(iOS 18.4, *) else {
            throw XCTSkip("Web extension Autoconsent dashboard state refresh requires iOS 18.4")
        }

        let privacyInfo = makePrivacyInfo(url: URL(string: "https://example.com/articles/two")!)
        privacyInfo.cookieConsentManaged = CookieConsentInfo.initialCPMDiagnostics
        let consentStatus = ConsentStatusInfo(consentManaged: true)
        let refreshURL = URL(string: "https://example.com/articles/one")!

        privacyInfo.updateCookieConsentManagedForWebExtensionDashboardState(url: refreshURL, consentStatus: consentStatus)

        let cookieConsentInfo = try cookieConsentInfoDictionary(from: privacyInfo)
        XCTAssertEqual(cookieConsentInfo["consentManaged"] as? Bool, false)
        XCTAssertEqual(cookieConsentInfo["cpmDashboardState"] as? String, "waiting")
        XCTAssertEqual(cookieConsentInfo["cpmStage"] as? String, "not_started")
        XCTAssertEqual(cookieConsentInfo["cpmConfigVersion"] as? String, "")
    }

    private func makePrivacyInfo(url: URL) -> PrivacyInfo {
        PrivacyInfo(
            url: url,
            parentEntity: nil,
            protectionStatus: ProtectionStatus(
                unprotectedTemporary: false,
                enabledFeatures: [],
                allowlisted: false,
                denylisted: false))
    }

    private func cookieConsentInfoDictionary(from privacyInfo: PrivacyInfo) throws -> [String: Any] {
        let cookieConsentInfo = try XCTUnwrap(privacyInfo.cookieConsentManaged)
        let data = try JSONEncoder().encode(cookieConsentInfo)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
