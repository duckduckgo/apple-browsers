//
//  WebNotificationsHandlerTests.swift
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

import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

/// Tests for WebNotificationsHandler configuration and message handling.
/// Each test is isolated with its own instance created in setUp.
final class WebNotificationsHandlerTests: XCTestCase {

    var handler: WebNotificationsHandler!

    override func setUp() {
        super.setUp()
        handler = WebNotificationsHandler()
    }

    override func tearDown() {
        handler = nil
        super.tearDown()
    }

    // MARK: - Configuration Tests

    func testFeatureNameIsWebNotifications() {
        XCTAssertEqual(handler.featureName, "webNotifications")
    }

    func testMessageOriginPolicyIsAll() {
        XCTAssertEqual(handler.messageOriginPolicy, .all)
    }

    // MARK: - Handler Registration Tests

    func testHandlerExistsForShowNotification() {
        XCTAssertNotNil(handler.handler(forMethodNamed: "showNotification"))
    }

    func testHandlerExistsForCloseNotification() {
        XCTAssertNotNil(handler.handler(forMethodNamed: "closeNotification"))
    }

    func testHandlerExistsForRequestPermission() {
        XCTAssertNotNil(handler.handler(forMethodNamed: "requestPermission"))
    }

    func testHandlerReturnsNilForUnknownMethod() {
        XCTAssertNil(handler.handler(forMethodNamed: "unknownMethod"))
    }

    // MARK: - showNotification Handler Tests

    func testShowNotificationHandlerWithValidParams() async {
        // Handler should process valid params without throwing
        let params: [String: Any] = [
            "id": "test-id-123",
            "title": "Test Notification",
            "body": "This is a test body",
            "icon": "https://example.com/icon.png",
            "tag": "test-tag"
        ]

        let handlerFunc = handler.handler(forMethodNamed: "showNotification")
        let mockMessage = WebNotificationsHandlerMockWKScriptMessage(name: "webNotifications", body: params)

        let result = try? await handlerFunc?(params, mockMessage)
        XCTAssertNil(result) // showNotification returns nil
    }

    func testShowNotificationHandlerWithMinimalParams() async {
        // Handler should work with only required fields
        let params: [String: Any] = [
            "id": "test-id-456",
            "title": "Minimal Notification"
        ]

        let handlerFunc = handler.handler(forMethodNamed: "showNotification")
        let mockMessage = WebNotificationsHandlerMockWKScriptMessage(name: "webNotifications", body: params)

        let result = try? await handlerFunc?(params, mockMessage)
        XCTAssertNil(result)
    }

    func testShowNotificationHandlerWithInvalidParams() async {
        // Handler should gracefully handle invalid params
        let params = "invalid string params"

        let handlerFunc = handler.handler(forMethodNamed: "showNotification")
        let mockMessage = WebNotificationsHandlerMockWKScriptMessage(name: "webNotifications", body: params)

        // Should not throw
        let result = try? await handlerFunc?(params, mockMessage)
        XCTAssertNil(result)
    }

    // MARK: - closeNotification Handler Tests

    func testCloseNotificationHandlerWithValidParams() async {
        let params: [String: Any] = ["id": "test-id-789"]

        let handlerFunc = handler.handler(forMethodNamed: "closeNotification")
        let mockMessage = WebNotificationsHandlerMockWKScriptMessage(name: "webNotifications", body: params)

        let result = try? await handlerFunc?(params, mockMessage)
        XCTAssertNil(result) // closeNotification returns nil
    }

    func testCloseNotificationHandlerWithInvalidParams() async {
        let params: [String: Any] = [:] // Missing required id

        let handlerFunc = handler.handler(forMethodNamed: "closeNotification")
        let mockMessage = WebNotificationsHandlerMockWKScriptMessage(name: "webNotifications", body: params)

        // Should not throw
        let result = try? await handlerFunc?(params, mockMessage)
        XCTAssertNil(result)
    }

    // MARK: - requestPermission Handler Tests

    func testRequestPermissionHandlerReturnsGranted() async {
        // Currently auto-grants - should return "granted"
        let params: [String: Any] = [:]

        let handlerFunc = handler.handler(forMethodNamed: "requestPermission")
        let mockMessage = WebNotificationsHandlerMockWKScriptMessage(name: "webNotifications", body: params)

        let result = try? await handlerFunc?(params, mockMessage)
        XCTAssertNotNil(result)

        // Verify it's the expected response type
        if let response = result as? WebNotificationsHandler.RequestPermissionResponse {
            XCTAssertEqual(response.permission, "granted")
        } else {
            XCTFail("Expected RequestPermissionResponse")
        }
    }
}

// MARK: - Test Helpers

/// Mock WKScriptMessage for testing message handlers without a real WebView
private class WebNotificationsHandlerMockWKScriptMessage: WKScriptMessage {

    let mockedName: String
    let mockedBody: Any
    let mockedWebView: WKWebView?

    override var name: String { mockedName }
    override var body: Any { mockedBody }
    override var webView: WKWebView? { mockedWebView }

    init(name: String, body: Any, webView: WKWebView? = nil) {
        self.mockedName = name
        self.mockedBody = body
        self.mockedWebView = webView
        super.init()
    }
}

