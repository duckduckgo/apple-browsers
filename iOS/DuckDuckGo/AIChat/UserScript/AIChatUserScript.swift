//
//  AIChatUserScript.swift
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

import Common
import UserScript
import Foundation
import AIChat
import WebKit
import Combine

// MARK: - Delegate Protocol

protocol AIChatUserScriptDelegate: AnyObject {

    /// Called when the user script receives a message from the web content
    /// - Parameters:
    ///   - userScript: The user script that received the message
    ///   - message: The type of message received
    func aiChatUserScript(_ userScript: AIChatUserScript, didReceiveMessage message: AIChatUserScriptMessages)
}

// MARK: - AIChatUserScript Class

final class AIChatUserScript: NSObject, Subfeature {

    // MARK: - Push Message Enum

    enum AIChatPushMessage {
        case submitPrompt(AIChatNativePrompt)
        case fireButtonAction
        case newChatAction
        case promptInterruption

        var methodName: String {
            switch self {
            case .submitPrompt:
                return "submitAIChatNativePrompt"
            case .fireButtonAction:
                return "submitFireButtonAction"
            case .newChatAction:
                return "submitNewChatAction"
            case .promptInterruption:
                return "submitPromptInterruption"
            }
        }

        var params: Encodable? {
            switch self {
            case .submitPrompt(let prompt):
                return prompt
            default:
                return nil
            }
        }
    }

    // MARK: - Properties

    weak var delegate: AIChatUserScriptDelegate?
    weak var broker: UserScriptMessageBroker?
    weak var webView: WKWebView?

    private let handler: AIChatUserScriptHandling
    private(set) var messageOriginPolicy: MessageOriginPolicy
    private var cancellables = Set<AnyCancellable>()

    var inputBoxHandler: AIChatInputBoxHandling? {
        didSet { subscribeToInputBoxEvents() }
    }

    let featureName: String = "aiChat"

    // MARK: - Initialization

    init(handler: AIChatUserScriptHandling, debugSettings: AIChatDebugSettingsHandling) {
        self.handler = handler
        self.messageOriginPolicy = .only(rules: Self.buildMessageOriginRules(debugSettings: debugSettings))
    }

    private static func buildMessageOriginRules(debugSettings: AIChatDebugSettingsHandling) -> [HostnameMatchingRule] {
        var rules: [HostnameMatchingRule] = []

        if let ddgDomain = URL.ddg.host {
            rules.append(.exact(hostname: ddgDomain))
        }

        if let debugHostname = debugSettings.messagePolicyHostname {
            rules.append(.exact(hostname: debugHostname))
        }
        return rules
    }

    // MARK: - Subfeature

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        guard let message = AIChatUserScriptMessages(rawValue: methodName) else {
            Logger.aiChat.debug("Unhandled message: \(methodName) in AIChatUserScript")
            return nil
        }

        delegate?.aiChatUserScript(self, didReceiveMessage: message)

        switch message {
        case .responseState:
            return handler.getResponseState
        case .getAIChatNativeConfigValues:
            return handler.getAIChatNativeConfigValues
        case .getAIChatNativeHandoffData:
            return handler.getAIChatNativeHandoffData
        case .openAIChat:
            return handler.openAIChat
        case .hideChatInput:
            return handler.hideChatInput
        case .showChatInput:
            return handler.showChatInput
        default:
            return nil
        }
    }

    func setPayloadHandler(_ payloadHandler: any AIChatConsumableDataHandling) {
        handler.setPayloadHandler(payloadHandler)
    }

    // MARK: - Input Box Event Subscription

    private func subscribeToInputBoxEvents() {
        inputBoxHandler?.didSubmitText
            .sink(receiveValue: submitPrompt)
            .store(in: &cancellables)

        inputBoxHandler?.didPressNewChatButton
            .sink(receiveValue: { [weak self] _ in self?.push(.newChatAction) })
            .store(in: &cancellables)

        inputBoxHandler?.didPressFireButton
            .sink(receiveValue: { [weak self] _ in self?.push(.fireButtonAction) })
            .store(in: &cancellables)

        inputBoxHandler?.didPressStopGeneratingButton
            .sink(receiveValue: { [weak self] _ in self?.push(.promptInterruption) })
            .store(in: &cancellables)

        handler.setAIChatInputBoxHandler(inputBoxHandler)
    }

    // MARK: - AI Chat Actions

    func submitPrompt(_ prompt: String) {
        let promptPayload = AIChatNativePrompt.queryPrompt(prompt, autoSubmit: true)
        push(.submitPrompt(promptPayload))
    }

    // MARK: - Private Helper

    private func push(_ message: AIChatPushMessage) {
        guard let webView = webView else { return }
        let params: Encodable? = message.params
        broker?.push(method: message.methodName, params: params, for: self, into: webView)
    }
}
