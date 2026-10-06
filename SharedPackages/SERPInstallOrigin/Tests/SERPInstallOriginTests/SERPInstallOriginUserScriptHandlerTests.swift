//
//  SERPInstallOriginUserScriptHandlerTests.swift
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

@testable import SERPInstallOrigin
import BrowserServicesKitTestsUtils
import UserScript
import WebKit
import XCTest

final class SERPInstallOriginUserScriptHandlerTests: XCTestCase {

    func testWhenInstallOriginEnabledAndProviderPresentThenHandshakeReturnsPlatformAndInstallOriginTrue() async throws {
        let provider = MockInstallOriginVariantProvider()
        let handler = SERPInstallOriginUserScriptHandler(
            platform: .macos,
            installOriginEnabled: true,
            installOriginVariantProvider: provider
        )
        let response = try await handler.handshake(params: [:], message: WKScriptMessage.mock())
        XCTAssertEqual(response.platform, .macos)
        XCTAssertTrue(response.installOrigin)
    }

    func testWhenInstallOriginDisabledThenHandshakeReturnsPlatformAndInstallOriginFalse() async throws {
        let handler = SERPInstallOriginUserScriptHandler(
            platform: .macos,
            installOriginEnabled: false,
            installOriginVariantProvider: nil
        )
        let response = try await handler.handshake(params: [:], message: WKScriptMessage.mock())
        XCTAssertEqual(response.platform, .macos)
        XCTAssertFalse(response.installOrigin)
    }

    func testWhenProviderReturnsVariantThenHandlerReturnsIt() async throws {
        let provider = MockInstallOriginVariantProvider()
        provider.result = "bar"
        let handler = SERPInstallOriginUserScriptHandler(
            installOriginEnabled: true,
            installOriginVariantProvider: provider
        )
        let response = try await handler.getInstallOriginVariant(
            params: ["campaign": "foo"],
            message: WKScriptMessage.mock()
        )
        XCTAssertEqual(response, GetInstallOriginVariantResponse(variant: "bar"))
        XCTAssertEqual(provider.lastCampaign, "foo")
    }

    func testWhenInstallOriginDisabledThenReturnsNullVariant() async throws {
        let handler = SERPInstallOriginUserScriptHandler(
            installOriginEnabled: false,
            installOriginVariantProvider: nil
        )
        let response = try await handler.getInstallOriginVariant(
            params: ["campaign": "foo"],
            message: WKScriptMessage.mock()
        )
        XCTAssertEqual(response, GetInstallOriginVariantResponse(variant: nil))
    }

    func testWhenInstallOriginDisabledThenReturnsNullVariantEvenWithProvider() async throws {
        let provider = MockInstallOriginVariantProvider()
        provider.result = "bar"
        let handler = SERPInstallOriginUserScriptHandler(
            installOriginEnabled: false,
            installOriginVariantProvider: provider
        )
        let response = try await handler.getInstallOriginVariant(
            params: ["campaign": "foo"],
            message: WKScriptMessage.mock()
        )
        XCTAssertEqual(response, GetInstallOriginVariantResponse(variant: nil))
        XCTAssertNil(provider.lastCampaign)
    }

    func testWhenCampaignParamMissingThenProviderReceivesNilCampaign() async throws {
        let provider = MockInstallOriginVariantProvider()
        let handler = SERPInstallOriginUserScriptHandler(
            installOriginEnabled: true,
            installOriginVariantProvider: provider
        )
        _ = try await handler.getInstallOriginVariant(params: [:], message: WKScriptMessage.mock())
        XCTAssertNil(provider.lastCampaign)
    }

    func testWhenSerpBaseURLHasHostnameThenMessageOriginPolicyAllowsThatHostname() {
        let script = SERPInstallOriginUserScript(
            serpBaseURL: URL(string: "https://use-devtesting18.duckduckgo.com")!,
            installOriginEnabled: true,
            installOriginVariantProvider: nil
        )

        XCTAssertTrue(script.messageOriginPolicy.isAllowed("use-devtesting18.duckduckgo.com"))
        XCTAssertFalse(script.messageOriginPolicy.isAllowed("duckduckgo.com"))
    }

    func testWhenSerpBaseURLHasNonStandardPortThenMessageOriginPolicyIncludesPort() {
        let script = SERPInstallOriginUserScript(
            serpBaseURL: URL(string: "http://localhost:8080")!,
            installOriginEnabled: true,
            installOriginVariantProvider: nil
        )

        XCTAssertTrue(script.messageOriginPolicy.isAllowed("localhost:8080"))
        XCTAssertFalse(script.messageOriginPolicy.isAllowed("localhost"))
    }

    func testWhenSerpBaseURLHasNoHostThenMessageOriginPolicyFallsBackToDuckDuckGo() {
        let script = SERPInstallOriginUserScript(
            serpBaseURL: URL(string: "file:///serp")!,
            installOriginEnabled: true,
            installOriginVariantProvider: nil
        )

        XCTAssertTrue(script.messageOriginPolicy.isAllowed("duckduckgo.com"))
    }

    func testWhenUnknownMethodRequestedThenHandlerThrowsMessageNotImplemented() async throws {
        let script = SERPInstallOriginUserScript(
            serpBaseURL: URL(string: "https://duckduckgo.com")!,
            installOriginEnabled: true,
            installOriginVariantProvider: MockInstallOriginVariantProvider()
        )
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "futureFeature"))
        do {
            _ = try await handler([:], WKScriptMessage.mock())
            XCTFail("Expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Message not implemented")
        }
    }

    func testWhenGetInstallOriginVariantMessageReceivedThenHandlerIsCalled() async throws {
        let provider = MockInstallOriginVariantProvider()
        let script = SERPInstallOriginUserScript(
            serpBaseURL: URL(string: "https://duckduckgo.com")!,
            installOriginEnabled: true,
            installOriginVariantProvider: provider
        )
        let handler = try XCTUnwrap(script.handler(forMethodNamed: SERPInstallOriginUserScript.MessageName.getInstallOriginVariant.rawValue))
        _ = try await handler(["campaign": "foo"], WKScriptMessage.mock())
        XCTAssertEqual(provider.lastCampaign, "foo")
    }

    func testWhenUnknownMethodRequestedThenBrokerReturnsErrorEnvelope() async throws {
        let script = SERPInstallOriginUserScript(
            serpBaseURL: URL(string: "https://duckduckgo.com")!,
            installOriginEnabled: true,
            installOriginVariantProvider: MockInstallOriginVariantProvider()
        )
        let broker = UserScriptMessageBroker(context: "contentScopeScripts", hostProvider: MockDuckDuckGoHostProvider())
        broker.registerSubfeature(delegate: script)

        let message = await WKScriptMessage.mock(
            name: "contentScopeScripts",
            body: [
                "context": "contentScopeScripts",
                "featureName": "serp",
                "method": "unknownMethod",
                "id": "test-id-1",
                "params": [:]
            ]
        )

        let action = broker.messageHandlerFor(message)
        let json = try await broker.execute(action: action, original: message)

        let data = try XCTUnwrap(json.data(using: .utf8))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(dict["context"] as? String, "contentScopeScripts")
        XCTAssertEqual(dict["featureName"] as? String, "serp")
        XCTAssertEqual(dict["id"] as? String, "test-id-1")
        let error = try XCTUnwrap(dict["error"] as? [String: Any])
        XCTAssertEqual(error["message"] as? String, "Message not implemented")
    }
}

private struct MockDuckDuckGoHostProvider: UserScriptHostProvider {
    func hostForMessage(_ message: UserScriptMessage) -> String {
        "duckduckgo.com"
    }
}

private final class MockInstallOriginVariantProvider: InstallOriginVariantProviding {
    var result: String?
    var lastCampaign: String?

    func installOriginVariant(forCampaign campaign: String?) -> String? {
        lastCampaign = campaign
        return result
    }
}
