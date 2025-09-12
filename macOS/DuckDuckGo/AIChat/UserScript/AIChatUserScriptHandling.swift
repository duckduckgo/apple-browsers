//
//  AIChatUserScriptHandling.swift
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
import AppKit
import Combine
import Common
import Foundation
import PixelKit
import UserScript

protocol AIChatUserScriptHandling {
    @MainActor func openAIChatSettings(params: Any, message: UserScriptMessage) async -> Encodable?
    func getAIChatNativeConfigValues(params: Any, message: UserScriptMessage) async -> Encodable?
    func closeAIChat(params: Any, message: UserScriptMessage) async -> Encodable?
    func getAIChatNativePrompt(params: Any, message: UserScriptMessage) async -> Encodable?
    @MainActor func openAIChat(params: Any, message: UserScriptMessage) async -> Encodable?
    func getAIChatNativeHandoffData(params: Any, message: UserScriptMessage) -> Encodable?
    func recordChat(params: Any, message: UserScriptMessage) -> Encodable?
    func restoreChat(params: Any, message: UserScriptMessage) -> Encodable?
    func removeChat(params: Any, message: UserScriptMessage) -> Encodable?
    @MainActor func openSummarizationSourceLink(params: Any, message: UserScriptMessage) async -> Encodable?
    @MainActor func openTranslationSourceLink(params: Any, message: UserScriptMessage) async -> Encodable?
    var aiChatNativePromptPublisher: AnyPublisher<AIChatNativePrompt, Never> { get }

    func getPageContext(params: Any, message: UserScriptMessage) -> Encodable?
    var pageContextPublisher: AnyPublisher<AIChatPageContextData?, Never> { get }
    var pageContextRequestedPublisher: AnyPublisher<Void, Never> { get }

    var messageHandling: AIChatMessageHandling { get }
    func submitAIChatNativePrompt(_ prompt: AIChatNativePrompt)
    func submitPageContext(_ pageContext: AIChatPageContextData?)

    func togglePageContextTelemetry(params: Any, message: UserScriptMessage) -> Encodable?
}

struct AIChatUserScriptHandler: AIChatUserScriptHandling {
    public let messageHandling: AIChatMessageHandling
    public let aiChatNativePromptPublisher: AnyPublisher<AIChatNativePrompt, Never>
    public let pageContextPublisher: AnyPublisher<AIChatPageContextData?, Never>
    public let pageContextRequestedPublisher: AnyPublisher<Void, Never>

    private let aiChatNativePromptSubject = PassthroughSubject<AIChatNativePrompt, Never>()
    private let pageContextSubject = PassthroughSubject<AIChatPageContextData?, Never>()
    private let pageContextRequestedSubject = PassthroughSubject<Void, Never>()
    private let storage: AIChatPreferencesStorage
    private let windowControllersManager: WindowControllersManagerProtocol
    private let notificationCenter: NotificationCenter
    private let pixelFiring: PixelFiring?

    init(
        storage: AIChatPreferencesStorage,
        messageHandling: AIChatMessageHandling = AIChatMessageHandler(),
        windowControllersManager: WindowControllersManagerProtocol,
        pixelFiring: PixelFiring?,
        notificationCenter: NotificationCenter = .default
    ) {
        self.storage = storage
        self.messageHandling = messageHandling
        self.windowControllersManager = windowControllersManager
        self.pixelFiring = pixelFiring
        self.notificationCenter = notificationCenter
        self.aiChatNativePromptPublisher = aiChatNativePromptSubject.eraseToAnyPublisher()
        self.pageContextPublisher = pageContextSubject.eraseToAnyPublisher()
        self.pageContextRequestedPublisher = pageContextRequestedSubject.eraseToAnyPublisher()
    }

    enum AIChatKeys {
        static let aiChatPayload = "aiChatPayload"
        static let serializedChatData = "serializedChatData"
    }

    @MainActor public func openAIChatSettings(params: Any, message: UserScriptMessage) async -> Encodable? {
        windowControllersManager.showTab(with: .settings(pane: .aiChat))
        return nil
    }

    public func getAIChatNativeConfigValues(params: Any, message: UserScriptMessage) async -> Encodable? {
        messageHandling.getDataForMessageType(.nativeConfigValues)
    }

    func closeAIChat(params: Any, message: UserScriptMessage) async -> Encodable? {
        await windowControllersManager.mainWindowController?.mainViewController.closeTab(nil)
        return nil
    }

    func getAIChatNativePrompt(params: Any, message: UserScriptMessage) async -> Encodable? {
        messageHandling.getDataForMessageType(.nativePrompt)
    }

    func getPageContext(params: Any, message: any UserScriptMessage) -> Encodable? {
        guard let payload: GetPageContext = DecodableHelper.decode(from: params) else {
            return nil
        }

        let data = messageHandling.getDataForMessageType(.pageContext) as? PageContextPayload
        if data?.serializedPageData == nil, payload.explicitConsent {
            pageContextRequestedSubject.send()
        }
        return data
    }

    @MainActor
    func openAIChat(params: Any, message: UserScriptMessage) async -> Encodable? {
        var payload: AIChatPayload?
        if let paramsDict = params as? AIChatPayload {
            payload = paramsDict[AIChatKeys.aiChatPayload] as? AIChatPayload
        }

        notificationCenter.post(name: .aiChatNativeHandoffData, object: payload, userInfo: nil)
        return nil
    }

    public func getAIChatNativeHandoffData(params: Any, message: UserScriptMessage) -> Encodable? {
       messageHandling.getDataForMessageType(.nativeHandoffData)
    }

    public func recordChat(params: Any, message: any UserScriptMessage) -> (any Encodable)? {
        guard let params = params as? [String: String],
              let data = params[AIChatKeys.serializedChatData]
        else { return nil }

        messageHandling.setData(data, forMessageType: .chatRestorationData)
        return nil
    }

    public func restoreChat(params: Any, message: any UserScriptMessage) -> (any Encodable)? {
        guard let data = messageHandling.getDataForMessageType(.chatRestorationData) as? String
        else { return nil }

        return [AIChatKeys.serializedChatData: data]
    }

    public func removeChat(params: Any, message: any UserScriptMessage) -> (any Encodable)? {
        messageHandling.setData(nil, forMessageType: .chatRestorationData)
        return nil
    }

    @MainActor func openSummarizationSourceLink(params: Any, message: any UserScriptMessage) async -> (any Encodable)? {
        guard let openLinkParams: OpenLink = DecodableHelper.decode(from: params), let url = openLinkParams.url.url
        else { return nil }

        let isSidebar = message.messageWebView?.url?.hasAIChatSidebarPlacementParameter == true

        switch openLinkParams.target {
        case .sameTab where isSidebar == false: // for same tab outside of sidebar we force opening new tab to keep the AI chat tab
            windowControllersManager.show(url: url, source: .switchToOpenTab, newTab: true, selected: true)
        default:
            windowControllersManager.open(url, source: .link, target: nil, event: NSApp.currentEvent)
        }
        pixelFiring?.fire(AIChatPixel.aiChatSummarizeSourceLinkClicked, frequency: .dailyAndStandard)
        return nil
    }

    @MainActor func openTranslationSourceLink(params: Any, message: any UserScriptMessage) async -> (any Encodable)? {
        guard let openLinkParams: OpenLink = DecodableHelper.decode(from: params), let url = openLinkParams.url.url
        else { return nil }

        let isSidebar = message.messageWebView?.url?.hasAIChatSidebarPlacementParameter == true

        switch openLinkParams.target {
        case .sameTab where isSidebar == false: // for same tab outside of sidebar we force opening new tab to keep the AI chat tab
            windowControllersManager.show(url: url, source: .switchToOpenTab, newTab: true, selected: true)
        default:
            windowControllersManager.open(url, source: .link, target: nil, event: NSApp.currentEvent)
        }
        pixelFiring?.fire(AIChatPixel.aiChatTranslationSourceLinkClicked, frequency: .dailyAndStandard)
        return nil
    }

    func submitAIChatNativePrompt(_ prompt: AIChatNativePrompt) {
        aiChatNativePromptSubject.send(prompt)
    }

    func submitPageContext(_ pageContext: AIChatPageContextData?) {
        pageContextSubject.send(pageContext)
    }

    func togglePageContextTelemetry(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let payload: TogglePageContextTelemetry = DecodableHelper.decode(from: params) else {
            return nil
        }
        let pixel: PixelKitEvent = {
            if payload.enabled {
                return AIChatPixel.aiChatPageContextAdded(automaticEnabled: storage.shouldAutomaticallySendPageContext)
            }
            return AIChatPixel.aiChatPageContextRemoved(automaticEnabled: storage.shouldAutomaticallySendPageContext)
        }()
        pixelFiring?.fire(pixel, frequency: .dailyAndStandard)
        return nil
    }
}

extension NSNotification.Name {
    static let aiChatNativeHandoffData: NSNotification.Name = Notification.Name(rawValue: "com.duckduckgo.notification.aiChatNativeHandoffData")
}

extension AIChatUserScriptHandler {

    struct OpenLink: Codable, Equatable {
        let url: String
        let target: OpenTarget

        enum OpenTarget: String, Codable, Equatable {
            case sameTab = "same-tab"
            case newTab = "new-tab"
            case newWindow = "new-window"
        }
    }

    struct GetPageContext: Codable, Equatable {
        let explicitConsent: Bool
    }

    struct TogglePageContextTelemetry: Codable, Equatable {
        let enabled: Bool
    }
}
