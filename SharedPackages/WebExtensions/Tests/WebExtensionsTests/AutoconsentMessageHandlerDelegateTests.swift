//
//  AutoconsentMessageHandlerDelegateTests.swift
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
import PrivacyConfig
import PrivacyConfigTestsUtils
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
final class AutoconsentMessageHandlerDelegateTests: XCTestCase {

    private var mockDelegate: MockAutoconsentDelegate!
    private var handler: AutoconsentWebExtensionMessageHandler!
    private var mockPrivacyConfig: MockPrivacyConfigurationManager!
    private var mockPreferences: MockAutoconsentPreferences!

    private static let testFeatureName = "autoconsent"
    private static let testExtensionIdentifier = "test-extension"

    override func setUp() {
        super.setUp()
        mockDelegate = MockAutoconsentDelegate()
        mockPrivacyConfig = MockPrivacyConfigurationManager()
        mockPreferences = MockAutoconsentPreferences()
        handler = AutoconsentWebExtensionMessageHandler(
            privacyConfigurationManager: mockPrivacyConfig,
            autoconsentPreferences: mockPreferences,
            delegate: mockDelegate
        )
    }

    override func tearDown() {
        mockDelegate = nil
        handler = nil
        mockPrivacyConfig = nil
        mockPreferences = nil
        super.tearDown()
    }

    func testShowCpmAnimation() async {
        let params: [String: Any] = [
            "topUrl": "https://example.com",
            "isCosmetic": true
        ]
        let message = WebExtensionMessage(
            featureName: Self.testFeatureName,
            method: "showCpmAnimation",
            id: nil,
            params: params,
            context: nil,
            extensionIdentifier: Self.testExtensionIdentifier
        )

        let result = await handler.handleMessage(message)

        switch result {
        case .success(let response):
            let dict = response as? [String: Any]
            XCTAssertEqual(dict?["response"] as? String, "ok")
            XCTAssertNotNil(mockDelegate.animationShown)
            XCTAssertEqual(mockDelegate.animationShown?.0.absoluteString, "https://example.com")
            XCTAssertEqual(mockDelegate.animationShown?.1, true)
        case .failure(let error):
            XCTFail("Expected success but got failure: \(error)")
        case .noHandler:
            XCTFail("Expected success but got noHandler")
        }
    }

    func testShowCpmAnimationMissingParameters() async {
        let params: [String: Any] = [
            "topUrl": "https://example.com"
        ]
        let message = WebExtensionMessage(
            featureName: Self.testFeatureName,
            method: "showCpmAnimation",
            id: nil,
            params: params,
            context: nil,
            extensionIdentifier: Self.testExtensionIdentifier
        )

        let result = await handler.handleMessage(message)

        switch result {
        case .success:
            XCTFail("Expected failure but got success")
        case .failure(let error):
            XCTAssertEqual(error.localizedDescription, WebExtensionMessageHandlerError.missingParameter("topUrl or isCosmetic").localizedDescription)
        case .noHandler:
            XCTFail("Expected failure but got noHandler")
        }
    }

    func testRefreshDashboardState() async {
        let consentStatus: [String: Any] = [
            "consentManaged": true,
            "cosmetic": false,
            "optoutFailed": false,
            "selftestFailed": nil as Any?,
            "consentReloadLoop": false,
            "consentRule": "test-rule",
            "consentHeuristicEnabled": true
        ]
        let params: [String: Any] = [
            "url": "https://example.com",
            "consentStatus": consentStatus
        ]
        let message = WebExtensionMessage(
            featureName: Self.testFeatureName,
            method: "refreshCpmDashboardState",
            id: nil,
            params: params,
            context: nil,
            extensionIdentifier: Self.testExtensionIdentifier
        )

        let result = await handler.handleMessage(message)

        switch result {
        case .success(let response):
            let dict = response as? [String: Any]
            XCTAssertEqual(dict?["response"] as? String, "ok")
            XCTAssertNotNil(mockDelegate.dashboardRefreshed)
            XCTAssertEqual(mockDelegate.dashboardRefreshed?.0, "example.com")
            XCTAssertEqual(mockDelegate.dashboardRefreshed?.1.consentManaged, true)
            XCTAssertEqual(mockDelegate.dashboardRefreshed?.1.cosmetic, false)
            XCTAssertEqual(mockDelegate.dashboardRefreshed?.1.consentRule, "test-rule")
        case .failure(let error):
            XCTFail("Expected success but got failure: \(error)")
        case .noHandler:
            XCTFail("Expected success but got noHandler")
        }
    }

    func testSendPixel() async {
        let params: [String: Any] = [
            "pixelName": "autoconsent_test",
            "type": "unique",
            "params": ["key1": "value1", "key2": "value2"]
        ]
        let message = WebExtensionMessage(
            featureName: Self.testFeatureName,
            method: "sendPixel",
            id: nil,
            params: params,
            context: nil,
            extensionIdentifier: Self.testExtensionIdentifier
        )

        let result = await handler.handleMessage(message)

        switch result {
        case .success(let response):
            let dict = response as? [String: Any]
            XCTAssertEqual(dict?["response"] as? String, "ok")
            XCTAssertNotNil(mockDelegate.pixelSent)
            XCTAssertEqual(mockDelegate.pixelSent?.name, "autoconsent_test")
            XCTAssertEqual(mockDelegate.pixelSent?.type, "unique")
            XCTAssertEqual(mockDelegate.pixelSent?.params["key1"] as? String, "value1")
        case .failure(let error):
            XCTFail("Expected success but got failure: \(error)")
        case .noHandler:
            XCTFail("Expected success but got noHandler")
        }
    }

    func testHandleCookiePopup() async {
        let msg: [String: Any] = [
            "url": "https://example.com/page",
            "cmp": "test-cmp",
            "result": true
        ]
        let params: [String: Any] = [
            "msg": msg
        ]
        let message = WebExtensionMessage(
            featureName: Self.testFeatureName,
            method: "cookiePopupHandled",
            id: nil,
            params: params,
            context: nil,
            extensionIdentifier: Self.testExtensionIdentifier
        )

        let result = await handler.handleMessage(message)

        switch result {
        case .success(let response):
            let dict = response as? [String: Any]
            XCTAssertEqual(dict?["response"] as? String, "ok")
            XCTAssertNotNil(mockDelegate.popupHandled)
            XCTAssertEqual(mockDelegate.popupHandled?.url.absoluteString, "https://example.com/page")
            XCTAssertEqual(mockDelegate.popupHandled?.message["cmp"] as? String, "test-cmp")
        case .failure(let error):
            XCTFail("Expected success but got failure: \(error)")
        case .noHandler:
            XCTFail("Expected success but got noHandler")
        }
    }
}

@available(macOS 15.4, iOS 18.4, *)
final class MockAutoconsentDelegate: AutoconsentMessageHandlerDelegate {
    var animationShown: (URL, Bool)?
    var dashboardRefreshed: (String, ConsentStatusInfo)?
    var popupHandled: CookiePopupHandledInfo?
    var pixelSent: PixelInfo?

    func showCookiePopupAnimation(topUrl: URL, isCosmetic: Bool) {
        animationShown = (topUrl, isCosmetic)
    }

    func refreshDashboardState(domain: String, consentStatus: ConsentStatusInfo) {
        dashboardRefreshed = (domain, consentStatus)
    }

    func handleCookiePopup(_ popupInfo: CookiePopupHandledInfo) {
        popupHandled = popupInfo
    }

    func sendPixel(_ pixelInfo: PixelInfo) {
        pixelSent = pixelInfo
    }
}
