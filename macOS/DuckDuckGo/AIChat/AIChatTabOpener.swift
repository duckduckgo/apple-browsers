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

protocol AIChatTabOpening {
    @MainActor
    func openAIChatTab(_ query: String?, with linkOpenBehavior: LinkOpenBehavior)

    @MainActor
    func openAIChatTab(_ value: AddressBarTextField.Value, with linkOpenBehavior: LinkOpenBehavior)

    @MainActor
    func openNewAIChatTab(_ aiChatURL: URL, with linkOpenBehavior: LinkOpenBehavior)

    @MainActor
    func openNewAIChatTab(withPayload payload: AIChatPayload)

    @MainActor
    func openNewAIChatTab(withChatRestorationData data: AIChatRestorationData)
}

extension AIChatTabOpening {
    @MainActor
    func openAIChatTab() {
        openAIChatTab(nil, with: .currentTab)
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

    @MainActor
    func openAIChatTab(_ value: AddressBarTextField.Value, with linkOpenBehavior: LinkOpenBehavior) {
        let query = addressBarQueryExtractor.queryForValue(value)

        // We don't want to auto-submit if the user is opening duck.ai from the SERP
        // https://app.asana.com/1/137249556945/project/1204167627774280/task/1210024262385459?focus=true
        let shouldAutoSubmit: Bool
        if case let .url(_, url, _) = value {
            shouldAutoSubmit = !url.isDuckDuckGoSearch
        } else {
            shouldAutoSubmit = true
        }
        openAIChatTab(query, with: linkOpenBehavior, autoSubmit: shouldAutoSubmit)
    }

    @MainActor
    func openAIChatTab(_ query: String?, with linkOpenBehavior: LinkOpenBehavior) {
        openAIChatTab(query, with: linkOpenBehavior, autoSubmit: true)
    }

    @MainActor
    func openNewAIChatTab(_ aiChatURL: URL, with linkOpenBehavior: LinkOpenBehavior) {
        windowControllersManager.openAIChat(aiChatURL, with: linkOpenBehavior)
    }

    @MainActor
    private func openAIChatTab(_ query: String?, with linkOpenBehavior: LinkOpenBehavior, autoSubmit: Bool) {
        if let query = query {
            promptHandler.setData(.queryPrompt(query, autoSubmit: autoSubmit))
        }
        windowControllersManager.openAIChat(aiChatRemoteSettings.aiChatURL, with: linkOpenBehavior, hasPrompt: query != nil)
    }

    @MainActor
    func openNewAIChatTab(withPayload payload: AIChatPayload) {
        guard let tabCollectionViewModel = windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel else { return }

        let newAIChatTab = Tab(content: .url(aiChatRemoteSettings.aiChatURL, source: .ui))
        newAIChatTab.aiChat?.setAIChatNativeHandoffData(payload: payload)

        tabCollectionViewModel.insertOrAppend(tab: newAIChatTab, selected: true)
    }

    @MainActor
    func openNewAIChatTab(withChatRestorationData data: AIChatRestorationData) {
        guard let tabCollectionViewModel = windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel else { return }

        let newAIChatTab = Tab(content: .url(aiChatRemoteSettings.aiChatURL, source: .ui))
        newAIChatTab.aiChat?.setAIChatRestorationData(data: data)

        tabCollectionViewModel.insertOrAppend(tab: newAIChatTab, selected: true)
    }
}
