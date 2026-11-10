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
import BrowserServicesKitTestsUtils
import Combine
import FeatureFlags_macOS
import PrivacyConfig
import UserScript
import WebKit
@_spi(Testing) import Persistence
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
        _ = try await handler([""], WKScriptMessage.mock())

        XCTAssertTrue(mockHandler.didOpenSettings, "openSettings should be called")
    }

    @MainActor func testGetAIChatNativeConfigValues() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatNativeConfigValues.rawValue))
        let result = try await handler([""], WKScriptMessage.mock())

        XCTAssertTrue(mockHandler.didGetConfigValues, "getAIChatNativeConfigValues should be called")
        XCTAssertNil(result, "Expected result to be nil")
    }

    @MainActor func testNativeConfigDispatcherAddsEnabledClientToolsAndPreservesOtherValues() async throws {
        let service = makeBrowserToolsService()
        userScript = AIChatUserScript(handler: mockHandler, urlSettings: AIChatMockDebugSettings(), browserTools: service)
        var baseConfig = AIChatNativeConfigValues.defaultValues
        baseConfig.supportsResponseStateReporting = true
        mockHandler.configResponse = baseConfig
        let webView = ClientToolsDocumentWebView()
        webView.documentURL = URL(string: "https://duck.ai/chat")

        let config = try await nativeConfig(from: webView)

        let clientTools = try XCTUnwrap(config.clientTools)
        XCTAssertEqual(clientTools.protocolVersion, 1)
        XCTAssertEqual(clientTools.capabilities.map(\.name), ["listOpenTabs"])
        XCTAssertEqual(clientTools.capabilities.map(\.version), [1])
        var remainingConfig = config
        remainingConfig.clientTools = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(remainingConfig), try encoder.encode(baseConfig))
    }

    @MainActor func testNativeConfigOmitsClientToolsInFireAndOutsideChat() async throws {
        let service = makeBrowserToolsService()
        userScript = AIChatUserScript(handler: mockHandler, urlSettings: AIChatMockDebugSettings(), browserTools: service)
        var baseConfig = AIChatNativeConfigValues.defaultValues
        baseConfig.clientTools = try ClientToolsConfiguration(capabilities: [.listOpenTabs])
        mockHandler.configResponse = baseConfig
        let webView = ClientToolsDocumentWebView()
        webView.documentURL = URL(string: "https://duck.ai/chat")
        mockHandler.isFireWindowProvider = { true }

        let fireConfig = try await nativeConfig(from: webView)
        XCTAssertNil(fireConfig.clientTools)

        mockHandler.isFireWindowProvider = { false }
        webView.documentURL = URL(string: "https://example.com")
        let unrelatedPageConfig = try await nativeConfig(from: webView)
        XCTAssertNil(unrelatedPageConfig.clientTools)

        webView.documentURL = nil
        let missingURLConfig = try await nativeConfig(from: webView)
        XCTAssertNil(missingURLConfig.clientTools)
    }

    @MainActor func testNativeConfigIncludesClientToolsForCustomChatHost() async throws {
        let service = makeBrowserToolsService()
        let settings = AIChatMockDebugSettings()
        settings.customURL = "https://chat.example.com"
        userScript = AIChatUserScript(handler: mockHandler, urlSettings: settings, browserTools: service)
        mockHandler.configResponse = AIChatNativeConfigValues.defaultValues
        let webView = ClientToolsDocumentWebView()
        webView.documentURL = URL(string: "https://chat.example.com/conversation")

        let config = try await nativeConfig(from: webView)

        XCTAssertEqual(config.clientTools?.capabilities, [.listOpenTabs])
    }

    @MainActor func testNativeConfigReflectsParentAndIndividualFlagChanges() async throws {
        let flags = browserToolsFlags()
        let service = makeBrowserToolsService(featureFlagger: flags)
        userScript = AIChatUserScript(handler: mockHandler, urlSettings: AIChatMockDebugSettings(), browserTools: service)
        mockHandler.configResponse = AIChatNativeConfigValues.defaultValues
        let webView = ClientToolsDocumentWebView()
        webView.documentURL = URL(string: "https://duck.ai/chat")

        let enabledConfig = try await nativeConfig(from: webView)
        XCTAssertEqual(enabledConfig.clientTools?.capabilities, [.listOpenTabs])

        flags.featuresStub[FeatureFlag.aiChatBrowserTools.rawValue] = false
        let parentDisabledConfig = try await nativeConfig(from: webView)
        XCTAssertNil(parentDisabledConfig.clientTools)

        flags.featuresStub[FeatureFlag.aiChatBrowserTools.rawValue] = true
        flags.featuresStub[FeatureFlag.aiChatBrowserToolListOpenTabs.rawValue] = false
        let toolDisabledConfig = try await nativeConfig(from: webView)
        XCTAssertNil(toolDisabledConfig.clientTools)

        flags.featuresStub[FeatureFlag.aiChatBrowserToolListOpenTabs.rawValue] = true
        let reenabledConfig = try await nativeConfig(from: webView)
        XCTAssertEqual(reenabledConfig.clientTools?.capabilities, [.listOpenTabs])
    }

    @MainActor func testFeatureFlagChangesPushUpdatedClientToolsConfiguration() async {
        let flags = browserToolsFlags()
        let service = makeBrowserToolsService(featureFlagger: flags)
        let pusher = ClientToolsChangePusherSpy()
        service.register(pusher)

        flags.triggerUpdate()
        await settleFeatureFlagUpdate()
        XCTAssertTrue(pusher.configurations.isEmpty)

        flags.featuresStub[FeatureFlag.aiChatBrowserTools.rawValue] = false
        flags.triggerUpdate()
        await settleFeatureFlagUpdate()
        XCTAssertEqual(pusher.configurations.count, 1)
        XCTAssertNil(pusher.configurations[0])

        flags.featuresStub[FeatureFlag.aiChatBrowserTools.rawValue] = true
        flags.featuresStub[FeatureFlag.aiChatBrowserToolListOpenTabs.rawValue] = true
        flags.triggerUpdate()
        await settleFeatureFlagUpdate()
        XCTAssertEqual(pusher.configurations.count, 2)
        XCTAssertEqual(pusher.configurations[1]?.capabilities, [.listOpenTabs])

        flags.featuresStub[FeatureFlag.aiChatBrowserToolListOpenTabs.rawValue] = false
        flags.triggerUpdate()
        await settleFeatureFlagUpdate()
        XCTAssertEqual(pusher.configurations.count, 3)
        XCTAssertNil(pusher.configurations[2])
    }

    func testClientToolsChangedDataEncodesDisabledConfigurationAsNull() throws {
        let data = try JSONEncoder().encode(ClientToolsChangedData(clientTools: nil))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertTrue(object["clientTools"] is NSNull)
    }

    @MainActor func testClientToolsChangedUsesTheClientToolsPagePolicyAndExcludesFire() async throws {
        let settings = AIChatMockDebugSettings()
        settings.customURL = "https://chat.example.com"
        userScript = AIChatUserScript(handler: mockHandler, urlSettings: settings, browserTools: nil)
        let broker = UserScriptMessageBroker(context: "client-tools-tests", requiresRunInPageContentWorld: true)
        userScript.broker = broker
        let webView = ClientToolsDocumentWebView()
        userScript.webView = webView
        let cases: [(url: String?, isFire: Bool, shouldPush: Bool)] = [
            ("https://duck.ai/chat", false, true),
            ("https://duckduckgo.com/?ia=chat", false, true),
            ("https://chat.example.com/conversation", false, true),
            ("https://duckduckgo.com/?q=search", false, false),
            ("https://example.com", false, false),
            (nil, false, false),
            ("https://duck.ai/chat", true, false),
            ("https://duckduckgo.com/?ia=chat", true, false),
            ("https://chat.example.com/conversation", true, false)
        ]
        let configurations: [ClientToolsConfiguration?] = [try ClientToolsConfiguration(capabilities: [.listOpenTabs]), nil]

        for testCase in cases {
            webView.documentURL = testCase.url.flatMap(URL.init(string:))
            mockHandler.isFireWindowProvider = { testCase.isFire }
            for configuration in configurations {
                webView.evaluatedScripts.removeAll()
                withExtendedLifetime(broker) {
                    userScript.pushClientToolsChanged(ClientToolsChangedData(clientTools: configuration))
                }
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }

                XCTAssertEqual(webView.evaluatedScripts.count, testCase.shouldPush ? 1 : 0,
                               "URL: \(testCase.url ?? "nil"), Fire: \(testCase.isFire)")
                if testCase.shouldPush {
                    let script = try XCTUnwrap(webView.evaluatedScripts.first)
                    XCTAssertTrue(script.contains("clientToolsChanged"))
                }
            }
        }
    }

    @MainActor func testNativeConfigDispatcherPreservesNonConfigResponse() async throws {
        mockHandler.configResponse = ["message": "unchanged"]
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatNativeConfigValues.rawValue))

        let result = try await handler(["request": "config"], WKScriptMessage.mock())

        XCTAssertEqual(result as? [String: String], ["message": "unchanged"])
    }

    @MainActor func testCancellationInvokesAllRegisteredSourcesOnceAndAllowsNextCycle() {
        let firstSource = ClientToolCancellationSpy()
        let secondSource = ClientToolCancellationSpy()
        userScript.registerClientToolPermissionCancellation(firstSource)
        userScript.registerClientToolPermissionCancellation(secondSource)
        userScript.registerClientToolPermissionCancellation(firstSource)

        userScript.cancelClientToolPermissionRequests()
        XCTAssertEqual(firstSource.cancellationCount, 1)
        XCTAssertEqual(secondSource.cancellationCount, 1)

        userScript.cancelClientToolPermissionRequests()
        XCTAssertEqual(firstSource.cancellationCount, 1)
        XCTAssertEqual(secondSource.cancellationCount, 1)

        userScript.registerClientToolPermissionCancellation(firstSource)
        userScript.cancelClientToolPermissionRequests()
        XCTAssertEqual(firstSource.cancellationCount, 2)
        XCTAssertEqual(secondSource.cancellationCount, 1)
    }

    @MainActor func testRegisteredCancellationSourceIsNotRetained() throws {
        var source: ClientToolCancellationSpy? = ClientToolCancellationSpy()
        weak var weakSource = source
        userScript.registerClientToolPermissionCancellation(try XCTUnwrap(source))

        source = nil

        XCTAssertNil(weakSource)
        userScript.cancelClientToolPermissionRequests()
    }

    @MainActor func testCancellationRevokesScriptAuthorizationAndCancelsAdditionalSource() async throws {
        let service = makeBrowserToolsService()
        userScript = AIChatUserScript(handler: mockHandler, urlSettings: AIChatMockDebugSettings(), browserTools: service)
        let tool = try XCTUnwrap(service.catalog.tool(named: "listOpenTabs"))
        service.permissions.setState(.allow, forToolNamed: tool.name)
        let control = await service.clientToolPermissions.authorize(callID: "control", tool: tool, source: userScript)
        guard case .granted(let confirmControl) = control else {
            return XCTFail("Stored permission should authorize script source")
        }
        let controlResult = await confirmControl { .success(.null) }
        XCTAssertNotNil(controlResult)
        let authorization = await service.clientToolPermissions.authorize(callID: "cancelled", tool: tool, source: userScript)
        guard case .granted(let confirmExecution) = authorization else {
            return XCTFail("Stored permission should authorize script source")
        }
        let additionalSource = ClientToolCancellationSpy()
        userScript.registerClientToolPermissionCancellation(additionalSource)

        userScript.cancelClientToolPermissionRequests()

        let cancelledResult = await confirmExecution {
            XCTFail("Cancelled authorization must not start execution")
            return .success(.null)
        }
        XCTAssertNil(cancelledResult)
        XCTAssertEqual(additionalSource.cancellationCount, 1)
        XCTAssertEqual(service.permissions.state(forToolNamed: tool.name), .allow)
    }

    @MainActor func testClientToolsDocumentReadinessRequiresCurrentLoadedAllowedDocument() {
        let settings = AIChatMockDebugSettings()
        settings.customURL = "https://chat.example.com"
        userScript = AIChatUserScript(handler: mockHandler, urlSettings: settings, browserTools: nil)
        let webView = ClientToolsDocumentWebView()
        webView.documentURL = URL(string: "https://duck.ai/chat")
        userScript.webView = webView
        XCTAssertTrue(userScript.isClientToolsDocumentReady(webView))

        webView.documentIsLoading = true
        XCTAssertFalse(userScript.isClientToolsDocumentReady(webView))
        webView.documentIsLoading = false
        webView.documentURL = nil
        XCTAssertFalse(userScript.isClientToolsDocumentReady(webView))
        webView.documentURL = URL(string: "https://example.com")
        XCTAssertFalse(userScript.isClientToolsDocumentReady(webView))
        webView.documentURL = URL(string: "https://chat.example.com/conversation")
        XCTAssertTrue(userScript.isClientToolsDocumentReady(webView))

        let otherWebView = ClientToolsDocumentWebView()
        otherWebView.documentURL = webView.documentURL
        XCTAssertFalse(userScript.isClientToolsDocumentReady(otherWebView))
        userScript.webView = nil
        XCTAssertFalse(userScript.isClientToolsDocumentReady(webView))
    }

    @MainActor private func nativeConfig(from webView: WKWebView) async throws -> AIChatNativeConfigValues {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatNativeConfigValues.rawValue))
        let response = try await handler([""], WKScriptMessage.mock(webView: webView))
        return try XCTUnwrap(response as? AIChatNativeConfigValues)
    }

    @MainActor private func browserToolsFlags() -> MockFeatureFlagger {
        MockFeatureFlagger(featuresStub: [
            FeatureFlag.aiChatBrowserTools.rawValue: true,
            FeatureFlag.aiChatBrowserToolListOpenTabs.rawValue: true,
            FeatureFlag.aiChatBrowserToolSearchHistory.rawValue: false,
            FeatureFlag.aiChatBrowserToolSwitchToTab.rawValue: false,
            FeatureFlag.aiChatBrowserToolReadTabContent.rawValue: false,
            FeatureFlag.aiChatBrowserToolFindInPage.rawValue: false,
            FeatureFlag.aiChatBrowserToolHighlightInPage.rawValue: false
        ])
    }

    @MainActor private func makeBrowserToolsService(featureFlagger: MockFeatureFlagger? = nil) -> AIChatBrowserToolsService {
        AIChatBrowserToolsService(featureFlagger: featureFlagger ?? browserToolsFlags(),
                                 windowControllersManager: WindowControllersManagerMock(),
                                 historyCoordinator: HistoryCoordinatingMock(),
                                 permissionStorage: MockKeyValueStore().keyedStoring())
    }

    @MainActor private func settleFeatureFlagUpdate() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }

    @MainActor func testCloseAIChat() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.closeAIChat.rawValue))
        let result = try await handler([""], WKScriptMessage.mock())

        XCTAssertTrue(mockHandler.didCloseChat, "closeAIChat should be called")
        XCTAssertNil(result, "Expected result to be nil")
    }

    @MainActor func testGetAIChatNativePrompt() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatNativePrompt.rawValue))
        let result = try await handler([""], WKScriptMessage.mock())

        XCTAssertTrue(mockHandler.didGetPrompt, "getAIChatNativePrompt should be called")
        XCTAssertNil(result, "Expected result to be nil")
    }

    @MainActor func testOpenAIChat() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.openAIChat.rawValue))
        let result = try await handler([""], WKScriptMessage.mock())

        XCTAssertTrue(mockHandler.didOpenChat, "openAIChat should be called")
        XCTAssertNil(result, "Expected result to be nil")
    }

    @MainActor func testGetAIChatNativeHandoffData() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatNativeHandoffData.rawValue))
        let result = try await handler([""], WKScriptMessage.mock())

        XCTAssertTrue(mockHandler.didGetHandoffData, "getAIChatNativeHandoffData should be called")
        XCTAssertNil(result, "Expected result to be nil")
    }

    @MainActor func testGetAIChatPageContext() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatPageContext.rawValue))
        let result = try await handler([""], WKScriptMessage.mock())

        XCTAssertTrue(mockHandler.didGetAIChatPageContext, "getAIChatPageContext should be called")
        XCTAssertNil(result, "Expected result to be nil")
    }

    @MainActor func testStoreMigrationData() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.storeMigrationData.rawValue))
        let result = try await handler([""], WKScriptMessage.mock())

        XCTAssertTrue(mockHandler.didStoreMigrationData, "storeMigrationData should be called")
        XCTAssertNil(result, "Expected result to be nil")
    }

    @MainActor func testGetMigrationDataByIndex() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.getMigrationDataByIndex.rawValue))
        let result = try await handler([""], WKScriptMessage.mock())

        XCTAssertTrue(mockHandler.didGetMigrationDataByIndex, "getMigrationDataByIndex should be called")
        XCTAssertNil(result, "Expected result to be nil")
    }

    @MainActor func testGetMigrationInfo() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.getMigrationInfo.rawValue))
        let result = try await handler([""], WKScriptMessage.mock())

        XCTAssertTrue(mockHandler.didGetMigrationInfo, "getMigrationInfo should be called")
        XCTAssertNil(result, "Expected result to be nil")
    }

    @MainActor func testClearMigrationData() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.clearMigrationData.rawValue))
        let result = try await handler([""], WKScriptMessage.mock())

        XCTAssertTrue(mockHandler.didClearMigrationData, "clearMigrationData should be called")
        XCTAssertNil(result, "Expected result to be nil")
    }

    @MainActor func testGetAIChatOpenTabs() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatOpenTabs.rawValue))
        _ = try await handler([""], WKScriptMessage.mock())

        XCTAssertTrue(mockHandler.didGetAIChatOpenTabs, "getAIChatOpenTabs should be called")
    }

    @MainActor func testGetAIChatTabContent() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatTabContent.rawValue))
        _ = try await handler([""], WKScriptMessage.mock())

        XCTAssertTrue(mockHandler.didGetAIChatTabContent, "getAIChatTabContent should be called")
    }

    // MARK: - Browser tools

    @MainActor func testWhenLegacyBrowserToolMethodIsRequestedThenNoHandlerIsReturned() {
        let methods = ["initialize", "notifications/initialized", "tools/list", "tools/call", "elicitation/response"]

        for method in methods {
            XCTAssertNil(userScript.handler(forMethodNamed: method), method)
        }
    }

    /// Client tools are only for a Duck.ai chat; a call from any other page gets no permission prompter.
    @MainActor func testWhenExecuteClientToolComesFromAPageOutsideDuckAIThenThereIsNoPermissionPrompter() async throws {
        let handler = try XCTUnwrap(userScript.handler(forMethodNamed: AIChatUserScriptMessages.executeClientTool.rawValue))
        _ = try await handler([""], WKScriptMessage.mock())

        XCTAssertTrue(mockHandler.didCallExecuteClientTool)
        XCTAssertNil(mockHandler.receivedClientToolPermissionPrompter)
    }

    /// The browser asks natively, so a page, or a script injected into it, cannot answer a prompt.
    @MainActor func testWhenThePageSendsAPermissionAnswerThenNoHandlerIsReturned() {
        XCTAssertNil(userScript.handler(forMethodNamed: "respondToClientToolPermission"))
    }

    // MARK: - Open Settings handshake

    @MainActor func testRequestOpenSettingsActionArmsHandshake() {
        XCTAssertFalse(userScript.pendingOpenSettingsAction, "Handshake should not be armed by default")

        userScript.requestOpenSettingsAction()

        XCTAssertTrue(userScript.pendingOpenSettingsAction, "requestOpenSettingsAction should arm the handshake")
    }

    @MainActor func testOpenSettingsHandshakeStaysPendingAfterFirstMessage() {
        userScript.requestOpenSettingsAction()

        _ = userScript.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatNativeConfigValues.rawValue)

        XCTAssertTrue(userScript.pendingOpenSettingsAction,
                      "Single page message must not fire the push — JS subscriptions are not guaranteed wired yet")
    }

    @MainActor func testOpenSettingsHandshakeFiresAfterSecondMessage() {
        userScript.requestOpenSettingsAction()

        _ = userScript.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatNativeConfigValues.rawValue)
        _ = userScript.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatNativePrompt.rawValue)

        XCTAssertFalse(userScript.pendingOpenSettingsAction,
                       "Second page message must clear the pending flag (push fired)")
    }

    @MainActor func testOpenSettingsHandshakeIgnoresUnknownMethods() {
        userScript.requestOpenSettingsAction()

        // Two unknown method names — resolveHandler returns nil, so neither should count.
        _ = userScript.handler(forMethodNamed: "definitelyNotAKnownMethod")
        _ = userScript.handler(forMethodNamed: "stillNotKnown")

        XCTAssertTrue(userScript.pendingOpenSettingsAction,
                      "Unknown methods must not count toward the readiness handshake")
    }

    @MainActor func testMessagesWithoutRequestDoNotArmHandshake() {
        // Two known messages, but no requestOpenSettingsAction() — the handshake must stay unarmed
        // so the next time it IS armed, it starts fresh from zero.
        _ = userScript.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatNativeConfigValues.rawValue)
        _ = userScript.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatNativePrompt.rawValue)

        XCTAssertFalse(userScript.pendingOpenSettingsAction)

        userScript.requestOpenSettingsAction()
        _ = userScript.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatNativeConfigValues.rawValue)

        XCTAssertTrue(userScript.pendingOpenSettingsAction,
                      "Pre-arm messages must not be counted: one post-arm message should still leave the handshake pending")
    }

    @MainActor func testOpenSettingsHandshakeIsOneShot() {
        userScript.requestOpenSettingsAction()
        _ = userScript.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatNativeConfigValues.rawValue)
        _ = userScript.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatNativePrompt.rawValue)
        XCTAssertFalse(userScript.pendingOpenSettingsAction)

        // Subsequent messages must not re-fire — the next request must be explicitly armed.
        _ = userScript.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatNativeConfigValues.rawValue)
        _ = userScript.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatNativePrompt.rawValue)

        XCTAssertFalse(userScript.pendingOpenSettingsAction,
                       "Handshake must not re-arm itself after firing")
    }
}

// swiftlint:disable inclusive_language
final class MockAIChatUserScriptHandler: AIChatUserScriptHandling {
    var didOpenSettings = false
    var didGetConfigValues = false
    var configResponse: (any Encodable)?
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
    var didGetAIChatSelectionContext = false
    var didSubmitAIChatSelectionContext = false
    var didTogglePageContextTelemetry = false
    var pageContextSubject = PassthroughSubject<AIChatPageContextData?, Never>()
    var selectionContextSubject = PassthroughSubject<AIChatSelectionContextData, Never>()
    var pageContextRequestedSubject = PassthroughSubject<Void, Never>()
    var chatRestorationDataSubject = PassthroughSubject<AIChatRestorationData?, Never>()
    var syncStatusSubject = PassthroughSubject<AIChatSyncHandler.SyncStatus, Never>()

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
    var isFireWindowProvider: (() -> Bool)?
    var isSidebarProvider: (() -> Bool)?
    var attachmentPrivacyDisclosureProvider: (() -> AttachmentPrivacyDisclosure)?
    var directNavigationFallback: AIChatConversationSource?

    init(messageHandling: any AIChatMessageHandling = MockAIChatMessageHandling()) {
        self.messageHandling = messageHandling
    }

    func openAIChatSettings(params: Any, message: UserScriptMessage) async -> (any Encodable)? {
        didOpenSettings = true
        return nil
    }

    @MainActor
    func attachmentPrivacyShouldDisplay(params: Any, message: UserScriptMessage) async -> (any Encodable)? {
        nil
    }

    func getAIChatNativeConfigValues(params: Any, message: UserScriptMessage) -> (any Encodable)? {
        didGetConfigValues = true
        return configResponse
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

    func getAIChatPageContext(params: Any, message: any UserScriptMessage) async -> (any Encodable)? {
        didGetAIChatPageContext = true
        return nil
    }

    func getAIChatSelectionContext(params: Any, message: any UserScriptMessage) -> (any Encodable)? {
        didGetAIChatSelectionContext = true
        return nil
    }

    var pageContextPublisher: AnyPublisher<AIChatPageContextData?, Never> {
        pageContextSubject.eraseToAnyPublisher()
    }

    var selectionContextPublisher: AnyPublisher<AIChatSelectionContextData, Never> {
        selectionContextSubject.eraseToAnyPublisher()
    }

    var pageContextRequestedPublisher: AnyPublisher<Void, Never> {
        pageContextRequestedSubject.eraseToAnyPublisher()
    }

    var pageContextConsumedPublisher: AnyPublisher<Void, Never> {
        PassthroughSubject<Void, Never>().eraseToAnyPublisher()
    }

    var pageContextRemovedPublisher: AnyPublisher<Void, Never> {
        PassthroughSubject<Void, Never>().eraseToAnyPublisher()
    }

    var pageContextAddedPublisher: AnyPublisher<Void, Never> {
        PassthroughSubject<Void, Never>().eraseToAnyPublisher()
    }

    var didGetAIChatOpenTabs = false
    var didGetAIChatTabContent = false

    func getAIChatOpenTabs(params: Any, message: UserScriptMessage) async -> Encodable? {
        didGetAIChatOpenTabs = true
        return nil
    }

    func getAIChatTabContent(params: Any, message: UserScriptMessage) async -> Encodable? {
        didGetAIChatTabContent = true
        return nil
    }

    var receivedClientToolPermissionPrompter: (any ClientToolPermissionPrompting)?
    var didCallExecuteClientTool = false

    func executeClientTool(params: Any, message: UserScriptMessage, permissionPrompter: (any ClientToolPermissionPrompting)?) async -> Encodable? {
        didCallExecuteClientTool = true
        receivedClientToolPermissionPrompter = permissionPrompter
        return nil
    }

    var chatRestorationDataPublisher: AnyPublisher<AIChatRestorationData?, Never> {
        chatRestorationDataSubject.eraseToAnyPublisher()
    }

    var syncStatusPublisher: AnyPublisher<AIChatSyncHandler.SyncStatus, Never> {
        syncStatusSubject.eraseToAnyPublisher()
    }

    func submitAIChatPageContext(_ pageContext: AIChatPageContextData?) {
        didSubmitAIChatPageContext = true
    }

    func resetConversationSourceForNewDocument() {
        directNavigationFallback = nil
    }

    func submitAIChatSelectionContext(_ selection: AIChatSelectionContextData) {
        didSubmitAIChatSelectionContext = true
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

    func voiceSessionStarted(params: Any, message: any UserScriptMessage) async -> (any Encodable)? {
        return nil
    }

    func voiceSessionEnded(params: Any, message: any UserScriptMessage) async -> (any Encodable)? {
        return nil
    }

    func voiceChatStartFailed(params: Any, message: any UserScriptMessage) async -> (any Encodable)? {
        return nil
    }

    func dictationStartFailed(params: Any, message: any UserScriptMessage) async -> (any Encodable)? {
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
    func customizeResponsesModalClosed(params: Any, message: any UserScriptMessage) async -> (any Encodable)? {
        return nil
    }

    func getAIChats(params: Any, message: any UserScriptMessage) async -> (any Encodable)? {
        return nil
    }
}
// swiftlint:enable inclusive_language

func AIChatMockDebugSettings() -> any KeyedStoring<AIChatDebugURLSettings> {
    return MockKeyValueStore().keyedStoring()
}

private final class MockAIChatMessageHandling: AIChatMessageHandling {
    func getNativeConfigValues(isFireWindow: Bool) -> AIChatNativeConfigValues {
        .defaultValues
    }

    func getDataForMessageType(_ type: DuckDuckGo_Privacy_Browser.AIChatMessageType) -> (any Encodable)? {
        nil
    }

    func setData(_ data: Any?, forMessageType type: DuckDuckGo_Privacy_Browser.AIChatMessageType) {}

    func appendSelectionContext(_ selection: AIChatSelectionContextData) {}
    func getSelectionContexts() -> [AIChatSelectionContextData] { [] }
    func clearSelectionContexts() {}
}

@MainActor
private final class ClientToolCancellationSpy: AIChatClientToolPermissionCancellation {
    private(set) var cancellationCount = 0

    func cancelClientToolPermissionRequests() {
        cancellationCount += 1
    }
}

@MainActor
private final class ClientToolsDocumentWebView: WKWebView {
    var documentURL: URL?
    var documentIsLoading = false
    var evaluatedScripts: [String] = []

    override var url: URL? { documentURL }
    override var isLoading: Bool { documentIsLoading }

    override func evaluateJavaScript(_ javaScriptString: String, completionHandler: ((Any?, (any Error)?) -> Void)? = nil) {
        evaluatedScripts.append(javaScriptString)
        completionHandler?(nil, nil)
    }
}

@MainActor
private final class ClientToolsChangePusherSpy: AIChatBrowserToolsPushing {
    let pushTargetWebView: WKWebView? = nil
    private(set) var configurations: [ClientToolsConfiguration?] = []

    func pushClientToolsChanged(_ data: ClientToolsChangedData) {
        configurations.append(data.clientTools)
    }

    func pushTabChanged(_ data: AIChatTabChangedData) {}
}
