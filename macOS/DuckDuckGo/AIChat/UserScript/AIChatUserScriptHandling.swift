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

import Foundation
import UserScript
import AIChat

protocol AIChatUserScriptHandling {
    func openAIChatSettings(params: Any, message: UserScriptMessage) async -> Encodable?
    func getAIChatNativeConfigValues(params: Any, message: UserScriptMessage) async -> Encodable?
    func closeAIChat(params: Any, message: UserScriptMessage) async -> Encodable?
    func getAIChatNativePrompt(params: Any, message: UserScriptMessage) async -> Encodable?
    func openAIChat(params: Any, message: UserScriptMessage) async -> Encodable?
    func getAIChatNativeHandoffData(params: Any, message: UserScriptMessage) -> Encodable?

    var messageHandling: AIChatMessageHandling { get }
}

struct AIChatUserScriptHandler: AIChatUserScriptHandling {
    public let messageHandling: AIChatMessageHandling
    private let storage: AIChatPreferencesStorage

    init(storage: AIChatPreferencesStorage,
         messageHandling: AIChatMessageHandling = AIChatMessageHandler()) {
        self.storage = storage
        self.messageHandling = messageHandling
    }

    enum AIChatKeys {
        static let aiChatPayload = "aiChatPayload"
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
}

extension NSNotification.Name {
    static let aiChatNativeHandoffData: NSNotification.Name = Notification.Name(rawValue: "com.duckduckgo.notification.aiChatNativeHandoffData")
}
