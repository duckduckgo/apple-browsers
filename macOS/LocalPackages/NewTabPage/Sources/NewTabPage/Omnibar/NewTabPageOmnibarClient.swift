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
import FoundationExtensions

public final class NewTabPageOmnibarClient: NewTabPageUserScriptClient {

    enum MessageName: String, CaseIterable {
        case getConfig = "omnibar_getConfig"
        case setConfig = "omnibar_setConfig"
        case getSuggestions = "omnibar_getSuggestions"
        case submitSearch = "omnibar_submitSearch"
        case onConfigUpdate = "omnibar_onConfigUpdate"
        case openSuggestion = "omnibar_openSuggestion"
        case submitChat = "omnibar_submitChat"
        case getAiChats = "omnibar_getAiChats"
        case openAiChat = "omnibar_openAiChat"
        case viewAllAIChats = "omnibar_viewAllAIChats"
        case getOpenTabs = "omnibar_getOpenTabs"
        case getTabContent = "omnibar_getTabContent"
    }

    private let configProvider: NewTabPageOmnibarConfigProviding
    private let suggestionsProvider: NewTabPageOmnibarSuggestionsProviding
    private let aiChatsProvider: NewTabPageOmnibarAiChatsProviding
    private let modelsProvider: NewTabPageOmnibarModelsProviding?
    private let actionHandler: NewTabPageOmnibarActionsHandling
    private let tabsProvider: NewTabPageOmnibarTabsProviding
    private var cancellables = Set<AnyCancellable>()

    public init(configProvider: NewTabPageOmnibarConfigProviding,
                suggestionsProvider: NewTabPageOmnibarSuggestionsProviding,
                aiChatsProvider: NewTabPageOmnibarAiChatsProviding,
                modelsProvider: NewTabPageOmnibarModelsProviding? = nil,
                actionHandler: NewTabPageOmnibarActionsHandling,
                tabsProvider: NewTabPageOmnibarTabsProviding) {
        self.configProvider = configProvider
        self.suggestionsProvider = suggestionsProvider
        self.aiChatsProvider = aiChatsProvider
        self.modelsProvider = modelsProvider
        self.actionHandler = actionHandler
        self.tabsProvider = tabsProvider
        super.init()

        Publishers.MergeMany(
            configProvider.isAIChatShortcutEnabledPublisher.map { _ in () }.eraseToAnyPublisher(),
            configProvider.isAIChatSettingVisiblePublisher.map { _ in () }.eraseToAnyPublisher(),
            configProvider.modePublisher.map { _ in () }.eraseToAnyPublisher(),
            configProvider.showViewAllAiChatsPublisher.map { _ in () }.eraseToAnyPublisher(),
            configProvider.selectedModelIdPublisher.map { _ in () }.eraseToAnyPublisher(),
            configProvider.selectedReasoningEffortPublisher.map { _ in () }.eraseToAnyPublisher(),
            configProvider.isVoiceChatAccessEnabledPublisher.map { _ in () }.eraseToAnyPublisher(),
            configProvider.showAskAiSuggestionPublisher.map { _ in () }.eraseToAnyPublisher(),
            configProvider.isAttachTabsEnabledPublisher.map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.notifyConfigUpdated()
            }
        }
        .store(in: &cancellables)

        configProvider.modePublisher
            .filter { $0 == .ai }
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshModelsAndNotify()
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
            MessageName.submitChat.rawValue: { [weak self] in try await self?.submitChat(params: $0, original: $1) },
            MessageName.getAiChats.rawValue: { [weak self] in try await self?.getAiChats(params: $0, original: $1) },
            MessageName.openAiChat.rawValue: { [weak self] in try await self?.openAiChat(params: $0, original: $1) },
            MessageName.viewAllAIChats.rawValue: { [weak self] in try await self?.viewAllAIChats(params: $0, original: $1) },
            MessageName.getOpenTabs.rawValue: { [weak self] in try await self?.getOpenTabs(params: $0, original: $1) },
            MessageName.getTabContent.rawValue: { [weak self] in try await self?.getTabContent(params: $0, original: $1) }
        ])
    }

    @MainActor
    private func getConfig(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        let aiModelSections = await modelsProvider?.fetchAIModelSections()
        return NewTabPageDataModel.OmnibarConfig(
            mode: configProvider.mode,
            enableAi: configProvider.isAIChatShortcutEnabled,
            showAiSetting: configProvider.isAIChatSettingVisible,
            showCustomizePopover: configProvider.showCustomizePopover,
            enableRecentAiChats: configProvider.isAIChatRecentChatsEnabled,
            showViewAllAiChats: configProvider.showViewAllAiChats,
            enableAiChatTools: configProvider.isAIChatToolsEnabled,
            enableImageGeneration: configProvider.isImageGenerationEnabled,
            enableWebSearch: configProvider.isWebSearchEnabled,
            enableVoiceChatAccess: configProvider.isVoiceChatAccessEnabled,
            enableAskAiSuggestion: configProvider.showAskAiSuggestion,
            selectedModelId: configProvider.selectedModelId,
            aiModelSections: sectionsForWeb(aiModelSections),
            selectedReasoningEffort: configProvider.selectedReasoningEffort,
            enableAttachTabs: configProvider.isAttachTabsEnabled,
            attachmentLimits: modelsProvider?.attachmentLimits
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
        if let selectedModelId = config.selectedModelId {
            // Only refresh the cached short name when the id actually changes. Echoing back the
            // same id (e.g. on web launch) must not overwrite a valid cache with `nil` just
            // because `lastFetchedSections` hasn't been populated yet on this side.
            let didChangeModelId = configProvider.selectedModelId != selectedModelId
            configProvider.selectedModelId = selectedModelId
            if didChangeModelId {
                configProvider.selectedModelShortName = modelsProvider?.lastFetchedSections?
                    .flatMap(\.items)
                    .first(where: { $0.id == selectedModelId })?
                    .shortName
            }
        }
        persistReasoningEffort(from: config)
        return nil
    }

    /// Persists the incoming reasoning effort only when the feature is enabled and the value is
    /// supported by the currently selected model. This prevents a stale or unsupported value
    /// (e.g. from a web state that predates a model switch or a tier change) from being stored.
    @MainActor
    private func persistReasoningEffort(from config: NewTabPageDataModel.OmnibarConfig) {
        guard configProvider.isReasoningEffortEnabled else { return }
        let incoming = config.selectedReasoningEffort
        guard let incoming else {
            configProvider.selectedReasoningEffort = nil
            return
        }
        let selectedModelId = configProvider.selectedModelId
        let supportedForCurrentModel = modelsProvider?.lastFetchedSections?
            .flatMap(\.items)
            .first(where: { $0.id == selectedModelId })?
            .supportedReasoningEffort ?? []
        guard supportedForCurrentModel.contains(incoming) else { return }
        configProvider.selectedReasoningEffort = incoming
    }

    @MainActor
    private func refreshModelsAndNotify() async {
        _ = await modelsProvider?.fetchAIModelSections()
        notifyConfigUpdated()
    }

    @MainActor
    private func notifyConfigUpdated() {
        let config = NewTabPageDataModel.OmnibarConfig(
            mode: configProvider.mode,
            enableAi: configProvider.isAIChatShortcutEnabled,
            showAiSetting: configProvider.isAIChatSettingVisible,
            showCustomizePopover: configProvider.showCustomizePopover,
            enableRecentAiChats: configProvider.isAIChatRecentChatsEnabled,
            showViewAllAiChats: configProvider.showViewAllAiChats,
            enableAiChatTools: configProvider.isAIChatToolsEnabled,
            enableImageGeneration: configProvider.isImageGenerationEnabled,
            enableWebSearch: configProvider.isWebSearchEnabled,
            enableVoiceChatAccess: configProvider.isVoiceChatAccessEnabled,
            enableAskAiSuggestion: configProvider.showAskAiSuggestion,
            selectedModelId: configProvider.selectedModelId,
            aiModelSections: sectionsForWeb(modelsProvider?.lastFetchedSections),
            selectedReasoningEffort: configProvider.selectedReasoningEffort,
            enableAttachTabs: configProvider.isAttachTabsEnabled,
            attachmentLimits: modelsProvider?.attachmentLimits
        )
        pushMessage(named: MessageName.onConfigUpdate.rawValue, params: config)
    }

    /// Native is the single point of control for rollout: strip `supportedReasoningEffort` from
    /// every item when the feature is disabled, so the web app never sees a non-empty list and
    /// the picker stays hidden without any flag check on the web side.
    @MainActor
    private func sectionsForWeb(_ sections: [NewTabPageDataModel.AIModelSection]?) -> [NewTabPageDataModel.AIModelSection]? {
        guard let sections else { return nil }
        guard !configProvider.isReasoningEffortEnabled else { return sections }
        return sections.map { section in
            NewTabPageDataModel.AIModelSection(
                header: section.header,
                items: section.items.map { item in
                    NewTabPageDataModel.AIModelItem(
                        id: item.id,
                        name: item.name,
                        shortName: item.shortName,
                        isEnabled: item.isEnabled,
                        supportsImageUpload: item.supportsImageUpload,
                        supportedTools: item.supportedTools,
                        supportedReasoningEffort: [],
                        supportedFileTypes: item.supportedFileTypes
                    )
                }
            )
        }
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
        await actionHandler.submitChat(
            action.chat,
            target: action.target,
            modelId: action.modelId,
            images: action.images,
            mode: action.mode,
            toolChoice: action.toolChoice,
            reasoningEffort: reasoningEffortForSubmission(action: action),
            pageContexts: action.pageContext,
            files: action.files
        )
        return nil
    }

    @MainActor
    private func getOpenTabs(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        return NewTabPageDataModel.OmnibarGetOpenTabsResponse(tabs: await tabsProvider.openTabs(requestingWebView: original.webView))
    }

    @MainActor
    private func getTabContent(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let request: NewTabPageDataModel.OmnibarGetTabContentRequest = DecodableHelper.decode(from: params) else {
            return NewTabPageDataModel.OmnibarGetTabContentResponse(pageContext: nil)
        }
        return NewTabPageDataModel.OmnibarGetTabContentResponse(pageContext: await tabsProvider.tabContent(tabId: request.tabId, requestingWebView: original.webView))
    }

    /// Returns the reasoning effort to attach to this submission, or `nil` if the feature is
    /// disabled, the web didn't send a value, or the value isn't supported by the submission's
    /// model. Enforcing support at submit time catches stale web state where the models list
    /// changed between a selection and a submission.
    @MainActor
    private func reasoningEffortForSubmission(action: NewTabPageDataModel.SubmitChatAction) -> String? {
        guard configProvider.isReasoningEffortEnabled else { return nil }
        guard let incoming = action.reasoningEffort else { return nil }
        let modelId = action.modelId ?? configProvider.selectedModelId
        let supported = modelsProvider?.lastFetchedSections?
            .flatMap(\.items)
            .first(where: { $0.id == modelId })?
            .supportedReasoningEffort ?? []
        return supported.contains(incoming) ? incoming : nil
    }

    private func getAiChats(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let request: NewTabPageDataModel.OmnibarGetAiChatsRequest = DecodableHelper.decode(from: params) else {
            return nil
        }
        return await aiChatsProvider.aiChats(query: request.query)
    }

    private func openAiChat(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let action: NewTabPageDataModel.OpenAiChatAction = DecodableHelper.decode(from: params) else {
            return nil
        }
        await actionHandler.openAiChat(action.chatId, isPinned: action.isPinned ?? false, trigger: action.trigger ?? .mouse, target: action.target)
        return nil
    }

    private func viewAllAIChats(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let action: NewTabPageDataModel.ViewAllAiChatsAction = DecodableHelper.decode(from: params) else {
            return nil
        }
        await actionHandler.viewAllAiChats(target: action.target)
        return nil
    }

}
