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

/// Protocol for tab controllers that support full mode AIChat content loading.
protocol AITabController {
    /// Loads AIChat with optional query, auto-submit, payload, and RAG tools.
    func load(_ query: String?, autoSend: Bool, payload: Any?, tools: [AIChatRAGTool]?)

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
    func load(_ query: String? = nil, autoSend: Bool = false, payload: Any? = nil, tools: [AIChatRAGTool]? = nil) {

        aiChatContentHandler.setPayload(payload: payload)

        let queryURL = aiChatContentHandler.buildQueryURL(query: query, autoSend: autoSend, tools: tools)

        load(url: queryURL)
    }
    
    /// Submits a start chat action to initiate a new AI Chat conversation.
    func submitStartChatAction() {
        aiChatContentHandler.submitStartChatAction()
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
        let newChatURL = aiChatContentHandler.buildQueryURL(query: nil, autoSend: false, tools: nil)
        delegate?.tab(self, didRequestNewTabForUrl: newChatURL, openedByPage: false, inheritingAttribution: nil)
    }

    /// Reloads the full mode AI Chat tab if this is an AI tab.
    func reloadFullModeAIChatIfNeeded() {
        if isAITab {
            webView.reload()
        }
    }
}
