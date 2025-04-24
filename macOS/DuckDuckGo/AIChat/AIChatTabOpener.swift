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
        openAIChatTab(query, target: target)
    }

    @MainActor
    func openAIChatTab(_ query: String?, target: AIChatTabOpenerTarget) {
        if let query = query {
            promptHandler.setData(query)
        }
        WindowControllersManager.shared.openAIChat(aiChatRemoteSettings.aiChatURL, target: target, hasPrompt: query != nil)
    }
}
