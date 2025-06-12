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

import AIChat

protocol AIChatTabOpening {
    @MainActor
    func openAIChatTab(_ query: String?, target: AIChatTabOpenerTarget)

    @MainActor
    func openAIChatTab(_ value: AddressBarTextField.Value, target: AIChatTabOpenerTarget)
}

extension AIChatTabOpening {
    @MainActor
    func openAIChatTab() {
        openAIChatTab(nil, target: .sameTab)
    }
}

enum AIChatTabOpenerTarget {
    case newTabSelected
    case newTabUnselected
    case sameTab
}

struct AIChatTabOpener: AIChatTabOpening {
    private let promptHandler: AIChatPromptHandler
    private let addressBarQueryExtractor: AIChatAddressBarPromptExtractor

    let aiChatRemoteSettings = AIChatRemoteSettings()

    init(promptHandler: AIChatPromptHandler,
         addressBarQueryExtractor: AIChatAddressBarPromptExtractor) {
        self.promptHandler = promptHandler
        self.addressBarQueryExtractor = addressBarQueryExtractor
    }

    @MainActor
    func openAIChatTab(_ value: AddressBarTextField.Value, target: AIChatTabOpenerTarget) {
        let query = addressBarQueryExtractor.queryForValue(value)

        // We don't want to auto-submit if the user is opening duck.ai from the SERP
        // https://app.asana.com/1/137249556945/project/1204167627774280/task/1210024262385459?focus=true
        let shouldAutoSubmit: Bool
        if case let .url(_, url, _) = value {
            shouldAutoSubmit = !url.isDuckDuckGoSearch
        } else {
            shouldAutoSubmit = true
        }
        openAIChatTab(query, target: target, autoSubmit: shouldAutoSubmit)
    }

    @MainActor
    func openAIChatTab(_ query: String?, target: AIChatTabOpenerTarget) {
        openAIChatTab(query, target: target, autoSubmit: true)
    }

    @MainActor
    private func openAIChatTab(_ query: String?, target: AIChatTabOpenerTarget, autoSubmit: Bool) {
        if let query = query {
            promptHandler.setData(.queryPrompt(query, autoSubmit: autoSubmit))
        }
        Application.appDelegate.windowControllersManager.openAIChat(aiChatRemoteSettings.aiChatURL, target: target, hasPrompt: query != nil)
    }
}
