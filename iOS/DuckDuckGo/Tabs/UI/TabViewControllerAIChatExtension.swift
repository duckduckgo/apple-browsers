//
//  TabViewControllerAIChatExtension.swift
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
import Foundation
import UIKit
import WebKit

/// Protocol for tab controllers that support full mode AIChat content loading.
protocol AITabController {
    /// Loads AIChat with optional query, auto-submit, payload, and RAG tools.
    func load(_ query: String?, autoSend: Bool, payload: Any?, flowType: AIChatOnboardingFlowType, tools: [AIChatRAGTool]?, modelId: String?, reasoningEffort: AIChatReasoningEffort?, attachments: AIChatPromptAttachments, termsAccepted: Bool)

    /// Loads AIChat in voice mode.
    func loadVoiceMode()

    /// Submits a start chat action to initiate a new AI Chat conversation.
    func submitStartChatAction()

    /// Submits an open settings action to open the AI Chat settings.
    func submitOpenSettingsAction()

    /// Submits a toggle sidebar action to open/close the sidebar.
    func submitToggleSidebarAction()

    /// Opens a new AI chat in a new tab.
    func openNewChatInNewTab(source: AIChatEntryPointSource?)
}

// MARK: - AITabController
extension TabViewController: AITabController {

    /// Loads AIChat with optional query, auto-submit, payload, and RAG tools.
    func load(_ query: String? = nil,
              autoSend: Bool = false,
              payload: Any? = nil,
              flowType: AIChatOnboardingFlowType = .default,
              tools: [AIChatRAGTool]? = nil,
              modelId: String? = nil,
              reasoningEffort: AIChatReasoningEffort? = nil,
              attachments: AIChatPromptAttachments = .none,
              termsAccepted: Bool = false) {
        let openingQuery = AIChatOpeningRequest.Query(query: query, autoSend: autoSend, flowType: flowType, tools: tools,
                                                     modelId: modelId, reasoningEffort: reasoningEffort,
                                                     attachments: attachments, termsAccepted: termsAccepted)
        configureAIChatOpening(payload: payload)
        if let prompt = openingQuery.sharedPrompt { AIChatPromptHandler.shared.setData(prompt) }
        let queryURL = openingQuery.url(using: aiChatContentHandler)

        load(url: queryURL)
    }

    func configureAIChatOpening(payload: Any?) {
        isVoiceModeRequested = false
        aiChatContentHandler.setPayload(payload: payload)
    }
    
    /// Loads AIChat in voice mode.
    func loadVoiceMode() {
        isVoiceModeRequested = true
        let url = aiChatContentHandler.buildVoiceModeURL()
        load(url: url)
    }

    /// Submits a start chat action to initiate a new AI Chat conversation.
    func submitStartChatAction() {
        cancelPendingAIChatTabAttachmentPrompt()
        Task { @MainActor in
            await aiChatContentHandler.submitStartChatAction()
        }
    }

    /// Submits an open settings action to open the AI Chat settings.
    func submitOpenSettingsAction() {
        if nativeChat != nil {
            load(url: AIChatURLParameters.settingsOpenURL(from: aiChatSettings.aiChatURL))
            return
        }
        aiChatContentHandler.submitOpenSettingsAction()
    }

    /// Submits a toggle sidebar action to open/close the sidebar.
    func submitToggleSidebarAction() {
        if nativeChat != nil {
            load(url: AIChatURLParameters.sidebarOpenURL(from: aiChatSettings.aiChatURL))
            return
        }
        aiChatContentHandler.submitToggleSidebarAction()
    }
    
    /// Opens a new AI chat in a new tab.
    func openNewChatInNewTab(source: AIChatEntryPointSource?) {
        let newChatURL = aiChatContentHandler.buildQueryURL(
            query: nil,
            autoSend: false,
            flowType: .default,
            tools: nil
        )
        delegate?.tab(self, didRequestNewDuckAITabForUrl: newChatURL, entrySource: source, nativeChat: nil)
    }

    /// Opens the Duck.ai chats sidebar in a new tab. Mirrors the contextual sheet's "View all chats"
    /// (`sidebarOpenURL`), so it works from any tab — unlike the in-page sidebar toggle.
    func openChatListInNewTab() {
        let url = AIChatURLParameters.sidebarOpenURL(from: aiChatSettings.aiChatURL)
        delegate?.tab(self, didRequestNewTabForUrl: url, openedByPage: false, inheritingAttribution: nil)
    }

    func openSettingsInNewTab() {
        let url = AIChatURLParameters.settingsOpenURL(from: aiChatSettings.aiChatURL)
        delegate?.tab(self, didRequestNewTabForUrl: url, openedByPage: false, inheritingAttribution: nil)
    }

    func submitOpenChatProtectionAction() {
        if nativeChat != nil {
            load(url: AIChatURLParameters.chatProtectionURL(from: aiChatSettings.aiChatURL))
            return
        }
        aiChatContentHandler.submitOpenChatProtectionAction()
    }

    /// Reloads the full mode AI Chat tab if this is an AI tab.
    func reloadFullModeAIChatIfNeeded() {
        if isAITab {
            webView.reload()
        }
    }
}

extension TabViewController {

    enum AIChatNewWindowDecision: Equatable {
        case ignore
        case loadInTab(URL)
        case openInNewTab(URL)
    }

    static func aiChatNewWindowDecision(currentURL: URL?,
                                        navigationAction: WKNavigationAction) -> AIChatNewWindowDecision {
        guard navigationAction.navigationType == .linkActivated,
              navigationAction.targetFrame == nil,
              currentURL?.isDuckAIURL == true,
              let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return .ignore
        }

        if url.isDuckAIURL {
            return .loadInTab(url)
        }

        return .openInNewTab(url)
    }

    /// Page-started main-frame navigations into Duck.ai that native attributes. The tab's own loads
    /// report their entry where they start, so the one still pending is skipped.
    static func inPageDuckAIEntrySource(currentURL: URL?,
                                        navigationAction: WKNavigationAction,
                                        pendingNativeLoadURL: URL?) -> AIChatEntryPointSource? {
        guard navigationAction.isTargetingMainFrame,
              navigationAction.navigationType != .backForward,
              navigationAction.navigationType != .reload,
              let targetURL = navigationAction.request.url,
              targetURL != pendingNativeLoadURL else {
            return nil
        }
        return AIChatEntryPointSource.forInPageNavigation(from: currentURL, to: targetURL,
                                                          isLinkActivation: navigationAction.navigationType == .linkActivated)
    }
}
