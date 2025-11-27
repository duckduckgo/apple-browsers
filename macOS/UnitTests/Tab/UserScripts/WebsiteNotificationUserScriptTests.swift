//
//  WebsiteNotificationUserScriptTests.swift
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

/// Tests for WebsiteNotificationUserScript configuration and message handling.
/// Each test is isolated with its own instance created in setUp.
final class WebsiteNotificationUserScriptTests: XCTestCase {

    var userScript: WebsiteNotificationUserScript!

    override func setUp() {
        super.setUp()
        userScript = WebsiteNotificationUserScript()
    }

    override func tearDown() {
        userScript = nil
        super.tearDown()
    }

    // MARK: - Configuration Tests

    func testInjectionTimeIsAtDocumentStart() {
        // Script must inject before page JS runs to polyfill window.Notification
        XCTAssertEqual(userScript.injectionTime, .atDocumentStart)
    }

    func testForMainFrameOnlyIsFalse() {
        // Script should run in iframes too (sites may use iframes for notifications)
        XCTAssertFalse(userScript.forMainFrameOnly)
    }

    func testMessageNamesContainsExpectedHandler() {
        XCTAssertEqual(userScript.messageNames, ["websiteNotification"])
    }

    func testRequiresRunInPageContentWorld() {
        // Must run in page content world to polyfill window.Notification
        XCTAssertTrue(userScript.requiresRunInPageContentWorld)
    }

    func testSourceIsNotEmpty() {
        // Basic sanity check that we have JS source
        XCTAssertFalse(userScript.source.isEmpty)
    }

    func testSourceContainsNotificationPolyfill() {
        // Verify the JS source contains key polyfill components
        XCTAssertTrue(userScript.source.contains("NotificationPolyfill"))
        XCTAssertTrue(userScript.source.contains("window.Notification"))
        XCTAssertTrue(userScript.source.contains("requestPermission"))
    }

    // MARK: - Message Handler Tests

    func testHandleShowMessageWithValidData() {
        // Valid message should not crash - currently logs only
        let mockMessage = WebsiteNotificationMockWKScriptMessage(
            name: "websiteNotification",
            body: [
                "type": "show",
                "title": "Test Title",
                "body": "Test Body",
                "icon": "https://example.com/icon.png",
                "tag": "test-tag"
            ]
        )

        // Should not throw or crash
        userScript.userContentController(WKUserContentController(), didReceive: mockMessage)
    }

    func testHandleShowMessageWithMinimalData() {
        // Minimal valid message (only required type field)
        let mockMessage = WebsiteNotificationMockWKScriptMessage(
            name: "websiteNotification",
            body: ["type": "show"]
        )

        userScript.userContentController(WKUserContentController(), didReceive: mockMessage)
    }

    func testHandleMessageWithInvalidFormat() {
        // Non-dictionary body should be handled gracefully
        let mockMessage = WebsiteNotificationMockWKScriptMessage(
            name: "websiteNotification",
            body: "invalid string body"
        )

        userScript.userContentController(WKUserContentController(), didReceive: mockMessage)
    }

    func testHandleMessageWithMissingType() {
        // Dictionary without 'type' field should be handled gracefully
        let mockMessage = WebsiteNotificationMockWKScriptMessage(
            name: "websiteNotification",
            body: ["title": "Test", "body": "Test body"]
        )

        userScript.userContentController(WKUserContentController(), didReceive: mockMessage)
    }

    func testHandleMessageWithUnknownType() {
        // Unknown type should be handled gracefully
        let mockMessage = WebsiteNotificationMockWKScriptMessage(
            name: "websiteNotification",
            body: ["type": "unknownType"]
        )

        userScript.userContentController(WKUserContentController(), didReceive: mockMessage)
    }
}

// MARK: - Test Helpers

/// Mock WKScriptMessage for testing message handlers without a real WebView
private class WebsiteNotificationMockWKScriptMessage: WKScriptMessage {

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

