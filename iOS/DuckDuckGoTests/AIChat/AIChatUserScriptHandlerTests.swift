//
//  AIChatUserScriptHandlerTests.swift
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


import Combine
import DDGSync
import XCTest
@testable import DuckDuckGo
import UserScript
import WebKit
@testable import AIChat

// swiftlint:disable inclusive_language
class AIChatUserScriptHandlerTests: XCTestCase {
    var aiChatUserScriptHandler: AIChatUserScriptHandler!
    var mockFeatureFlagger: MockFeatureFlagger!
    var mockPayloadHandler: AIChatPayloadHandler!
    var mockAIChatSyncHandler: MockAIChatSyncHandling!
    var mockAIChatFullModeFeature: MockAIChatFullModeFeatureProviding!
    var mockAIChatContextualModeFeature: MockAIChatContextualModeFeatureProviding!
    private var mockUserDefaults: UserDefaults!

    private var mockSuiteName: String {
        String(describing: self)
    }

    override func setUp() {
        super.setUp()
        mockFeatureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        mockPayloadHandler = AIChatPayloadHandler()
        mockAIChatSyncHandler = MockAIChatSyncHandling()
        mockAIChatFullModeFeature = MockAIChatFullModeFeatureProviding()
        mockAIChatContextualModeFeature = MockAIChatContextualModeFeatureProviding()

        mockUserDefaults = UserDefaults(suiteName: mockSuiteName)
        mockUserDefaults.removePersistentDomain(forName: mockSuiteName)

        let experimentalAIChatManager = ExperimentalAIChatManager(featureFlagger: mockFeatureFlagger, userDefaults: mockUserDefaults)
        aiChatUserScriptHandler = AIChatUserScriptHandler(
            experimentalAIChatManager: experimentalAIChatManager,
            syncHandler: mockAIChatSyncHandler,
            featureFlagger: mockFeatureFlagger,
            aichatFullModeFeature: mockAIChatFullModeFeature,
            aichatContextualModeFeature: mockAIChatContextualModeFeature
        )
        aiChatUserScriptHandler.setPayloadHandler(mockPayloadHandler)
    }

    override func tearDown() {
        aiChatUserScriptHandler = nil
        mockFeatureFlagger = nil
        mockPayloadHandler = nil
        mockAIChatSyncHandler = nil
        mockAIChatFullModeFeature = nil
        mockAIChatContextualModeFeature = nil
        super.tearDown()
    }

    func testGetAIChatNativeConfigValues() {
        // Given
        // MockFeatureFlagger is already initialized with .aiChatDeepLink enabled

        // When
        let configValues = aiChatUserScriptHandler.getAIChatNativeConfigValues(params: [], message: MockUserScriptMessage(name: "test", body: [:])) as? AIChatNativeConfigValues

        // Then
        XCTAssertNotNil(configValues)
        XCTAssertEqual(configValues?.isAIChatHandoffEnabled, true)
        XCTAssertEqual(configValues?.platform, "ios")
        XCTAssertEqual(configValues?.supportsHomePageEntryPoint, true)
        XCTAssertEqual(configValues?.supportsAIChatSync, false)
    }
    
    func testGetAIChatNativeConfigValuesWithFullModeFeatureAvailable() {
        // Given
        mockAIChatFullModeFeature.isAvailable = true

        // When
        let configValues = aiChatUserScriptHandler.getAIChatNativeConfigValues(params: [], message: MockUserScriptMessage(name: "test", body: [:])) as? AIChatNativeConfigValues

        // Then
        XCTAssertNotNil(configValues)
        XCTAssertEqual(configValues?.supportsURLChatIDRestoration, true)
        XCTAssertEqual(configValues?.supportsAIChatFullMode, true)
        XCTAssertEqual(configValues?.supportsHomePageEntryPoint, true)
    }
    
    func testGetAIChatNativeConfigValuesWithFullModeFeatureUnavailable() {
        // Given
        mockAIChatFullModeFeature.isAvailable = false

        // When
        let configValues = aiChatUserScriptHandler.getAIChatNativeConfigValues(params: [], message: MockUserScriptMessage(name: "test", body: [:])) as? AIChatNativeConfigValues

        // Then
        XCTAssertNotNil(configValues)
        XCTAssertEqual(configValues?.supportsURLChatIDRestoration, AIChatNativeConfigValues.defaultValues.supportsURLChatIDRestoration)
        XCTAssertEqual(configValues?.supportsAIChatFullMode, false)
        XCTAssertEqual(configValues?.supportsHomePageEntryPoint, AIChatNativeConfigValues.defaultValues.supportsHomePageEntryPoint)
    }

    func testGetAIChatNativeConfigValuesWithContextualModeFeatureAvailable() {
        // Given
        mockAIChatContextualModeFeature.isAvailable = true

        // When
        let configValues = aiChatUserScriptHandler.getAIChatNativeConfigValues(params: [], message: MockUserScriptMessage(name: "test", body: [:])) as? AIChatNativeConfigValues

        // Then
        XCTAssertNotNil(configValues)
        XCTAssertEqual(configValues?.supportsAIChatContextualMode, true)
    }

    func testGetAIChatNativeConfigValuesWithContextualModeFeatureUnavailable() {
        // Given
        mockAIChatContextualModeFeature.isAvailable = false

        // When
        let configValues = aiChatUserScriptHandler.getAIChatNativeConfigValues(params: [], message: MockUserScriptMessage(name: "test", body: [:])) as? AIChatNativeConfigValues

        // Then
        XCTAssertNotNil(configValues)
        XCTAssertEqual(configValues?.supportsAIChatContextualMode, false)
    }

    func testGetAIChatNativeHandoffData() {
        // Given
        let expectedPayload = ["key": "value"]
        mockPayloadHandler.setData(expectedPayload)

        // When
        let handoffData = aiChatUserScriptHandler.getAIChatNativeHandoffData(params: [], message: MockUserScriptMessage(name: "test", body: [:])) as? AIChatNativeHandoffData

        // Then
        XCTAssertNotNil(handoffData)
        XCTAssertEqual(handoffData?.isAIChatHandoffEnabled, true)
        XCTAssertEqual(handoffData?.platform, "ios")
        XCTAssertEqual(handoffData?.aiChatPayload as? [String: String], expectedPayload)
    }

    func testOpenAIChat() async {
        // Given
        let expectation = self.expectation(description: "Notification should be posted")
        let payload = ["key": "value"]
        let message = MockUserScriptMessage(name: "test", body: payload)

        // When
        let result = await aiChatUserScriptHandler.openAIChat(params: payload, message: message)

        // Then
        XCTAssertNil(result)
        // Wait for the notification to be posted
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation])
    }

    // MARK: - Sync

    func testGetSyncStatusPassesFeatureFlagToSyncHandler() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []
        mockAIChatSyncHandler.syncStatus = AIChatSyncHandler.SyncStatus(syncAvailable: false)

        // When
        let response = aiChatUserScriptHandler.getSyncStatus(params: [], message: MockUserScriptMessage(name: "test", body: [:]))

        // Then
        XCTAssertEqual(mockAIChatSyncHandler.getSyncStatusFeatureAvailableCalls, [false])
        XCTAssertNotNil(response as? AIChatPayloadResponse)
    }

    func testGetSyncStatusReturnsPayloadFromSyncHandler() throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatSync]
        mockAIChatSyncHandler.syncStatus = AIChatSyncHandler.SyncStatus(syncAvailable: true,
                                                                        userId: "user",
                                                                        deviceId: "device",
                                                                        deviceName: "My Device",
                                                                        deviceType: "iPhone")

        // When
        let response = aiChatUserScriptHandler.getSyncStatus(params: [], message: MockUserScriptMessage(name: "test", body: [:]))

        // Then
        XCTAssertEqual(mockAIChatSyncHandler.getSyncStatusFeatureAvailableCalls, [true])
        let payloadResponse = try XCTUnwrap(response as? AIChatPayloadResponse)
        let status = try XCTUnwrap(payloadResponse.payload as? AIChatSyncHandler.SyncStatus)
        XCTAssertTrue(payloadResponse.ok)
        XCTAssertTrue(status.syncAvailable)
        XCTAssertEqual(status.userId, "user")
        XCTAssertEqual(status.deviceId, "device")
        XCTAssertEqual(status.deviceName, "My Device")
        XCTAssertEqual(status.deviceType, "iPhone")
    }

    func testGetScopedSyncAuthTokenReturnsSyncUnavailableWhenFeatureOff() async throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []

        // When
        let response = await aiChatUserScriptHandler.getScopedSyncAuthToken(params: [], message: MockUserScriptMessage(name: "test", body: [:]))

        // Then
        let errorResponse = try XCTUnwrap(response as? AIChatErrorResponse)
        XCTAssertEqual(errorResponse.reason, "sync unavailable")
        XCTAssertEqual(mockAIChatSyncHandler.getScopedTokenCallCount, 0)
    }

    func testGetScopedSyncAuthTokenReturnsTokenPayloadWhenFeatureOn() async throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatSync]
        mockAIChatSyncHandler.scopedToken = AIChatSyncHandler.SyncToken(token: "scoped-token")

        // When
        let response = await aiChatUserScriptHandler.getScopedSyncAuthToken(params: [], message: MockUserScriptMessage(name: "test", body: [:]))

        // Then
        XCTAssertEqual(mockAIChatSyncHandler.getScopedTokenCallCount, 1)
        let payloadResponse = try XCTUnwrap(response as? AIChatPayloadResponse)
        let tokenPayload = try XCTUnwrap(payloadResponse.payload as? AIChatSyncHandler.SyncToken)
        XCTAssertEqual(tokenPayload.token, "scoped-token")
    }

    func testEncryptWithSyncMasterKeyReturnsSyncUnavailableWhenFeatureOff() throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []
        mockAIChatSyncHandler.syncTurnedOn = true

        // When
        let response = aiChatUserScriptHandler.encryptWithSyncMasterKey(
            params: ["data": "plain"],
            message: MockUserScriptMessage(name: "test", body: [:]))

        // Then
        let errorResponse = try XCTUnwrap(response as? AIChatErrorResponse)
        XCTAssertEqual(errorResponse.reason, "sync unavailable")
        XCTAssertTrue(mockAIChatSyncHandler.encryptCalls.isEmpty)
    }

    func testEncryptWithSyncMasterKeyReturnsSyncOffWhenSyncNotTurnedOn() throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatSync]
        mockAIChatSyncHandler.syncTurnedOn = false

        // When
        let response = aiChatUserScriptHandler.encryptWithSyncMasterKey(
            params: ["data": "plain"],
            message: MockUserScriptMessage(name: "test", body: [:]))

        // Then
        let errorResponse = try XCTUnwrap(response as? AIChatErrorResponse)
        XCTAssertEqual(errorResponse.reason, "sync off")
        XCTAssertTrue(mockAIChatSyncHandler.encryptCalls.isEmpty)
    }

    func testEncryptWithSyncMasterKeyReturnsEncryptedPayloadWhenSyncOn() throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatSync]
        mockAIChatSyncHandler.syncTurnedOn = true

        // When
        let response = aiChatUserScriptHandler.encryptWithSyncMasterKey(
            params: ["data": "plain"],
            message: MockUserScriptMessage(name: "test", body: [:]))

        // Then
        let payloadResponse = try XCTUnwrap(response as? AIChatPayloadResponse)
        let encryptedPayload = try XCTUnwrap(payloadResponse.payload as? AIChatSyncHandler.EncryptedData)
        XCTAssertEqual(encryptedPayload.encryptedData, "encrypted_plain")
        XCTAssertEqual(mockAIChatSyncHandler.encryptCalls, ["plain"])
    }

    func testDecryptWithSyncMasterKeyReturnsSyncUnavailableWhenFeatureOff() throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []
        mockAIChatSyncHandler.syncTurnedOn = true

        // When
        let response = aiChatUserScriptHandler.decryptWithSyncMasterKey(
            params: ["data": "encrypted_plain"],
            message: MockUserScriptMessage(name: "test", body: [:]))

        // Then
        let errorResponse = try XCTUnwrap(response as? AIChatErrorResponse)
        XCTAssertEqual(errorResponse.reason, "sync unavailable")
        XCTAssertTrue(mockAIChatSyncHandler.decryptCalls.isEmpty)
    }

    func testDecryptWithSyncMasterKeyReturnsSyncOffWhenSyncNotTurnedOn() throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatSync]
        mockAIChatSyncHandler.syncTurnedOn = false

        // When
        let response = aiChatUserScriptHandler.decryptWithSyncMasterKey(
            params: ["data": "encrypted_plain"],
            message: MockUserScriptMessage(name: "test", body: [:]))

        // Then
        let errorResponse = try XCTUnwrap(response as? AIChatErrorResponse)
        XCTAssertEqual(errorResponse.reason, "sync off")
        XCTAssertTrue(mockAIChatSyncHandler.decryptCalls.isEmpty)
    }

    func testDecryptWithSyncMasterKeyReturnsDecryptedPayloadWhenSyncOn() throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatSync]
        mockAIChatSyncHandler.syncTurnedOn = true

        // When
        let response = aiChatUserScriptHandler.decryptWithSyncMasterKey(
            params: ["data": "encrypted_plain"],
            message: MockUserScriptMessage(name: "test", body: [:]))

        // Then
        let payloadResponse = try XCTUnwrap(response as? AIChatPayloadResponse)
        let decryptedPayload = try XCTUnwrap(payloadResponse.payload as? AIChatSyncHandler.DecryptedData)
        XCTAssertEqual(decryptedPayload.decryptedData, "plain")
        XCTAssertEqual(mockAIChatSyncHandler.decryptCalls, ["encrypted_plain"])
    }

    func testSendToSyncSettingsReturnsOKResponse() throws {
        // When
        let response = aiChatUserScriptHandler.sendToSyncSettings(params: [], message: MockUserScriptMessage(name: "test", body: [:]))

        // Then
        let okResponse = try XCTUnwrap(response as? AIChatOKResponse)
        XCTAssertTrue(okResponse.ok)
    }

    func testSendToSetupSyncReturnsOKResponse() throws {
        // When
        let response = aiChatUserScriptHandler.sendToSetupSync(params: [], message: MockUserScriptMessage(name: "test", body: [:]))

        // Then
        let okResponse = try XCTUnwrap(response as? AIChatOKResponse)
        XCTAssertTrue(okResponse.ok)
    }

    func testSetAIChatHistoryEnabledCallsSyncHandler() throws {
        // Given
        XCTAssertTrue(mockAIChatSyncHandler.setAIChatHistoryEnabledCalls.isEmpty)

        // When
        let response = aiChatUserScriptHandler.setAIChatHistoryEnabled(
            params: ["enabled": true],
            message: MockUserScriptMessage(name: "test", body: [:]))

        // Then
        XCTAssertNil(response)
        XCTAssertEqual(mockAIChatSyncHandler.setAIChatHistoryEnabledCalls, [true])
    }
}

struct MockUserScriptMessage: UserScriptMessage {
    public var messageName: String
    public var messageBody: Any
    public var messageHost: String
    public var isMainFrame: Bool
    public var messageWebView: WKWebView?

    // Initializer for the mock
    public init(messageName: String, messageBody: Any, messageHost: String, isMainFrame: Bool, messageWebView: WKWebView?) {
        self.messageName = messageName
        self.messageBody = messageBody
        self.messageHost = messageHost
        self.isMainFrame = isMainFrame
        self.messageWebView = messageWebView
    }

    // Convenience initializer
    public init(name: String, body: Any) {
        self.messageName = name
        self.messageBody = body
        self.messageHost = "localhost" // Default value
        self.isMainFrame = true // Default value
        self.messageWebView = nil // Default value
    }
}
// swiftlint: enable inclusive_language

/// Mock implementation of AIChatFullModeFeatureProviding for testing
final class MockAIChatFullModeFeatureProviding: AIChatFullModeFeatureProviding {
    var isAvailable: Bool = false
}

/// Mock implementation of AIChatContextualModeFeatureProviding for testing
final class MockAIChatContextualModeFeatureProviding: AIChatContextualModeFeatureProviding {
    var isAvailable: Bool = false
}

/// Mock implementation of AIChatSyncHandling for testing
final class MockAIChatSyncHandling: AIChatSyncHandling {

    var syncTurnedOn = false
    var authStatePublisher: AnyPublisher<SyncAuthState, Never> {
        Empty().eraseToAnyPublisher()
    }

    var syncStatus: AIChatSyncHandler.SyncStatus = AIChatSyncHandler.SyncStatus(syncAvailable: false)
    var scopedToken: AIChatSyncHandler.SyncToken = AIChatSyncHandler.SyncToken(token: "token")
    var encryptValue: (String) throws -> String = { "encrypted_\($0)" }
    var decryptValue: (String) throws -> String = { $0.dropping(prefix: "encrypted_") }

    private(set) var getSyncStatusFeatureAvailableCalls: [Bool] = []
    private(set) var getScopedTokenCallCount: Int = 0
    private(set) var encryptCalls: [String] = []
    private(set) var decryptCalls: [String] = []
    private(set) var setAIChatHistoryEnabledCalls: [Bool] = []

    func isSyncTurnedOn() -> Bool {
        syncTurnedOn
    }

    func getSyncStatus(featureAvailable: Bool) throws -> AIChatSyncHandler.SyncStatus {
        getSyncStatusFeatureAvailableCalls.append(featureAvailable)
        return syncStatus
    }

    func getScopedToken() async throws -> AIChatSyncHandler.SyncToken {
        getScopedTokenCallCount += 1
        return scopedToken
    }

    func encrypt(_ string: String) throws -> AIChatSyncHandler.EncryptedData {
        encryptCalls.append(string)
        return AIChatSyncHandler.EncryptedData(encryptedData: try encryptValue(string))
    }

    func decrypt(_ string: String) throws -> AIChatSyncHandler.DecryptedData {
        decryptCalls.append(string)
        return AIChatSyncHandler.DecryptedData(decryptedData: try decryptValue(string))
    }

    func setAIChatHistoryEnabled(_ enabled: Bool) {
        setAIChatHistoryEnabledCalls.append(enabled)
    }
}

// MARK: - getAIChatPageContext Tests

extension AIChatUserScriptHandlerTests {

    func testGetAIChatPageContextReturnsNilContextWhenNoHandler() {
        let response = aiChatUserScriptHandler.getAIChatPageContext(params: [], message: MockUserScriptMessage(name: "test", body: [:])) as? PageContextResponse

        XCTAssertNotNil(response)
        XCTAssertNil(response?.pageContext)
    }

    func testGetAIChatPageContextReturnsContextWhenHandlerSet() {
        let expectedContext = AIChatPageContextData(
            title: "Test Page",
            favicon: [],
            url: "https://example.com",
            content: "Test content",
            truncated: false,
            fullContentLength: 12
        )
        let mockHandler = MockPageContextHandler(context: expectedContext)
        aiChatUserScriptHandler.setPageContextHandler(mockHandler)

        let response = aiChatUserScriptHandler.getAIChatPageContext(params: [], message: MockUserScriptMessage(name: "test", body: [:])) as? PageContextResponse

        XCTAssertNotNil(response)
        XCTAssertNotNil(response?.pageContext)
        XCTAssertEqual(response?.pageContext?.title, "Test Page")
        XCTAssertEqual(response?.pageContext?.url, "https://example.com")
        XCTAssertEqual(response?.pageContext?.content, "Test content")
    }

    func testGetAIChatPageContextReturnsNilContextWhenHandlerReturnsNil() {
        let mockHandler = MockPageContextHandler(context: nil)
        aiChatUserScriptHandler.setPageContextHandler(mockHandler)

        let response = aiChatUserScriptHandler.getAIChatPageContext(params: [], message: MockUserScriptMessage(name: "test", body: [:])) as? PageContextResponse

        XCTAssertNotNil(response)
        XCTAssertNil(response?.pageContext)
    }
}

private final class MockPageContextHandler: AIChatPageContextHandling {
    private let context: AIChatPageContextData?

    init(context: AIChatPageContextData?) {
        self.context = context
    }

    func getPageContext() -> AIChatPageContextData? {
        context
    }
}
