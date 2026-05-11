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
@testable import DuckDuckGo
@testable import Core
import BrowserServicesKitTestsUtils
import WebKit
import PrivacyConfig
import PrivacyConfigTestsUtils

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
}

class MockAutoconsentPreferences: AutoconsentPreferences {
    var autoconsentEnabled: Bool = true
}
