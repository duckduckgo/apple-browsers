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
import Persistence
import PersistenceTestingUtils
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

    @MainActor func testGetAIChatPageContext() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatPageContext.rawValue))
        let result = try await handler([""], WKScriptMessage())

        XCTAssertTrue(mockHandler.didGetAIChatPageContext, "getAIChatPageContext should be called")
        XCTAssertNil(result, "Expected result to be nil")
    }

    @MainActor func testStoreMigrationData() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.storeMigrationData.rawValue))
        let result = try await handler([""], WKScriptMessage())

        XCTAssertTrue(mockHandler.didStoreMigrationData, "storeMigrationData should be called")
        XCTAssertNil(result, "Expected result to be nil")
    }

    @MainActor func testGetMigrationDataByIndex() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.getMigrationDataByIndex.rawValue))
        let result = try await handler([""], WKScriptMessage())

        XCTAssertTrue(mockHandler.didGetMigrationDataByIndex, "getMigrationDataByIndex should be called")
        XCTAssertNil(result, "Expected result to be nil")
    }

    @MainActor func testGetMigrationInfo() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.getMigrationInfo.rawValue))
        let result = try await handler([""], WKScriptMessage())

        XCTAssertTrue(mockHandler.didGetMigrationInfo, "getMigrationInfo should be called")
        XCTAssertNil(result, "Expected result to be nil")
    }

    @MainActor func testClearMigrationData() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.clearMigrationData.rawValue))
        let result = try await handler([""], WKScriptMessage())

        XCTAssertTrue(mockHandler.didClearMigrationData, "clearMigrationData should be called")
        XCTAssertNil(result, "Expected result to be nil")
    }
}

// swiftlint:disable inclusive_language
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
    var didOpenTranslationSourceLink = false
    var didOpenAIChatLink = false

    var didSubmitAIChatNativePrompt = false
    var aiChatNativePromptSubject = PassthroughSubject<AIChatNativePrompt, Never>()

    var didGetAIChatPageContext = false
    var didSubmitAIChatPageContext = false
    var didTogglePageContextTelemetry = false
    var pageContextSubject = PassthroughSubject<AIChatPageContextData?, Never>()
    var pageContextRequestedSubject = PassthroughSubject<Void, Never>()
    var chatRestorationDataSubject = PassthroughSubject<AIChatRestorationData?, Never>()

    var didReportMetric = false

    // Migration tracking flags
    var didStoreMigrationData = false
    var didGetMigrationDataByIndex = false
    var didGetMigrationInfo = false
    var didClearMigrationData = false

    // Sync tracking flags
    var didGetSyncStatus = false
    var didGetScopedSyncAuthToken = false
    var didEncryptWithSyncMasterKey = false
    var didDecryptWithSyncMasterKey = false
    var didSendToSyncSettings = false
    var didSendToSetupSync = false

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

    func openTranslationSourceLink(params: Any, message: any UserScriptMessage) async -> (any Encodable)? {
        didOpenTranslationSourceLink = true
        return nil
    }

    func openAIChatLink(params: Any, message: any UserScriptMessage) async -> (any Encodable)? {
        didOpenAIChatLink = true
        return nil
    }

    func getAIChatPageContext(params: Any, message: any UserScriptMessage) -> (any Encodable)? {
        didGetAIChatPageContext = true
        return nil
    }

    var pageContextPublisher: AnyPublisher<AIChatPageContextData?, Never> {
        pageContextSubject.eraseToAnyPublisher()
    }

    var pageContextRequestedPublisher: AnyPublisher<Void, Never> {
        pageContextRequestedSubject.eraseToAnyPublisher()
    }

    var chatRestorationDataPublisher: AnyPublisher<AIChatRestorationData?, Never> {
        chatRestorationDataSubject.eraseToAnyPublisher()
    }

    func submitAIChatPageContext(_ pageContext: AIChatPageContextData?) {
        didSubmitAIChatPageContext = true
    }

    func reportMetric(params: Any, message: UserScriptMessage) async -> Encodable? {
        didReportMetric = true
        return nil
    }

    func togglePageContextTelemetry(params: Any, message: any UserScriptMessage) -> (any Encodable)? {
        didTogglePageContextTelemetry = true
        return nil
    }

    // MARK: - Sync stubs

    func getSyncStatus(params: Any, message: UserScriptMessage) -> Encodable? {
        didGetSyncStatus = true
        return nil
    }

    func getScopedSyncAuthToken(params: Any, message: UserScriptMessage) async -> Encodable? {
        didGetScopedSyncAuthToken = true
        return nil
    }

    func encryptWithSyncMasterKey(params: Any, message: UserScriptMessage) -> Encodable? {
        didEncryptWithSyncMasterKey = true
        return nil
    }

    func decryptWithSyncMasterKey(params: Any, message: UserScriptMessage) -> Encodable? {
        didDecryptWithSyncMasterKey = true
        return nil
    }

    func sendToSyncSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        didSendToSyncSettings = true
        return nil
    }

    func sendToSetupSync(params: Any, message: UserScriptMessage) -> Encodable? {
        didSendToSetupSync = true
        return nil
    }

    func setAIChatHistoryEnabled(params: Any, message: any UserScriptMessage) -> (any Encodable)? {
        return nil
    }

    // Migration data mocks
    func storeMigrationData(params: Any, message: UserScriptMessage) -> Encodable? {
        didStoreMigrationData = true
        return nil
    }
    func getMigrationDataByIndex(params: Any, message: UserScriptMessage) -> Encodable? {
        didGetMigrationDataByIndex = true
        return nil
    }
    func getMigrationInfo(params: Any, message: UserScriptMessage) -> Encodable? {
        didGetMigrationInfo = true
        return nil
    }
    func clearMigrationData(params: Any, message: UserScriptMessage) -> Encodable? {
        didClearMigrationData = true
        return nil
    }
}
// swiftlint:enable inclusive_language

func AIChatMockDebugSettings() -> any KeyedStoring<AIChatDebugURLSettings> {
    return MockKeyValueStore().keyedStoring()
}

private final class MockAIChatMessageHandling: AIChatMessageHandling {
    func getDataForMessageType(_ type: DuckDuckGo_Privacy_Browser.AIChatMessageType) -> (any Encodable)? {
        nil
    }

    func setData(_ data: Any?, forMessageType type: DuckDuckGo_Privacy_Browser.AIChatMessageType) {}
}
