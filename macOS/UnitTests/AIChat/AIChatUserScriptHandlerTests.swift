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

import Combine
import PixelKitTestingUtilities
import Testing
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
    var setDataCalls: [SetData] = []

    var getDataForMessageTypeImpl: (AIChatMessageType) -> Encodable? = { _ in nil }
    var setData: (Any?, AIChatMessageType) -> Void = { _, _ in }

    func getDataForMessageType(_ type: AIChatMessageType) -> Encodable? {
        getDataForMessageTypeCalls.append(type)
        return getDataForMessageTypeImpl(type)
    }

    func setData(_ data: Any?, forMessageType type: AIChatMessageType) {
        setDataCalls.append(.init(data, type))
        setData(data, type)
    }
}

struct AIChatUserScriptHandlerTests {
    private var storage = MockAIChatPreferencesStorage()
    private var messageHandler = MockAIChatMessageHandler()
    private var windowControllersManager: WindowControllersManagerMock
    private var notificationCenter = NotificationCenter()
    private var pixelFiring = PixelKitMock()
    private var handler: AIChatUserScriptHandler

    @MainActor
    init() {
        windowControllersManager = WindowControllersManagerMock()

        handler = AIChatUserScriptHandler(
            storage: storage,
            messageHandling: messageHandler,
            windowControllersManager: windowControllersManager,
            pixelFiring: pixelFiring,
            notificationCenter: notificationCenter
        )
    }

    @Test("openAIChatSettings calls windowControllersManager")
    @MainActor
    func testThatOpenAIChatSettingsCallsWindowControllersManager() async {
        _ = await handler.openAIChatSettings(params: [], message: WKScriptMessage())
        #expect(windowControllersManager.showTabCalls == [.settings(pane: .aiChat)])
    }

    @Test("getAIChatNativeConfigValues calls messageHandler")
    func testThatGetAIChatNativeConfigValuesCallsMessageHandler() async {
        _ = await handler.getAIChatNativeConfigValues(params: [], message: WKScriptMessage())
        #expect(messageHandler.getDataForMessageTypeCalls == [.nativeConfigValues])
    }

    @Test("getAIChatNativePrompt calls messageHandler")
    func testThatGetAIChatNativePromptCallsMessageHandler() async {
        _ = await handler.getAIChatNativePrompt(params: [], message: WKScriptMessage())
        #expect(messageHandler.getDataForMessageTypeCalls == [.nativePrompt])
    }

    @Test("openAIChat posts a notification with a payload")
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
        _ = await handler.openAIChat(params: [AIChatUserScriptHandler.AIChatKeys.aiChatPayload: payload], message: WKScriptMessage())

        guard let notificationObject = await notificationsStream.map(\.object).first(where: { _ in true }) else {
            throw NotificationNotReceivedError()
        }
        let notificationPayload = try #require(notificationObject as? [String: String])
        #expect(notificationPayload == payload)
    }

    @Test("getAIChatNativeHandoffData calls messageHandler")
    func testThatGetAIChatNativeHandoffDataCallsMessageHandler() async throws {
        _ = await handler.getAIChatNativeHandoffData(params: [], message: WKScriptMessage())
        #expect(messageHandler.getDataForMessageTypeCalls == [.nativeHandoffData])
    }

    @Test("recordChat calls messageHandler")
    func testThatRecordChatCallsMessageHandler() async throws {
        _ = await handler.recordChat(
            params: [AIChatUserScriptHandler.AIChatKeys.serializedChatData: "test"],
            message: WKScriptMessage()
        )
        #expect(messageHandler.setDataCalls.count == 1)
        let setDataCall = try #require(messageHandler.setDataCalls.first?.data as? String)
        #expect(setDataCall == "test")
    }

    @Test("restoreChat returns serialized chat data")
    func testThatRestoreChatReturnsSerializedChatData() async throws {
        messageHandler.getDataForMessageTypeImpl = { _ in return "test" }

        let result = await handler.restoreChat(params: [], message: WKScriptMessage())
        #expect(messageHandler.getDataForMessageTypeCalls == [.chatRestorationData])
        let resultDictionary = try #require(result as? [String: String])
        #expect(resultDictionary[AIChatUserScriptHandler.AIChatKeys.serializedChatData] == "test")
    }

    @Test("restoreChat returns nil when chat data is not a string")
    func testThatRestoreChatReturnsNilWhenChatDataIsNotString() async throws {
        messageHandler.getDataForMessageTypeImpl = { _ in return 123 }

        let result = await handler.restoreChat(params: [], message: WKScriptMessage())
        #expect(messageHandler.getDataForMessageTypeCalls == [.chatRestorationData])
        #expect(result == nil)
    }

    @Test("restoreChat returns nil when chat data is nil")
    func testThatRestoreChatReturnsNilWhenChatDataIsNil() async throws {
        messageHandler.getDataForMessageTypeImpl = { _ in return nil }

        let result = await handler.restoreChat(params: [], message: WKScriptMessage())
        #expect(messageHandler.getDataForMessageTypeCalls == [.chatRestorationData])
        #expect(result == nil)
    }

    @Test("removeChat calls messageHandler")
    func testThatRemoveChatCallsMessageHandler() async throws {
        _ = await handler.removeChat(params: [], message: WKScriptMessage())
        #expect(messageHandler.setDataCalls.count == 1)
        #expect(messageHandler.setDataCalls.first?.data == nil)
    }

    @Test("openSummarizationSourceLink calls windowControllersManager when valid URL is passed")
    @MainActor
    func testThatOpenSummarizationSourceLinkCallsWindowControllersManager() async throws {
        let urlString = "https://example.com"
        let params = [AIChatUserScriptHandler.AIChatKeys.url: urlString]
        pixelFiring.expectedFireCalls = [.init(pixel: AIChatPixel.aiChatSummarizeSourceLinkClicked, frequency: .dailyAndStandard)]

        _ = await handler.openSummarizationSourceLink(params: params, message: WKScriptMessage())

        #expect(windowControllersManager.openCalls.count == 1)
        let openCall = try #require(windowControllersManager.openCalls.first)
        #expect(openCall.url.absoluteString == urlString)
        #expect(openCall.source == .link)
        #expect(pixelFiring.expectedFireCalls == pixelFiring.actualFireCalls)
    }

    @Test("openSummarizationSourceLink doesn't call windowControllersManager when invalid URL is passed")
    @MainActor
    func testThatOpenSummarizationSourceLinkDoesNotCallWindowControllersManagerWhenInvalidURLIsPassed() async {
        let urlString = "invalid"
        let params = [AIChatUserScriptHandler.AIChatKeys.url: urlString]

        _ = await handler.openSummarizationSourceLink(params: params, message: WKScriptMessage())

        #expect(windowControllersManager.openCalls.count == 0)
    }

    @Test("submitAIChatNativePrompt forwards prompt to the publisher")
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

}
