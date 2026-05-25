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
import UIKit
import UserScript
import XCTest
import WebKit
import Subscription
@testable import DuckDuckGo
@testable import Core

final class AIChatContentHandlerTests: XCTestCase {

    var handler: AIChatContentHandler!
    var mockSettings: MockAIChatSettingsProvider!
    var mockPayloadHandler: AIChatPayloadHandler!
    var mockMetricHandler: MockAIChatPixelMetricHandler!
    var mockProductSurfaceTelemetry: MockProductSurfaceTelemetry!
    var mockFreeTrialConversionService: MockFreeTrialConversionInstrumentationService!
    var mockUnifiedToggleInputFeature: MockUnifiedToggleInputFeatureProvider!

    override func setUpWithError() throws {
        mockSettings = MockAIChatSettingsProvider()
        mockPayloadHandler = AIChatPayloadHandler()
        mockMetricHandler = MockAIChatPixelMetricHandler()
        mockProductSurfaceTelemetry = MockProductSurfaceTelemetry()
        mockFreeTrialConversionService = MockFreeTrialConversionInstrumentationService()
        mockUnifiedToggleInputFeature = MockUnifiedToggleInputFeatureProvider()

        handler = AIChatContentHandler(
            aiChatSettings: mockSettings,
            payloadHandler: mockPayloadHandler,
            pixelMetricHandler: mockMetricHandler,
            featureDiscovery: MockFeatureDiscovery(),
            productSurfaceTelemetry: mockProductSurfaceTelemetry,
            freeTrialConversionService: mockFreeTrialConversionService,
            statisticsLoader: StatisticsLoader(fireSearchExperimentPixels: {}),
            unifiedToggleInputFeature: mockUnifiedToggleInputFeature
        )
    }

    // MARK: - setup(with:webView:)

    func testSetupSetsUserScriptDelegate() throws {
        // Given
        let mockUserScript = MockAIChatUserScript()
        let mockWebView = WKWebView()

        // When
        handler.setup(with: mockUserScript, webView: mockWebView, displayMode: .fullTab)

        // Then
        XCTAssertTrue(mockUserScript.delegateSet)
    }

    func testSetupSetsPayloadHandler() throws {
        // Given
        let mockUserScript = MockAIChatUserScript()
        let mockWebView = WKWebView()

        // When
        handler.setup(with: mockUserScript, webView: mockWebView, displayMode: .fullTab)

        // Then
        XCTAssertTrue(mockUserScript.payloadHandlerSet)
    }

    func testSetupSetsOpenLinkHandler() throws {
        // Given
        let mockUserScript = MockAIChatUserScript()
        let mockWebView = WKWebView()

        // When
        handler.setup(with: mockUserScript, webView: mockWebView, displayMode: .fullTab)

        // Then
        XCTAssertTrue(mockUserScript.openLinkHandlerSet)
    }

    func testSetupSetsWebView() throws {
        // Given
        let mockUserScript = MockAIChatUserScript()
        let mockWebView = WKWebView()

        // When
        handler.setup(with: mockUserScript, webView: mockWebView, displayMode: .fullTab)

        // Then
        XCTAssertTrue(mockUserScript.webViewSet)
    }

    func testSetupSetsDisplayMode() throws {
        // Given
        let mockUserScript = MockAIChatUserScript()
        let mockWebView = WKWebView()

        // When
        handler.setup(with: mockUserScript, webView: mockWebView, displayMode: .contextual)

        // Then
        XCTAssertEqual(mockUserScript.lastDisplayModeSet, .contextual)
    }

    func testSetupSetsPageContextProvider() throws {
        // Given
        let mockUserScript = MockAIChatUserScript()
        let mockWebView = WKWebView()

        // When
        handler.setup(with: mockUserScript, webView: mockWebView, displayMode: .fullTab)

        // Then
        XCTAssertTrue(mockUserScript.pageContextProviderSet)
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
        let url = handler.buildQueryURL(query: query, autoSend: false, flowType: .default, tools: nil)

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
        let url = handler.buildQueryURL(query: "test", autoSend: autoSend, flowType: .default, tools: nil)

        // Then
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            XCTFail("Invalid URL components")
            return
        }

        let autoSendItem = components.queryItems?.first { $0.name == AIChatURLParameters.autoSubmitPromptQueryName }
        XCTAssertEqual(autoSendItem?.value, AIChatURLParameters.autoSubmitPromptQueryValue)
    }

    func testBuildQueryURLWithOnboardingFlow() throws {
        // Given
        let flowType: AIChatOnboardingFlowType = .mobileAppOnboarding

        // When
        let url = handler.buildQueryURL(query: "test", autoSend: false, flowType: flowType, tools: nil)

        // Then
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            XCTFail("Invalid URL components")
            return
        }

        let flowItem = components.queryItems?.first { $0.name == AIChatURLParameters.flowQueryName }
        XCTAssertEqual(flowItem?.value, AIChatURLParameters.mobileAppOnboardingFlowQueryValue)
        XCTAssertEqual(components.host, mockSettings.aiChatURL.host)
    }

    func testBuildQueryURLWithTools() throws {
        // Given
        let tools: [AIChatRAGTool] = [.webSearch, .newsSearch]

        // When
        let url = handler.buildQueryURL(query: "test", autoSend: false, flowType: .default, tools: tools)

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
        let url = handler.buildQueryURL(query: emptyQuery, autoSend: false, flowType: .default, tools: nil)

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
        let url = handler.buildQueryURL(query: nilQuery, autoSend: false, flowType: .default, tools: nil)

        // Then
        XCTAssertEqual(url, mockSettings.aiChatURL)
    }

    func testBuildQueryURLWithNativeInputAvailableAddsNativeInputParameter() throws {
        mockSettings.aiChatURL = URL(string: "https://duck.ai")!
        mockUnifiedToggleInputFeature.isAvailable = true

        let url = handler.buildQueryURL(query: "test", autoSend: false, flowType: .default, tools: nil)

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            XCTFail("Invalid URL components")
            return
        }

        let nativeInputItem = components.queryItems?.first { $0.name == AIChatURLParameters.nativeInputName }
        XCTAssertEqual(nativeInputItem?.value, AIChatURLParameters.nativeInputValue)
    }

    func testBuildQueryURLWithNativeInputAvailableAndNilQueryAddsNativeInputParameter() throws {
        mockSettings.aiChatURL = URL(string: "https://duck.ai")!
        mockUnifiedToggleInputFeature.isAvailable = true

        let url = handler.buildQueryURL(query: nil, autoSend: false, flowType: .default, tools: nil)

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            XCTFail("Invalid URL components")
            return
        }

        let promptItem = components.queryItems?.first { $0.name == AIChatURLParameters.promptQueryName }
        let nativeInputItem = components.queryItems?.first { $0.name == AIChatURLParameters.nativeInputName }
        XCTAssertEqual(url, AIChatURLParameters.nativeInputURL(from: mockSettings.aiChatURL))
        XCTAssertNil(promptItem)
        XCTAssertEqual(nativeInputItem?.value, AIChatURLParameters.nativeInputValue)
    }

    func testBuildQueryURLWithNativeInputUnavailableRemovesStaleNativeInputParameter() throws {
        mockSettings.aiChatURL = URL(string: "https://duck.ai?native-input=true")!
        mockUnifiedToggleInputFeature.isAvailable = false

        let url = handler.buildQueryURL(query: nil, autoSend: false, flowType: .default, tools: nil)

        XCTAssertEqual(url.absoluteString, "https://duck.ai")
    }

    func testBuildQueryURLWithNativeInputAvailableDoesNotAddNativeInputParameterToUnsupportedURL() throws {
        mockSettings.aiChatURL = URL(string: "https://example.com")!
        mockUnifiedToggleInputFeature.isAvailable = true

        let url = handler.buildQueryURL(query: nil, autoSend: false, flowType: .default, tools: nil)

        XCTAssertEqual(url, mockSettings.aiChatURL)
    }

    func testBuildQueryURLWithNativeInputAvailableAndEmptyQueryAddsNativeInputParameter() throws {
        mockSettings.aiChatURL = URL(string: "https://duck.ai")!
        mockUnifiedToggleInputFeature.isAvailable = true

        let url = handler.buildQueryURL(query: "", autoSend: false, flowType: .default, tools: nil)

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            XCTFail("Invalid URL components")
            return
        }

        let promptItem = components.queryItems?.first { $0.name == AIChatURLParameters.promptQueryName }
        let nativeInputItem = components.queryItems?.first { $0.name == AIChatURLParameters.nativeInputName }
        XCTAssertNil(promptItem)
        XCTAssertEqual(nativeInputItem?.value, AIChatURLParameters.nativeInputValue)
    }

    func testBuildVoiceModeURLWithNativeInputAvailableAddsNativeInputParameter() throws {
        mockSettings.aiChatURL = URL(string: "https://duck.ai")!
        mockUnifiedToggleInputFeature.isAvailable = true

        let url = handler.buildVoiceModeURL()

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            XCTFail("Invalid URL components")
            return
        }

        let modeItem = components.queryItems?.first { $0.name == AIChatURLParameters.modeName }
        let nativeInputItem = components.queryItems?.first { $0.name == AIChatURLParameters.nativeInputName }
        XCTAssertEqual(modeItem?.value, AIChatURLParameters.voiceModeValue)
        XCTAssertEqual(nativeInputItem?.value, AIChatURLParameters.nativeInputValue)
    }

    func testBuildVoiceModeURLWithNativeInputUnavailableRemovesStaleNativeInputParameter() throws {
        mockSettings.aiChatURL = URL(string: "https://duck.ai?native-input=true")!
        mockUnifiedToggleInputFeature.isAvailable = false

        let url = handler.buildVoiceModeURL()

        XCTAssertEqual(url.absoluteString, "https://duck.ai?mode=voice")
    }

    func testBuildQueryURLReplacesExistingQueryParameters() throws {
        // Given
        let firstQuery = "first"
        let secondQuery = "second"

        // When
        let url1 = handler.buildQueryURL(query: firstQuery, autoSend: false, flowType: .default, tools: nil)
        let url2 = handler.buildQueryURL(query: secondQuery, autoSend: false, flowType: .default, tools: nil)

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
        handler.setup(with: mockUserScript, webView: mockWebView, displayMode: .fullTab)

        // When
        handler.submitStartChatAction()

        // Then
        XCTAssertEqual(mockUserScript.submitStartChatActionCallCount, 1)
    }

    func testSubmitStartChatActionPushesPageContextWhenAvailable() throws {
        // Given
        let pageContext = AIChatPageContextData(
            title: "Test Page",
            favicon: [],
            url: "https://example.com",
            content: "Test content",
            truncated: false,
            fullContentLength: 12
        )

        let settingsWithAutoAttach = MockAIChatSettingsProvider(isAutomaticContextAttachmentEnabled: true)
        let handlerWithContext = AIChatContentHandler(
            aiChatSettings: settingsWithAutoAttach,
            payloadHandler: mockPayloadHandler,
            pixelMetricHandler: mockMetricHandler,
            featureDiscovery: MockFeatureDiscovery(),
            productSurfaceTelemetry: mockProductSurfaceTelemetry,
            freeTrialConversionService: mockFreeTrialConversionService,
            statisticsLoader: StatisticsLoader(fireSearchExperimentPixels: {}),
            getPageContext: { _ in pageContext }
        )

        let mockUserScript = MockAIChatUserScript()
        let mockWebView = WKWebView()
        handlerWithContext.setup(with: mockUserScript, webView: mockWebView, displayMode: .contextual)

        // When
        handlerWithContext.submitStartChatAction()

        // Then
        XCTAssertEqual(mockUserScript.submitPageContextCallCount, 1)
        XCTAssertEqual(mockUserScript.lastSubmittedPageContextViaSubmit?.title, "Test Page")
        XCTAssertEqual(mockUserScript.lastSubmittedPageContextViaSubmit?.url, "https://example.com")
        XCTAssertEqual(mockUserScript.submitStartChatActionCallCount, 1)
    }

    func testSubmitStartChatActionDoesNotPushContextWhenNil() throws {
        // Given
        let settingsWithAutoAttach = MockAIChatSettingsProvider(isAutomaticContextAttachmentEnabled: true)
        let handlerWithoutContext = AIChatContentHandler(
            aiChatSettings: settingsWithAutoAttach,
            payloadHandler: mockPayloadHandler,
            pixelMetricHandler: mockMetricHandler,
            featureDiscovery: MockFeatureDiscovery(),
            productSurfaceTelemetry: mockProductSurfaceTelemetry,
            freeTrialConversionService: mockFreeTrialConversionService,
            statisticsLoader: StatisticsLoader(fireSearchExperimentPixels: {}),
            getPageContext: { _ in nil }
        )

        let mockUserScript = MockAIChatUserScript()
        let mockWebView = WKWebView()
        handlerWithoutContext.setup(with: mockUserScript, webView: mockWebView, displayMode: .contextual)

        // When
        handlerWithoutContext.submitStartChatAction()

        // Then
        XCTAssertEqual(mockUserScript.submitPageContextCallCount, 0)
        XCTAssertEqual(mockUserScript.submitStartChatActionCallCount, 1)
    }

    func testSubmitOpenSettingsActionCallsUserScript() throws {
        // Given
        let mockUserScript = MockAIChatUserScript()
        let mockWebView = WKWebView()
        handler.setup(with: mockUserScript, webView: mockWebView, displayMode: .fullTab)

        // When
        handler.submitOpenSettingsAction()

        // Then
        XCTAssertEqual(mockUserScript.submitOpenSettingsActionCallCount, 1)
    }

    func testSubmitToggleSidebarActionCallsThroughDirectly() throws {
        // Given
        let mockUserScript = MockAIChatUserScript()
        let mockWebView = WKWebView()
        handler.setup(with: mockUserScript, webView: mockWebView, displayMode: .fullTab)

        // When
        handler.submitToggleSidebarAction()

        // Then
        XCTAssertEqual(mockUserScript.submitToggleSidebarActionCallCount, 1)
    }

    // MARK: - submitPrompt with pageContext

    func testSubmitPromptPassesPageContextToUserScript() throws {
        // Given
        let mockUserScript = MockAIChatUserScript()
        let mockWebView = WKWebView()
        handler.setup(with: mockUserScript, webView: mockWebView, displayMode: .contextual)

        let pageContext = AIChatPageContextData(
            title: "Test Page",
            favicon: [],
            url: "https://example.com",
            content: "Test content",
            truncated: false,
            fullContentLength: 12
        )

        // When
        handler.submitPrompt("Summarize this", pageContext: pageContext)

        // Then
        XCTAssertEqual(mockUserScript.submitPromptCallCount, 1)
        XCTAssertEqual(mockUserScript.lastSubmittedPrompt, "Summarize this")
        XCTAssertEqual(mockUserScript.lastSubmittedPageContext?.title, "Test Page")
        XCTAssertEqual(mockUserScript.lastSubmittedPageContext?.url, "https://example.com")
        XCTAssertEqual(mockUserScript.lastSubmittedPageContext?.content, "Test content")
    }

    func testSubmitPromptWithoutPageContextPassesNil() throws {
        // Given
        let mockUserScript = MockAIChatUserScript()
        let mockWebView = WKWebView()
        handler.setup(with: mockUserScript, webView: mockWebView, displayMode: .contextual)

        // When
        handler.submitPrompt("Hello")

        // Then
        XCTAssertEqual(mockUserScript.submitPromptCallCount, 1)
        XCTAssertEqual(mockUserScript.lastSubmittedPrompt, "Hello")
        XCTAssertNil(mockUserScript.lastSubmittedPageContext)
    }

    func testSubmitPromptWithExplicitNilPageContext() throws {
        // Given
        let mockUserScript = MockAIChatUserScript()
        let mockWebView = WKWebView()
        handler.setup(with: mockUserScript, webView: mockWebView, displayMode: .contextual)

        // When
        handler.submitPrompt("Hello", pageContext: nil)

        // Then
        XCTAssertEqual(mockUserScript.submitPromptCallCount, 1)
        XCTAssertEqual(mockUserScript.lastSubmittedPrompt, "Hello")
        XCTAssertNil(mockUserScript.lastSubmittedPageContext)
    }
    
    // MARK: - Delegate Notifications

    func testDidReceiveMessageGetAIChatPageContextNotifiesDelegate() throws {
        // Given
        let mockUserScript = MockAIChatUserScript()
        let mockWebView = WKWebView()
        handler.setup(with: mockUserScript, webView: mockWebView, displayMode: .fullTab)
        let mockDelegate = MockAIChatContentHandlingDelegate()
        handler.delegate = mockDelegate

        // When
        handler.aiChatUserScript(makeTestUserScript(), didReceiveMessage: .getAIChatPageContext)

        // Then
        XCTAssertEqual(mockDelegate.didReceivePageContextRequestCallCount, 1)
    }

    func testDidReceiveMessageOtherThanGetAIChatPageContextDoesNotNotifyPageContextDelegate() throws {
        // Given
        let mockUserScript = MockAIChatUserScript()
        let mockWebView = WKWebView()
        handler.setup(with: mockUserScript, webView: mockWebView, displayMode: .fullTab)
        let mockDelegate = MockAIChatContentHandlingDelegate()
        handler.delegate = mockDelegate

        // When
        handler.aiChatUserScript(makeTestUserScript(), didReceiveMessage: .closeAIChat)

        // Then
        XCTAssertEqual(mockDelegate.didReceivePageContextRequestCallCount, 0)
    }

    func testOpenLinkHandlerNotifiesDelegate() throws {
        // Given
        let mockUserScript = MockAIChatUserScript()
        let mockWebView = WKWebView()
        let mockDelegate = MockAIChatContentHandlingDelegate()
        let url = URL(string: "https://duckduckgo.com/?q=cat%20breeds&t=duck_ai")!
        handler.delegate = mockDelegate
        handler.setup(with: mockUserScript, webView: mockWebView, displayMode: .fullTab)

        // When
        mockUserScript.openLinkHandler?(url)

        // Then
        XCTAssertEqual(mockDelegate.didRequestToOpenCallCount, 1)
        XCTAssertEqual(mockDelegate.requestedOpenURL, url)
    }

    // MARK: - fireAIChatTelemetry

    func testFireAIChatTelemetryCallsProductSurfaceTelemetry() throws {
        // When
        handler.fireAIChatTelemetry()

        // Then
        XCTAssertEqual(mockProductSurfaceTelemetry.duckAIUsedCallCount, 1)
    }

    // MARK: - Free Trial Conversion Tracking

    func testWhenPlusModelTierPromptSubmitted_ThenMarkDuckAIActivatedIsCalled() throws {
        // Given
        let metric = AIChatMetric(metricName: .userDidSubmitPrompt, modelTier: .plus)

        // When
        handler.aiChatUserScript(makeTestUserScript(), didReceiveMetric: metric)

        // Then
        XCTAssertTrue(mockFreeTrialConversionService.markDuckAIActivatedCalled)
    }

    func testWhenPlusModelTierFirstPromptSubmitted_ThenMarkDuckAIActivatedIsCalled() throws {
        // Given
        let metric = AIChatMetric(metricName: .userDidSubmitFirstPrompt, modelTier: .plus)

        // When
        handler.aiChatUserScript(makeTestUserScript(), didReceiveMetric: metric)

        // Then
        XCTAssertTrue(mockFreeTrialConversionService.markDuckAIActivatedCalled)
    }

    func testWhenFreeModelTierPromptSubmitted_ThenMarkDuckAIActivatedIsNotCalled() throws {
        // Given
        let metric = AIChatMetric(metricName: .userDidSubmitPrompt, modelTier: .free)

        // When
        handler.aiChatUserScript(makeTestUserScript(), didReceiveMetric: metric)

        // Then
        XCTAssertFalse(mockFreeTrialConversionService.markDuckAIActivatedCalled)
    }

    func testWhenNoModelTierPromptSubmitted_ThenMarkDuckAIActivatedIsNotCalled() throws {
        // Given
        let metric = AIChatMetric(metricName: .userDidSubmitPrompt, modelTier: nil)

        // When
        handler.aiChatUserScript(makeTestUserScript(), didReceiveMetric: metric)

        // Then
        XCTAssertFalse(mockFreeTrialConversionService.markDuckAIActivatedCalled)
    }
}

// MARK: - Mocks

final class MockAIChatRequestAuthHandler: AIChatRequestAuthorizationHandling {
    func shouldAllowRequestWithNavigationAction(_ navigationAction: WKNavigationAction) -> Bool {
        true
    }
}

final class MockUnifiedToggleInputFeatureProvider: UnifiedToggleInputFeatureProviding {
    var isAvailable: Bool

    init(isAvailable: Bool = false) {
        self.isAvailable = isAvailable
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
    var canDispatchBridgeMessages: Bool = true

    var delegateSet = false
    var webViewSet = false
    var payloadHandlerSet = false
    var openLinkHandlerSet = false
    var openLinkHandler: ((URL) -> Void)?
    var pageContextProviderSet = false
    var submitPromptCallCount = 0
    var lastSubmittedPrompt: String?
    var lastSubmittedPageContext: AIChatPageContextData?
    var submitStartChatActionCallCount = 0
    var submitOpenSettingsActionCallCount = 0
    var submitToggleSidebarActionCallCount = 0
    var submitPageContextCallCount = 0
    var lastSubmittedPageContextViaSubmit: AIChatPageContextData?
    var lastDisplayModeSet: AIChatDisplayMode?

    func setPayloadHandler(_ payloadHandler: any AIChat.AIChatConsumableDataHandling) {
        payloadHandlerSet = true
    }

    func setOpenLinkHandler(_ openLinkHandler: ((URL) -> Void)?) {
        openLinkHandlerSet = true
        self.openLinkHandler = openLinkHandler
    }

    func setPageContextProvider(_ provider: ((PageContextRequestReason) -> AIChatPageContextData?)?) {
        pageContextProviderSet = true
    }

    func setContextualModePixelHandler(_ pixelHandler: AIChatContextualModePixelFiring) {
        // No-op for testing
    }

    func setDisplayMode(_ displayMode: AIChatDisplayMode) {
        lastDisplayModeSet = displayMode
    }

    func submitPrompt(_ prompt: String, pageContext: AIChatPageContextData?) {
        submitPromptCallCount += 1
        lastSubmittedPrompt = prompt
        lastSubmittedPageContext = pageContext
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

    func submitPageContext(_ context: AIChatPageContextData?) {
        submitPageContextCallCount += 1
        lastSubmittedPageContextViaSubmit = context
    }
}

// swiftlint:disable inclusive_language
final class MockAIChatUserScriptHandling: AIChatUserScriptHandling {
    var displayMode: AIChatDisplayMode?
    var isFireModeProvider: (() -> Bool)?

    func setPageContextProvider(_ provider: ((PageContextRequestReason) -> AIChatPageContextData?)?) {}
    func setContextualModePixelHandler(_ pixelHandler: AIChatContextualModePixelFiring) {}
    func getAIChatNativeConfigValues(params: Any, message: UserScriptMessage) -> Encodable? { nil }
    func getAIChatNativeHandoffData(params: Any, message: UserScriptMessage) -> Encodable? { nil }
    func getAIChatPageContext(params: Any, message: UserScriptMessage) -> Encodable? { nil }
    func openAIChat(params: Any, message: UserScriptMessage) async -> Encodable? { nil }
    @MainActor func openSummarizationSourceLink(params: Any, message: UserScriptMessage) async -> Encodable? { nil }
    @MainActor func openTranslationSourceLink(params: Any, message: UserScriptMessage) async -> Encodable? { nil }
    @MainActor func openAIChatLink(params: Any, message: UserScriptMessage) async -> Encodable? { nil }
    func setPayloadHandler(_ payloadHandler: (any AIChatConsumableDataHandling)?) {}
    func setOpenLinkHandler(_ handler: ((URL) -> Void)?) {}
    func setAIChatInputBoxHandler(_ inputBoxHandler: (any AIChatInputBoxHandling)?) {}
    func setMetricReportingHandler(_ metricHandler: (any AIChatMetricReportingHandling)?) {}
    func setSyncStatusChangedHandler(_ handler: ((AIChatSyncHandler.SyncStatus) -> Void)?) {}
    func getResponseState(params: Any, message: UserScriptMessage) async -> Encodable? { nil }
    func hideChatInput(params: Any, message: UserScriptMessage) async -> Encodable? { nil }
    func showChatInput(params: Any, message: UserScriptMessage) async -> Encodable? { nil }
    func reportMetric(params: Any, message: UserScriptMessage) async -> Encodable? { nil }
    func togglePageContextTelemetry(params: Any, message: UserScriptMessage) async -> Encodable? { nil }
    func openKeyboard(params: Any, message: UserScriptMessage, webView: WKWebView?) async -> Encodable? { nil }
    func storeMigrationData(params: Any, message: UserScriptMessage) -> Encodable? { nil }
    func getMigrationDataByIndex(params: Any, message: UserScriptMessage) -> Encodable? { nil }
    func getMigrationInfo(params: Any, message: UserScriptMessage) -> Encodable? { nil }
    func clearMigrationData(params: Any, message: UserScriptMessage) -> Encodable? { nil }
    func getSyncStatus(params: Any, message: UserScriptMessage) -> Encodable? { nil }
    func getScopedSyncAuthToken(params: Any, message: UserScriptMessage) async -> Encodable? { nil }
    func encryptWithSyncMasterKey(params: Any, message: UserScriptMessage) -> Encodable? { nil }
    func decryptWithSyncMasterKey(params: Any, message: UserScriptMessage) -> Encodable? { nil }
    func sendToSyncSettings(params: Any, message: UserScriptMessage) -> Encodable? { nil }
    func sendToSetupSync(params: Any, message: UserScriptMessage) -> Encodable? { nil }
    func setAIChatHistoryEnabled(params: Any, message: UserScriptMessage) -> Encodable? { nil }
    func getAIChatNativePrompt(params: Any, message: UserScriptMessage) -> Encodable? { nil }
    func responseReceived(params: Any, message: any UserScriptMessage) async -> (any Encodable)? { nil }
    func voiceSessionStarted(params: Any, message: UserScriptMessage) async -> Encodable? { nil }
    func voiceSessionEnded(params: Any, message: UserScriptMessage) async -> Encodable? { nil }
}
// swiftlint:enable inclusive_language

final class MockAIChatDebugSettingsForTests: AIChatDebugSettingsHandling {
    var messagePolicyHostname: String?
    var customURL: String?
    var contextualSessionTimerSeconds: Int?
    func reset() {}
    func matchesCustomURL(_ url: URL) -> Bool { false }
}

func makeTestUserScript() -> AIChatUserScript {
    AIChatUserScript(handler: MockAIChatUserScriptHandling(), debugSettings: MockAIChatDebugSettingsForTests())
}
