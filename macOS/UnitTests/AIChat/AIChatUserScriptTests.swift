//
//  AIChatUserScriptTests.swift
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

import AIChat
import Combine
import UserScript
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class AIChatUserScriptTests: XCTestCase {
    var mockHandler: MockAIChatUserScriptHandler!
    var userScript: AIChatUserScript!

    override func setUp() {
        super.setUp()
        mockHandler = MockAIChatUserScriptHandler()
        userScript = AIChatUserScript(handler: mockHandler, urlSettings: AIChatMockDebugSettings())
    }

    override func tearDown() {
        mockHandler = nil
        userScript = nil
        super.tearDown()
    }

    @MainActor func testOpenSettingsMessageTriggersOpenSettingsMethod() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.openAIChatSettings.rawValue))
        _ = try await handler([""], WKScriptMessage())

        XCTAssertTrue(mockHandler.didOpenSettings, "openSettings should be called")
    }

    @MainActor func testGetAIChatNativeConfigValues() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatNativeConfigValues.rawValue))
        let result = try await handler([""], WKScriptMessage())

        XCTAssertTrue(mockHandler.didGetConfigValues, "getAIChatNativeConfigValues should be called")
        XCTAssertNil(result, "Expected result to be nil")
    }

    @MainActor func testCloseAIChat() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.closeAIChat.rawValue))
        let result = try await handler([""], WKScriptMessage())

        XCTAssertTrue(mockHandler.didCloseChat, "closeAIChat should be called")
        XCTAssertNil(result, "Expected result to be nil")
    }

    @MainActor func testGetAIChatNativePrompt() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatNativePrompt.rawValue))
        let result = try await handler([""], WKScriptMessage())

        XCTAssertTrue(mockHandler.didGetPrompt, "getAIChatNativePrompt should be called")
        XCTAssertNil(result, "Expected result to be nil")
    }

    @MainActor func testOpenAIChat() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.openAIChat.rawValue))
        let result = try await handler([""], WKScriptMessage())

        XCTAssertTrue(mockHandler.didOpenChat, "openAIChat should be called")
        XCTAssertNil(result, "Expected result to be nil")
    }

    @MainActor func testGetAIChatNativeHandoffData() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatNativeHandoffData.rawValue))
        let result = try await handler([""], WKScriptMessage())

        XCTAssertTrue(mockHandler.didGetHandoffData, "getAIChatNativeHandoffData should be called")
        XCTAssertNil(result, "Expected result to be nil")
    }
}

final class MockAIChatUserScriptHandler: AIChatUserScriptHandling {
    var didOpenSettings = false
    var didGetConfigValues = false
    var didCloseChat = false
    var didGetPrompt = false
    var didOpenChat = false
    var didGetHandoffData = false

    var didRecordChat = false
    var didRestoreChat = false
    var didRemoveChat = false
    var didOpenSummarizationSourceLink = false

    var didSubmitAIChatNativePrompt = false
    var aiChatNativePromptSubject = PassthroughSubject<AIChatNativePrompt, Never>()

    var messageHandling: any DuckDuckGo_Privacy_Browser.AIChatMessageHandling

    init(messageHandling: any AIChatMessageHandling = MockAIChatMessageHandling()) {
        self.messageHandling = messageHandling
    }

    func openAIChatSettings(params: Any, message: UserScriptMessage) async -> (any Encodable)? {
        didOpenSettings = true
        return nil
    }

    func getAIChatNativeConfigValues(params: Any, message: UserScriptMessage) -> (any Encodable)? {
        didGetConfigValues = true
        return nil
    }

    func closeAIChat(params: Any, message: UserScriptMessage) -> (any Encodable)? {
        didCloseChat = true
        return nil
    }

    func getAIChatNativePrompt(params: Any, message: UserScriptMessage) -> (any Encodable)? {
        didGetPrompt = true
        return nil
    }

    func openAIChat(params: Any, message: any UserScriptMessage) async -> (any Encodable)? {
        didOpenChat = true
        return nil
    }

    func getAIChatNativeHandoffData(params: Any, message: any UserScriptMessage) -> (any Encodable)? {
        didGetHandoffData = true
        return nil
    }

    func recordChat(params: Any, message: any UserScriptMessage) -> (any Encodable)? {
        didRecordChat = true
        return nil
    }

    func restoreChat(params: Any, message: any UserScriptMessage) -> (any Encodable)? {
        didRestoreChat = true
        return nil
    }

    func removeChat(params: Any, message: any UserScriptMessage) -> (any Encodable)? {
        didRemoveChat = true
        return nil
    }

    func submitAIChatNativePrompt(_ prompt: AIChatNativePrompt) {
        didSubmitAIChatNativePrompt = true
    }

    var aiChatNativePromptPublisher: AnyPublisher<AIChatNativePrompt, Never> {
        aiChatNativePromptSubject.eraseToAnyPublisher()
    }

    func openSummarizationSourceLink(params: Any, message: any UserScriptMessage) async -> (any Encodable)? {
        didOpenSummarizationSourceLink = true
        return nil
    }
}

final class AIChatMockDebugSettings: AIChatDebugURLSettingsRepresentable {
    var customURLHostname: String?
    var customURL: String?
    func reset() { }
}

private final class MockAIChatMessageHandling: AIChatMessageHandling {
    func getDataForMessageType(_ type: DuckDuckGo_Privacy_Browser.AIChatMessageType) -> (any Encodable)? {
        nil
    }

    func setData(_ data: Any?, forMessageType type: DuckDuckGo_Privacy_Browser.AIChatMessageType) {}
}
