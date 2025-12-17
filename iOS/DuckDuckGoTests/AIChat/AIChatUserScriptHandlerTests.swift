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


import XCTest
@testable import DuckDuckGo
import UserScript
import WebKit
@testable import AIChat

class AIChatUserScriptHandlerTests: XCTestCase {
    var aiChatUserScriptHandler: AIChatUserScriptHandler!
    var mockFeatureFlagger: MockFeatureFlagger!
    var mockPayloadHandler: AIChatPayloadHandler!
    var mockAIChatSyncHandler: MockAIChatSyncHandling!
    var mockAIChatFullModeFeature: MockAIChatFullModeFeatureProviding!
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

        mockUserDefaults = UserDefaults(suiteName: mockSuiteName)
        mockUserDefaults.removePersistentDomain(forName: mockSuiteName)

        let experimentalAIChatManager = ExperimentalAIChatManager(featureFlagger: mockFeatureFlagger, userDefaults: mockUserDefaults)
        aiChatUserScriptHandler = AIChatUserScriptHandler(experimentalAIChatManager: experimentalAIChatManager, syncHandler: mockAIChatSyncHandler, featureFlagger: mockFeatureFlagger, aichatFullModeFeature: mockAIChatFullModeFeature)
        aiChatUserScriptHandler.setPayloadHandler(mockPayloadHandler)
    }

    override func tearDown() {
        aiChatUserScriptHandler = nil
        mockFeatureFlagger = nil
        mockPayloadHandler = nil
        mockAIChatSyncHandler = nil
        mockAIChatFullModeFeature = nil
        super.tearDown()
    }

    func testGetAIChatNativeConfigValues() {
        // Given
        // MockFeatureFlagger is already initialized with .aiChatDeepLink enabled

        // When
        let configValues = aiChatUserScriptHandler.getAIChatNativeConfigValues(params: [], message: MockUserScriptMessage(name: "test", body: [:]))  as? AIChatNativeConfigValues

        // Then
        XCTAssertNotNil(configValues)
        XCTAssertEqual(configValues?.isAIChatHandoffEnabled, true)
        XCTAssertEqual(configValues?.platform, "ios")
        XCTAssertEqual(configValues?.supportsHomePageEntryPoint, true)
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

/// Mock implementation of AIChatFullModeFeatureProviding for testing
final class MockAIChatFullModeFeatureProviding: AIChatFullModeFeatureProviding {
    var isAvailable: Bool = false
}

/// Mock implementation of AIChatSyncHandling for testing
final class MockAIChatSyncHandling: AIChatSyncHandling {

    var syncTurnedOn = false

    var syncStatus: AIChatSyncHandler.SyncStatus = AIChatSyncHandler.SyncStatus(syncAvailable: false,
                                                                                userId: nil,
                                                                                deviceId: nil,
                                                                                deviceName: nil,
                                                                                deviceType: nil)
    var scopedToken: AIChatSyncHandler.SyncToken = AIChatSyncHandler.SyncToken(token: "token")
    var encryptValue: (String) throws -> String = { "encrypted_\($0)" }
    var decryptValue: (String) throws -> String = { $0.dropping(prefix: "encrypted_") }

    private(set) var encryptCalls: [String] = []
    private(set) var decryptCalls: [String] = []
    private(set) var setAIChatHistoryEnabledCalls: [Bool] = []

    func isSyncTurnedOn() -> Bool {
        syncTurnedOn
    }

    func getSyncStatus(featureAvailable: Bool) throws -> AIChatSyncHandler.SyncStatus {
        syncStatus
    }

    func getScopedToken() async throws -> AIChatSyncHandler.SyncToken {
        scopedToken
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
