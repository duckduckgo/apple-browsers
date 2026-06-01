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

    /// Opens an existing AI chat by its chat ID.
    /// - Parameter chatId: The unique identifier of the chat to open.
    case existingChat(chatId: String)

    /// Opens a new AI chat session pre-set with a `mode` value in the prompt handoff.
    /// Used for mode-driven entry points (e.g. voice) where there is no user query but Duck.ai
    /// must route to a specific flow based on the mode — same mechanism image-generation submissions use.
    /// - Parameter mode: The mode string forwarded in the native prompt payload (e.g. `AIChatNativePrompt.voiceMode`).
    case mode(String)

    /// Opens duck.ai in a new tab and arms the user script to push the open-settings
    /// action once the page's subscriptions are wired. Used by Settings → AI Features →
    /// "Open Duck.ai Settings".
    case openSettings
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

    /// Opens a Duck.ai voice chat. If the same window already has a tab hosting an active voice
    /// session (signalled by Duck.ai's `voiceSessionStarted` user-script message), focuses that
    /// tab instead of opening a new one. Otherwise opens a fresh tab and hands off `mode: voice-mode`
    /// via the prompt payload — same handoff mechanism image generation uses.
    ///
    /// On the focus-existing branch the prompt handler is intentionally NOT updated: the existing
    /// voice tab keeps its in-progress state. Mirrors Windows-browser's `WillActivateExistingVoiceTab`
    /// guard, which prevents a stale cached prompt from overriding the next real submission.
    ///
    /// - Parameters:
    ///   - sourceCollection: The `TabCollectionViewModel` of the window the request originated
    ///     from. Used to scope the lookup to that window — voice in window A doesn't focus a
    ///     voice tab in window B. Pass the user-facing window's TCVM rather than a tab so the
    ///     scope is unambiguous when the source is a pinned tab (pinned tabs are shared across
    ///     windows; a tab-only argument leaves the source-window ambiguous).
    ///   - behavior: The `LinkOpenBehavior` used when opening a fresh voice tab.
    @MainActor
    func openVoiceSession(inSourceCollection sourceCollection: TabCollectionViewModel?, behavior: LinkOpenBehavior)
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

        case .existingChat(let chatId):
            let chatURL = buildChatURL(for: chatId)
            aiChatTabManaging.openAIChat(chatURL, with: behavior, hasPrompt: false)

        case .mode(let mode):
            let prompt = AIChatNativePrompt.queryPrompt("", autoSubmit: false, mode: mode)
            promptHandler.setData(prompt)
            aiChatTabManaging.openAIChat(aiChatRemoteSettings.aiChatURL, with: behavior, hasPrompt: true)

        case .openSettings:
            aiChatTabManaging.insertAIChatTabRequestingOpenSettings(with: aiChatRemoteSettings.aiChatURL)
        }
    }

    @MainActor
    func openNewAIChat(in linkOpenBehavior: LinkOpenBehavior) {
        openAIChatTab(with: .newChat, behavior: linkOpenBehavior)
    }

    @MainActor
    func openVoiceSession(inSourceCollection sourceCollection: TabCollectionViewModel?, behavior: LinkOpenBehavior) {
        if aiChatTabManaging.focusActiveVoiceSessionTab(inSourceCollection: sourceCollection) {
            return
        }
        openAIChatTab(with: .mode(AIChatNativePrompt.voiceMode), behavior: behavior)
    }

    // MARK: - Private Helpers

    @MainActor
    private func openAIChatTab(query: String?, with linkOpenBehavior: LinkOpenBehavior, autoSubmit: Bool) {
        if let query = query {
            promptHandler.setData(.queryPrompt(query, autoSubmit: autoSubmit))
        }
        aiChatTabManaging.openAIChat(aiChatRemoteSettings.aiChatURL, with: linkOpenBehavior, hasPrompt: query != nil)
    }

    /// Builds a URL to open an existing chat by its ID.
    /// - Parameter chatId: The unique identifier of the chat to open.
    /// - Returns: A URL with the chatID query parameter.
    private func buildChatURL(for chatId: String) -> URL {
        guard var components = URLComponents(url: aiChatRemoteSettings.aiChatURL, resolvingAgainstBaseURL: false) else {
            return aiChatRemoteSettings.aiChatURL
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "chatID", value: chatId))
        components.queryItems = queryItems

        return components.url ?? aiChatRemoteSettings.aiChatURL
    }
}

protocol AIChatTabManaging {
    @MainActor
    func openAIChat(_ url: URL, with behavior: LinkOpenBehavior, hasPrompt: Bool)

    @MainActor
    func insertAIChatTab(with url: URL, payload: AIChatPayload)

    @MainActor
    func insertAIChatTab(with url: URL, restorationData: AIChatRestorationData)

    /// Inserts a new Duck.ai tab and arms its `AIChatUserScript` to push the open-settings
    /// action once the page's subscriptions are wired. Used by Settings → AI Features →
    /// "Open Duck.ai Settings".
    @MainActor
    func insertAIChatTabRequestingOpenSettings(with url: URL)

    /// If a tab in `sourceCollection`'s window currently hosts an active Duck.ai voice session,
    /// focuses that window and selects the tab. When the original session was hosted in a Duck.ai
    /// sidebar, also surfaces the sidebar so the user lands on the in-progress voice UI.
    /// Returns `true` on success so callers can short-circuit before opening a new tab.
    @MainActor
    func focusActiveVoiceSessionTab(inSourceCollection sourceCollection: TabCollectionViewModel?) -> Bool
}

extension WindowControllersManager: AIChatTabManaging {

    /// Opens an AI chat URL in the application.
    ///
    /// - Parameters:
    ///   - url: The AI chat URL to open.
    ///   - linkOpenBehavior: Specifies where to open the URL. Defaults to `.currentTab`.
    ///   - hasPrompt: With `.currentTab`, if the current tab is already an AI chat and a prompt was supplied,
    ///                opens a fresh chat in a new selected tab so the loaded conversation is left untouched.
    ///                Ignored for `.newTab` / `.newWindow`, which always open a new tab/window.
    func openAIChat(_ url: URL, with linkOpenBehavior: LinkOpenBehavior = .currentTab, hasPrompt: Bool) {

        let tabCollectionViewModel = mainWindowController?.mainViewController.tabCollectionViewModel

        switch linkOpenBehavior {
        case .currentTab:
            if let currentTab = tabCollectionViewModel?.selectedTab, currentTab.url?.isDuckAIURL == true {
                if hasPrompt {
                    // Omnibar submission while Duck.ai is already loaded: open a fresh chat in a new
                    // selected tab rather than injecting the prompt into the loaded conversation,
                    // which users found confusing.
                    open(url, with: .newTab(selected: true), source: .ui, target: nil)
                } else if url.getParameter(named: "chatID") != nil {
                    // Navigate to a specific existing chat — must load even if already on duck.ai
                    show(url: url, source: .ui, newTab: false)
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
        let newAIChatTab = Tab(content: .url(url, source: .ui), burnerMode: tabCollectionViewModel.burnerMode)
        newAIChatTab.aiChat?.setAIChatNativeHandoffData(payload: payload)
        tabCollectionViewModel.insertOrAppend(tab: newAIChatTab, selected: true)

    }

    func insertAIChatTab(with url: URL, restorationData: AIChat.AIChatRestorationData) {
        guard let tabCollectionViewModel = lastKeyMainWindowController?.mainViewController.tabCollectionViewModel else { return }
        let newAIChatTab = Tab(content: .url(url, source: .ui), burnerMode: tabCollectionViewModel.burnerMode)
        newAIChatTab.aiChat?.setAIChatRestorationData(restorationData)
        tabCollectionViewModel.insertOrAppend(tab: newAIChatTab, selected: true)
    }

    func insertAIChatTabRequestingOpenSettings(with url: URL) {
        guard let tabCollectionViewModel = lastKeyMainWindowController?.mainViewController.tabCollectionViewModel else { return }
        let newAIChatTab = Tab(content: .url(url, source: .ui), burnerMode: tabCollectionViewModel.burnerMode)
        newAIChatTab.aiChat?.requestOpenSettings()
        tabCollectionViewModel.insertOrAppend(tab: newAIChatTab, selected: true)
    }

    @MainActor
    func focusActiveVoiceSessionTab(inSourceCollection sourceCollection: TabCollectionViewModel?) -> Bool {
        guard let target = voiceSessionTracker.findActiveVoiceTab(in: sourceCollection) else {
            return false
        }
        // Find the window controller hosting the target tab and select that tab. `AnyTab` is an
        // enum, so we must pattern-match `.loaded` instead of attempting a class downcast.
        for windowController in mainWindowControllers {
            let tabCollectionViewModel = windowController.mainViewController.tabCollectionViewModel
            guard let index = tabCollectionViewModel.indexInAllTabs(where: { anyTab in
                if case .loaded(let tab) = anyTab { return tab === target }
                return false
            }) else { continue }
            windowController.window?.makeKeyAndOrderFront(self)
            tabCollectionViewModel.select(at: index)
            return true
        }
        return false
    }
}
