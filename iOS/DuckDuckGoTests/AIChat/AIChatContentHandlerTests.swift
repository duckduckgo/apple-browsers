//
//  AIChatContentHandlerTests.swift
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

import AIChat
import BrowserServicesKitTestsUtils
import XCTest
import WebKit
@testable import DuckDuckGo

final class AIChatContentHandlerTests: XCTestCase {

    var handler: AIChatContentHandler!
    var mockSettings: MockAIChatSettingsProvider!
    var mockPayloadHandler: AIChatPayloadHandler!
    var mockMetricHandler: MockAIChatPixelMetricHandler!

    override func setUpWithError() throws {
        mockSettings = MockAIChatSettingsProvider()
        mockPayloadHandler = AIChatPayloadHandler()
        mockMetricHandler = MockAIChatPixelMetricHandler()

        handler = AIChatContentHandler(
            aiChatSettings: mockSettings,
            payloadHandler: mockPayloadHandler,
            pixelMetricHandler: mockMetricHandler,
            featureDiscovery: MockFeatureDiscovery()
        )
    }

    // MARK: - setup(with:webView:)

    func testSetupSetsUserScriptDelegate() throws {
        // Given
        let mockUserScript = MockAIChatUserScript()
        let mockWebView = WKWebView()

        // When
        handler.setup(with: mockUserScript, webView: mockWebView)

        // Then
        XCTAssertTrue(mockUserScript.delegateSet)
    }

    func testSetupSetsPayloadHandler() throws {
        // Given
        let mockUserScript = MockAIChatUserScript()
        let mockWebView = WKWebView()

        // When
        handler.setup(with: mockUserScript, webView: mockWebView)

        // Then
        XCTAssertTrue(mockUserScript.payloadHandlerSet)
    }

    func testSetupSetsWebView() throws {
        // Given
        let mockUserScript = MockAIChatUserScript()
        let mockWebView = WKWebView()

        // When
        handler.setup(with: mockUserScript, webView: mockWebView)

        // Then
        XCTAssertTrue(mockUserScript.webViewSet)
    }

    // MARK: - setPayload(payload:)

    func testSetPayloadWithValidPayload() throws {
        // Given
        let payload: AIChatPayload = ["query": "hello world"]

        // When
        handler.setPayload(payload: payload)

        // Then
        let consumed = mockPayloadHandler.consumeData()
        XCTAssertEqual(consumed?["query"] as? String, "hello world")
    }

    func testSetPayloadWithInvalidPayload() throws {
        // Given
        let invalidPayload = "invalid"

        // When
        handler.setPayload(payload: invalidPayload)

        // Then - payload handler should remain empty
        let consumed = mockPayloadHandler.consumeData()
        XCTAssertNil(consumed)
    }

    func testSetPayloadWithNilPayload() throws {
        // Given
        let nilPayload: Any? = nil

        // When
        handler.setPayload(payload: nilPayload)

        // Then - payload handler should remain empty
        let consumed = mockPayloadHandler.consumeData()
        XCTAssertNil(consumed)
    }

    // MARK: - buildQueryURL(query:autoSend:tools:)

    func testBuildQueryURLWithQuery() throws {
        // Given
        let query = "hello world"

        // When
        let url = handler.buildQueryURL(query: query, autoSend: false, tools: nil)

        // Then
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            XCTFail("Invalid URL components")
            return
        }

        let promptItem = components.queryItems?.first { $0.name == AIChatURLParameters.promptQueryName }
        XCTAssertEqual(promptItem?.value, query)
    }

    func testBuildQueryURLWithAutoSend() throws {
        // Given
        let autoSend = true

        // When
        let url = handler.buildQueryURL(query: "test", autoSend: autoSend, tools: nil)

        // Then
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            XCTFail("Invalid URL components")
            return
        }

        let autoSendItem = components.queryItems?.first { $0.name == AIChatURLParameters.autoSubmitPromptQueryName }
        XCTAssertEqual(autoSendItem?.value, AIChatURLParameters.autoSubmitPromptQueryValue)
    }

    func testBuildQueryURLWithTools() throws {
        // Given
        let tools: [AIChatRAGTool] = [.webSearch, .newsSearch]

        // When
        let url = handler.buildQueryURL(query: "test", autoSend: false, tools: tools)

        // Then
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            XCTFail("Invalid URL components")
            return
        }

        let toolItems = components.queryItems?.filter { $0.name == AIChatURLParameters.toolChoiceName }
        XCTAssertEqual(toolItems?.count, 2)
        XCTAssertTrue(toolItems?.contains { $0.value == AIChatRAGTool.webSearch.rawValue } ?? false)
        XCTAssertTrue(toolItems?.contains { $0.value == AIChatRAGTool.newsSearch.rawValue } ?? false)
    }

    func testBuildQueryURLWithEmptyQuery() throws {
        // Given
        let emptyQuery = ""

        // When
        let url = handler.buildQueryURL(query: emptyQuery, autoSend: false, tools: nil)

        // Then
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            XCTFail("Invalid URL components")
            return
        }

        let promptItem = components.queryItems?.first { $0.name == AIChatURLParameters.promptQueryName }
        XCTAssertNil(promptItem)
    }

    func testBuildQueryURLWithoutQueryReturnsBaseURL() throws {
        // Given
        let nilQuery: String? = nil

        // When
        let url = handler.buildQueryURL(query: nilQuery, autoSend: false, tools: nil)

        // Then
        XCTAssertEqual(url, mockSettings.aiChatURL)
    }

    func testBuildQueryURLReplacesExistingQueryParameters() throws {
        // Given
        let firstQuery = "first"
        let secondQuery = "second"

        // When
        let url1 = handler.buildQueryURL(query: firstQuery, autoSend: false, tools: nil)
        let url2 = handler.buildQueryURL(query: secondQuery, autoSend: false, tools: nil)

        // Then - first URL contains first query
        guard let components1 = URLComponents(url: url1, resolvingAgainstBaseURL: false) else {
            XCTFail("Invalid URL components for url1")
            return
        }
        let promptItem1 = components1.queryItems?.first { $0.name == AIChatURLParameters.promptQueryName }
        XCTAssertEqual(promptItem1?.value, firstQuery)

        // And second URL contains only second query (not both)
        guard let components2 = URLComponents(url: url2, resolvingAgainstBaseURL: false) else {
            XCTFail("Invalid URL components for url2")
            return
        }
        let promptItems = components2.queryItems?.filter { $0.name == AIChatURLParameters.promptQueryName }
        XCTAssertEqual(promptItems?.count, 1)
        XCTAssertEqual(promptItems?.first?.value, secondQuery)
    }
    
    // MARK: - Submit Actions

    func testSubmitStartChatActionCallsUserScript() throws {
        // Given
        let mockUserScript = MockAIChatUserScript()
        let mockWebView = WKWebView()
        handler.setup(with: mockUserScript, webView: mockWebView)

        // When
        handler.submitStartChatAction()

        // Then
        XCTAssertEqual(mockUserScript.submitStartChatActionCallCount, 1)
    }

    func testSubmitOpenSettingsActionCallsUserScript() throws {
        // Given
        let mockUserScript = MockAIChatUserScript()
        let mockWebView = WKWebView()
        handler.setup(with: mockUserScript, webView: mockWebView)

        // When
        handler.submitOpenSettingsAction()

        // Then
        XCTAssertEqual(mockUserScript.submitOpenSettingsActionCallCount, 1)
    }
    
    func testSubmitToggleSidebarActionCallsUserScript() throws {
        // Given
        let mockUserScript = MockAIChatUserScript()
        let mockWebView = WKWebView()
        handler.setup(with: mockUserScript, webView: mockWebView)

        // When
        handler.submitToggleSidebarAction()

        // Then
        XCTAssertEqual(mockUserScript.submitToggleSidebarActionCallCount, 1)
    }
}

// MARK: - Mocks

final class MockAIChatRequestAuthHandler: AIChatRequestAuthorizationHandling {
    func shouldAllowRequestWithNavigationAction(_ navigationAction: WKNavigationAction) -> Bool {
        true
    }
}

final class MockAIChatUserScript: AIChatUserScriptProviding {
    var delegate: (any DuckDuckGo.AIChatUserScriptDelegate)? {
        get { nil }
        set { delegateSet = true }
    }
    var webView: WKWebView? {
        get { nil }
        set { webViewSet = true }
    }
    var delegateSet = false
    var webViewSet = false
    var payloadHandlerSet = false
    var submitStartChatActionCallCount = 0
    var submitOpenSettingsActionCallCount = 0
    var submitToggleSidebarActionCallCount = 0

    func setPayloadHandler(_ payloadHandler: any AIChat.AIChatConsumableDataHandling) {
        payloadHandlerSet = true
    }

    func submitStartChatAction() {
        submitStartChatActionCallCount += 1
    }

    func submitOpenSettingsAction() {
        submitOpenSettingsActionCallCount += 1
    }

    func submitToggleSidebarAction() {
        submitToggleSidebarActionCallCount += 1
    }
}
