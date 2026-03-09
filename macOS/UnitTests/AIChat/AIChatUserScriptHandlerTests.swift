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
import BrowserServicesKitTestsUtils
import Combine
import Common
@testable import DDGSync
import PixelKitTestingUtilities
import PrivacyConfig
import SharedTestUtilities
import Subscription
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
}

// swiftlint:disable inclusive_language
struct AIChatUserScriptHandlerTests {
    private var storage = MockAIChatPreferencesStorage()
    private var messageHandler = MockAIChatMessageHandler()
    private var windowControllersManager: WindowControllersManagerMock
    private var notificationCenter = NotificationCenter()
    private var pixelFiring = PixelKitMock()
    private var syncErrorHandler = SyncErrorHandler(alertPresenter: CapturingAlertPresenter())
    private var handler: AIChatUserScriptHandler
    private var statisticsLoader = StatisticsLoader(statisticsStore: MockStatisticsStore())
    private var mockFreeTrialConversionService = MockFreeTrialConversionInstrumentationService()

    @MainActor
    init() {
        windowControllersManager = WindowControllersManagerMock()

        handler = AIChatUserScriptHandler(
            storage: storage,
            messageHandling: messageHandler,
            windowControllersManager: windowControllersManager,
            pixelFiring: pixelFiring,
            statisticsLoader: statisticsLoader,
            syncServiceProvider: { nil },
            syncErrorHandler: syncErrorHandler,
            featureFlagger: MockFeatureFlagger(),
            freeTrialConversionService: mockFreeTrialConversionService,
            notificationCenter: notificationCenter
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
    @Test("getAIChatNativePrompt calls messageHandler", .timeLimit(.minutes(1)))
    func testThatGetAIChatNativePromptCallsMessageHandler() async {
        _ = await handler.getAIChatNativePrompt(params: [], message: WKScriptMessage.mock())
        #expect(messageHandler.getDataForMessageTypeCalls == [.nativePrompt])
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

    @available(iOS 16, macOS 13, *)
    @Test("didReportMetric refreshes ATBs only for prompt submission metrics", .timeLimit(.minutes(1)))
    func testThatUserDidSubmitPromptRefreshesATBs() async throws {
        let promptMetrics: [AIChatMetricName] = [
            .userDidSubmitPrompt,
            .userDidSubmitFirstPrompt
        ]

        for metric in promptMetrics {
            let statisticsStore = MockStatisticsStore()
            let loader = StatisticsLoader(statisticsStore: statisticsStore)
            let testHandler = AIChatUserScriptHandler(
                storage: storage,
                messageHandling: messageHandler,
                windowControllersManager: windowControllersManager,
                pixelFiring: pixelFiring,
                statisticsLoader: loader,
                syncServiceProvider: { nil },
                syncErrorHandler: syncErrorHandler,
                featureFlagger: MockFeatureFlagger(),
                notificationCenter: notificationCenter
            )

            await withCheckedContinuation { continuation in
                testHandler.didReportMetric(.init(metricName: metric)) {
                    #expect(statisticsStore.searchRetentionRefreshed)
                    #expect(statisticsStore.duckAIRetentionRefreshed)
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
            let statisticsStore = MockStatisticsStore()
            let loader = StatisticsLoader(statisticsStore: statisticsStore)
            let testHandler = AIChatUserScriptHandler(
                storage: storage,
                messageHandling: messageHandler,
                windowControllersManager: windowControllersManager,
                pixelFiring: pixelFiring,
                statisticsLoader: loader,
                syncServiceProvider: { nil },
                syncErrorHandler: syncErrorHandler,
                featureFlagger: MockFeatureFlagger(),
                notificationCenter: notificationCenter
            )

            await withCheckedContinuation { continuation in
                testHandler.didReportMetric(.init(metricName: metric)) {
                    #expect(!statisticsStore.searchRetentionRefreshed)
                    #expect(!statisticsStore.duckAIRetentionRefreshed)
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
        testPixelFiring.expectedFireCalls = [.init(pixel: AIChatPixel.aiChatMetricStartNewConversation, frequency: .standard)]

        let testHandler = AIChatUserScriptHandler(
            storage: storage,
            messageHandling: messageHandler,
            windowControllersManager: windowControllersManager,
            pixelFiring: testPixelFiring,
            statisticsLoader: statisticsLoader,
            syncServiceProvider: { nil },
            syncErrorHandler: syncErrorHandler,
            featureFlagger: MockFeatureFlagger(),
            notificationCenter: notificationCenter
        )

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
        testPixelFiring.expectedFireCalls = [.init(pixel: AIChatPixel.aiChatMetricSentPromptOngoingChat, frequency: .standard)]

        let testHandler = AIChatUserScriptHandler(
            storage: storage,
            messageHandling: messageHandler,
            windowControllersManager: windowControllersManager,
            pixelFiring: testPixelFiring,
            statisticsLoader: statisticsLoader,
            syncServiceProvider: { nil },
            syncErrorHandler: syncErrorHandler,
            featureFlagger: MockFeatureFlagger(),
            notificationCenter: notificationCenter
        )

        await withCheckedContinuation { continuation in
            testHandler.didReportMetric(.init(metricName: .userDidSubmitPrompt)) {
                continuation.resume()
            }
        }

        #expect(testPixelFiring.expectedFireCalls == testPixelFiring.actualFireCalls)
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
            notificationCenter: notificationCenter
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

    private func makeFeatureFlagger(aiChatSyncEnabled: Bool) -> MockFeatureFlagger {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub["aiChatSync"] = aiChatSyncEnabled
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
            notificationCenter: notificationCenter
        )
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

    // MARK: - AIChatMessageHandler config values

    @available(iOS 16, macOS 13, *)
    @Test("When aiChatSync is enabled and not a fire window, supportsAIChatSync is true", .timeLimit(.minutes(1)))
    func testWhenAIChatSyncEnabledAndNotFireWindowThenSupportsAIChatSyncIsTrue() {
        let featureFlagger = makeFeatureFlagger(aiChatSyncEnabled: true)
        let handler = AIChatMessageHandler(featureFlagger: featureFlagger,
                                           promptHandler: AIChatPromptHandler.shared)

        let config = handler.getNativeConfigValues(isFireWindow: false)

        #expect(config.supportsAIChatSync == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("When aiChatSync is enabled and is a fire window, supportsAIChatSync is false", .timeLimit(.minutes(1)))
    func testWhenAIChatSyncEnabledAndFireWindowThenSupportsAIChatSyncIsFalse() {
        let featureFlagger = makeFeatureFlagger(aiChatSyncEnabled: true)
        let handler = AIChatMessageHandler(featureFlagger: featureFlagger,
                                           promptHandler: AIChatPromptHandler.shared)

        let config = handler.getNativeConfigValues(isFireWindow: true)

        #expect(config.supportsAIChatSync == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("When aiChatSync is disabled, supportsAIChatSync is false regardless of fire window", .timeLimit(.minutes(1)))
    func testWhenAIChatSyncDisabledThenSupportsAIChatSyncIsFalse() {
        let featureFlagger = makeFeatureFlagger(aiChatSyncEnabled: false)
        let handler = AIChatMessageHandler(featureFlagger: featureFlagger,
                                           promptHandler: AIChatPromptHandler.shared)

        #expect(handler.getNativeConfigValues(isFireWindow: false).supportsAIChatSync == false)
        #expect(handler.getNativeConfigValues(isFireWindow: true).supportsAIChatSync == false)
    }
}
// swiftlint:enable inclusive_language
