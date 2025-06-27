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
import Combine
import Foundation
import UserScript

protocol AIChatUserScriptHandling {
    func openAIChatSettings(params: Any, message: UserScriptMessage) async -> Encodable?
    func getAIChatNativeConfigValues(params: Any, message: UserScriptMessage) async -> Encodable?
    func closeAIChat(params: Any, message: UserScriptMessage) async -> Encodable?
    func getAIChatNativePrompt(params: Any, message: UserScriptMessage) async -> Encodable?
    func openAIChat(params: Any, message: UserScriptMessage) async -> Encodable?
    func getAIChatNativeHandoffData(params: Any, message: UserScriptMessage) -> Encodable?
    func recordChat(params: Any, message: UserScriptMessage) -> Encodable?
    func restoreChat(params: Any, message: UserScriptMessage) -> Encodable?
    func removeChat(params: Any, message: UserScriptMessage) -> Encodable?
    var aiChatNativePromptPublisher: AnyPublisher<AIChatNativePrompt, Never> { get }

    var messageHandling: AIChatMessageHandling { get }
    func submitAIChatNativePrompt(_ prompt: AIChatNativePrompt)
}

struct AIChatUserScriptHandler: AIChatUserScriptHandling {
    public let messageHandling: AIChatMessageHandling
    public let aiChatNativePromptPublisher: AnyPublisher<AIChatNativePrompt, Never>

    private let aiChatNativePromptSubject = PassthroughSubject<AIChatNativePrompt, Never>()
    private let storage: AIChatPreferencesStorage

    init(storage: AIChatPreferencesStorage,
         messageHandling: AIChatMessageHandling = AIChatMessageHandler()) {
        self.storage = storage
        self.messageHandling = messageHandling
        self.aiChatNativePromptPublisher = aiChatNativePromptSubject.eraseToAnyPublisher()
    }

    enum AIChatKeys {
        static let aiChatPayload = "aiChatPayload"
        static let serializedChatData = "serializedChatData"
    }

    @MainActor public func openAIChatSettings(params: Any, message: UserScriptMessage) async -> Encodable? {
        Application.appDelegate.windowControllersManager.showTab(with: .settings(pane: .aiChat))
        return nil
    }

    public func getAIChatNativeConfigValues(params: Any, message: UserScriptMessage) async -> Encodable? {
        messageHandling.getDataForMessageType(.nativeConfigValues)
    }

    func closeAIChat(params: Any, message: UserScriptMessage) async -> Encodable? {
        await Application.appDelegate.windowControllersManager.mainWindowController?.mainViewController.closeTab(nil)
        return nil
    }

    func getAIChatNativePrompt(params: Any, message: UserScriptMessage) async -> Encodable? {
        messageHandling.getDataForMessageType(.nativePrompt)
    }

    @MainActor
    func openAIChat(params: Any, message: UserScriptMessage) async -> Encodable? {
        var payload: AIChatPayload?
        if let paramsDict = params as? AIChatPayload {
            payload = paramsDict[AIChatKeys.aiChatPayload] as? AIChatPayload
        }

        NotificationCenter.default.post(name: .aiChatNativeHandoffData,
                                        object: payload,
                                        userInfo: nil)
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

    func submitAIChatNativePrompt(_ prompt: AIChatNativePrompt) {
        aiChatNativePromptSubject.send(prompt)
    }
}

extension NSNotification.Name {
    static let aiChatNativeHandoffData: NSNotification.Name = Notification.Name(rawValue: "com.duckduckgo.notification.aiChatNativeHandoffData")
    static let aiChatSummarizationQuery: NSNotification.Name = Notification.Name(rawValue: "com.duckduckgo.notification.aiChatSummarizationQuery")
}
