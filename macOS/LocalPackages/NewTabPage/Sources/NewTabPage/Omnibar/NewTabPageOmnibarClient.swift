//
//  NewTabPageOmnibarClient.swift
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

import WebKit
import Combine
import Common

public final class NewTabPageOmnibarClient: NewTabPageUserScriptClient {

    enum MessageName: String, CaseIterable {
        case getConfig = "omnibar_getConfig"
        case setConfig = "omnibar_setConfig"
        case getSuggestions = "omnibar_getSuggestions"
        case submitSearch = "omnibar_submitSearch"
        case onConfigUpdate = "omnibar_onConfigUpdate"
        case openSuggestion = "omnibar_openSuggestion"
        case submitChat = "omnibar_submitChat"
    }

    private let configProvider: NewTabPageOmnibarConfigProviding
    private let suggestionsProvider: NewTabPageOmnibarSuggestionsProviding
    private let actionHandler: NewTabPageOmnibarActionsHandling
    private var cancellables = Set<AnyCancellable>()

    public init(configProvider: NewTabPageOmnibarConfigProviding,
                suggestionsProvider: NewTabPageOmnibarSuggestionsProviding,
                actionHandler: NewTabPageOmnibarActionsHandling) {
        self.configProvider = configProvider
        self.suggestionsProvider = suggestionsProvider
        self.actionHandler = actionHandler
        super.init()

        Publishers.Merge3(
            configProvider.isAIChatShortcutEnabledPublisher,
            configProvider.isAIChatSettingVisiblePublisher,
            configProvider.showCustomizePopoverPublisher
        )
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.notifyConfigUpdated()
            }
        }
        .store(in: &cancellables)
    }

    public override func registerMessageHandlers(for userScript: NewTabPageUserScript) {
        userScript.registerMessageHandlers([
            MessageName.getConfig.rawValue: { [weak self] in try await self?.getConfig(params: $0, original: $1) },
            MessageName.setConfig.rawValue: { [weak self] in try await self?.setConfig(params: $0, original: $1) },
            MessageName.getSuggestions.rawValue: { [weak self] in try await self?.getSuggestions(params: $0, original: $1) },
            MessageName.submitSearch.rawValue: { [weak self] in try await self?.submitSearch(params: $0, original: $1) },
            MessageName.openSuggestion.rawValue: { [weak self] in try await self?.openSuggestion(params: $0, original: $1) },
            MessageName.submitChat.rawValue: { [weak self] in try await self?.submitChat(params: $0, original: $1) }
        ])
    }

    @MainActor
    private func getConfig(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        // Count the number of popover presentations
        if configProvider.showCustomizePopover {
            configProvider.customizePopoverPresentationCount += 1
        }

        return NewTabPageDataModel.OmnibarConfig(
            mode: configProvider.mode,
            enableAi: configProvider.isAIChatShortcutEnabled,
            showAiSetting: configProvider.isAIChatSettingVisible,
            showCustomizePopover: configProvider.showCustomizePopover
        )
    }

    @MainActor
    private func setConfig(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let config: NewTabPageDataModel.OmnibarConfig = DecodableHelper.decode(from: params) else {
            return nil
        }
        configProvider.mode = config.mode
        configProvider.isAIChatShortcutEnabled = config.enableAi
        if let showCustomizePopover = config.showCustomizePopover {
            configProvider.showCustomizePopover = showCustomizePopover
        }
        return nil
    }

    @MainActor
    private func notifyConfigUpdated() {
        let config = NewTabPageDataModel.OmnibarConfig(
            mode: configProvider.mode,
            enableAi: configProvider.isAIChatShortcutEnabled,
            showAiSetting: configProvider.isAIChatSettingVisible,
            showCustomizePopover: configProvider.showCustomizePopover
        )
        pushMessage(named: MessageName.onConfigUpdate.rawValue, params: config)
    }

    private func getSuggestions(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let request: NewTabPageDataModel.OmnibarGetSuggestionsRequest = DecodableHelper.decode(from: params) else {
            return nil
        }
        return NewTabPageDataModel.SuggestionsData(suggestions: await suggestionsProvider.suggestions(for: request.term))
    }

    private func submitSearch(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let action: NewTabPageDataModel.SubmitSearchAction = DecodableHelper.decode(from: params) else {
            return nil
        }
        await actionHandler.submitSearch(action.term, target: action.target)
        return nil
    }

    private func openSuggestion(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let action: NewTabPageDataModel.OpenSuggestionAction = DecodableHelper.decode(from: params) else {
            return nil
        }
        await actionHandler.openSuggestion(action.suggestion, target: action.target)
        return nil
    }

    private func submitChat(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let action: NewTabPageDataModel.SubmitChatAction = DecodableHelper.decode(from: params) else {
            return nil
        }
        await actionHandler.submitChat(action.chat, target: action.target)
        return nil
    }

}
