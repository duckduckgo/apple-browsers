//
//  AIChatUserScript.swift
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
import Common
import FoundationExtensions
import Foundation
import Persistence
import UserScript
import WebKit

final class AIChatUserScript: NSObject, Subfeature {
    public let handler: AIChatUserScriptHandling
    public let featureName: String = "aiChat"
    weak var broker: UserScriptMessageBroker?
    weak var webView: WKWebView?
    private(set) var messageOriginPolicy: MessageOriginPolicy
    private(set) var messageDestinationPolicy: MessageOriginPolicy

    private var cancellables: Set<AnyCancellable> = []

    /// When true, the next two messages received from the page act as a readiness
    /// handshake: after the second message we push `submitOpenSettingsAction`. Mirrors
    /// the Windows two-phase TabId flag — by the second message the FE subscriptions
    /// are wired so the push won't be dropped.
    private(set) var pendingOpenSettingsAction = false
    private var openSettingsMessageCount = 0

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    /// Arms the two-phase open-settings handshake. Called when a Duck.ai tab is opened
    /// from Settings → AI Features so the FE's settings modal opens automatically once
    /// the page has wired up its subscriptions.
    func requestOpenSettingsAction() {
        pendingOpenSettingsAction = true
        openSettingsMessageCount = 0
    }

    init(handler: AIChatUserScriptHandling, urlSettings: any KeyedStoring<AIChatDebugURLSettings>) {
        self.handler = handler
        var originRules = [HostnameMatchingRule]()
        var destinationRules = [HostnameMatchingRule]()

        /// Default rule for DuckDuckGo AI Chat
        if let ddgDomain = URL.duckDuckGo.host {
            originRules.append(.exact(hostname: ddgDomain))
        }

        /// Default rule for standalone DuckDuckGo AI Chat
        if let duckAiDomain = URL.duckAi.host {
            originRules.append(.exact(hostname: duckAiDomain))
            destinationRules.append(.exact(hostname: duckAiDomain))
        }

        /// Check if a custom hostname is provided in the URL settings
        /// Custom hostnames are used for debugging purposes
        if let customURLHostname = urlSettings.customURLHostname {
            originRules.append(.exact(hostname: customURLHostname))
            destinationRules.append(.exact(hostname: customURLHostname))
        }
        self.messageOriginPolicy = .only(rules: originRules)
        self.messageDestinationPolicy = .only(rules: destinationRules)
        super.init()

        handler.aiChatNativePromptPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] prompt in
                self?.submitAIChatNativePrompt(prompt)
            }
            .store(in: &cancellables)

        handler.pageContextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pageContext in
                self?.submitAIChatPageContext(pageContext)
            }
            .store(in: &cancellables)

        handler.selectionContextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selection in
                self?.submitAIChatSelectionContext(selection)
            }
            .store(in: &cancellables)

        handler.syncStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.submitSyncStatusChanged(status)
            }
            .store(in: &cancellables)
    }

    private func submitAIChatNativePrompt(_ prompt: AIChatNativePrompt) {
        guard let webView else {
            return
        }
        broker?.push(method: AIChatUserScriptMessages.submitAIChatNativePrompt.rawValue, params: prompt, for: self, into: webView)
    }

    private func submitAIChatPageContext(_ pageContextData: AIChatPageContextData?) {
        guard let webView else {
            return
        }
        let response = PageContextResponse(pageContext: pageContextData)
        broker?.push(method: AIChatUserScriptMessages.submitAIChatPageContext.rawValue, params: response, for: self, into: webView)
    }

    private func submitAIChatSelectionContext(_ selection: AIChatSelectionContextData) {
        guard let webView else {
            return
        }
        broker?.push(method: AIChatUserScriptMessages.submitAIChatSelectionContext.rawValue, params: selection, for: self, into: webView)
    }

    private func submitOpenSettingsAction() {
        guard let webView,
              let host = webView.url?.host,
              messageDestinationPolicy.isAllowed(host) else {
            return
        }
        broker?.push(method: AIChatUserScriptMessages.submitOpenSettingsAction.rawValue, params: nil, for: self, into: webView)
    }

    private func submitSyncStatusChanged(_ status: AIChatSyncHandler.SyncStatus) {
        // Push only to websites matching origin policy
        guard let webView,
              let host = webView.url?.host,
              messageDestinationPolicy.isAllowed(host) else {
            return
        }

        broker?.push(method: AIChatUserScriptMessages.submitSyncStatusChanged.rawValue, params: status, for: self, into: webView)
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        let handler = resolveHandler(forMethodNamed: methodName)
        if handler != nil {
            advanceOpenSettingsHandshake()
        }
        return handler
    }

    private func advanceOpenSettingsHandshake() {
        guard pendingOpenSettingsAction else { return }
        openSettingsMessageCount += 1
        guard openSettingsMessageCount >= 2 else { return }
        pendingOpenSettingsAction = false
        openSettingsMessageCount = 0
        submitOpenSettingsAction()
    }

    private func resolveHandler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch AIChatUserScriptMessages(rawValue: methodName) {
        case .openAIChatSettings:
            return handler.openAIChatSettings
        case .getAIChatNativeConfigValues:
            return handler.getAIChatNativeConfigValues
        case .closeAIChat:
            return handler.closeAIChat
        case .getAIChatNativePrompt:
            return handler.getAIChatNativePrompt
        case .openAIChat:
            return handler.openAIChat
        case .getAIChatNativeHandoffData:
            return handler.getAIChatNativeHandoffData
        case .recordChat:
            return handler.recordChat
        case .restoreChat:
            return handler.restoreChat
        case .removeChat:
            return handler.removeChat
        case .openSummarizationSourceLink:
            return handler.openSummarizationSourceLink
        case .openTranslationSourceLink:
            return handler.openTranslationSourceLink
        case .openAIChatLink:
            return handler.openAIChatLink
        case .getAIChatPageContext:
            return handler.getAIChatPageContext
        case .getAIChatSelectionContext:
            return handler.getAIChatSelectionContext
        case .getAIChatOpenTabs:
            return handler.getAIChatOpenTabs
        case .getAIChatTabContent:
            return handler.getAIChatTabContent
        case .reportMetric:
            return handler.reportMetric
        case .togglePageContextTelemetry:
            return handler.togglePageContextTelemetry
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
        case .voiceSessionStarted:
            return handler.voiceSessionStarted
        case .voiceSessionEnded:
            return handler.voiceSessionEnded
        case .voiceChatStartFailed:
            return handler.voiceChatStartFailed
        case .dictationStartFailed:
            return handler.dictationStartFailed
        default:
            return nil
        }
    }
}
