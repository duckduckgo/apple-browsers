//
//  AIChatUserScriptHandlerTests.swift
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

@testable import AIChat
import BrowserServicesKit
import BrowserServicesKitTestsUtils
import Combine
import Common
import FeatureFlags_macOS
import FoundationExtensions
@testable import DDGSync
@_spi(Testing) import Persistence
@_spi(Testing) import PixelKit
import PrivacyConfig
@_spi(Testing) import SharedTestUtilities
import Subscription
import SubscriptionTestingUtilities
import Testing
import UserScript
import WebKit

@testable import DuckDuckGo_Privacy_Browser

final class MockAIChatMessageHandler: AIChatMessageHandling {

    struct SetData {
        let data: Any?
        let type: AIChatMessageType

        init(_ data: Any?, _ type: AIChatMessageType) {
            self.data = data
            self.type = type
        }
    }
    var getDataForMessageTypeCalls: [AIChatMessageType] = []
    var getNativeConfigValuesCalls: [Bool] = []
    var setDataCalls: [SetData] = []

    var getDataForMessageTypeImpl: (AIChatMessageType) -> Encodable? = { _ in nil }
    var getNativeConfigValuesImpl: (Bool) -> AIChatNativeConfigValues = { _ in .defaultValues }
    var setData: (Any?, AIChatMessageType) -> Void = { _, _ in }

    func getNativeConfigValues(isFireWindow: Bool) -> AIChatNativeConfigValues {
        getNativeConfigValuesCalls.append(isFireWindow)
        return getNativeConfigValuesImpl(isFireWindow)
    }

    func getDataForMessageType(_ type: AIChatMessageType) -> Encodable? {
        getDataForMessageTypeCalls.append(type)
        return getDataForMessageTypeImpl(type)
    }

    func setData(_ data: Any?, forMessageType type: AIChatMessageType) {
        setDataCalls.append(.init(data, type))
        setData(data, type)
    }

    var appendSelectionContextCalls: [AIChatSelectionContextData] = []
    var clearSelectionContextsCallCount = 0
    var getSelectionContextsImpl: () -> [AIChatSelectionContextData] = { [] }

    func appendSelectionContext(_ selection: AIChatSelectionContextData) {
        appendSelectionContextCalls.append(selection)
    }

    func getSelectionContexts() -> [AIChatSelectionContextData] {
        getSelectionContextsImpl()
    }

    func clearSelectionContexts() {
        clearSelectionContextsCallCount += 1
    }
}

final class MockDuckAIPromptAtbRefresher: DuckAIPromptAtbRefreshing {
    private(set) var refreshCallCount = 0

    func refreshRetentionAtbOnDuckAiPromptSubmition(completion: @escaping () -> Void) {
        refreshCallCount += 1
        completion()
    }
}

// swiftlint:disable inclusive_language
struct AIChatUserScriptHandlerTests {
    private var storage = MockAIChatPreferencesStorage()
    private var messageHandler = MockAIChatMessageHandler()
    private var windowControllersManager: WindowControllersManagerMock
    private var notificationCenter = NotificationCenter()
    private var pixelFiring = PixelKitMock()
    private var userScriptErrorEventMapper = CapturingAIChatUserScriptErrorEventMapper()
    private var syncErrorHandler = SyncErrorHandler(alertPresenter: CapturingAlertPresenter())
    private var handler: AIChatUserScriptHandler
    private var statisticsLoader = MockDuckAIPromptAtbRefresher()
    private var mockFreeTrialConversionService = MockFreeTrialConversionInstrumentationService()
    /// An install that has prompted before, so only the tests about the first prompt see the flag.
    private var featureDiscovery = MockFeatureDiscovery()

    @MainActor
    init() {
        windowControllersManager = WindowControllersManagerMock()
        featureDiscovery.setReturnValue(true, for: .duckAIPrompt)

        handler = AIChatUserScriptHandler(
            storage: storage,
            messageHandling: messageHandler,
            windowControllersManager: windowControllersManager,
            pixelFiring: pixelFiring,
            statisticsLoader: statisticsLoader,
            syncServiceProvider: { nil },
            syncErrorHandler: syncErrorHandler,
            featureFlagger: MockFeatureFlagger(),
            aiChatUserScriptErrorEventMapper: userScriptErrorEventMapper,
            freeTrialConversionService: mockFreeTrialConversionService,
            notificationCenter: notificationCenter,
            featureDiscovery: featureDiscovery
        )
    }

    @available(iOS 16, macOS 13, *)
    @Test("openAIChatSettings calls windowControllersManager", .timeLimit(.minutes(1)))
    @MainActor
    func testThatOpenAIChatSettingsCallsWindowControllersManager() async {
        _ = await handler.openAIChatSettings(params: [], message: WKScriptMessage.mock())
        #expect(windowControllersManager.showTabCalls == [.settings(pane: .aiChat)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("getAIChatNativeConfigValues calls messageHandler", .timeLimit(.minutes(1)))
    func testThatGetAIChatNativeConfigValuesCallsMessageHandler() async {
        _ = await handler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock())
        #expect(messageHandler.getNativeConfigValuesCalls == [false])
    }

    @available(iOS 16, macOS 13, *)
    @Test("getAIChatNativeConfigValues propagates fire-window provider value", .timeLimit(.minutes(1)))
    func testWhenFireWindowProviderReturnsTrueThenGetAIChatNativeConfigValuesPassesTrue() async {
        handler.isFireWindowProvider = { true }
        _ = await handler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock())
        #expect(messageHandler.getNativeConfigValuesCalls == [true])
    }

    @available(iOS 16, macOS 13, *)
    @Test("getAIChatNativeConfigValues defaults to false when no provider set", .timeLimit(.minutes(1)))
    func testWhenFireWindowProviderIsNilThenGetAIChatNativeConfigValuesPassesFalse() async {
        handler.isFireWindowProvider = nil
        _ = await handler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock())
        #expect(messageHandler.getNativeConfigValuesCalls == [false])
    }

    @available(iOS 16, macOS 13, *)
    @Test("getAIChatNativePrompt calls messageHandler", .timeLimit(.minutes(1)))
    func testThatGetAIChatNativePromptCallsMessageHandler() async {
        _ = await handler.getAIChatNativePrompt(params: [], message: WKScriptMessage.mock())
        #expect(messageHandler.getDataForMessageTypeCalls == [.nativePrompt])
    }

    @available(iOS 16, macOS 13, *)
    @Test("getAIChatSelectionContext returns the stored selections", .timeLimit(.minutes(1)))
    @MainActor
    func testThatGetAIChatSelectionContextReturnsStoredSelections() {
        let selection = AIChatSelectionContextData(id: "id-1", title: "Text selection", url: "https://example.com", content: "hi", truncated: false, fullContentLength: 2, wordCount: 1)
        messageHandler.getSelectionContextsImpl = { [selection] }

        let response = handler.getAIChatSelectionContext(params: [], message: WKScriptMessage.mock()) as? SelectionContextResponse

        #expect(response?.selections == [selection])
    }

    @available(iOS 16, macOS 13, *)
    @Test("submitting a prompt clears the stored selections", .timeLimit(.minutes(1)))
    @MainActor
    func testThatSubmittingPromptClearsSelectionStore() {
        handler.didReportMetric(.init(metricName: .userDidSubmitPrompt))
        #expect(messageHandler.clearSelectionContextsCallCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("openAIChat posts a notification with a payload", .timeLimit(.minutes(1)))
    @MainActor
    func testThatOpenAIChatPostsNotificationWithPayload() async throws {

        struct NotificationNotReceivedError: Error {}

        let notificationsStream = AsyncStream { continuation in
            let observer = notificationCenter.addObserver(forName: .aiChatNativeHandoffData, object: nil, queue: nil) { notification in
                continuation.yield(notification)
            }
            continuation.onTermination = { _ in
                notificationCenter.removeObserver(observer)
            }
        }

        let payload: [String: String] = ["foo": "bar"]
        _ = await handler.openAIChat(params: [AIChatUserScriptHandler.AIChatKeys.aiChatPayload: payload], message: WKScriptMessage.mock())

        guard let notificationObject = await notificationsStream.map(\.object).first(where: { _ in true }) else {
            throw NotificationNotReceivedError()
        }
        let notificationPayload = try #require(notificationObject as? [String: String])
        #expect(notificationPayload == payload)
    }

    @available(iOS 16, macOS 13, *)
    @Test("getAIChatNativeHandoffData calls messageHandler", .timeLimit(.minutes(1)))
    func testThatGetAIChatNativeHandoffDataCallsMessageHandler() async throws {
        _ = await handler.getAIChatNativeHandoffData(params: [], message: WKScriptMessage.mock())
        #expect(messageHandler.getDataForMessageTypeCalls == [.nativeHandoffData])
    }

    @available(iOS 16, macOS 13, *)
    @Test("recordChat calls messageHandler", .timeLimit(.minutes(1)))
    func testThatRecordChatCallsMessageHandler() async throws {
        _ = await handler.recordChat(
            params: [AIChatUserScriptHandler.AIChatKeys.serializedChatData: "test"],
            message: WKScriptMessage.mock()
        )
        #expect(messageHandler.setDataCalls.count == 1)
        let setDataCall = try #require(messageHandler.setDataCalls.first?.data as? String)
        #expect(setDataCall == "test")
    }

    @available(iOS 16, macOS 13, *)
    @Test("restoreChat returns serialized chat data", .timeLimit(.minutes(1)))
    func testThatRestoreChatReturnsSerializedChatData() async throws {
        messageHandler.getDataForMessageTypeImpl = { _ in return "test" }

        let result = await handler.restoreChat(params: [], message: WKScriptMessage.mock())
        #expect(messageHandler.getDataForMessageTypeCalls == [.chatRestorationData])
        let resultDictionary = try #require(result as? [String: String])
        #expect(resultDictionary[AIChatUserScriptHandler.AIChatKeys.serializedChatData] == "test")
    }

    @available(iOS 16, macOS 13, *)
    @Test("restoreChat returns nil when chat data is not a string", .timeLimit(.minutes(1)))
    func testThatRestoreChatReturnsNilWhenChatDataIsNotString() async throws {
        messageHandler.getDataForMessageTypeImpl = { _ in return 123 }

        let result = await handler.restoreChat(params: [], message: WKScriptMessage.mock())
        #expect(messageHandler.getDataForMessageTypeCalls == [.chatRestorationData])
        #expect(result == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("restoreChat returns nil when chat data is nil", .timeLimit(.minutes(1)))
    func testThatRestoreChatReturnsNilWhenChatDataIsNil() async throws {
        messageHandler.getDataForMessageTypeImpl = { _ in return nil }

        let result = await handler.restoreChat(params: [], message: WKScriptMessage.mock())
        #expect(messageHandler.getDataForMessageTypeCalls == [.chatRestorationData])
        #expect(result == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("removeChat calls messageHandler", .timeLimit(.minutes(1)))
    func testThatRemoveChatCallsMessageHandler() async throws {
        _ = await handler.removeChat(params: [], message: WKScriptMessage.mock())
        #expect(messageHandler.setDataCalls.count == 1)
        #expect(messageHandler.setDataCalls.first?.data == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("openSummarizationSourceLink calls windowControllersManager show when valid URL is passed with same tab target", .timeLimit(.minutes(1)))
    @MainActor
    func testThatOpenSummarizationSourceLinkCallsWindowControllersManagerShow() async throws {
        let urlString = "https://example.com"
        let openLinkPayload = AIChatUserScriptHandler.OpenLink(url: urlString, target: .sameTab, name: nil)
        let params = try #require(DecodableHelper.encode(openLinkPayload).flatMap { try JSONSerialization.jsonObject(with: $0, options: []) })
        pixelFiring.expectedFireCalls = [.init(pixel: AIChatPixel.aiChatSummarizeSourceLinkClicked, frequency: .dailyAndStandard)]

        _ = await handler.openSummarizationSourceLink(params: params, message: WKScriptMessage.mock())

        let showCall = try #require(windowControllersManager.showCalled)
        #expect(showCall.url?.absoluteString == urlString)
        #expect(showCall.source == .switchToOpenTab)
        #expect(showCall.newTab == true)
        #expect(showCall.selected == true)
        #expect(pixelFiring.expectedFireCalls == pixelFiring.actualFireCalls)
    }

    static let targets: [AIChatUserScriptHandler.OpenLink.OpenTarget] = [.newTab, .newWindow]
    @available(iOS 16, macOS 13, *)
    @Test("openSummarizationSourceLink calls windowControllersManager open when valid URL is passed with non-same-tab target", .timeLimit(.minutes(1)), arguments: targets)
    @MainActor
    func testThatOpenSummarizationSourceLinkCallsWindowControllersManagerOpen(_ target: AIChatUserScriptHandler.OpenLink.OpenTarget) async throws {
        let urlString = "https://example.com"
        let openLinkPayload = AIChatUserScriptHandler.OpenLink(url: urlString, target: target, name: nil)
        let params = try #require(DecodableHelper.encode(openLinkPayload).flatMap { try JSONSerialization.jsonObject(with: $0, options: []) })
        pixelFiring.expectedFireCalls = [.init(pixel: AIChatPixel.aiChatSummarizeSourceLinkClicked, frequency: .dailyAndStandard)]

        _ = await handler.openSummarizationSourceLink(params: params, message: WKScriptMessage.mock())

        #expect(windowControllersManager.openCalls.count == 1)
        let openCall = try #require(windowControllersManager.openCalls.first)
        #expect(openCall.url.absoluteString == urlString)
        #expect(openCall.source == .link)
        #expect(pixelFiring.expectedFireCalls == pixelFiring.actualFireCalls)
    }

    @available(iOS 16, macOS 13, *)
    @Test("openSummarizationSourceLink doesn't call windowControllersManager when invalid URL is passed", .timeLimit(.minutes(1)))
    @MainActor
    func testThatOpenSummarizationSourceLinkDoesNotCallWindowControllersManagerWhenInvalidURLIsPassed() async throws {
        let urlString = "invalid"
        let openLinkPayload = AIChatUserScriptHandler.OpenLink(url: urlString, target: .sameTab, name: nil)
        let params = try #require(DecodableHelper.encode(openLinkPayload).flatMap { try JSONSerialization.jsonObject(with: $0, options: []) })

        _ = await handler.openSummarizationSourceLink(params: params, message: WKScriptMessage.mock())

        #expect(windowControllersManager.openCalls.count == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("openTranslationSourceLink calls windowControllersManager show when valid URL is passed with same tab target", .timeLimit(.minutes(1)))
    @MainActor
    func testThatOpenTranslationSourceLinkCallsWindowControllersManagerShow() async throws {
        let urlString = "https://example.com"
        let openLinkPayload = AIChatUserScriptHandler.OpenLink(url: urlString, target: .sameTab, name: nil)
        let params = try #require(DecodableHelper.encode(openLinkPayload).flatMap { try JSONSerialization.jsonObject(with: $0, options: []) })
        pixelFiring.expectedFireCalls = [.init(pixel: AIChatPixel.aiChatTranslationSourceLinkClicked, frequency: .dailyAndStandard)]

        _ = await handler.openTranslationSourceLink(params: params, message: WKScriptMessage.mock())

        let showCall = try #require(windowControllersManager.showCalled)
        #expect(showCall.url?.absoluteString == urlString)
        #expect(showCall.source == .switchToOpenTab)
        #expect(showCall.newTab == true)
        #expect(showCall.selected == true)
        #expect(pixelFiring.expectedFireCalls == pixelFiring.actualFireCalls)
    }

    @available(iOS 16, macOS 13, *)
    @Test("openTranslationSourceLink calls windowControllersManager open when valid URL is passed with non-same-tab target", .timeLimit(.minutes(1)), arguments: targets)
    @MainActor
    func testThatOpenTranslationSourceLinkCallsWindowControllersManagerOpen(_ target: AIChatUserScriptHandler.OpenLink.OpenTarget) async throws {
        let urlString = "https://example.com"
        let openLinkPayload = AIChatUserScriptHandler.OpenLink(url: urlString, target: target, name: nil)
        let params = try #require(DecodableHelper.encode(openLinkPayload).flatMap { try JSONSerialization.jsonObject(with: $0, options: []) })
        pixelFiring.expectedFireCalls = [.init(pixel: AIChatPixel.aiChatTranslationSourceLinkClicked, frequency: .dailyAndStandard)]

        _ = await handler.openTranslationSourceLink(params: params, message: WKScriptMessage.mock())

        #expect(windowControllersManager.openCalls.count == 1)
        let openCall = try #require(windowControllersManager.openCalls.first)
        #expect(openCall.url.absoluteString == urlString)
        #expect(openCall.source == .link)
        #expect(pixelFiring.expectedFireCalls == pixelFiring.actualFireCalls)
    }

    @available(iOS 16, macOS 13, *)
    @Test("openTranslationSourceLink doesn't call windowControllersManager when invalid URL is passed", .timeLimit(.minutes(1)))
    @MainActor
    func testThatOpenTranslationSourceLinkDoesNotCallWindowControllersManagerWhenInvalidURLIsPassed() async throws {
        let urlString = "invalid"
        let openLinkPayload = AIChatUserScriptHandler.OpenLink(url: urlString, target: .sameTab, name: nil)
        let params = try #require(DecodableHelper.encode(openLinkPayload).flatMap { try JSONSerialization.jsonObject(with: $0, options: []) })

        _ = await handler.openTranslationSourceLink(params: params, message: WKScriptMessage.mock())

        #expect(windowControllersManager.openCalls.count == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("submitAIChatNativePrompt forwards prompt to the publisher", .timeLimit(.minutes(1)))
    func testThatSubmitAIChatNativePromptForwardsPromptToPublisher() async throws {
        struct EventNotReceivedError: Error {}

        let promptStream = AsyncStream { continuation in
            let cancellable = handler.aiChatNativePromptPublisher
                .sink { prompt in
                    continuation.yield(prompt)
                }

            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }

        handler.submitAIChatNativePrompt(.queryPrompt("test", autoSubmit: true))

        guard let prompt = await promptStream.first(where: { _ in true }) else {
            throw EventNotReceivedError()
        }
        #expect(prompt == .queryPrompt("test", autoSubmit: true))
    }

    // MARK: - Terms of Service

    @available(iOS 16, macOS 13, *)
    @Test("A prompt sent with Ask once the terms are accepted crosses the bridge accepted", .timeLimit(.minutes(1)))
    @MainActor
    func testWhenSentWithAskAndTermsAreAcceptedThenPulledPromptCarriesTermsAccepted() async {
        let termsOfServiceStore = makeTermsOfServiceStore(accepted: true)
        let testHandler = makeTermsOfServiceHandler(termsOfServiceStore: termsOfServiceStore)
        messageHandler.getDataForMessageTypeImpl = { _ in AIChatNativePrompt.queryPrompt("test", autoSubmit: true).withTermsAccepted(true) }

        let prompt = await testHandler.getAIChatNativePrompt(params: [], message: WKScriptMessage.mock()) as? AIChatNativePrompt

        #expect(prompt?.termsAccepted == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A prompt sent with Ask before any acceptance crosses the bridge not accepted", .timeLimit(.minutes(1)))
    @MainActor
    func testWhenSentWithAskAndTermsAreNotAcceptedThenPulledPromptCarriesFalse() async {
        let testHandler = makeTermsOfServiceHandler(termsOfServiceStore: makeTermsOfServiceStore(accepted: false))
        messageHandler.getDataForMessageTypeImpl = { _ in AIChatNativePrompt.queryPrompt("test", autoSubmit: true).withTermsAccepted(true) }

        let prompt = await testHandler.getAIChatNativePrompt(params: [], message: WKScriptMessage.mock()) as? AIChatNativePrompt

        #expect(prompt?.termsAccepted == false)
    }

    /// Return, and every surface without an Ask button, leaves the web app to apply its own terms.
    @available(iOS 16, macOS 13, *)
    @Test("A prompt not sent with Ask crosses the bridge not accepted", .timeLimit(.minutes(1)))
    @MainActor
    func testWhenNotSentWithAskThenPulledPromptCarriesFalse() async {
        let testHandler = makeTermsOfServiceHandler(termsOfServiceStore: makeTermsOfServiceStore(accepted: true))
        messageHandler.getDataForMessageTypeImpl = { _ in AIChatNativePrompt.queryPrompt("test", autoSubmit: true) }

        let prompt = await testHandler.getAIChatNativePrompt(params: [], message: WKScriptMessage.mock()) as? AIChatNativePrompt

        #expect(prompt?.termsAccepted == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("With native Terms of Service off, prompts carry no termsAccepted", .timeLimit(.minutes(1)))
    @MainActor
    func testWhenNativeTermsOfServiceIsOffThenPulledPromptOmitsTermsAccepted() async {
        let testHandler = makeTermsOfServiceHandler(isFlagOn: false, termsOfServiceStore: makeTermsOfServiceStore(accepted: true))
        messageHandler.getDataForMessageTypeImpl = { _ in AIChatNativePrompt.queryPrompt("test", autoSubmit: true).withTermsAccepted(true) }

        let prompt = await testHandler.getAIChatNativePrompt(params: [], message: WKScriptMessage.mock()) as? AIChatNativePrompt

        #expect(prompt != nil)
        #expect(prompt?.termsAccepted == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A pushed prompt sent with Ask carries the acceptance", .timeLimit(.minutes(1)))
    @MainActor
    func testWhenPushedPromptWasSentWithAskThenItCarriesTermsAccepted() async throws {
        struct EventNotReceivedError: Error {}
        let testHandler = makeTermsOfServiceHandler(termsOfServiceStore: makeTermsOfServiceStore(accepted: true))

        let promptStream = AsyncStream { continuation in
            let cancellable = testHandler.aiChatNativePromptPublisher
                .sink { prompt in
                    continuation.yield(prompt)
                }

            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }

        testHandler.submitAIChatNativePrompt(AIChatNativePrompt.queryPrompt("test", autoSubmit: true).withTermsAccepted(true))

        guard let prompt = await promptStream.first(where: { _ in true }) else {
            throw EventNotReceivedError()
        }
        #expect(prompt.termsAccepted == true)
    }

    /// The web reports the acceptance an Ask click carried; that report is the same acceptance.
    @available(iOS 16, macOS 13, *)
    @Test("The web's report of a native acceptance is not a duplicate", .timeLimit(.minutes(1)))
    @MainActor
    func testWhenWebReportsAnAcceptanceMadeNativelyThenNoDuplicatePixelFires() async {
        let termsOfServiceStore = makeTermsOfServiceStore(accepted: false)
        termsOfServiceStore.recordAcceptedInNativeInput()
        let testPixelFiring = PixelKitMock()
        let testHandler = makeTermsOfServiceHandler(termsOfServiceStore: termsOfServiceStore, pixelFiring: testPixelFiring)

        await withCheckedContinuation { continuation in
            testHandler.didReportMetric(.init(metricName: .userDidAcceptTermsAndConditions)) {
                continuation.resume()
            }
        }

        #expect(testPixelFiring.actualFireCalls.isEmpty)
        #expect(termsOfServiceStore.hasAccepted)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A repeat web acceptance fires the duplicate pixel", .timeLimit(.minutes(1)))
    @MainActor
    func testWhenWebReportsARepeatAcceptanceThenDuplicatePixelFires() async throws {
        let testPixelFiring = PixelKitMock()
        let testHandler = makeTermsOfServiceHandler(termsOfServiceStore: makeTermsOfServiceStore(accepted: true),
                                                    pixelFiring: testPixelFiring)

        await withCheckedContinuation { continuation in
            testHandler.didReportMetric(.init(metricName: .userDidAcceptTermsAndConditions)) {
                continuation.resume()
            }
        }
        // The pixel fires on a main-actor task of its own.
        let deadline = Date().addingTimeInterval(5)
        while testPixelFiring.actualFireCalls.isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(testPixelFiring.actualFireCalls == [.init(pixel: AIChatPixel.aiChatTermsAcceptedDuplicateSyncOff, frequency: .dailyAndStandard)])
    }

    private func makeTermsOfServiceStore(accepted: Bool) -> DuckAiTermsOfServiceStore {
        let store = DuckAiTermsOfServiceStore(keyValueStore: MockKeyValueStore())
        if accepted {
            store.recordWebReport()
        }
        return store
    }

    @MainActor
    private func makeTermsOfServiceHandler(isFlagOn: Bool = true,
                                           termsOfServiceStore: DuckAiTermsOfServiceStore,
                                           pixelFiring testPixelFiring: PixelKitMock = PixelKitMock()) -> AIChatUserScriptHandler {
        AIChatUserScriptHandler(
            storage: storage,
            messageHandling: messageHandler,
            windowControllersManager: windowControllersManager,
            pixelFiring: testPixelFiring,
            statisticsLoader: statisticsLoader,
            syncServiceProvider: { nil },
            syncErrorHandler: syncErrorHandler,
            featureFlagger: MockFeatureFlagger(featuresStub: [FeatureFlag.aiChatNativeTermsOfService.rawValue: isFlagOn]),
            notificationCenter: notificationCenter,
            featureDiscovery: featureDiscovery,
            termsOfServiceStore: termsOfServiceStore
        )
    }

    @available(iOS 16, macOS 13, *)
    @Test("didReportMetric refreshes ATBs only for prompt submission metrics", .timeLimit(.minutes(1)))
    func testThatUserDidSubmitPromptRefreshesATBs() async throws {
        let promptMetrics: [AIChatMetricName] = [
            .userDidSubmitPrompt,
            .userDidSubmitFirstPrompt
        ]

        for metric in promptMetrics {
            let loader = MockDuckAIPromptAtbRefresher()
            let testHandler = AIChatUserScriptHandler(
                storage: storage,
                messageHandling: messageHandler,
                windowControllersManager: windowControllersManager,
                pixelFiring: pixelFiring,
                statisticsLoader: loader,
                syncServiceProvider: { nil },
                syncErrorHandler: syncErrorHandler,
                featureFlagger: MockFeatureFlagger(),
                notificationCenter: notificationCenter,
                featureDiscovery: featureDiscovery
            )

            await withCheckedContinuation { continuation in
                testHandler.didReportMetric(.init(metricName: metric))
                DispatchQueue.main.async {
                    #expect(loader.refreshCallCount == 1)
                    continuation.resume()
                }
            }
        }

        let otherMetrics: [AIChatMetricName] = [
            .userDidOpenHistory,
            .userDidSelectFirstHistoryItem,
            .userDidCreateNewChat,
            .userDidTapKeyboardReturnKey
        ]

        for metric in otherMetrics {
            let loader = MockDuckAIPromptAtbRefresher()
            let testHandler = AIChatUserScriptHandler(
                storage: storage,
                messageHandling: messageHandler,
                windowControllersManager: windowControllersManager,
                pixelFiring: pixelFiring,
                statisticsLoader: loader,
                syncServiceProvider: { nil },
                syncErrorHandler: syncErrorHandler,
                featureFlagger: MockFeatureFlagger(),
                notificationCenter: notificationCenter,
                featureDiscovery: featureDiscovery
            )

            await withCheckedContinuation { continuation in
                testHandler.didReportMetric(.init(metricName: metric))
                DispatchQueue.main.async {
                    #expect(loader.refreshCallCount == 0)
                    continuation.resume()
                }
            }
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("didReportMetric fires start new conversation pixel for first prompt", .timeLimit(.minutes(1)))
    @MainActor
    func testThatUserDidSubmitFirstPromptFiresStartNewConversationPixel() async throws {
        let testPixelFiring = PixelKitMock()
        testPixelFiring.expectedFireCalls = [.init(pixel: AIChatPixel.aiChatMetricStartNewConversation(source: .unattributed, hasPageContext: false, surface: .duckAI, firstPromptNewInstall: false), frequency: .standard)]

        let testHandler = AIChatUserScriptHandler(
            storage: storage,
            messageHandling: messageHandler,
            windowControllersManager: windowControllersManager,
            pixelFiring: testPixelFiring,
            statisticsLoader: statisticsLoader,
            syncServiceProvider: { nil },
            syncErrorHandler: syncErrorHandler,
            featureFlagger: MockFeatureFlagger(),
            notificationCenter: notificationCenter,
            featureDiscovery: featureDiscovery
        )

        await withCheckedContinuation { continuation in
            testHandler.didReportMetric(.init(metricName: .userDidSubmitFirstPrompt)) {
                continuation.resume()
            }
        }

        #expect(testPixelFiring.expectedFireCalls == testPixelFiring.actualFireCalls)
    }

    @available(iOS 16, macOS 13, *)
    @Test("didReportMetric reports the surface that opened the chat", .timeLimit(.minutes(1)))
    @MainActor
    func testThatConversationPixelReportsTheOpeningSurface() async throws {
        // A tab-bar Duck.ai button gesture stamps the pending source just before opening the chat.
        let sourceHandler = AIChatConversationSourceHandler()
        sourceHandler.setData(.tabBarButton)

        let testPixelFiring = PixelKitMock()
        testPixelFiring.expectedFireCalls = [.init(pixel: AIChatPixel.aiChatMetricStartNewConversation(source: .tabBarButton, hasPageContext: false, surface: .duckAI, firstPromptNewInstall: false), frequency: .standard)]

        let testHandler = AIChatUserScriptHandler(
            storage: storage,
            messageHandling: messageHandler,
            windowControllersManager: windowControllersManager,
            pixelFiring: testPixelFiring,
            statisticsLoader: statisticsLoader,
            syncServiceProvider: { nil },
            syncErrorHandler: syncErrorHandler,
            featureFlagger: MockFeatureFlagger(),
            notificationCenter: notificationCenter,
            conversationSourceHandler: sourceHandler,
            featureDiscovery: featureDiscovery
        )

        // The chat's first native-config fetch (load) consumes and stores the pending source...
        _ = await testHandler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock())

        // ...so the deferred first-prompt pixel is attributed to it.
        await withCheckedContinuation { continuation in
            testHandler.didReportMetric(.init(metricName: .userDidSubmitFirstPrompt)) {
                continuation.resume()
            }
        }

        #expect(testPixelFiring.expectedFireCalls == testPixelFiring.actualFireCalls)
    }

    @available(iOS 16, macOS 13, *)
    @Test("didReportMetric fires sent prompt ongoing chat pixel for subsequent prompts", .timeLimit(.minutes(1)))
    @MainActor
    func testThatUserDidSubmitPromptFiresSentPromptOngoingChatPixel() async throws {
        let testPixelFiring = PixelKitMock()
        testPixelFiring.expectedFireCalls = [.init(pixel: AIChatPixel.aiChatMetricSentPromptOngoingChat(source: .unattributed, hasPageContext: false, surface: .duckAI, firstPromptNewInstall: false), frequency: .standard)]

        let testHandler = AIChatUserScriptHandler(
            storage: storage,
            messageHandling: messageHandler,
            windowControllersManager: windowControllersManager,
            pixelFiring: testPixelFiring,
            statisticsLoader: statisticsLoader,
            syncServiceProvider: { nil },
            syncErrorHandler: syncErrorHandler,
            featureFlagger: MockFeatureFlagger(),
            notificationCenter: notificationCenter,
            featureDiscovery: featureDiscovery
        )

        await withCheckedContinuation { continuation in
            testHandler.didReportMetric(.init(metricName: .userDidSubmitPrompt)) {
                continuation.resume()
            }
        }

        #expect(testPixelFiring.expectedFireCalls == testPixelFiring.actualFireCalls)
    }

    @available(iOS 16, macOS 13, *)
    @Test("didReportMetric fires the duck_ai_new_chat experiment metric only for the first prompt in a chat",
          .timeLimit(.minutes(1)),
          arguments: [(AIChatMetricName.userDidSubmitFirstPrompt, 1),
                      (AIChatMetricName.userDidSubmitPrompt, 0),
                      (AIChatMetricName.userDidCreateNewChat, 0)])
    @MainActor
    func testThatNewAIChatExperimentPixelsFireOnlyForFirstPrompt(metric: AIChatMetricName, expectedFireCount: Int) async throws {
        var firedCount = 0
        let testHandler = AIChatUserScriptHandler(
            storage: storage,
            messageHandling: messageHandler,
            windowControllersManager: windowControllersManager,
            pixelFiring: PixelKitMock(),
            statisticsLoader: statisticsLoader,
            syncServiceProvider: { nil },
            syncErrorHandler: syncErrorHandler,
            featureFlagger: MockFeatureFlagger(),
            notificationCenter: notificationCenter,
            fireNewAIChatExperimentPixels: { firedCount += 1 },
            featureDiscovery: featureDiscovery
        )

        await withCheckedContinuation { continuation in
            testHandler.didReportMetric(.init(metricName: metric)) {
                continuation.resume()
            }
        }

        #expect(firedCount == expectedFireCount)
    }

    /// `PixelKitMock` runs both sides through the same `parameters` code, so it can't catch a wrong
    /// value — these read the fired parameters directly.
    @MainActor
    private func firedConversationParameters(source: AIChatConversationSource?,
                                             metric: AIChatMetricName,
                                             webView: WKWebView? = nil) async -> [String: String]? {
        let sourceHandler = AIChatConversationSourceHandler()
        if let source {
            sourceHandler.setData(source)
        }

        let testPixelFiring = PixelKitMock()
        let testHandler = AIChatUserScriptHandler(
            storage: storage,
            messageHandling: messageHandler,
            windowControllersManager: windowControllersManager,
            pixelFiring: testPixelFiring,
            statisticsLoader: statisticsLoader,
            syncServiceProvider: { nil },
            syncErrorHandler: syncErrorHandler,
            featureFlagger: MockFeatureFlagger(),
            notificationCenter: notificationCenter,
            conversationSourceHandler: sourceHandler,
            featureDiscovery: featureDiscovery
        )

        // The first native-config fetch is what consumes the pending source.
        _ = await testHandler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock(webView: webView))

        await withCheckedContinuation { continuation in
            testHandler.didReportMetric(.init(metricName: metric)) {
                continuation.resume()
            }
        }

        return testPixelFiring.actualFireCalls.first?.pixel.parameters
    }

    @available(iOS 16, macOS 13, *)
    @Test("A chat with no recorded surface is attributed to 'other' rather than dropped", .timeLimit(.minutes(1)))
    @MainActor
    func testThatConversationPixelFallsBackToOtherSource() async {
        let parameters = await firedConversationParameters(source: nil, metric: .userDidSubmitFirstPrompt)
        #expect(parameters?["source"] == "unattributed")
        #expect(parameters?["isOpenedFromAskDuckAiButton"] == "false")
    }

    /// Where duckduckgo.com redirects a prompt its homepage composer hands to Duck.ai.
    private static let homepageFunnelChatURL = "https://duck.ai/chat?ia=chat&duckai=1&home=1&prompt=1&origin=funnel_home_website&t=h_"

    @available(iOS 16, macOS 13, *)
    @Test("A chat the homepage handed over is attributed to it", .timeLimit(.minutes(1)))
    @MainActor
    func testThatConversationPixelAttributesUnstampedChatToDuckDuckGoHomepage() async {
        let webView = mockWebView(url: Self.homepageFunnelChatURL)
        let parameters = await firedConversationParameters(source: nil, metric: .userDidSubmitFirstPrompt, webView: webView)
        #expect(parameters?["source"] == "duckduckgo-homepage")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A chat without the homepage funnel marker stays unattributed", .timeLimit(.minutes(1)))
    @MainActor
    func testThatConversationPixelDoesNotAttributeAChatWithoutTheFunnelMarkerToDuckDuckGoHomepage() async {
        let webView = mockWebView(url: "https://duck.ai/chat?ia=chat")
        let parameters = await firedConversationParameters(source: nil, metric: .userDidSubmitFirstPrompt, webView: webView)
        #expect(parameters?["source"] == "unattributed")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A recorded surface wins over the homepage funnel marker", .timeLimit(.minutes(1)))
    @MainActor
    func testThatConversationPixelPrefersRecordedSourceOverDuckDuckGoHomepageFallback() async {
        let webView = mockWebView(url: Self.homepageFunnelChatURL)
        let parameters = await firedConversationParameters(source: .serp, metric: .userDidSubmitFirstPrompt, webView: webView)
        #expect(parameters?["source"] == "serp")
    }

    @available(iOS 16, macOS 13, *)
    @Test("An ordinary duckduckgo.com page leaves a stamp pending for the chat it was meant for", .timeLimit(.minutes(1)))
    @MainActor
    func testThatANonChatPageDoesNotConsumeAPendingStamp() async {
        // The mailbox is app-wide, so a page that can't be a chat must not drain it — the chat it
        // was stamped for may be loading in another tab.
        let sourceHandler = AIChatConversationSourceHandler()
        let testPixelFiring = PixelKitMock()
        let testHandler = makeHandler(sourceHandler: sourceHandler, pixelFiring: testPixelFiring)

        sourceHandler.setData(.tabBarButton)

        let serpWebView = mockWebView(url: "https://duckduckgo.com/?q=test")
        _ = await testHandler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock(webView: serpWebView))

        #expect(sourceHandler.consumeData() == .tabBarButton)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A source staged after an earlier, empty config fetch is picked up by the next document", .timeLimit(.minutes(1)))
    @MainActor
    func testThatConversationPixelPicksUpSourceStagedAfterAnEarlierEmptyConfigFetch() async {
        // Mirrors the omnibar reusing a tab already on duckduckgo.com: the homepage's config fetch
        // runs first, then the omnibar stamps the real source and navigates that same tab to Duck.ai.
        let sourceHandler = AIChatConversationSourceHandler()
        let testPixelFiring = PixelKitMock()
        let testHandler = makeHandler(sourceHandler: sourceHandler, pixelFiring: testPixelFiring)

        let homepageWebView = mockWebView(url: "https://duckduckgo.com/")
        _ = await testHandler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock(webView: homepageWebView))

        sourceHandler.setData(.omnibar)
        testHandler.resetConversationSourceForNewDocument()

        let chatWebView = mockWebView(url: "https://duck.ai/")
        _ = await testHandler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock(webView: chatWebView))
        _ = await testHandler.reportMetric(params: ["metricName": "userDidSubmitFirstPrompt"], message: WKScriptMessage.mock())

        #expect(testPixelFiring.actualFireCalls.first?.pixel.parameters?["source"] == "omnibar")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Leaving the homepage for Duck.ai in the same tab is not attributed to the homepage", .timeLimit(.minutes(1)))
    @MainActor
    func testThatNavigatingFromTheHomepageToDuckAIIsNotAttributedToTheHomepage() async {
        let sourceHandler = AIChatConversationSourceHandler()
        let testPixelFiring = PixelKitMock()
        let testHandler = makeHandler(sourceHandler: sourceHandler, pixelFiring: testPixelFiring)

        let homepageWebView = mockWebView(url: "https://duckduckgo.com/")
        _ = await testHandler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock(webView: homepageWebView))
        testHandler.resetConversationSourceForNewDocument()

        let duckAIWebView = mockWebView(url: "https://duck.ai/")
        _ = await testHandler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock(webView: duckAIWebView))
        _ = await testHandler.reportMetric(params: ["metricName": "userDidSubmitFirstPrompt"], message: WKScriptMessage.mock())

        #expect(testPixelFiring.actualFireCalls.first?.pixel.parameters?["source"] == "unattributed")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Returning to the homepage for a second conversation drops the first conversation's source", .timeLimit(.minutes(1)))
    @MainActor
    func testThatASecondConversationInTheSameTabDoesNotReuseTheFirstSource() async {
        let sourceHandler = AIChatConversationSourceHandler()
        let testPixelFiring = PixelKitMock()
        let testHandler = makeHandler(sourceHandler: sourceHandler, pixelFiring: testPixelFiring)

        let homepageWebView = mockWebView(url: "https://duckduckgo.com/")
        _ = await testHandler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock(webView: homepageWebView))

        sourceHandler.setData(.omnibar)
        testHandler.resetConversationSourceForNewDocument()
        let chatWebView = mockWebView(url: "https://duck.ai/")
        _ = await testHandler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock(webView: chatWebView))
        _ = await testHandler.reportMetric(params: ["metricName": "userDidSubmitFirstPrompt"], message: WKScriptMessage.mock())
        #expect(testPixelFiring.actualFireCalls.first?.pixel.parameters?["source"] == "omnibar")

        // Back to the homepage in that same tab, then a fresh conversation from its toggle.
        testHandler.resetConversationSourceForNewDocument()
        let secondHomepageWebView = mockWebView(url: "https://duckduckgo.com/")
        _ = await testHandler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock(webView: secondHomepageWebView))
        testHandler.resetConversationSourceForNewDocument()
        let funnelWebView = mockWebView(url: Self.homepageFunnelChatURL)
        _ = await testHandler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock(webView: funnelWebView))
        _ = await testHandler.reportMetric(params: ["metricName": "userDidSubmitFirstPrompt"], message: WKScriptMessage.mock())

        #expect(testPixelFiring.actualFireCalls.last?.pixel.parameters?["source"] == "duckduckgo-homepage")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A new chat document in the same tab derives its own source", .timeLimit(.minutes(1)))
    @MainActor
    func testThatANewChatDocumentInTheSameTabDerivesItsOwnSource() async {
        // e.g. picking a recent chat from the omnibar while already on a Duck.ai tab.
        let sourceHandler = AIChatConversationSourceHandler()
        let testPixelFiring = PixelKitMock()
        let testHandler = makeHandler(sourceHandler: sourceHandler, pixelFiring: testPixelFiring)

        sourceHandler.setData(.omnibar)
        let chatWebView = mockWebView(url: "https://duck.ai/")
        _ = await testHandler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock(webView: chatWebView))

        sourceHandler.setData(.omnibarRecentChat)
        testHandler.resetConversationSourceForNewDocument()
        let recentChatWebView = mockWebView(url: "https://duck.ai/chat?chatID=abc123")
        _ = await testHandler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock(webView: recentChatWebView))
        _ = await testHandler.reportMetric(params: ["metricName": "userDidSubmitFirstPrompt"], message: WKScriptMessage.mock())

        #expect(testPixelFiring.actualFireCalls.first?.pixel.parameters?["source"] == "omnibar-recent-chat")
        #expect(sourceHandler.consumeData() == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A chat served from a homepage-shaped duckduckgo.com URL is not attributed to the homepage", .timeLimit(.minutes(1)))
    @MainActor
    func testThatAChatServedFromAHomepageShapedURLIsNotAttributedToTheHomepage() async {
        let webView = mockWebView(url: "https://duckduckgo.com/?ia=chat")
        let parameters = await firedConversationParameters(source: nil, metric: .userDidSubmitFirstPrompt, webView: webView)
        #expect(parameters?["source"] == "unattributed")
    }

    @available(iOS 16, macOS 13, *)
    @Test("An ongoing chat keeps its source within a document and leaves a later stamp alone", .timeLimit(.minutes(1)))
    @MainActor
    func testThatOngoingChatKeepsItsSourceAndLeavesALaterStampAlone() async {
        // Duck.ai rewrites its own URL as a conversation proceeds and may fetch the config again;
        // without a new document that must neither re-derive the source nor drain a stamp meant
        // for another chat.
        let sourceHandler = AIChatConversationSourceHandler()
        let testPixelFiring = PixelKitMock()
        let testHandler = makeHandler(sourceHandler: sourceHandler, pixelFiring: testPixelFiring)

        let funnelWebView = mockWebView(url: Self.homepageFunnelChatURL)
        _ = await testHandler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock(webView: funnelWebView))
        _ = await testHandler.reportMetric(params: ["metricName": "userDidSubmitFirstPrompt"], message: WKScriptMessage.mock())

        sourceHandler.setData(.omnibar)
        let rewrittenWebView = mockWebView(url: "https://duck.ai/chat?ia=chat&chatID=abc123")
        _ = await testHandler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock(webView: rewrittenWebView))
        _ = await testHandler.reportMetric(params: ["metricName": "userDidSubmitPrompt"], message: WKScriptMessage.mock())

        #expect(testPixelFiring.actualFireCalls.last?.pixel.parameters?["source"] == "duckduckgo-homepage")
        #expect(sourceHandler.consumeData() == .omnibar)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A non-button surface is reported verbatim and leaves the legacy boolean false", .timeLimit(.minutes(1)))
    @MainActor
    func testThatConversationPixelReportsNonButtonSourceVerbatim() async {
        let parameters = await firedConversationParameters(source: .contextualSummarize, metric: .userDidSubmitFirstPrompt)
        #expect(parameters?["source"] == "contextual-summarize")
        #expect(parameters?["isOpenedFromAskDuckAiButton"] == "false")
    }

    @available(iOS 16, macOS 13, *)
    @Test("An ongoing chat reports the surface that originally opened it", .timeLimit(.minutes(1)))
    @MainActor
    func testThatOngoingChatPixelReportsTheOpeningSurface() async {
        let parameters = await firedConversationParameters(source: .newTabPage, metric: .userDidSubmitPrompt)
        #expect(parameters?["source"] == "new-tab-page")
    }

    // MARK: - Direct navigation fallback

    @MainActor
    private func reportedSource(stamp: AIChatConversationSource?,
                                url: String,
                                fallbackBeforeLoad: AIChatConversationSource? = nil,
                                fallbackAfterLoad: AIChatConversationSource? = nil) async -> String? {
        let sourceHandler = AIChatConversationSourceHandler()
        if let stamp {
            sourceHandler.setData(stamp)
        }
        let testPixelFiring = PixelKitMock()
        let testHandler = makeHandler(sourceHandler: sourceHandler, pixelFiring: testPixelFiring)
        let webView = mockWebView(url: url)

        testHandler.directNavigationFallback = fallbackBeforeLoad
        _ = await testHandler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock(webView: webView))
        if let fallbackAfterLoad {
            testHandler.directNavigationFallback = fallbackAfterLoad
        }
        _ = await testHandler.reportMetric(params: ["metricName": "userDidSubmitFirstPrompt"], message: WKScriptMessage.mock(webView: webView))

        return testPixelFiring.actualFireCalls.last?.pixel.parameters?["source"]
    }

    @available(iOS 16, macOS 13, *)
    @Test("A direct navigation names a chat nothing else stamped", .timeLimit(.minutes(1)))
    @MainActor
    func testThatTheDirectNavigationFallbackAttributesAnUnstampedChat() async {
        #expect(await reportedSource(stamp: nil, url: "https://duck.ai/", fallbackBeforeLoad: .directBookmark) == "direct-bookmark")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A surface's stamp wins over a direct navigation", .timeLimit(.minutes(1)))
    @MainActor
    func testThatAStampWinsOverTheDirectNavigationFallback() async {
        #expect(await reportedSource(stamp: .omnibar, url: "https://duck.ai/", fallbackBeforeLoad: .directTyped) == "omnibar")
    }

    @available(iOS 16, macOS 13, *)
    @Test("The homepage marker wins over a direct navigation", .timeLimit(.minutes(1)))
    @MainActor
    func testThatTheHomepageMarkerWinsOverTheDirectNavigationFallback() async {
        #expect(await reportedSource(stamp: nil, url: Self.homepageFunnelChatURL, fallbackBeforeLoad: .directLink) == "duckduckgo-homepage")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A direct navigation that commits after the chat loaded still names it", .timeLimit(.minutes(1)))
    @MainActor
    func testThatALateDirectNavigationFallbackIsAdopted() async {
        #expect(await reportedSource(stamp: nil, url: "https://duck.ai/", fallbackAfterLoad: .directTyped) == "direct-typed")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A late direct navigation doesn't replace a surface's stamp", .timeLimit(.minutes(1)))
    @MainActor
    func testThatALateDirectNavigationFallbackDoesNotReplaceAStamp() async {
        #expect(await reportedSource(stamp: .omnibar, url: "https://duck.ai/", fallbackAfterLoad: .directTyped) == "omnibar")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A new document drops the previous document's direct navigation", .timeLimit(.minutes(1)))
    @MainActor
    func testThatANewDocumentDropsTheDirectNavigationFallback() async {
        let testPixelFiring = PixelKitMock()
        let testHandler = makeHandler(sourceHandler: AIChatConversationSourceHandler(), pixelFiring: testPixelFiring)
        let webView = mockWebView(url: "https://duck.ai/")
        testHandler.directNavigationFallback = .directHistory

        testHandler.resetConversationSourceForNewDocument()
        _ = await testHandler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock(webView: webView))
        _ = await testHandler.reportMetric(params: ["metricName": "userDidSubmitFirstPrompt"], message: WKScriptMessage.mock(webView: webView))

        #expect(testPixelFiring.actualFireCalls.last?.pixel.parameters?["source"] == "unattributed")
    }

    // MARK: - Prompt surface

    @available(iOS 16, macOS 13, *)
    @Test("Prompt surface values match the pixel definition", .timeLimit(.minutes(1)))
    func testPromptSurfaceRawValuesMatchPixelDefinition() {
        #expect(AIChatPromptSurface.allCases.map(\.rawValue) == ["address_bar", "new_tab_page", "prompt_bar", "duck_ai", "sidebar", "floating"])
    }

    /// Loads a chat the way it would after `source` opened it.
    @MainActor
    private func loadChat(stampedWith source: AIChatConversationSource,
                          pixelFiring testPixelFiring: PixelKitMock,
                          webView: WKWebView) async -> AIChatUserScriptHandler {
        let sourceHandler = AIChatConversationSourceHandler()
        sourceHandler.setData(source)
        let testHandler = makeHandler(sourceHandler: sourceHandler, pixelFiring: testPixelFiring)
        _ = await testHandler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock(webView: webView))
        return testHandler
    }

    @MainActor
    private func reportPrompt(_ metricName: String = "userDidSubmitFirstPrompt",
                              to testHandler: AIChatUserScriptHandler,
                              webView: WKWebView) async {
        _ = await testHandler.reportMetric(params: ["metricName": metricName], message: WKScriptMessage.mock(webView: webView))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A prompt typed in a Duck.ai tab reports duck_ai", .timeLimit(.minutes(1)))
    @MainActor
    func testThatAPromptInADuckAITabReportsDuckAI() async {
        let testPixelFiring = PixelKitMock()
        let webView = mockWebView(url: "https://duck.ai/")
        let testHandler = await loadChat(stampedWith: .tabBarButton, pixelFiring: testPixelFiring, webView: webView)

        await reportPrompt(to: testHandler, webView: webView)

        #expect(testPixelFiring.actualFireCalls.last?.pixel.parameters?["surface"] == "duck_ai")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A prompt typed in the sidebar reports sidebar", .timeLimit(.minutes(1)))
    @MainActor
    func testThatAPromptInTheSidebarReportsSidebar() async {
        let testPixelFiring = PixelKitMock()
        let webView = mockWebView(url: "https://duck.ai/?placement=sidebar")
        let testHandler = await loadChat(stampedWith: .tabBarSidebar, pixelFiring: testPixelFiring, webView: webView)
        testHandler.isSidebarProvider = { true }

        await reportPrompt(to: testHandler, webView: webView)

        #expect(testPixelFiring.actualFireCalls.last?.pixel.parameters?["surface"] == "sidebar")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A prompt typed in a detached sidebar reports floating", .timeLimit(.minutes(1)))
    @MainActor
    func testThatAPromptInADetachedSidebarReportsFloating() async {
        let testPixelFiring = PixelKitMock()
        let webView = mockWebView(url: "https://duck.ai/?placement=sidebar")
        let window = AIChatFloatingWindow()
        window.contentView = webView
        let testHandler = await loadChat(stampedWith: .tabBarSidebar, pixelFiring: testPixelFiring, webView: webView)
        testHandler.isSidebarProvider = { true }

        await reportPrompt(to: testHandler, webView: webView)

        #expect(testPixelFiring.actualFireCalls.last?.pixel.parameters?["surface"] == "floating")
        window.contentView = nil
    }

    @available(iOS 16, macOS 13, *)
    @Test("A prompt a native composer hands to a new chat reports that composer", .timeLimit(.minutes(1)), arguments: [
        (AIChatConversationSource.omnibar, "address_bar"),
        (.addressBar, "address_bar"),
        (.addressBarSuggestion, "address_bar"),
        (.addressBarContextMenu, "address_bar"),
        (.newTabPage, "new_tab_page"),
        (.promptBar, "prompt_bar")
    ])
    @MainActor
    func testThatAPulledNativePromptReportsItsComposer(source: AIChatConversationSource, expectedSurface: String) async {
        let testPixelFiring = PixelKitMock()
        let webView = mockWebView(url: "https://duck.ai/")
        messageHandler.getDataForMessageTypeImpl = { _ in AIChatNativePrompt.queryPrompt("Hello", autoSubmit: true) }
        let testHandler = await loadChat(stampedWith: source, pixelFiring: testPixelFiring, webView: webView)

        _ = await testHandler.getAIChatNativePrompt(params: [], message: WKScriptMessage.mock(webView: webView))
        await reportPrompt(to: testHandler, webView: webView)

        #expect(testPixelFiring.actualFireCalls.last?.pixel.parameters?["surface"] == expectedSurface)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A prompt a native composer pushes into an open chat reports that composer", .timeLimit(.minutes(1)), arguments: [
        (AIChatConversationSource.omnibar, "address_bar"),
        (.addressBar, "address_bar"),
        (.addressBarSuggestion, "address_bar"),
        (.addressBarContextMenu, "address_bar"),
        (.newTabPage, "new_tab_page"),
        (.promptBar, "prompt_bar")
    ])
    @MainActor
    func testThatAPushedNativePromptReportsItsComposer(source: AIChatConversationSource, expectedSurface: String) async {
        let testPixelFiring = PixelKitMock()
        let webView = mockWebView(url: "https://duck.ai/?placement=sidebar")
        let testHandler = await loadChat(stampedWith: source, pixelFiring: testPixelFiring, webView: webView)
        testHandler.isSidebarProvider = { true }

        testHandler.submitAIChatNativePrompt(.queryPrompt("Hello", autoSubmit: true))
        await reportPrompt(to: testHandler, webView: webView)

        #expect(testPixelFiring.actualFireCalls.last?.pixel.parameters?["surface"] == expectedSurface)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A native prompt the user still has to send reports where the chat is shown", .timeLimit(.minutes(1)))
    @MainActor
    func testThatANativePromptWithoutAutoSubmitReportsTheWindowSurface() async {
        let testPixelFiring = PixelKitMock()
        let webView = mockWebView(url: "https://duck.ai/")
        messageHandler.getDataForMessageTypeImpl = { _ in
            AIChatNativePrompt.queryPrompt("", autoSubmit: false, mode: AIChatNativePrompt.voiceMode)
        }
        let testHandler = await loadChat(stampedWith: .omnibar, pixelFiring: testPixelFiring, webView: webView)

        _ = await testHandler.getAIChatNativePrompt(params: [], message: WKScriptMessage.mock(webView: webView))
        await reportPrompt(to: testHandler, webView: webView)

        #expect(testPixelFiring.actualFireCalls.last?.pixel.parameters?["surface"] == "duck_ai")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A summary sent to an open sidebar reports sidebar", .timeLimit(.minutes(1)))
    @MainActor
    func testThatASummaryPushedToAnOpenSidebarReportsSidebar() async {
        let testPixelFiring = PixelKitMock()
        let webView = mockWebView(url: "https://duck.ai/?placement=sidebar")
        let testHandler = await loadChat(stampedWith: .addressBar, pixelFiring: testPixelFiring, webView: webView)
        testHandler.isSidebarProvider = { true }

        testHandler.submitAIChatNativePrompt(.summaryPrompt("Some text", url: nil, title: nil))
        await reportPrompt(to: testHandler, webView: webView)

        #expect(testPixelFiring.actualFireCalls.last?.pixel.parameters?["surface"] == "sidebar")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A prompt handed over by anything but a native composer reports where the chat is shown", .timeLimit(.minutes(1)))
    @MainActor
    func testThatANonComposerNativePromptReportsTheWindowSurface() async {
        let testPixelFiring = PixelKitMock()
        let webView = mockWebView(url: "https://duck.ai/")
        messageHandler.getDataForMessageTypeImpl = { _ in AIChatNativePrompt.queryPrompt("Hello", autoSubmit: true) }
        let testHandler = await loadChat(stampedWith: .serp, pixelFiring: testPixelFiring, webView: webView)

        _ = await testHandler.getAIChatNativePrompt(params: [], message: WKScriptMessage.mock(webView: webView))
        await reportPrompt(to: testHandler, webView: webView)

        #expect(testPixelFiring.actualFireCalls.last?.pixel.parameters?["surface"] == "duck_ai")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Only the prompt a composer handed over reports that composer", .timeLimit(.minutes(1)))
    @MainActor
    func testThatAHandedOverPromptReportsItsComposerOnlyOnce() async {
        let testPixelFiring = PixelKitMock()
        let webView = mockWebView(url: "https://duck.ai/")
        messageHandler.getDataForMessageTypeImpl = { _ in AIChatNativePrompt.queryPrompt("Hello", autoSubmit: true) }
        let testHandler = await loadChat(stampedWith: .newTabPage, pixelFiring: testPixelFiring, webView: webView)

        _ = await testHandler.getAIChatNativePrompt(params: [], message: WKScriptMessage.mock(webView: webView))
        await reportPrompt("userDidSubmitFirstPrompt", to: testHandler, webView: webView)
        await reportPrompt("userDidSubmitPrompt", to: testHandler, webView: webView)

        #expect(testPixelFiring.actualFireCalls.map { $0.pixel.parameters?["surface"] } == ["new_tab_page", "duck_ai"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A handed-over prompt that was never sent does not carry into the next document", .timeLimit(.minutes(1)))
    @MainActor
    func testThatANewDocumentDropsAnUnsentHandedOverPrompt() async {
        let sourceHandler = AIChatConversationSourceHandler()
        let testPixelFiring = PixelKitMock()
        let testHandler = makeHandler(sourceHandler: sourceHandler, pixelFiring: testPixelFiring)
        let webView = mockWebView(url: "https://duck.ai/")
        messageHandler.getDataForMessageTypeImpl = { _ in AIChatNativePrompt.queryPrompt("Hello", autoSubmit: true) }

        sourceHandler.setData(.omnibar)
        _ = await testHandler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock(webView: webView))
        _ = await testHandler.getAIChatNativePrompt(params: [], message: WKScriptMessage.mock(webView: webView))

        sourceHandler.setData(.omnibar)
        testHandler.resetConversationSourceForNewDocument()
        _ = await testHandler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage.mock(webView: webView))
        await reportPrompt(to: testHandler, webView: webView)

        #expect(testPixelFiring.actualFireCalls.last?.pixel.parameters?["surface"] == "duck_ai")
    }

    // MARK: - First prompt on a new install

    @available(iOS 16, macOS 13, *)
    @Test("Only a new install's first prompt reports first_prompt_new_install", .timeLimit(.minutes(1)))
    @MainActor
    func testThatOnlyTheFirstPromptOfANewInstallReportsTheFlag() async {
        let testPixelFiring = PixelKitMock()
        let newInstall = DefaultFeatureDiscovery(wasUsedBeforeStorage: InMemoryKeyValueStore(), notificationCenter: NotificationCenter())
        let testHandler = makeHandler(sourceHandler: AIChatConversationSourceHandler(),
                                      pixelFiring: testPixelFiring,
                                      featureDiscovery: newInstall)

        _ = await testHandler.reportMetric(params: ["metricName": "userDidSubmitFirstPrompt"], message: WKScriptMessage.mock())
        _ = await testHandler.reportMetric(params: ["metricName": "userDidSubmitPrompt"], message: WKScriptMessage.mock())
        _ = await testHandler.reportMetric(params: ["metricName": "userDidSubmitFirstPrompt"], message: WKScriptMessage.mock())

        #expect(testPixelFiring.actualFireCalls.map { $0.pixel.parameters?["first_prompt_new_install"] } == ["true", nil, nil])
    }

    @available(iOS 16, macOS 13, *)
    @Test("An ongoing-chat prompt can be a new install's first and reports it", .timeLimit(.minutes(1)))
    @MainActor
    func testThatAnOngoingChatPromptReportsTheFlagOnANewInstall() async {
        let testPixelFiring = PixelKitMock()
        let newInstall = MockFeatureDiscovery()
        let testHandler = makeHandler(sourceHandler: AIChatConversationSourceHandler(),
                                      pixelFiring: testPixelFiring,
                                      featureDiscovery: newInstall)

        _ = await testHandler.reportMetric(params: ["metricName": "userDidSubmitPrompt"], message: WKScriptMessage.mock())

        #expect(testPixelFiring.actualFireCalls.last?.pixel.parameters?["first_prompt_new_install"] == "true")
        #expect(newInstall.wasSetWasUsedBeforeCalled(for: .duckAIPrompt))
    }

    @available(iOS 16, macOS 13, *)
    @Test("An install that has prompted before never reports first_prompt_new_install", .timeLimit(.minutes(1)))
    @MainActor
    func testThatAnInstallThatPromptedBeforeOmitsTheFlag() async {
        let testPixelFiring = PixelKitMock()
        let testHandler = makeHandler(sourceHandler: AIChatConversationSourceHandler(), pixelFiring: testPixelFiring)

        _ = await testHandler.reportMetric(params: ["metricName": "userDidSubmitFirstPrompt"], message: WKScriptMessage.mock())

        #expect(testPixelFiring.actualFireCalls.last?.pixel.parameters?.keys.contains("first_prompt_new_install") == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("didReportMetric does not fire pixels for non-prompt metrics", .timeLimit(.minutes(1)))
    @MainActor
    func testThatNonPromptMetricsDoNotFirePixels() async throws {
        let testPixelFiring = PixelKitMock()

        let testHandler = AIChatUserScriptHandler(
            storage: storage,
            messageHandling: messageHandler,
            windowControllersManager: windowControllersManager,
            pixelFiring: testPixelFiring,
            statisticsLoader: statisticsLoader,
            syncServiceProvider: { nil },
            syncErrorHandler: syncErrorHandler,
            featureFlagger: MockFeatureFlagger(),
            notificationCenter: notificationCenter,
            featureDiscovery: featureDiscovery
        )

        let otherMetrics: [AIChatMetricName] = [
            .userDidOpenHistory,
            .userDidSelectFirstHistoryItem,
            .userDidCreateNewChat,
            .userDidTapKeyboardReturnKey
        ]

        for metric in otherMetrics {
            await withCheckedContinuation { continuation in
                testHandler.didReportMetric(.init(metricName: metric)) {
                    continuation.resume()
                }
            }
        }

        #expect(testPixelFiring.actualFireCalls.isEmpty)
    }

    // Constructing AIChatMetric from the enum can't catch a Swift
    // name that doesn't match what Duck.ai posts. 
    @available(iOS 16, macOS 13, *)
    @Test("reportMetric fires the subscription-funnel impression pixel with the matching origin", .timeLimit(.minutes(1)), arguments: [
        ("userDidViewAiSidebarUpgradeButton", "funnel_duckai_macos__aisidebar"),
        ("userDidViewActivateSubscriptionBanner", "funnel_duckai_macos__activatesubscription"),
        ("userDidViewFreePlanBadge", "funnel_duckai_macos__freelabel"),
        ("userDidViewFreeLimitMessage", "funnel_duckai_macos__freelimit"),
        ("userDidViewImageGenerationLimitMessage", "funnel_duckai_macos__imagegenerationlimit"),
        ("userDidViewPlusLimitMessage", "funnel_duckai_macos__pluslimit"),
        ("userDidViewPromotionCard", "funnel_duckai_macos__promotioncard"),
        ("userDidViewSettingsSubscribeButton", "funnel_duckai_macos__settings"),
        ("userDidViewProUpgradeDisclaimerBanner", "funnel_duckai_macos__disclaimerbanner"),
        ("userDidViewVoiceChatLimitModal", "funnel_duckai_macos__voicechatlimit"),
        ("userDidViewVoiceChatDurationLimitModal", "funnel_duckai_macos__voicechatdurationlimit"),
        ("userDidViewModelPickerUpgrade", "funnel_duckai_macos__modelpicker"),
        ("userDidViewReasoningDropdownUpgrade", "funnel_duckai_macos__reasoningdropdown"),
        ("userDidViewSwitchModelUpgrade", "funnel_duckai_macos__switchmodel")
    ])
    @MainActor
    func testFunnelImpressionMetricFiresImpressionPixelWithOrigin(metricName: String, origin: String) async {
        pixelFiring.expectedFireCalls = [.init(pixel: AIChatPixel.aiChatSubscriptionFunnelImpression(origin: origin), frequency: .dailyAndCount)]

        _ = await handler.reportMetric(
            params: ["metricName": metricName],
            message: WKScriptMessage.mock()
        )

        #expect(pixelFiring.expectedFireCalls == pixelFiring.actualFireCalls)
        #expect(userScriptErrorEventMapper.events.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("reportMetric fires the subscription-funnel click pixel with the matching origin", .timeLimit(.minutes(1)), arguments: [
        ("userDidClickAiSidebarUpgradeButton", "funnel_duckai_macos__aisidebar"),
        ("userDidClickActivateSubscriptionButton", "funnel_duckai_macos__activatesubscription"),
        ("userDidClickFreePlanUpgradeButton", "funnel_duckai_macos__freelabel"),
        ("userDidClickFreeLimitSubscribeLink", "funnel_duckai_macos__freelimit"),
        ("userDidClickImageGenerationLimitSubscribeButton", "funnel_duckai_macos__imagegenerationlimit"),
        ("userDidClickPlusLimitUpgradeLink", "funnel_duckai_macos__pluslimit"),
        ("userDidClickPromotionCardButton", "funnel_duckai_macos__promotioncard"),
        ("userDidClickSettingsSubscribeButton", "funnel_duckai_macos__settings"),
        ("userDidClickProUpgradeDisclaimerBannerButton", "funnel_duckai_macos__disclaimerbanner"),
        ("userDidClickVoiceChatLimitModalSubscribeButton", "funnel_duckai_macos__voicechatlimit"),
        ("userDidClickVoiceChatDurationLimitModalSubscribeButton", "funnel_duckai_macos__voicechatdurationlimit"),
        ("userDidClickModelPickerUpgrade", "funnel_duckai_macos__modelpicker"),
        ("userDidClickReasoningDropdownUpgrade", "funnel_duckai_macos__reasoningdropdown"),
        ("userDidClickSwitchModelUpgrade", "funnel_duckai_macos__switchmodel")
    ])
    @MainActor
    func testFunnelClickMetricFiresClickPixelWithOrigin(metricName: String, origin: String) async {
        pixelFiring.expectedFireCalls = [.init(pixel: AIChatPixel.aiChatSubscriptionFunnelClick(origin: origin), frequency: .dailyAndCount)]

        _ = await handler.reportMetric(
            params: ["metricName": metricName],
            message: WKScriptMessage.mock()
        )

        #expect(pixelFiring.expectedFireCalls == pixelFiring.actualFireCalls)
        #expect(userScriptErrorEventMapper.events.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("didReportMetric fires the matching modal pixel for each modal metric", .timeLimit(.minutes(1)), arguments: [
        (AIChatMetricName.userDidOpenSubscribeModal,
         AIChatPixel.aiChatSubscriptionFunnelSubscribeModalImpression(origin: "funnel_duckai_macos__freelimit")),
        (.userDidClickSubscribeOnSubscribeModal,
         .aiChatSubscriptionFunnelSubscribeModalSubscribeClick(origin: "funnel_duckai_macos__freelimit")),
        (.userDidClickActivateOnSubscribeModal,
         .aiChatSubscriptionFunnelSubscribeModalActivateClick(origin: "funnel_duckai_macos__freelimit")),
        (.userDidOpenUpgradeToProModal,
         .aiChatSubscriptionFunnelUpgradeToProModalImpression(origin: "funnel_duckai_macos__freelimit")),
        (.userDidClickUpgradeOnUpgradeToProModal,
         .aiChatSubscriptionFunnelUpgradeToProModalUpgradeClick(origin: "funnel_duckai_macos__freelimit"))
    ])
    @MainActor
    func testModalMetricFiresMatchingModalPixel(metric: AIChatMetricName, expectedPixel: AIChatPixel) async {
        pixelFiring.expectedFireCalls = [.init(pixel: expectedPixel, frequency: .dailyAndCount)]

        await withCheckedContinuation { continuation in
            handler.didReportMetric(.init(metricName: metric, source: "freelimit")) {
                continuation.resume()
            }
        }

        #expect(pixelFiring.expectedFireCalls == pixelFiring.actualFireCalls)
    }

    // Pins the names against the aichat_pixels.json5 keys; the firing tests build both sides from
    // the same enum, so they can't catch a wrong name.
    @available(iOS 16, macOS 13, *)
    @Test("Modal funnel pixels use the agreed names and carry the origin parameter", .timeLimit(.minutes(1)), arguments: [
        (AIChatPixel.aiChatSubscriptionFunnelSubscribeModalImpression(origin: "funnel_duckai_macos__freelimit"),
         "aichat_subscription-funnel_subscribe-modal_impression"),
        (.aiChatSubscriptionFunnelSubscribeModalSubscribeClick(origin: "funnel_duckai_macos__freelimit"),
         "aichat_subscription-funnel_subscribe-modal_subscribe_click"),
        (.aiChatSubscriptionFunnelSubscribeModalActivateClick(origin: "funnel_duckai_macos__freelimit"),
         "aichat_subscription-funnel_subscribe-modal_activate_click"),
        (.aiChatSubscriptionFunnelUpgradeToProModalImpression(origin: "funnel_duckai_macos__freelimit"),
         "aichat_subscription-funnel_upgrade-to-pro-modal_impression"),
        (.aiChatSubscriptionFunnelUpgradeToProModalUpgradeClick(origin: "funnel_duckai_macos__freelimit"),
         "aichat_subscription-funnel_upgrade-to-pro-modal_upgrade_click")
    ])
    @MainActor
    func testModalFunnelPixelNameAndParameters(pixel: AIChatPixel, expectedName: String) {
        #expect(pixel.name == expectedName)
        #expect(pixel.parameters == ["origin": "funnel_duckai_macos__freelimit"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("didReportMetric maps every allowed modal source to its funnel origin", .timeLimit(.minutes(1)), arguments: [
        ("activatesubscription", "funnel_duckai_macos__activatesubscription"),
        ("aisidebar", "funnel_duckai_macos__aisidebar"),
        ("disclaimerbanner", "funnel_duckai_macos__disclaimerbanner"),
        ("freelabel", "funnel_duckai_macos__freelabel"),
        ("freelimit", "funnel_duckai_macos__freelimit"),
        ("imagegenerationlimit", "funnel_duckai_macos__imagegenerationlimit"),
        ("modelpicker", "funnel_duckai_macos__modelpicker"),
        ("pluslimit", "funnel_duckai_macos__pluslimit"),
        ("promotioncard", "funnel_duckai_macos__promotioncard"),
        ("reasoningdropdown", "funnel_duckai_macos__reasoningdropdown"),
        ("switchmodel", "funnel_duckai_macos__switchmodel"),
        ("voicechatdurationlimit", "funnel_duckai_macos__voicechatdurationlimit"),
        ("voicechatlimit", "funnel_duckai_macos__voicechatlimit"),
        ("unknown", "funnel_duckai_macos__unknown")
    ])
    @MainActor
    func testModalMetricMapsSourceToOrigin(source: String, origin: String) async {
        pixelFiring.expectedFireCalls = [
            .init(pixel: AIChatPixel.aiChatSubscriptionFunnelSubscribeModalImpression(origin: origin), frequency: .dailyAndCount)
        ]

        await withCheckedContinuation { continuation in
            handler.didReportMetric(.init(metricName: .userDidOpenSubscribeModal, source: source)) {
                continuation.resume()
            }
        }

        #expect(pixelFiring.expectedFireCalls == pixelFiring.actualFireCalls)
    }

    @available(iOS 16, macOS 13, *)
    @Test("didReportMetric fires no modal pixel when the source is missing or unrecognised", .timeLimit(.minutes(1)), arguments: [
        nil, "", "somethingnew", "funnel_duckai_macos__freelimit"
    ] as [String?])
    @MainActor
    func testModalMetricWithoutUsableSourceFiresNothing(source: String?) async {
        await withCheckedContinuation { continuation in
            handler.didReportMetric(.init(metricName: .userDidOpenSubscribeModal, source: source)) {
                continuation.resume()
            }
        }

        #expect(pixelFiring.actualFireCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("reportMetric decodes source off the wire and fires the modal pixel", .timeLimit(.minutes(1)))
    @MainActor
    func testReportMetricDecodesModalSource() async {
        pixelFiring.expectedFireCalls = [
            .init(pixel: AIChatPixel.aiChatSubscriptionFunnelSubscribeModalImpression(origin: "funnel_duckai_macos__pluslimit"),
                  frequency: .dailyAndCount)
        ]

        _ = await handler.reportMetric(
            params: ["metricName": "userDidOpenSubscribeModal", "source": "pluslimit"],
            message: WKScriptMessage.mock()
        )

        #expect(pixelFiring.expectedFireCalls == pixelFiring.actualFireCalls)
        #expect(userScriptErrorEventMapper.events.isEmpty)
    }

    // MARK: - Sync tests

    @available(iOS 16, macOS 13, *)
    @Test("getSyncStatus returns internal error when sync status could not be obtained", .timeLimit(.minutes(1)))
    @MainActor
    func testThatGetSyncStatusReturnsInternalErrorWhenSyncServiceUnavailable() throws {
        let featureFlagger = makeFeatureFlagger(aiChatSyncEnabled: true)
        let testHandler = makeHandler(featureFlagger: featureFlagger, syncServiceProvider: { nil })

        let response = testHandler.getSyncStatus(params: [String: Any](), message: WKScriptMessage.mock())
        let errorResponse = try #require(response as? AIChatErrorResponse)
        #expect(errorResponse.reason == "internal error")
    }

    @available(iOS 16, macOS 13, *)
    @Test("getSyncStatus returns internal error when sync service is unavailable", .timeLimit(.minutes(1)))
    @MainActor
    func testThatGetSyncStatusReturnsInternalErrorWhenFeatureOffAndSyncServiceUnavailable() throws {
        let featureFlagger = makeFeatureFlagger(aiChatSyncEnabled: false)
        let testHandler = makeHandler(featureFlagger: featureFlagger, syncServiceProvider: { nil })

        let response = testHandler.getSyncStatus(params: [String: Any](), message: WKScriptMessage.mock())
        let errorResponse = try #require(response as? AIChatErrorResponse)
        #expect(errorResponse.reason == "internal error")
    }

    @available(iOS 16, macOS 13, *)
    @Test("getSyncStatus returns syncAvailable=false when feature is off and sync service is available", .timeLimit(.minutes(1)))
    @MainActor
    func testThatGetSyncStatusReturnsSyncNotAvailableWhenFeatureOffAndSyncServiceAvailable() throws {
        let featureFlagger = makeFeatureFlagger(aiChatSyncEnabled: false)
        let syncService = makeSyncService(authState: .active, account: nil)
        let testHandler = makeHandler(featureFlagger: featureFlagger, syncServiceProvider: { syncService })

        let response = testHandler.getSyncStatus(params: [String: Any](), message: WKScriptMessage.mock())
        let payloadResponse = try #require(response as? AIChatPayloadResponse)
        let status = try #require(payloadResponse.payload as? AIChatSyncHandler.SyncStatus)
        #expect(status.syncAvailable == false)
        #expect(status.userId == nil)
        #expect(status.deviceId == nil)
        #expect(status.deviceName == nil)
        #expect(status.deviceType == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("getSyncStatus returns nil ids when sync service is available but account is missing", .timeLimit(.minutes(1)))
    @MainActor
    func testThatGetSyncStatusReturnsNilIdentifiersWhenAccountMissing() throws {
        let featureFlagger = makeFeatureFlagger(aiChatSyncEnabled: true)
        let syncService = makeSyncService(authState: .active, account: nil)
        let testHandler = makeHandler(featureFlagger: featureFlagger, syncServiceProvider: { syncService })

        let response = testHandler.getSyncStatus(params: [String: Any](), message: WKScriptMessage.mock())
        let payloadResponse = try #require(response as? AIChatPayloadResponse)
        let status = try #require(payloadResponse.payload as? AIChatSyncHandler.SyncStatus)
        #expect(status.syncAvailable == true)
        #expect(status.userId == nil)
        #expect(status.deviceId == nil)
        #expect(status.deviceName == nil)
        #expect(status.deviceType == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("getSyncStatus returns ids when sync is available and account exists", .timeLimit(.minutes(1)))
    @MainActor
    func testThatGetSyncStatusReturnsAccountIdentifiersWhenAccountExists() throws {
        let featureFlagger = makeFeatureFlagger(aiChatSyncEnabled: true)
        let account = SyncAccount(deviceId: "test-device-id",
                                  deviceName: "Test Device",
                                  deviceType: "desktop",
                                  userId: "test-user-id",
                                  primaryKey: Data(),
                                  secretKey: Data(),
                                  token: nil,
                                  state: .active)
        let syncService = makeSyncService(authState: .active, account: account)
        let testHandler = makeHandler(featureFlagger: featureFlagger, syncServiceProvider: { syncService })

        let response = testHandler.getSyncStatus(params: [String: Any](), message: WKScriptMessage.mock())
        let payloadResponse = try #require(response as? AIChatPayloadResponse)
        let status = try #require(payloadResponse.payload as? AIChatSyncHandler.SyncStatus)
        #expect(status.syncAvailable == true)
        #expect(status.userId == "test-user-id")
        #expect(status.deviceId == "test-device-id")
        #expect(status.deviceName == "Test Device")
        #expect(status.deviceType == "desktop")
    }

    @available(iOS 16, macOS 13, *)
    @Test("getScopedSyncAuthToken returns sync unavailable when feature is off", .timeLimit(.minutes(1)))
    func testThatGetScopedSyncAuthTokenReturnsSyncUnavailableWhenFeatureOff() async throws {
        let featureFlagger = makeFeatureFlagger(aiChatSyncEnabled: false)
        let testHandler = await MainActor.run {
            makeHandler(featureFlagger: featureFlagger, syncServiceProvider: { nil })
        }

        let response = await testHandler.getScopedSyncAuthToken(params: [String: Any](), message: WKScriptMessage.mock())
        let errorResponse = try #require(response as? AIChatErrorResponse)
        #expect(errorResponse.reason == "sync unavailable")
    }

    @available(iOS 16, macOS 13, *)
    @Test("getScopedSyncAuthToken returns payload when token rescope succeeds", .timeLimit(.minutes(1)))
    func testThatGetScopedSyncAuthTokenReturnsPayloadWhenRescopeSucceeds() async throws {
        let featureFlagger = makeFeatureFlagger(aiChatSyncEnabled: true)
        let syncService = makeSyncService(authState: .active, account: SyncAccount(deviceId: "id",
                                                                                   deviceName: "name",
                                                                                   deviceType: "desktop",
                                                                                   userId: "user",
                                                                                   primaryKey: Data(),
                                                                                   secretKey: Data(),
                                                                                   token: nil,
                                                                                   state: .active))
        syncService.mainTokenRescopeResult = "scoped-token"

        let testHandler = await MainActor.run {
            makeHandler(featureFlagger: featureFlagger, syncServiceProvider: { syncService })
        }

        let response = await testHandler.getScopedSyncAuthToken(params: [String: Any](), message: WKScriptMessage.mock())
        let payloadResponse = try #require(response as? AIChatPayloadResponse)
        let tokenPayload = try #require(payloadResponse.payload as? AIChatSyncHandler.SyncToken)
        #expect(tokenPayload.token == "scoped-token")
        #expect(syncService.mainTokenRescopeScopes == ["ai_chats"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("getScopedSyncAuthToken returns sync off when token rescope returns unauthenticated while logged in", .timeLimit(.minutes(1)))
    func testThatGetScopedSyncAuthTokenReturnsSyncOffWhenRescopeReturnsUnauthenticatedWhileLoggedIn() async throws {
        let featureFlagger = makeFeatureFlagger(aiChatSyncEnabled: true)
        let syncService = makeSyncService(authState: .active, account: SyncAccount(deviceId: "id",
                                                                                   deviceName: "name",
                                                                                   deviceType: "desktop",
                                                                                   userId: "user",
                                                                                   primaryKey: Data(),
                                                                                   secretKey: Data(),
                                                                                   token: nil,
                                                                                   state: .active))
        syncService.mainTokenRescopeError = SyncError.unauthenticatedWhileLoggedIn

        let testHandler = await MainActor.run {
            makeHandler(featureFlagger: featureFlagger, syncServiceProvider: { syncService })
        }

        let response = await testHandler.getScopedSyncAuthToken(params: [String: Any](), message: WKScriptMessage.mock())
        let errorResponse = try #require(response as? AIChatErrorResponse)
        #expect(errorResponse.reason == "sync off")
        #expect(syncService.mainTokenRescopeScopes == ["ai_chats"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("encryptWithSyncMasterKey returns payload when sync is on and params are valid", .timeLimit(.minutes(1)))
    @MainActor
    func testThatEncryptWithSyncMasterKeyReturnsPayloadWhenSyncIsOn() throws {
        let featureFlagger = makeFeatureFlagger(aiChatSyncEnabled: true)
        let syncService = makeSyncService(authState: .active, account: SyncAccount(deviceId: "id",
                                                                                   deviceName: "name",
                                                                                   deviceType: "desktop",
                                                                                   userId: "user",
                                                                                   primaryKey: Data(),
                                                                                   secretKey: Data(),
                                                                                   token: nil,
                                                                                   state: .active))
        syncService.encryptAndBase64URLEncodeResult = ["encrypted-data"]

        let testHandler = makeHandler(featureFlagger: featureFlagger, syncServiceProvider: { syncService })

        let response = testHandler.encryptWithSyncMasterKey(params: ["data": "plain"], message: WKScriptMessage.mock())
        let payloadResponse = try #require(response as? AIChatPayloadResponse)
        let encryptedPayload = try #require(payloadResponse.payload as? AIChatSyncHandler.EncryptedData)
        #expect(encryptedPayload.encryptedData == "encrypted-data")
        #expect(syncService.encryptAndBase64URLEncodeInputs == [["plain"]])
    }

    @available(iOS 16, macOS 13, *)
    @Test("decryptWithSyncMasterKey returns payload when sync is on and params are valid", .timeLimit(.minutes(1)))
    @MainActor
    func testThatDecryptWithSyncMasterKeyReturnsPayloadWhenSyncIsOn() throws {
        let featureFlagger = makeFeatureFlagger(aiChatSyncEnabled: true)
        let syncService = makeSyncService(authState: .active, account: SyncAccount(deviceId: "id",
                                                                                   deviceName: "name",
                                                                                   deviceType: "desktop",
                                                                                   userId: "user",
                                                                                   primaryKey: Data(),
                                                                                   secretKey: Data(),
                                                                                   token: nil,
                                                                                   state: .active))
        syncService.base64URLDecodeAndDecryptResult = ["decrypted-data"]

        let testHandler = makeHandler(featureFlagger: featureFlagger, syncServiceProvider: { syncService })

        let response = testHandler.decryptWithSyncMasterKey(params: ["data": "cipher"], message: WKScriptMessage.mock())
        let payloadResponse = try #require(response as? AIChatPayloadResponse)
        let decryptedPayload = try #require(payloadResponse.payload as? AIChatSyncHandler.DecryptedData)
        #expect(decryptedPayload.decryptedData == "decrypted-data")
        #expect(syncService.base64URLDecodeAndDecryptInputs == [["cipher"]])
    }

    @available(iOS 16, macOS 13, *)
    @Test("sendToSyncSettings returns ok and opens sync settings pane", .timeLimit(.minutes(1)))
    @MainActor
    func testThatSendToSyncSettingsShowsSyncSettingsPane() async throws {
        let response = handler.sendToSyncSettings(params: [String: Any](), message: WKScriptMessage.mock())
        let okResponse = try #require(response as? AIChatOKResponse)
        #expect(okResponse.ok)

        // Allow the Task { @MainActor } to run.
        await Task.yield()
        #expect(windowControllersManager.showTabCalls.contains(.settings(pane: .sync)))
    }

    @available(iOS 16, macOS 13, *)
    @Test("sendToSetupSync returns setup disabled when feature is off", .timeLimit(.minutes(1)))
    @MainActor
    func testThatSendToSetupSyncReturnsSetupDisabledWhenFeatureOff() throws {
        let featureFlagger = makeFeatureFlagger(aiChatSyncEnabled: false)
        let testHandler = makeHandler(featureFlagger: featureFlagger, syncServiceProvider: { nil })

        let response = testHandler.sendToSetupSync(params: [String: Any](), message: WKScriptMessage.mock())
        let errorResponse = try #require(response as? AIChatErrorResponse)
        #expect(errorResponse.reason == "setup disabled")
    }

    @available(iOS 16, macOS 13, *)
    @Test("sendToSetupSync returns setup disabled when sync service is unavailable", .timeLimit(.minutes(1)))
    @MainActor
    func testThatSendToSetupSyncReturnsSetupDisabledWhenSyncServiceUnavailable() throws {
        let featureFlagger = makeFeatureFlagger(aiChatSyncEnabled: true)
        let testHandler = makeHandler(featureFlagger: featureFlagger, syncServiceProvider: { nil })

        let response = testHandler.sendToSetupSync(params: [String: Any](), message: WKScriptMessage.mock())
        let errorResponse = try #require(response as? AIChatErrorResponse)
        #expect(errorResponse.reason == "setup disabled")
    }

    @available(iOS 16, macOS 13, *)
    @Test("sendToSetupSync does not fire sync promo confirmed pixel when sync is already on", .timeLimit(.minutes(1)))
    @MainActor
    func testThatSendToSetupSyncDoesNotFireSyncPromoConfirmedWhenSyncAlreadyOn() throws {
        let featureFlagger = makeFeatureFlagger(aiChatSyncEnabled: true)
        let syncService = makeSyncService(authState: .active, account: SyncAccount(deviceId: "id",
                                                                                   deviceName: "name",
                                                                                   deviceType: "desktop",
                                                                                   userId: "user",
                                                                                   primaryKey: Data(),
                                                                                   secretKey: Data(),
                                                                                   token: nil,
                                                                                   state: .active))
        let testHandler = makeHandler(featureFlagger: featureFlagger, syncServiceProvider: { syncService })

        let response = testHandler.sendToSetupSync(params: [String: Any](), message: WKScriptMessage.mock())

        let errorResponse = try #require(response as? AIChatErrorResponse)
        #expect(errorResponse.reason == "sync already on")
        #expect(!pixelFiring.actualFireCalls.contains { $0.pixel.name == SyncPromoPixelKitEvent.syncPromoConfirmed.name })
    }

    @available(iOS 16, macOS 13, *)
    @Test("setAIChatHistoryEnabled is notify-only and best-effort persists even when account is missing", .timeLimit(.minutes(1)))
    @MainActor
    func testThatSetAIChatHistoryEnabledBestEffortPersistsWhenAccountIsMissing() throws {
        let featureFlagger = makeFeatureFlagger(aiChatSyncEnabled: true)
        let syncService = makeSyncService(authState: .active, account: nil)
        let testHandler = makeHandler(featureFlagger: featureFlagger, syncServiceProvider: { syncService })

        let response = testHandler.setAIChatHistoryEnabled(params: ["enabled": true], message: WKScriptMessage.mock())
        #expect(response == nil)
        #expect(syncService.setAIChatHistoryEnabledCalls == [true])
    }

    @available(iOS 16, macOS 13, *)
    @Test("setAIChatHistoryEnabled calls sync service when sync is on", .timeLimit(.minutes(1)))
    @MainActor
    func testThatSetAIChatHistoryEnabledCallsSyncServiceWhenSyncIsOn() throws {
        let featureFlagger = makeFeatureFlagger(aiChatSyncEnabled: true)
        let syncService = makeSyncService(authState: .active, account: SyncAccount(deviceId: "id",
                                                                                   deviceName: "name",
                                                                                   deviceType: "desktop",
                                                                                   userId: "user",
                                                                                   primaryKey: Data(),
                                                                                   secretKey: Data(),
                                                                                   token: nil,
                                                                                   state: .active))
        let testHandler = makeHandler(featureFlagger: featureFlagger, syncServiceProvider: { syncService })

        let response = testHandler.setAIChatHistoryEnabled(params: ["enabled": true], message: WKScriptMessage.mock())
        #expect(response == nil)
        #expect(syncService.setAIChatHistoryEnabledCalls == [true])
        #expect(syncService.isAIChatHistoryEnabled)
    }

    @available(iOS 16, macOS 13, *)
    @Test("setAIChatHistoryEnabled is notify-only and best-effort persists when feature is off", .timeLimit(.minutes(1)))
    @MainActor
    func testThatSetAIChatHistoryEnabledBestEffortPersistsWhenFeatureOff() throws {
        let featureFlagger = makeFeatureFlagger(aiChatSyncEnabled: false)
        let syncService = makeSyncService(authState: .active, account: nil)
        let testHandler = makeHandler(featureFlagger: featureFlagger, syncServiceProvider: { syncService })

        let response = testHandler.setAIChatHistoryEnabled(params: ["enabled": true], message: WKScriptMessage.mock())
        #expect(response == nil)
        #expect(syncService.setAIChatHistoryEnabledCalls == [true])
    }

    // MARK: - Sync helpers

    private func makeFeatureFlagger(aiChatSyncEnabled: Bool = false,
                                    aiChatNativeStorageEnabled: Bool = false,
                                    aiChatNativeVoicePermissionFlowEnabled: Bool = false,
                                    aiChatTabAttachmentLimitEnabled: Bool = false) -> MockFeatureFlagger {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub["aiChatSync"] = aiChatSyncEnabled
        featureFlagger.featuresStub["aiChatNativeStorage"] = aiChatNativeStorageEnabled
        featureFlagger.featuresStub["aiChatNativeVoicePermissionFlow"] = aiChatNativeVoicePermissionFlowEnabled
        featureFlagger.featuresStub["aiChatTabAttachmentLimit"] = aiChatTabAttachmentLimitEnabled
        return featureFlagger
    }

    private func makeSyncService(authState: SyncAuthState = .active,
                                 account: SyncAccount? = nil) -> MockDDGSyncing {
        MockDDGSyncing(authState: authState, account: account, isSyncInProgress: false)
    }

    @MainActor
    private func makeHandler(featureFlagger: FeatureFlagger,
                             syncServiceProvider: @escaping () -> DDGSyncing?) -> AIChatUserScriptHandler {
        AIChatUserScriptHandler(
            storage: storage,
            messageHandling: messageHandler,
            windowControllersManager: windowControllersManager,
            pixelFiring: pixelFiring,
            statisticsLoader: statisticsLoader,
            syncServiceProvider: syncServiceProvider,
            syncErrorHandler: syncErrorHandler,
            featureFlagger: featureFlagger,
            freeTrialConversionService: mockFreeTrialConversionService,
            notificationCenter: notificationCenter,
            featureDiscovery: featureDiscovery
        )
    }

    /// For tests that stage the mailbox mid-flight, so they hold it and the pixel mock themselves.
    @MainActor
    private func makeHandler(sourceHandler: AIChatConversationSourceHandler,
                             pixelFiring: PixelKitMock,
                             featureDiscovery: FeatureDiscovery? = nil) -> AIChatUserScriptHandler {
        AIChatUserScriptHandler(
            storage: storage,
            messageHandling: messageHandler,
            windowControllersManager: windowControllersManager,
            pixelFiring: pixelFiring,
            statisticsLoader: statisticsLoader,
            syncServiceProvider: { nil },
            syncErrorHandler: syncErrorHandler,
            featureFlagger: MockFeatureFlagger(),
            notificationCenter: notificationCenter,
            conversationSourceHandler: sourceHandler,
            featureDiscovery: featureDiscovery ?? self.featureDiscovery
        )
    }

    /// Module-qualified because this test target has its own unrelated `MockWKWebView`. Bind the
    /// result to a local — `WKScriptMessage.mock` holds the web view weakly.
    private func mockWebView(url: String) -> WKWebView {
        SubscriptionTestingUtilities.MockWKWebView(url: URL(string: url)!)
    }

    // MARK: - Free Trial Conversion Tracking

    @available(iOS 16, macOS 13, *)
    @Test("When plus model tier prompt submitted, markDuckAIActivated is called", .timeLimit(.minutes(1)))
    @MainActor
    func testWhenPlusModelTierPromptSubmittedThenMarkDuckAIActivatedIsCalled() async {
        await handler.reportMetric(params: ["metricName": "userDidSubmitPrompt", "modelTier": "plus"], message: WKScriptMessage.mock())

        #expect(mockFreeTrialConversionService.markDuckAIActivatedCalled)
    }

    @available(iOS 16, macOS 13, *)
    @Test("When plus model tier first prompt submitted, markDuckAIActivated is called", .timeLimit(.minutes(1)))
    @MainActor
    func testWhenPlusModelTierFirstPromptSubmittedThenMarkDuckAIActivatedIsCalled() async {
        await handler.reportMetric(params: ["metricName": "userDidSubmitFirstPrompt", "modelTier": "plus"], message: WKScriptMessage.mock())

        #expect(mockFreeTrialConversionService.markDuckAIActivatedCalled)
    }

    @available(iOS 16, macOS 13, *)
    @Test("When free model tier prompt submitted, markDuckAIActivated is not called", .timeLimit(.minutes(1)))
    @MainActor
    func testWhenFreeModelTierPromptSubmittedThenMarkDuckAIActivatedIsNotCalled() async {
        await handler.reportMetric(params: ["metricName": "userDidSubmitPrompt", "modelTier": "free"], message: WKScriptMessage.mock())

        #expect(!mockFreeTrialConversionService.markDuckAIActivatedCalled)
    }

    @available(iOS 16, macOS 13, *)
    @Test("When no model tier prompt submitted, markDuckAIActivated is not called", .timeLimit(.minutes(1)))
    @MainActor
    func testWhenNoModelTierPromptSubmittedThenMarkDuckAIActivatedIsNotCalled() async {
        await handler.reportMetric(params: ["metricName": "userDidSubmitPrompt"], message: WKScriptMessage.mock())

        #expect(!mockFreeTrialConversionService.markDuckAIActivatedCalled)
    }

    @available(iOS 16, macOS 13, *)
    @Test("When reportMetric cannot decode payload, user-script error event is fired", .timeLimit(.minutes(1)))
    @MainActor
    func testWhenReportMetricDecodeFailsThenUserScriptErrorEventIsFired() async {
        _ = await handler.reportMetric(params: "not-a-dictionary", message: WKScriptMessage.mock())

        guard case .reportMetricDecodingFailed(let error, let failureReason) = userScriptErrorEventMapper.events.first else {
            Issue.record("Expected reportMetricDecodingFailed event")
            return
        }
        #expect(error == nil)
        #expect(failureReason == .typeMismatch)
    }

    @available(iOS 16, macOS 13, *)
    @Test("AIChatUserScriptErrorEventMapper maps reportMetric decode failures to pixels", .timeLimit(.minutes(1)))
    @MainActor
    func testUserScriptErrorEventMapperMapsReportMetricDecodeFailureToPixel() {
        let error = DecodingError.typeMismatch(
            AIChatMetricName.self,
            DecodingError.Context(codingPath: [], debugDescription: "Expected metric name")
        )
        let nsError = error as NSError
        let mapper = AIChatUserScriptErrorEventMapper(pixelFiring: pixelFiring)

        mapper.fire(.reportMetricDecodingFailed(error: error, failureReason: .typeMismatch))

        #expect(pixelFiring.actualFireCalls.count == 1)
        #expect(pixelFiring.actualFireCalls.first?.pixel.name == AIChatPixel.aiChatReportMetricDecodeError(
            nsError,
            failureReason: .typeMismatch
        ).name)
        #expect(pixelFiring.actualFireCalls.first?.frequency == .dailyAndCount)
        #expect(pixelFiring.actualFireCalls.first?.pixel.error == nsError)
        #expect(pixelFiring.actualFireCalls.first?.pixel.parameters == ["failureReason": "type_mismatch"])
    }

    // MARK: - AIChatMessageHandler config values

    @available(iOS 16, macOS 13, *)
    @Test("When aiChatSync is enabled and not a fire window, supportsAIChatSync is true", .timeLimit(.minutes(1)))
    func testWhenAIChatSyncEnabledAndNotFireWindowThenSupportsAIChatSyncIsTrue() {
        let featureFlagger = makeFeatureFlagger(aiChatSyncEnabled: true)
        let handler = AIChatMessageHandler(featureFlagger: featureFlagger,
                                           promptHandler: AIChatPromptHandler.shared,
                                           installDateProvider: { nil },
                                           installTypeProvider: { .new })

        let config = handler.getNativeConfigValues(isFireWindow: false)

        #expect(config.supportsAIChatSync == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("When aiChatSync is enabled and is a fire window, supportsAIChatSync is false", .timeLimit(.minutes(1)))
    func testWhenAIChatSyncEnabledAndFireWindowThenSupportsAIChatSyncIsFalse() {
        let featureFlagger = makeFeatureFlagger(aiChatSyncEnabled: true)
        let handler = AIChatMessageHandler(featureFlagger: featureFlagger,
                                           promptHandler: AIChatPromptHandler.shared,
                                           installDateProvider: { nil },
                                           installTypeProvider: { .new })

        let config = handler.getNativeConfigValues(isFireWindow: true)

        #expect(config.supportsAIChatSync == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("When aiChatSync is disabled, supportsAIChatSync is false regardless of fire window", .timeLimit(.minutes(1)))
    func testWhenAIChatSyncDisabledThenSupportsAIChatSyncIsFalse() {
        let featureFlagger = makeFeatureFlagger(aiChatSyncEnabled: false)
        let handler = AIChatMessageHandler(featureFlagger: featureFlagger,
                                           promptHandler: AIChatPromptHandler.shared,
                                           installDateProvider: { nil },
                                           installTypeProvider: { .new })

        #expect(handler.getNativeConfigValues(isFireWindow: false).supportsAIChatSync == false)
        #expect(handler.getNativeConfigValues(isFireWindow: true).supportsAIChatSync == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("When aiChatNativeStorage is enabled and bridge is available, supportsNativeStorage is true", .timeLimit(.minutes(1)))
    func testWhenAIChatNativeStorageEnabledAndBridgeAvailableThenSupportsNativeStorageIsTrue() {
        let featureFlagger = makeFeatureFlagger(aiChatNativeStorageEnabled: true)
        let handler = AIChatMessageHandler(featureFlagger: featureFlagger,
                                           promptHandler: AIChatPromptHandler.shared,
                                           isNativeStorageBridgeAvailable: true,
                                           installDateProvider: { nil },
                                           installTypeProvider: { .new })

        #expect(handler.getNativeConfigValues(isFireWindow: false).supportsNativeStorage == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("When aiChatNativeStorage is enabled and bridge is available in a fire window, supportsNativeStorage is true", .timeLimit(.minutes(1)))
    func testWhenAIChatNativeStorageEnabledAndBridgeAvailableInFireWindowThenSupportsNativeStorageIsTrue() {
        let featureFlagger = makeFeatureFlagger(aiChatNativeStorageEnabled: true)
        let handler = AIChatMessageHandler(featureFlagger: featureFlagger,
                                           promptHandler: AIChatPromptHandler.shared,
                                           isNativeStorageBridgeAvailable: true,
                                           installDateProvider: { nil },
                                           installTypeProvider: { .new })

        #expect(handler.getNativeConfigValues(isFireWindow: true).supportsNativeStorage == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("When aiChatNativeStorage is enabled but bridge is unavailable, supportsNativeStorage is false", .timeLimit(.minutes(1)))
    func testWhenAIChatNativeStorageEnabledAndBridgeUnavailableThenSupportsNativeStorageIsFalse() {
        let featureFlagger = makeFeatureFlagger(aiChatNativeStorageEnabled: true)
        let handler = AIChatMessageHandler(featureFlagger: featureFlagger,
                                           promptHandler: AIChatPromptHandler.shared,
                                           installDateProvider: { nil },
                                           installTypeProvider: { .new })

        #expect(handler.getNativeConfigValues(isFireWindow: false).supportsNativeStorage == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("When aiChatNativeStorage is disabled but bridge is available, supportsNativeStorage is false", .timeLimit(.minutes(1)))
    func testWhenAIChatNativeStorageDisabledAndBridgeAvailableThenSupportsNativeStorageIsFalse() {
        let featureFlagger = makeFeatureFlagger(aiChatNativeStorageEnabled: false)
        let handler = AIChatMessageHandler(featureFlagger: featureFlagger,
                                           promptHandler: AIChatPromptHandler.shared,
                                           isNativeStorageBridgeAvailable: true,
                                           installDateProvider: { nil },
                                           installTypeProvider: { .new })

        #expect(handler.getNativeConfigValues(isFireWindow: false).supportsNativeStorage == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("When aiChatNativeVoicePermissionFlow is enabled, supportsNativeVoicePermissionHandler is true", .timeLimit(.minutes(1)))
    func testWhenAIChatNativeVoicePermissionFlowEnabledThenSupportsNativeVoicePermissionHandlerIsTrue() {
        let featureFlagger = makeFeatureFlagger(aiChatNativeVoicePermissionFlowEnabled: true)
        let handler = AIChatMessageHandler(featureFlagger: featureFlagger,
                                           promptHandler: AIChatPromptHandler.shared,
                                           installDateProvider: { nil },
                                           installTypeProvider: { .new })

        #expect(handler.getNativeConfigValues(isFireWindow: false).supportsNativeVoicePermissionHandler == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("When aiChatNativeVoicePermissionFlow is disabled, supportsNativeVoicePermissionHandler is false", .timeLimit(.minutes(1)))
    func testWhenAIChatNativeVoicePermissionFlowDisabledThenSupportsNativeVoicePermissionHandlerIsFalse() {
        let featureFlagger = makeFeatureFlagger(aiChatNativeVoicePermissionFlowEnabled: false)
        let handler = AIChatMessageHandler(featureFlagger: featureFlagger,
                                           promptHandler: AIChatPromptHandler.shared,
                                           installDateProvider: { nil },
                                           installTypeProvider: { .new })

        #expect(handler.getNativeConfigValues(isFireWindow: false).supportsNativeVoicePermissionHandler == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("When aiChatTabAttachmentLimit is enabled, attachmentLimits.tabs carries the native cap", .timeLimit(.minutes(1)))
    func testWhenTabAttachmentLimitEnabledThenAttachmentLimitsCarriesTabCap() {
        let featureFlagger = makeFeatureFlagger(aiChatTabAttachmentLimitEnabled: true)
        let handler = AIChatMessageHandler(featureFlagger: featureFlagger,
                                           promptHandler: AIChatPromptHandler.shared,
                                           installDateProvider: { nil },
                                           installTypeProvider: { .new })

        let config = handler.getNativeConfigValues(isFireWindow: false)

        #expect(config.attachmentLimits?.tabs?.maxAttached == AIChatOmnibarController.maxTabAttachments)
    }

    @available(iOS 16, macOS 13, *)
    @Test("When aiChatTabAttachmentLimit is disabled, attachmentLimits is omitted", .timeLimit(.minutes(1)))
    func testWhenTabAttachmentLimitDisabledThenAttachmentLimitsIsNil() {
        let featureFlagger = makeFeatureFlagger(aiChatTabAttachmentLimitEnabled: false)
        let handler = AIChatMessageHandler(featureFlagger: featureFlagger,
                                           promptHandler: AIChatPromptHandler.shared,
                                           installDateProvider: { nil },
                                           installTypeProvider: { .new })

        #expect(handler.getNativeConfigValues(isFireWindow: false).attachmentLimits == nil)
    }

    // MARK: - voiceChatStartFailed flag gating

    @available(iOS 16, macOS 13, *)
    @MainActor
    @Test("voiceChatStartFailed dispatches to the failure handler when flag is enabled", .timeLimit(.minutes(1)))
    func testVoiceChatStartFailedDispatchesWhenFlagEnabled() async {
        let failureHandler = MockDuckAiVoiceChatFailureHandling()
        let featureFlagger = makeFeatureFlagger(aiChatNativeVoicePermissionFlowEnabled: true)
        let handler = AIChatUserScriptHandler(
            storage: storage,
            messageHandling: messageHandler,
            windowControllersManager: windowControllersManager,
            pixelFiring: pixelFiring,
            statisticsLoader: statisticsLoader,
            syncServiceProvider: { nil },
            syncErrorHandler: syncErrorHandler,
            featureFlagger: featureFlagger,
            freeTrialConversionService: mockFreeTrialConversionService,
            notificationCenter: notificationCenter,
            voiceChatFailureHandler: failureHandler,
            featureDiscovery: featureDiscovery
        )

        _ = await handler.voiceChatStartFailed(
            params: ["reason": "NotAllowedError"],
            message: WKScriptMessage.mock()
        )

        #expect(failureHandler.handleCalls.count == 1)
        #expect(failureHandler.handleCalls.first?.reason == "NotAllowedError")
    }

    @available(iOS 16, macOS 13, *)
    @MainActor
    @Test("voiceChatStartFailed is a no-op when flag is disabled", .timeLimit(.minutes(1)))
    func testVoiceChatStartFailedNoOpWhenFlagDisabled() async {
        let failureHandler = MockDuckAiVoiceChatFailureHandling()
        let featureFlagger = makeFeatureFlagger(aiChatNativeVoicePermissionFlowEnabled: false)
        let handler = AIChatUserScriptHandler(
            storage: storage,
            messageHandling: messageHandler,
            windowControllersManager: windowControllersManager,
            pixelFiring: pixelFiring,
            statisticsLoader: statisticsLoader,
            syncServiceProvider: { nil },
            syncErrorHandler: syncErrorHandler,
            featureFlagger: featureFlagger,
            freeTrialConversionService: mockFreeTrialConversionService,
            notificationCenter: notificationCenter,
            voiceChatFailureHandler: failureHandler,
            featureDiscovery: featureDiscovery
        )

        _ = await handler.voiceChatStartFailed(
            params: ["reason": "NotAllowedError"],
            message: WKScriptMessage.mock()
        )

        #expect(failureHandler.handleCalls.isEmpty)
    }
}

// MARK: - Mock failure handler

final class MockDuckAiVoiceChatFailureHandling: DuckAiVoiceChatFailureHandling {
    struct HandleCall {
        let reason: String
        let sourceWebView: WKWebView?
    }
    private(set) var handleCalls: [HandleCall] = []
    private(set) var dictationHandleCalls: [HandleCall] = []

    @MainActor
    func handleVoiceChatStartFailed(reason: String, sourceWebView: WKWebView?) {
        handleCalls.append(HandleCall(reason: reason, sourceWebView: sourceWebView))
    }

    @MainActor
    func handleDictationStartFailed(reason: String, sourceWebView: WKWebView?) {
        dictationHandleCalls.append(HandleCall(reason: reason, sourceWebView: sourceWebView))
    }
}

private final class CapturingAIChatUserScriptErrorEventMapper: EventMapping<AIChatUserScriptErrorEvent> {

    private(set) var events: [AIChatUserScriptErrorEvent] = []

    init() {
        super.init { _, _, _, _ in }
        eventMapper = { [weak self] event, _, _, _ in
            self?.events.append(event)
        }
    }
}
// swiftlint:enable inclusive_language

/// Covers the install-type / install-age values that `AIChatMessageHandler` adds to the
/// native config for the `web.conversion.duckai.prompt` pixel. The providers are injected so
/// the test doesn't depend on the real ATB store or build channel.
struct AIChatMessageHandlerInstallInfoTests {

    private func makeHandler(installDate: Date?, installType: AIChatInstallType) -> AIChatMessageHandler {
        AIChatMessageHandler(
            featureFlagger: MockFeatureFlagger(),
            installDateProvider: { installDate },
            installTypeProvider: { installType }
        )
    }

    @available(iOS 16, macOS 13, *)
    @Test("installType is propagated to the native config", .timeLimit(.minutes(1)))
    func testInstallTypeIsPropagated() {
        for type in [AIChatInstallType.new, .returning, .unknown] {
            let config = makeHandler(installDate: nil, installType: type).getNativeConfigValues(isFireWindow: false)
            #expect(config.installType == type)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("installAge is bucketed from the install date", .timeLimit(.minutes(1)))
    func testInstallAgeIsBucketed() {
        let twentyFourDaysAgo = Calendar.current.date(byAdding: .day, value: -24, to: Date())
        let config = makeHandler(installDate: twentyFourDaysAgo, installType: .new).getNativeConfigValues(isFireWindow: false)
        #expect(config.installAge == 4) // 22–28 -> bucket 4
    }

    @available(iOS 16, macOS 13, *)
    @Test("nil install date buckets to same-day (0)", .timeLimit(.minutes(1)))
    func testNilInstallDateBucketsToZero() {
        let config = makeHandler(installDate: nil, installType: .new).getNativeConfigValues(isFireWindow: false)
        #expect(config.installAge == 0)
    }
}

struct AIChatConversationSourcePixelTests {

    /// Pinned so a new case can't ship without the matching `aiChatConversationSource` value in
    /// `params_dictionary.json5` — the app would send a value the definition rejects.
    private static let expectedRawValues = [
        "tab-bar-button",
        "ask-about-page",
        "tab-bar-sidebar",
        "tab-bar-chats",
        "address-bar",
        "address-bar-suggestion",
        "address-bar-context-menu",
        "new-tab-page",
        "new-tab-page-view-all-chats",
        "new-tab-page-voice",
        "new-tab-page-recent-chat",
        "omnibar",
        "omnibar-view-all-chats",
        "omnibar-voice",
        "omnibar-recent-chat",
        "prompt-bar",
        "prompt-bar-voice",
        "main-menu-file-new-chat",
        "main-menu-sidebar",
        "main-menu-ask-about-page",
        "main-menu-open-duck-ai",
        "main-menu-new-chat",
        "main-menu-view-all-chats",
        "main-menu-voice",
        "main-menu-image",
        "main-menu-recent-chat",
        "more-options-menu-new-duck-ai-chat",
        "more-options-menu-open-duck-ai",
        "more-options-menu-new-chat",
        "more-options-menu-view-all-chats",
        "more-options-menu-voice",
        "more-options-menu-image",
        "more-options-menu-recent-chat",
        "contextual-summarize",
        "contextual-translate",
        "contextual-attach-selection",
        "serp",
        "sidebar-handoff",
        "settings",
        "direct-typed",
        "direct-suggestion",
        "direct-bookmark",
        "direct-favorite",
        "direct-history",
        "direct-external",
        "direct-link",
        "duckduckgo-homepage",
        "unattributed"
    ]

    @available(iOS 16, macOS 13, *)
    @Test("Conversation source raw values match the pixel definition", .timeLimit(.minutes(1)))
    func testConversationSourceRawValuesMatchPixelDefinition() {
        #expect(AIChatConversationSource.allCases.map(\.rawValue) == Self.expectedRawValues)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Every source is reported verbatim by both conversation pixels", .timeLimit(.minutes(1)),
          arguments: AIChatConversationSource.allCases)
    func testEverySourceIsReportedVerbatim(source: AIChatConversationSource) {
        #expect(AIChatPixel.aiChatMetricStartNewConversation(source: source, hasPageContext: false, surface: .duckAI, firstPromptNewInstall: false)
            .parameters?["source"] == source.rawValue)
        #expect(AIChatPixel.aiChatMetricSentPromptOngoingChat(source: source, hasPageContext: false, surface: .duckAI, firstPromptNewInstall: false)
            .parameters?["source"] == source.rawValue)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A button surface with page context reports every parameter", .timeLimit(.minutes(1)))
    func testButtonSourceWithPageContextParameters() {
        #expect(AIChatPixel.aiChatMetricStartNewConversation(source: .askAboutPage, hasPageContext: true, surface: .duckAI, firstPromptNewInstall: false).parameters == [
            "source": "ask-about-page",
            "isOpenedFromAskDuckAiButton": "true",
            "hasPageContext": "true",
            "surface": "duck_ai"
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Each Duck.ai menu item maps to a source scoped to its own menu", .timeLimit(.minutes(1)), arguments: [
        (AIChatMenuConversationSources.mainMenu, "main-menu"),
        (AIChatMenuConversationSources.moreOptionsMenu, "more-options-menu")
    ])
    func testMenuSourcesAreScopedToTheirMenu(sources: AIChatMenuConversationSources, prefix: String) {
        #expect(sources.openDuckAI.rawValue == "\(prefix)-open-duck-ai")
        #expect(sources.newChat.rawValue == "\(prefix)-new-chat")
        #expect(sources.viewAllChats.rawValue == "\(prefix)-view-all-chats")
        #expect(sources.voice.rawValue == "\(prefix)-voice")
        #expect(sources.image.rawValue == "\(prefix)-image")
        #expect(sources.recentChat.rawValue == "\(prefix)-recent-chat")
    }

    @available(iOS 16, macOS 13, *)
    @Test("The shared new-chat menu items resolve to distinct sources", .timeLimit(.minutes(1)))
    func testSharedNewChatItemsAreDistinct() {
        let sources = AIChatMenuConversationSources.mainMenu
        let resolved = [AIChatMenuNewChatItem.openDuckAI, .newChat, .viewAllChats]
            .map { sources.source(for: $0).rawValue }
        #expect(resolved == ["main-menu-open-duck-ai", "main-menu-new-chat", "main-menu-view-all-chats"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Tab-bar New Chat and Chats use distinct sources", .timeLimit(.minutes(1)))
    func testTabBarNewChatAndChatsAreDistinct() {
        #expect(AIChatConversationSource.tabBarButton.rawValue == "tab-bar-button")
        #expect(AIChatConversationSource.tabBarChats.rawValue == "tab-bar-chats")
        #expect(AIChatConversationSource.tabBarButton != .tabBarChats)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The no-stamp fallback reports 'unattributed'", .timeLimit(.minutes(1)))
    func testFallbackIsNamedUnattributed() {
        #expect(AIChatConversationSource.unattributed.rawValue == "unattributed")
        #expect(!AIChatConversationSource.unattributed.isAskDuckAiButton)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The address-bar button and its suggestion row report different sources", .timeLimit(.minutes(1)))
    func testAddressBarButtonAndSuggestionAreDistinct() {
        #expect(AIChatConversationSource.addressBar.rawValue == "address-bar")
        #expect(AIChatConversationSource.addressBarSuggestion.rawValue == "address-bar-suggestion")
    }

    @available(iOS 16, macOS 13, *)
    @Test("An unattributed chat reports every parameter", .timeLimit(.minutes(1)))
    func testUnattributedSourceParameters() {
        #expect(AIChatPixel.aiChatMetricSentPromptOngoingChat(source: .unattributed, hasPageContext: false, surface: .duckAI, firstPromptNewInstall: false).parameters == [
            "source": "unattributed",
            "isOpenedFromAskDuckAiButton": "false",
            "hasPageContext": "false",
            "surface": "duck_ai"
        ])
    }
}

struct DuckAIFirstPromptNewInstallCohortTests {

    private let statisticsStore = MockStatisticsStore()
    private let featureDiscovery = MockFeatureDiscovery()
    private let marker = InMemoryKeyValueStore()

    private func assignCohort() {
        DuckAIFirstPromptNewInstallCohort.assignIfNeeded(statisticsStore: statisticsStore,
                                                         featureDiscovery: featureDiscovery,
                                                         marker: marker)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An install with statistics is marked as having prompted, so it never reports the flag", .timeLimit(.minutes(1)))
    func testThatAnExistingInstallIsMarked() {
        statisticsStore.atb = "v123-1"

        assignCohort()

        #expect(featureDiscovery.wasSetWasUsedBeforeCalled(for: .duckAIPrompt))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A new install is left unmarked", .timeLimit(.minutes(1)))
    func testThatANewInstallIsLeftUnmarked() {
        assignCohort()

        #expect(featureDiscovery.setWasUsedBeforeCallCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A new install's later launch is not marked once it has statistics", .timeLimit(.minutes(1)))
    func testThatTheMarkerStopsALaterLaunchFromMarking() {
        assignCohort()
        statisticsStore.atb = "v123-1"

        assignCohort()

        #expect(featureDiscovery.setWasUsedBeforeCallCount == 0)
    }
}
