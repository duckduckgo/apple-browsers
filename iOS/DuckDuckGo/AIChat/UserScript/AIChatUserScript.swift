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

    /// Called when the user script receives a message related to metrics
    /// - Parameters:
    ///   - userScript: The user script that received the message
    ///   - metric: The metric received
    func aiChatUserScript(_ userScript: AIChatUserScript, didReceiveMetric metric: AIChatMetric)
}

// MARK: - AIChatUserScript Class

final class AIChatUserScript: NSObject, Subfeature {

    // MARK: - Push Message Enum

    enum AIChatPushMessage {
        case submitPrompt(AIChatNativePrompt)
        case fireButtonAction
        case newChatAction
        case promptInterruption
        case openSettingsAction
        case toggleSidebarAction
        case syncStatusChanged(AIChatSyncHandler.SyncStatus)

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
            case .openSettingsAction:
                return "submitOpenSettingsAction"
            case .toggleSidebarAction:
                return "submitToggleSidebarAction"
            case .syncStatusChanged:
                return "submitSyncStatusChanged"
            }
        }

        var params: Encodable? {
            switch self {
            case .submitPrompt(let prompt):
                return prompt
            case .syncStatusChanged(let status):
                return status
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
    private(set) var messageDestinationPolicy: MessageOriginPolicy
    private var inputBoxCancellables = Set<AnyCancellable>()

    var inputBoxHandler: AIChatInputBoxHandling? {
        didSet { subscribeToInputBoxEvents() }
    }

    let featureName: String = "aiChat"

    // MARK: - Initialization

    init(handler: AIChatUserScriptHandling, debugSettings: AIChatDebugSettingsHandling) {
        self.handler = handler
        self.messageOriginPolicy = .only(rules: Self.buildMessageOriginRules(debugSettings: debugSettings))
        self.messageDestinationPolicy = .only(rules: Self.buildMessageDestinationRules(debugSettings: debugSettings))
        super.init()

        // Set self as the metric reporting handler
        handler.setMetricReportingHandler(self)
        handler.setSyncStatusChangedHandler { [weak self] status in
            self?.submitSyncStatusChanged(status)
        }
    }

    private static func buildMessageOriginRules(debugSettings: AIChatDebugSettingsHandling) -> [HostnameMatchingRule] {
        var rules: [HostnameMatchingRule] = []

        if let ddgDomain = URL.ddg.host {
            rules.append(.exact(hostname: ddgDomain))
        }

        if let duckAiDomain = URL.duckAi.host {
            rules.append(.exact(hostname: duckAiDomain))
        }

        if let debugHostname = debugSettings.messagePolicyHostname {
            rules.append(.exact(hostname: debugHostname))
        }
        return rules
    }

    private static func buildMessageDestinationRules(debugSettings: AIChatDebugSettingsHandling) -> [HostnameMatchingRule] {
        var rules: [HostnameMatchingRule] = []

        if let duckAiDomain = URL.duckAi.host {
            rules.append(.exact(hostname: duckAiDomain))
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
        case .getAIChatNativePrompt:
            return handler.getAIChatNativePrompt
        case .getAIChatNativeHandoffData:
            return handler.getAIChatNativeHandoffData
        case .getAIChatPageContext:
            return handler.getAIChatPageContext
        case .openAIChat:
            return handler.openAIChat
        case .hideChatInput:
            return handler.hideChatInput
        case .showChatInput:
            return handler.showChatInput
        case .reportMetric:
            return handler.reportMetric
        case .togglePageContextTelemetry:
            return handler.togglePageContextTelemetry
        case .openKeyboard:
            return { [weak self] params, message in
                await self?.handler.openKeyboard(params: params, message: message, webView: self?.webView)
            }
        case .storeMigrationData:
            return handler.storeMigrationData
        case .getMigrationDataByIndex:
            return handler.getMigrationDataByIndex
        case .getMigrationInfo:
            return handler.getMigrationInfo
        case .clearMigrationData:
            return handler.clearMigrationData
        case .getSyncStatus:
            return handler.getSyncStatus
        case .getScopedSyncAuthToken:
            return handler.getScopedSyncAuthToken
        case .encryptWithSyncMasterKey:
            return handler.encryptWithSyncMasterKey
        case .decryptWithSyncMasterKey:
            return handler.decryptWithSyncMasterKey
        case .sendToSetupSync:
            return handler.sendToSetupSync
        case .sendToSyncSettings:
            return handler.sendToSyncSettings
        case .setAIChatHistoryEnabled:
            return handler.setAIChatHistoryEnabled
        default:
            return nil
        }
    }

    func setPayloadHandler(_ payloadHandler: any AIChatConsumableDataHandling) {
        handler.setPayloadHandler(payloadHandler)
    }

    func setDisplayMode(_ displayMode: AIChatDisplayMode) {
        handler.displayMode = displayMode
    }

    func setPageContextProvider(_ provider: ((PageContextRequestReason) -> AIChatPageContextData?)?) {
        self.handler.setPageContextProvider(provider)
    }

    func setContextualModePixelHandler(_ pixelHandler: AIChatContextualModePixelFiring) {
        self.handler.setContextualModePixelHandler(pixelHandler)
    }

    // MARK: - Input Box Event Subscription

    private func subscribeToInputBoxEvents() {
        inputBoxCancellables.removeAll()

        inputBoxHandler?.didSubmitPrompt
            .sink(receiveValue: { [weak self] prompt in
                let modelId = self?.inputBoxHandler?.persistedModelId
                self?.submitPrompt(prompt, modelId: modelId)
            })
            .store(in: &inputBoxCancellables)

        inputBoxHandler?.didPressNewChatButton
            .sink(receiveValue: { [weak self] _ in self?.push(.newChatAction) })
            .store(in: &inputBoxCancellables)

        inputBoxHandler?.didPressFireButton
            .sink(receiveValue: { [weak self] _ in self?.push(.fireButtonAction) })
            .store(in: &inputBoxCancellables)

        inputBoxHandler?.didPressStopGeneratingButton
            .sink(receiveValue: { [weak self] _ in self?.push(.promptInterruption) })
            .store(in: &inputBoxCancellables)

        handler.setAIChatInputBoxHandler(inputBoxHandler)
    }

    // MARK: - AI Chat Actions

    func submitPrompt(_ prompt: String, pageContext: AIChatPageContextData? = nil) {
        submitPrompt(prompt, pageContext: pageContext, modelId: nil)
    }

    func submitPrompt(_ prompt: String, pageContext: AIChatPageContextData? = nil, modelId: String?) {
        let promptPayload = AIChatNativePrompt.queryPrompt(prompt, autoSubmit: true, modelId: modelId, pageContext: pageContext)
        push(.submitPrompt(promptPayload))
    }
    
    /// Submits a start chat action to the web content, initiating a new AI Chat conversation.
    func submitStartChatAction() {
        push(.newChatAction)
    }

    /// Submits an open settings action to the web content, opening the AI Chat settings.
    func submitOpenSettingsAction() {
        push(.openSettingsAction)
    }

    /// Submits page context to the frontend (push update).
    func submitPageContext(_ context: AIChatPageContextData?) {
        pushPageContextToFrontend(context)
    }

    func submitToggleSidebarAction() {
        push(.toggleSidebarAction)
    }

    /// Pushes sync status change to the web content when sync state changes (login/logout, availability).
    func submitSyncStatusChanged(_ status: AIChatSyncHandler.SyncStatus) {
        // Push only to websites matching origin policy
        guard let host = webView?.url?.host,
              messageDestinationPolicy.isAllowed(host) else { return }

        push(.syncStatusChanged(status))
    }

    // MARK: - Private Helper

    private func pushPageContextToFrontend(_ context: AIChatPageContextData?) {
        guard let webView = webView else { return }
        let response = PageContextResponse(pageContext: context)
        broker?.push(method: AIChatUserScriptMessages.submitAIChatPageContext.rawValue, params: response, for: self, into: webView)
    }

    private func push(_ message: AIChatPushMessage) {
        guard let webView = webView else { return }
        let params: Encodable? = message.params
        broker?.push(method: message.methodName, params: params, for: self, into: webView)
    }
}

// MARK: - AIChatMetricReportingHandling

extension AIChatUserScript: AIChatMetricReportingHandling {
    func didReportMetric(_ metric: AIChatMetric) {
        delegate?.aiChatUserScript(self, didReceiveMetric: metric)
    }
}
