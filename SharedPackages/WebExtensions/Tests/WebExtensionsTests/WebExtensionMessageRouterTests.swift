//
//  WebExtensionMessageRouterTests.swift
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

import XCTest
import WebKit
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
final class WebExtensionMessageRouterTests: XCTestCase {

    var router: WebExtensionMessageRouter!
    var mockHandler: MockMessageHandler!
    var mockContext: MockWebExtensionContext!

    override func setUp() {
        super.setUp()
        router = WebExtensionMessageRouter()
        mockHandler = MockMessageHandler(featureName: "testFeatureName")
        mockContext = MockWebExtensionContext(identifier: "test-extension-id")
    }

    override func tearDown() {
        router = nil
        mockHandler = nil
        mockContext = nil
        super.tearDown()
    }

    func testWhenHandlerRegisteredThenMessageIsRouted() async {
        router.registerHandler(mockHandler, for: "test-extension-id")

        let message = WebExtensionMessage(
            featureName: "testFeatureName",
            method: "testMethod",
            id: nil,
            params: ["key": "value"],
            context: "test-extension-id",
            extensionIdentifier: "test-extension-id"
        )

        let result = await router.routeMessage(message)

        XCTAssertEqual(mockHandler.receivedMessages.count, 1)
        XCTAssertEqual(mockHandler.receivedMessages[0].method, "testMethod")

        if case .success = result {
            // Expected
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenNoHandlerRegisteredThenReturnsNoHandler() async {
        let message = WebExtensionMessage(
            featureName: "unknownFeatureName",
            method: "testMethod",
            id: nil,
            context: "test-extension-id",
            extensionIdentifier: "test-extension-id"
        )

        let result = await router.routeMessage(message)

        if case .noHandler = result {
            // Expected
        } else {
            XCTFail("Expected noHandler result")
        }
    }

    func testWhenHandlerUnregisteredThenNoLongerRoutes() async {
        router.registerHandler(mockHandler, for: "test-extension-id")
        router.unregisterHandlers(for: "test-extension-id")

        let message = WebExtensionMessage(
            featureName: "testFeatureName",
            method: "testMethod",
            id: nil,
            context: "test-extension-id",
            extensionIdentifier: "test-extension-id"
        )

        let result = await router.routeMessage(message)

        if case .noHandler = result {
            // Expected
        } else {
            XCTFail("Expected noHandler result")
        }
    }

    func testWhenMultipleHandlersForSameExtensionThenRoutesToCorrectHandler() async {
        let handler1 = MockMessageHandler(featureName: "featureName1")
        let handler2 = MockMessageHandler(featureName: "featureName2")

        router.registerHandler(handler1, for: "test-extension-id")
        router.registerHandler(handler2, for: "test-extension-id")

        let message1 = WebExtensionMessage(
            featureName: "featureName1",
            method: "method1",
            id: nil,
            context: "test-extension-id",
            extensionIdentifier: "test-extension-id"
        )

        let message2 = WebExtensionMessage(
            featureName: "featureName2",
            method: "method2",
            id: nil,
            context: "test-extension-id",
            extensionIdentifier: "test-extension-id"
        )

        _ = await router.routeMessage(message1)
        _ = await router.routeMessage(message2)

        XCTAssertEqual(handler1.receivedMessages.count, 1)
        XCTAssertEqual(handler1.receivedMessages[0].method, "method1")

        XCTAssertEqual(handler2.receivedMessages.count, 1)
        XCTAssertEqual(handler2.receivedMessages[0].method, "method2")
    }

    func testWhenMultipleExtensionsWithSameFeatureNameThenIsolated() async {
        let handler1 = MockMessageHandler(featureName: "sharedFeatureName")
        let handler2 = MockMessageHandler(featureName: "sharedFeatureName")

        router.registerHandler(handler1, for: "extension-1")
        router.registerHandler(handler2, for: "extension-2")

        let message1 = WebExtensionMessage(
            featureName: "sharedFeatureName",
            method: "method1",
            id: nil,
            context: "extension-1",
            extensionIdentifier: "extension-1"
        )

        let message2 = WebExtensionMessage(
            featureName: "sharedFeatureName",
            method: "method2",
            id: nil,
            context: "extension-2",
            extensionIdentifier: "extension-2"
        )

        _ = await router.routeMessage(message1)
        _ = await router.routeMessage(message2)

        XCTAssertEqual(handler1.receivedMessages.count, 1)
        XCTAssertEqual(handler1.receivedMessages[0].method, "method1")

        XCTAssertEqual(handler2.receivedMessages.count, 1)
        XCTAssertEqual(handler2.receivedMessages[0].method, "method2")
    }
}

// MARK: - Mock Classes

@available(macOS 15.4, iOS 18.4, *)
final class MockMessageHandler: WebExtensionMessageHandler {
    var handledFeatureName: String
    var receivedMessages: [WebExtensionMessage] = []
    var responseToReturn: WebExtensionMessageResult = .success(nil)

    init(featureName: String) {
        self.handledFeatureName = featureName
    }

    func handleMessage(_ message: WebExtensionMessage) async -> WebExtensionMessageResult {
        receivedMessages.append(message)
        return responseToReturn
    }
}

@available(macOS 15.4, iOS 18.4, *)
final class MockWebExtensionContext: WKWebExtensionContext {
    private let _uniqueIdentifier: String

    init(identifier: String) {
        self._uniqueIdentifier = identifier
        super.init(for: WKWebExtension())
    }

    override var uniqueIdentifier: String {
        _uniqueIdentifier
    }
}
