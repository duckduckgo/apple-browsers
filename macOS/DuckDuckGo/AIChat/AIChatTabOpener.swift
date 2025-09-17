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

enum AIChatContent {
    case empty
    case query(String?)
    case addressBarValue(AddressBarTextField.Value)
    case url(URL)
    case payload(AIChatPayload)
    case restoration(AIChatRestorationData)
}

protocol AIChatTabOpening {
    @MainActor
    func openAIChatTab(with content: AIChatContent, behavior: LinkOpenBehavior)

    @MainActor
    func openNewAIChat(in linkOpenBehavior: LinkOpenBehavior)
}

struct AIChatTabOpener: AIChatTabOpening {
    private let promptHandler: AIChatPromptHandler
    private let addressBarQueryExtractor: AIChatAddressBarPromptExtractor
    private let aiChatTabManaging: AIChatTabManaging

    let aiChatRemoteSettings = AIChatRemoteSettings()

    init(
        promptHandler: AIChatPromptHandler,
        addressBarQueryExtractor: AIChatAddressBarPromptExtractor,
        aiChatTabManaging: AIChatTabManaging
    ) {
        self.promptHandler = promptHandler
        self.addressBarQueryExtractor = addressBarQueryExtractor
        self.aiChatTabManaging = aiChatTabManaging
    }

    // MARK: - New Simplified API

    @MainActor
    func openAIChatTab(with content: AIChatContent, behavior: LinkOpenBehavior) {
        switch content {
        case .empty:
            openAIChatTab(query: nil, with: behavior, autoSubmit: true)

        case .query(let query):
            openAIChatTab(query: query, with: behavior, autoSubmit: true)

        case .addressBarValue(let value):
            let query = addressBarQueryExtractor.queryForValue(value)
            // We don't want to auto-submit if the user is opening duck.ai from the SERP
            let shouldAutoSubmit: Bool
            if case let .url(_, url, _) = value {
                shouldAutoSubmit = !url.isDuckDuckGoSearch
            } else {
                shouldAutoSubmit = true
            }
            openAIChatTab(query: query, with: behavior, autoSubmit: shouldAutoSubmit)

        case .url(let url):
            aiChatTabManaging.openAIChat(url, with: behavior)

        case .payload(let payload):
            aiChatTabManaging.insertAIChatTab(with: aiChatRemoteSettings.aiChatURL, payload: payload)
        case .restoration(let data):
            aiChatTabManaging.insertAIChatTab(with: aiChatRemoteSettings.aiChatURL, restorationData: data)
        }
    }

    @MainActor
    func openNewAIChat(in linkOpenBehavior: LinkOpenBehavior) {
        openAIChatTab(with: .empty, behavior: linkOpenBehavior)
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
    func openAIChat(_ url: URL, with behavior: LinkOpenBehavior)

    @MainActor
    func openAIChat(_ url: URL, with behavior: LinkOpenBehavior, hasPrompt: Bool)

    @MainActor
    func insertAIChatTab(with url: URL, payload: AIChatPayload)

    @MainActor
    func insertAIChatTab(with url: URL, restorationData: AIChatRestorationData)
}

extension WindowControllersManager: AIChatTabManaging {

    func openAIChat(_ url: URL, with linkOpenBehavior: LinkOpenBehavior = .currentTab) {
        openAIChat(url, with: linkOpenBehavior, hasPrompt: false)
    }

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
//        let newAIChatTab = Tab(content: .url(aiChatRemoteSettings.aiChatURL, source: .ui))
        let newAIChatTab = Tab(content: .url(url, source: .ui))
        newAIChatTab.aiChat?.setAIChatNativeHandoffData(payload: payload)
        tabCollectionViewModel.insertOrAppend(tab: newAIChatTab, selected: true)

    }

    func insertAIChatTab(with url: URL, restorationData: AIChat.AIChatRestorationData) {
        guard let tabCollectionViewModel = lastKeyMainWindowController?.mainViewController.tabCollectionViewModel else { return }
//        let newAIChatTab = Tab(content: .url(aiChatRemoteSettings.aiChatURL, source: .ui))
        let newAIChatTab = Tab(content: .url(url, source: .ui))
        newAIChatTab.aiChat?.setAIChatRestorationData(data: restorationData)
        tabCollectionViewModel.insertOrAppend(tab: newAIChatTab, selected: true)
    }
}
