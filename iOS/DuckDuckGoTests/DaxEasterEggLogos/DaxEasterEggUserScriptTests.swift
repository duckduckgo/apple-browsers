//
//  DaxEasterEggUserScriptTests.swift
//  DuckDuckGo
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
@testable import DuckDuckGo

final class DaxEasterEggUserScriptTests: XCTestCase {

    var userScript: DaxEasterEggUserScript!
    var mockHandler: MockDaxEasterEggHandler!

    override func setUpWithError() throws {
        userScript = DaxEasterEggUserScript()
        mockHandler = MockDaxEasterEggHandler()
        userScript.daxEasterEggHandler = mockHandler
    }

    override func tearDownWithError() throws {
        userScript = nil
        mockHandler = nil
    }

    // MARK: - UserScript Protocol Conformance Tests

    func testUserScriptProperties() {
        XCTAssertFalse(userScript.source.isEmpty, "UserScript source should not be empty")
        XCTAssertEqual(userScript.injectionTime, .atDocumentStart)
        XCTAssertTrue(userScript.forMainFrameOnly)
        XCTAssertEqual(userScript.messageNames, ["daxEasterEggHandler"])
        XCTAssertTrue(userScript.requiresRunInPageContentWorld)
    }

    func testJavaScriptSourceContainsRequiredFunctions() {
        let source = userScript.source
        XCTAssertTrue(source.contains("window.extractDaxEasterEggLogo"), "Should define global extraction function")
        XCTAssertTrue(source.contains("webkit.messageHandlers.daxEasterEggHandler"), "Should use correct message handler")
        XCTAssertTrue(source.contains(".js-logo-ddg"), "Should search for primary logo selector")
        XCTAssertTrue(source.contains("data-dynamic-logo"), "Should look for dynamic logo data attribute")
    }

    func testJavaScriptSourceContainsAlternativeSelectors() {
        let source = userScript.source
        XCTAssertTrue(source.contains(".logo-dynamic"), "Should search for alternative logo selector")
        XCTAssertTrue(source.contains("[data-dynamic-logo]"), "Should search for generic data attribute selector")
    }

    func testJavaScriptSourceContainsLogging() {
        let source = userScript.source
        XCTAssertTrue(source.contains("console.log"), "Should include debug logging")
        XCTAssertTrue(source.contains("DaxEasterEgg:"), "Should include consistent log prefixes")
    }

    func testJavaScriptSourceFormatsOutputCorrectly() {
        let source = userScript.source
        XCTAssertTrue(source.contains("'themed|'"), "Should format output with themed prefix")
        XCTAssertTrue(source.contains("window.location.href"), "Should include page URL in message")
    }

    func testJavaScriptSourceAlwaysSendsMessage() {
        let source = userScript.source
        XCTAssertTrue(source.contains("Always send message to native"), "Should always send message regardless of logo presence")
        XCTAssertFalse(source.contains("not sending message"), "Should not have conditional message sending")
    }

    // MARK: - Message Handling Tests

    func testUserContentController_WithValidMessage_CallsHandler() {
        // Given
        let mockContentController = WKUserContentController()
        let mockMessage = createMockScriptMessage(
            body: ["logoURL": "themed|/dist/logos/dynamic/terminator.png", "url": "https://duckduckgo.com/?q=test"]
        )

        // When
        userScript.userContentController(mockContentController, didReceive: mockMessage)

        // Then
        XCTAssertEqual(mockHandler.receivedLogoURL, "themed|/dist/logos/dynamic/terminator.png")
        XCTAssertEqual(mockHandler.receivedPageURL, "https://duckduckgo.com/?q=test")
        XCTAssertEqual(mockHandler.callCount, 1)
    }

    func testUserContentController_WithNilLogoURL_CallsHandlerWithNil() {
        // Given
        let mockContentController = WKUserContentController()
        let mockMessage = createMockScriptMessage(
            body: ["url": "https://duckduckgo.com/?q=test"]
        )

        // When
        userScript.userContentController(mockContentController, didReceive: mockMessage)

        // Then
        XCTAssertNil(mockHandler.receivedLogoURL)
        XCTAssertEqual(mockHandler.receivedPageURL, "https://duckduckgo.com/?q=test")
    }

    func testUserContentController_WithInvalidMessageBody_DoesNotCallHandler() {
        // Given
        let mockContentController = WKUserContentController()
        let mockMessage = createMockScriptMessage(body: "invalid-string-body")

        // When
        userScript.userContentController(mockContentController, didReceive: mockMessage)

        // Then
        XCTAssertEqual(mockHandler.callCount, 0)
    }

    func testUserContentController_WithMissingURL_DoesNotCallHandler() {
        // Given
        let mockContentController = WKUserContentController()
        let mockMessage = createMockScriptMessage(
            body: ["logoURL": "themed|/dist/logos/dynamic/test.png"]  // Missing "url" key
        )

        // When
        userScript.userContentController(mockContentController, didReceive: mockMessage)

        // Then
        XCTAssertEqual(mockHandler.callCount, 0)
    }

    func testUserContentController_WithNonStringURL_DoesNotCallHandler() {
        // Given
        let mockContentController = WKUserContentController()
        let mockMessage = createMockScriptMessage(
            body: ["logoURL": "themed|/test.png", "url": 123]  // Non-string URL
        )

        // When
        userScript.userContentController(mockContentController, didReceive: mockMessage)

        // Then
        XCTAssertEqual(mockHandler.callCount, 0)
    }

    // MARK: - Handler Integration Tests

    func testHandlerProperty_CanBeSetAndRetrieved() {
        // Given
        let newHandler = MockDaxEasterEggHandler()

        // When
        userScript.daxEasterEggHandler = newHandler

        // Then
        XCTAssertTrue(userScript.daxEasterEggHandler === newHandler)
    }

    func testHandlerProperty_CanBeSetToNil() {
        // Given
        userScript.daxEasterEggHandler = mockHandler

        // When
        userScript.daxEasterEggHandler = nil

        // Then
        XCTAssertNil(userScript.daxEasterEggHandler)
    }

    func testUserContentController_WithNilHandler_DoesNotCrash() {
        // Given
        userScript.daxEasterEggHandler = nil
        let mockContentController = WKUserContentController()
        let mockMessage = createMockScriptMessage(
            body: ["logoURL": "themed|/test.png", "url": "https://duckduckgo.com/?q=test"]
        )

        // When/Then - should not crash
        XCTAssertNoThrow {
            self.userScript.userContentController(mockContentController, didReceive: mockMessage)
        }
    }

    // MARK: - Edge Case Tests

    func testUserContentController_WithEmptyDictionary_DoesNotCallHandler() {
        // Given
        let mockContentController = WKUserContentController()
        let mockMessage = createMockScriptMessage(body: [:])

        // When
        userScript.userContentController(mockContentController, didReceive: mockMessage)

        // Then
        XCTAssertEqual(mockHandler.callCount, 0)
    }

    func testUserContentController_WithNestedDictionary_HandlesCorrectly() {
        // Given
        let mockContentController = WKUserContentController()
        let mockMessage = createMockScriptMessage(
            body: [
                "logoURL": "themed|/nested/path/logo.png",
                "url": "https://duckduckgo.com/?q=nested%20test",
                "extraData": ["key": "value"]  // Should be ignored
            ]
        )

        // When
        userScript.userContentController(mockContentController, didReceive: mockMessage)

        // Then
        XCTAssertEqual(mockHandler.receivedLogoURL, "themed|/nested/path/logo.png")
        XCTAssertEqual(mockHandler.receivedPageURL, "https://duckduckgo.com/?q=nested%20test")
        XCTAssertEqual(mockHandler.callCount, 1)
    }

    // MARK: - Helper Methods

    private func createMockScriptMessage(body: Any) -> WKScriptMessage {
        let mockMessage = EasterEggMockScriptMessage()
        mockMessage.body = body
        return mockMessage
    }
}

// MARK: - Mock Classes

class MockDaxEasterEggHandler: DaxEasterEggHandling {
    weak var delegate: DaxEasterEggDelegate?
    
    var receivedLogoURL: String?
    var receivedPageURL: String?
    var callCount = 0
    var extractCallCount = 0
    var resetCallCount = 0
    
    func extractLogosForCurrentPage() {
        extractCallCount += 1
    }
    
    func didExtractLogo(_ logoURL: String?, from pageURL: String) {
        receivedLogoURL = logoURL
        receivedPageURL = pageURL
        callCount += 1
    }
    
    func reset() {
        resetCallCount += 1
    }
}

class EasterEggMockScriptMessage: WKScriptMessage {
    override var body: Any {
        get { return _body }
        set { _body = newValue }
    }
    private var _body: Any = ""
    
    override var webView: WKWebView? { return nil }
    override var frameInfo: WKFrameInfo { return WKFrameInfo() }
    override var name: String { return "daxEasterEggHandler" }
}
