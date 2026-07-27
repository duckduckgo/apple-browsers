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
    func load(_ query: String?, autoSend: Bool, payload: Any?, flowType: AIChatOnboardingFlowType, tools: [AIChatRAGTool]?, modelId: String?, reasoningEffort: AIChatReasoningEffort?, images: [AIChatNativePrompt.NativePromptImage]?, files: [AIChatNativePrompt.NativePromptFile]?)

    /// Loads AIChat in voice mode.
    func loadVoiceMode()

    /// Submits a start chat action to initiate a new AI Chat conversation.
    func submitStartChatAction()

    /// Submits an open settings action to open the AI Chat settings.
    func submitOpenSettingsAction()

    /// Submits a toggle sidebar action to open/close the sidebar.
    func submitToggleSidebarAction()

    /// Opens a new AI chat in a new tab.
    func openNewChatInNewTab()
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
              images: [AIChatNativePrompt.NativePromptImage]? = nil,
              files: [AIChatNativePrompt.NativePromptFile]? = nil) {
        isVoiceModeRequested = false

        aiChatContentHandler.setPayload(payload: payload)
        let hasAttachments = images?.isEmpty == false || files?.isEmpty == false
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasAttachments {
            let prompt = AIChatNativePrompt.queryPrompt(
                query,
                autoSubmit: autoSend,
                toolChoice: tools?.map(\.rawValue),
                images: images,
                files: files,
                modelId: modelId,
                reasoningEffort: reasoningEffort
            )
            AIChatPromptHandler.shared.setData(prompt)
        }

        let queryURL = aiChatContentHandler.buildQueryURL(
            query: query,
            autoSend: autoSend,
            flowType: flowType,
            tools: tools
        )

        load(url: queryURL)
    }
    
    /// Loads AIChat in voice mode.
    func loadVoiceMode() {
        isVoiceModeRequested = true
        let url = aiChatContentHandler.buildVoiceModeURL()
        load(url: url)
    }

    /// Submits a start chat action to initiate a new AI Chat conversation.
    func submitStartChatAction() {
        Task { @MainActor in
            await aiChatContentHandler.submitStartChatAction()
        }
    }

    /// Submits an open settings action to open the AI Chat settings.
    func submitOpenSettingsAction() {
        aiChatContentHandler.submitOpenSettingsAction()
    }

    /// Submits a toggle sidebar action to open/close the sidebar.
    func submitToggleSidebarAction() {
        aiChatContentHandler.submitToggleSidebarAction()
    }
    
    /// Opens a new AI chat in a new tab.
    func openNewChatInNewTab() {
        let newChatURL = aiChatContentHandler.buildQueryURL(
            query: nil,
            autoSend: false,
            flowType: .default,
            tools: nil
        )
        delegate?.tab(self, didRequestNewTabForUrl: newChatURL, openedByPage: false, inheritingAttribution: nil)
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

    func openAIChatFeedback(positive: Bool) {
        let value = positive ? AIChatURLParameters.feedbackPositiveValue : AIChatURLParameters.feedbackNegativeValue
        if isAITab {
            aiChatContentHandler.submitOpenFeedbackAction(sentiment: value)
        } else {
            let url = AIChatURLParameters.feedbackURL(from: aiChatSettings.aiChatURL, value: value)
            delegate?.tab(self, didRequestNewTabForUrl: url, openedByPage: false, inheritingAttribution: nil)
        }
    }

    func submitOpenChatProtectionAction() {
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
}
