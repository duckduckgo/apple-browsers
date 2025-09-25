//
//  AIChatTabOpener.swift
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
import AIChat

/// Represents different triggers for opening an AI chat tab.
///
/// This enum encapsulates the various ways an AI chat session can be initiated,
/// providing a type-safe approach to handling different opening scenarios.
enum AIChatOpenTrigger {
    /// Opens a new, empty AI chat session.
    case newChat

    /// Opens an AI chat with an optional pre-filled query.
    /// - Parameters:
    ///   - query: The optional query string to pre-fill in the chat. If `nil`, opens an empty chat.
    ///   - shouldAutoSubmit: Whether to automatically submit the query upon opening. Defaults to `true`.
    case query(String?, shouldAutoSubmit: Bool = true)

    /// Opens an AI chat using a specific URL.
    /// - Parameter url: The URL to load in the AI chat tab.
    case url(URL)

    /// Opens an AI chat with a specific payload containing chat data.
    /// - Parameter payload: The `AIChatPayload` containing the chat session data to restore.
    case payload(AIChatPayload)

    /// Opens an AI chat using restoration data from a previous session.
    /// - Parameter data: The `AIChatRestorationData` used to restore a previous chat state.
    case restoration(AIChatRestorationData)
}

/// Protocol defining the interface for opening AI chat tabs.
///
/// This protocol provides methods for opening AI chat sessions in various ways,
/// supporting different triggers and link opening behaviors. Implementations
/// should handle the creation and management of AI chat tabs within the application.
protocol AIChatTabOpening {
    /// Opens an AI chat tab with the specified trigger and behavior.
    ///
    /// This is the primary method for opening AI chat tabs, supporting various
    /// opening scenarios through the `AIChatOpenTrigger` enum.
    ///
    /// - Parameters:
    ///   - trigger: The `AIChatOpenTrigger` specifying how the chat should be opened
    ///             (new chat, with query, from URL, payload, or restoration data).
    ///   - behavior: The `LinkOpenBehavior` determining where the chat tab should open
    ///              (current tab, new tab, etc.).
    @MainActor
    func openAIChatTab(with trigger: AIChatOpenTrigger, behavior: LinkOpenBehavior)

    /// Opens a new, empty AI chat session.
    ///
    /// This is a convenience method equivalent to calling `openAIChatTab(with: .newChat, behavior:)`.
    ///
    /// - Parameter linkOpenBehavior: The `LinkOpenBehavior` determining where the new chat tab should open.
    @MainActor
    func openNewAIChat(in linkOpenBehavior: LinkOpenBehavior)
}

struct AIChatTabOpener: AIChatTabOpening {
    private let promptHandler: AIChatPromptHandler
    private let aiChatTabManaging: AIChatTabManaging

    let aiChatRemoteSettings = AIChatRemoteSettings()

    init(
        promptHandler: AIChatPromptHandler,
        aiChatTabManaging: AIChatTabManaging
    ) {
        self.promptHandler = promptHandler
        self.aiChatTabManaging = aiChatTabManaging
    }

    // MARK: - New Simplified API

    @MainActor
    func openAIChatTab(with trigger: AIChatOpenTrigger, behavior: LinkOpenBehavior) {
        switch trigger {
        case .newChat:
            openAIChatTab(query: nil, with: behavior, autoSubmit: true)

        case .query(let query, shouldAutoSubmit: let shouldAutoSubmit):
            openAIChatTab(query: query, with: behavior, autoSubmit: shouldAutoSubmit)

        case .url(let url):
            aiChatTabManaging.openAIChat(url, with: behavior, hasPrompt: false)

        case .payload(let payload):
            aiChatTabManaging.insertAIChatTab(with: aiChatRemoteSettings.aiChatURL, payload: payload)
        case .restoration(let data):
            aiChatTabManaging.insertAIChatTab(with: aiChatRemoteSettings.aiChatURL, restorationData: data)
        }
    }

    @MainActor
    func openNewAIChat(in linkOpenBehavior: LinkOpenBehavior) {
        openAIChatTab(with: .newChat, behavior: linkOpenBehavior)
    }

    // MARK: - Private Helper

    @MainActor
    private func openAIChatTab(query: String?, with linkOpenBehavior: LinkOpenBehavior, autoSubmit: Bool) {
        if let query = query {
            promptHandler.setData(.queryPrompt(query, autoSubmit: autoSubmit))
        }
        aiChatTabManaging.openAIChat(aiChatRemoteSettings.aiChatURL, with: linkOpenBehavior, hasPrompt: query != nil)
    }
}

protocol AIChatTabManaging {
    @MainActor
    func openAIChat(_ url: URL, with behavior: LinkOpenBehavior, hasPrompt: Bool)

    @MainActor
    func insertAIChatTab(with url: URL, payload: AIChatPayload)

    @MainActor
    func insertAIChatTab(with url: URL, restorationData: AIChatRestorationData)
}

extension WindowControllersManager: AIChatTabManaging {

    /// Opens an AI chat URL in the application.
    ///
    /// - Parameters:
    ///   - url: The AI chat URL to open.
    ///   - linkOpenBehavior: Specifies where to open the URL. Defaults to `.currentTab`.
    ///   - hasPrompt: If `true` and the current tab is an AI chat, reloads the tab. Ignored if `target` is `.newTabSelected`
    ///                or `.newTabUnselected`.
    func openAIChat(_ url: URL, with linkOpenBehavior: LinkOpenBehavior = .currentTab, hasPrompt: Bool) {

        let tabCollectionViewModel = mainWindowController?.mainViewController.tabCollectionViewModel

        switch linkOpenBehavior {
        case .currentTab:
            if let currentURL = tabCollectionViewModel?.selectedTab?.url, currentURL.isDuckAIURL {
                if hasPrompt {
                    tabCollectionViewModel?.selectedTab?.reload()
                }
            } else {
                show(url: url, source: .ui, newTab: false)
            }
        default:
            open(url, with: linkOpenBehavior, source: .ui, target: nil)
        }
    }

    func insertAIChatTab(with url: URL, payload: AIChat.AIChatPayload) {
        guard let tabCollectionViewModel = lastKeyMainWindowController?.mainViewController.tabCollectionViewModel else { return }
        let newAIChatTab = Tab(content: .url(url, source: .ui))
        newAIChatTab.aiChat?.setAIChatNativeHandoffData(payload: payload)
        tabCollectionViewModel.insertOrAppend(tab: newAIChatTab, selected: true)

    }

    func insertAIChatTab(with url: URL, restorationData: AIChat.AIChatRestorationData) {
        guard let tabCollectionViewModel = lastKeyMainWindowController?.mainViewController.tabCollectionViewModel else { return }
        let newAIChatTab = Tab(content: .url(url, source: .ui))
        newAIChatTab.aiChat?.setAIChatRestorationData(data: restorationData)
        tabCollectionViewModel.insertOrAppend(tab: newAIChatTab, selected: true)
    }
}
