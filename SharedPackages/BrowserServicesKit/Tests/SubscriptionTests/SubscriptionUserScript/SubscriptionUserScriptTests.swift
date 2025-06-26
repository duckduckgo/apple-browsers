//
//  SubscriptionUserScriptTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

@testable import Subscription
import SubscriptionTestingUtilities
import UserScript
import WebKit
import XCTest

final class SubscriptionUserScriptTests: XCTestCase {

    var handler: MockSubscriptionUserScriptHandler!
    var userScript: SubscriptionUserScript!

    override func setUp() async throws {
        handler = MockSubscriptionUserScriptHandler()
        userScript = SubscriptionUserScript(handler: handler)
    }

    func testThatPublicInitializerSetsUpHandlerWithCorrectArguments() throws {
        let subscriptionManager = SubscriptionAuthV1toV2BridgeMock()
        userScript = SubscriptionUserScript(platform: .ios,
                                          subscriptionManager: subscriptionManager,
                                          paidAIChatFlagStatusProvider: { false },
                                          navigationDelegate: nil)
        let messageHandler = try XCTUnwrap(userScript.handler as? SubscriptionUserScriptHandler)
        XCTAssertEqual(messageHandler.platform, .ios)
        XCTAssertIdentical(messageHandler.subscriptionManager as AnyObject, subscriptionManager)
    }

    func testThatHandshakeMessageIsPassedToHandler() async throws {
        try await handleMessageIgnoringResponse(named: SubscriptionUserScript.MessageName.handshake)
        XCTAssertEqual(handler.handshakeCallCount, 1)
        XCTAssertEqual(handler.subscriptionDetailsCallCount, 0)
        XCTAssertEqual(handler.getAuthAccessTokenCallCount, 0)
        XCTAssertEqual(handler.getFeatureConfigCallCount, 0)
        XCTAssertEqual(handler.backToSettingsCallCount, 0)
        XCTAssertEqual(handler.openSubscriptionActivationCallCount, 0)
        XCTAssertEqual(handler.openSubscriptionPurchaseCallCount, 0)
    }

    func testThatSubscriptionDetailsMessageIsPassedToHandler() async throws {
        try await handleMessageIgnoringResponse(named: SubscriptionUserScript.MessageName.subscriptionDetails)
        XCTAssertEqual(handler.handshakeCallCount, 0)
        XCTAssertEqual(handler.subscriptionDetailsCallCount, 1)
        XCTAssertEqual(handler.getAuthAccessTokenCallCount, 0)
        XCTAssertEqual(handler.getFeatureConfigCallCount, 0)
        XCTAssertEqual(handler.backToSettingsCallCount, 0)
        XCTAssertEqual(handler.openSubscriptionActivationCallCount, 0)
        XCTAssertEqual(handler.openSubscriptionPurchaseCallCount, 0)
    }

    func testThatGetAuthAccessTokenMessageIsPassedToHandler() async throws {
        try await handleMessageIgnoringResponse(named: SubscriptionUserScript.MessageName.getAuthAccessToken)
        XCTAssertEqual(handler.handshakeCallCount, 0)
        XCTAssertEqual(handler.subscriptionDetailsCallCount, 0)
        XCTAssertEqual(handler.getAuthAccessTokenCallCount, 1)
        XCTAssertEqual(handler.getFeatureConfigCallCount, 0)
        XCTAssertEqual(handler.backToSettingsCallCount, 0)
        XCTAssertEqual(handler.openSubscriptionActivationCallCount, 0)
        XCTAssertEqual(handler.openSubscriptionPurchaseCallCount, 0)
    }

    func testThatGetFeatureConfigMessageIsPassedToHandler() async throws {
        try await handleMessageIgnoringResponse(named: SubscriptionUserScript.MessageName.getFeatureConfig)
        XCTAssertEqual(handler.handshakeCallCount, 0)
        XCTAssertEqual(handler.subscriptionDetailsCallCount, 0)
        XCTAssertEqual(handler.getAuthAccessTokenCallCount, 0)
        XCTAssertEqual(handler.getFeatureConfigCallCount, 1)
        XCTAssertEqual(handler.backToSettingsCallCount, 0)
        XCTAssertEqual(handler.openSubscriptionActivationCallCount, 0)
        XCTAssertEqual(handler.openSubscriptionPurchaseCallCount, 0)
    }

    func testThatBackToSettingsMessageIsPassedToHandler() async throws {
        try await handleMessageIgnoringResponse(named: SubscriptionUserScript.MessageName.backToSettings)
        XCTAssertEqual(handler.handshakeCallCount, 0)
        XCTAssertEqual(handler.subscriptionDetailsCallCount, 0)
        XCTAssertEqual(handler.getAuthAccessTokenCallCount, 0)
        XCTAssertEqual(handler.getFeatureConfigCallCount, 0)
        XCTAssertEqual(handler.backToSettingsCallCount, 1)
        XCTAssertEqual(handler.openSubscriptionActivationCallCount, 0)
        XCTAssertEqual(handler.openSubscriptionPurchaseCallCount, 0)
    }

    func testThatOpenSubscriptionActivationMessageIsPassedToHandler() async throws {
        try await handleMessageIgnoringResponse(named: SubscriptionUserScript.MessageName.openSubscriptionActivation)
        XCTAssertEqual(handler.handshakeCallCount, 0)
        XCTAssertEqual(handler.subscriptionDetailsCallCount, 0)
        XCTAssertEqual(handler.getAuthAccessTokenCallCount, 0)
        XCTAssertEqual(handler.getFeatureConfigCallCount, 0)
        XCTAssertEqual(handler.backToSettingsCallCount, 0)
        XCTAssertEqual(handler.openSubscriptionActivationCallCount, 1)
        XCTAssertEqual(handler.openSubscriptionPurchaseCallCount, 0)
    }

    func testThatOpenSubscriptionPurchaseMessageIsPassedToHandler() async throws {
        try await handleMessageIgnoringResponse(named: SubscriptionUserScript.MessageName.openSubscriptionPurchase)
        XCTAssertEqual(handler.handshakeCallCount, 0)
        XCTAssertEqual(handler.subscriptionDetailsCallCount, 0)
        XCTAssertEqual(handler.getAuthAccessTokenCallCount, 0)
        XCTAssertEqual(handler.getFeatureConfigCallCount, 0)
        XCTAssertEqual(handler.backToSettingsCallCount, 0)
        XCTAssertEqual(handler.openSubscriptionActivationCallCount, 0)
        XCTAssertEqual(handler.openSubscriptionPurchaseCallCount, 1)
    }

    // MARK: - Helpers

    private func handleMessageIgnoringResponse<MessageName: RawRepresentable>(
        named messageName: MessageName,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws where MessageName.RawValue == String {

        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: messageName.rawValue), file: file, line: line)
        _ = try await handler([], WKScriptMessage())
    }
}
