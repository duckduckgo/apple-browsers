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

extension AIChatTabOpening {
    @MainActor
    func openNewAIChat(in linkOpenBehavior: LinkOpenBehavior) {
        openAIChatTab(with: .empty, behavior: linkOpenBehavior)
    }
}

struct AIChatTabOpener: AIChatTabOpening {
    private let promptHandler: AIChatPromptHandler
    private let addressBarQueryExtractor: AIChatAddressBarPromptExtractor
    private let windowControllersManager: WindowControllersManagerProtocol

    let aiChatRemoteSettings = AIChatRemoteSettings()

    init(
        promptHandler: AIChatPromptHandler,
        addressBarQueryExtractor: AIChatAddressBarPromptExtractor,
        windowControllersManager: WindowControllersManagerProtocol
    ) {
        self.promptHandler = promptHandler
        self.addressBarQueryExtractor = addressBarQueryExtractor
        self.windowControllersManager = windowControllersManager
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
            windowControllersManager.openAIChat(url, with: behavior)

        case .payload(let payload):
            guard let tabCollectionViewModel = windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel else { return }
            let newAIChatTab = Tab(content: .url(aiChatRemoteSettings.aiChatURL, source: .ui))
            newAIChatTab.aiChat?.setAIChatNativeHandoffData(payload: payload)
            tabCollectionViewModel.insertOrAppend(tab: newAIChatTab, selected: true)

        case .restoration(let data):
            guard let tabCollectionViewModel = windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel else { return }
            let newAIChatTab = Tab(content: .url(aiChatRemoteSettings.aiChatURL, source: .ui))
            newAIChatTab.aiChat?.setAIChatRestorationData(data: data)
            tabCollectionViewModel.insertOrAppend(tab: newAIChatTab, selected: true)
        }
    }

    // MARK: - Private Helper

    @MainActor
    private func openAIChatTab(query: String?, with linkOpenBehavior: LinkOpenBehavior, autoSubmit: Bool) {
        if let query = query {
            promptHandler.setData(.queryPrompt(query, autoSubmit: autoSubmit))
        }
        windowControllersManager.openAIChat(aiChatRemoteSettings.aiChatURL, with: linkOpenBehavior, hasPrompt: query != nil)
    }
}
