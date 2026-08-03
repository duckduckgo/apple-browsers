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
        case openCustomizeResponses = "omnibar_openCustomizeResponses"
        case setCustomizeResponsesActive = "omnibar_setCustomizeResponsesActive"
        case getOpenTabs = "omnibar_getOpenTabs"
        case getTabContent = "omnibar_getTabContent"
        case showSubscriptionUpsell = "omnibar_showSubscriptionUpsell"
        case showSubscriptionUpgrade = "omnibar_showSubscriptionUpgrade"
        case confirmDeleteAiChat = "omnibar_confirmDeleteAiChat"
        case removeSuggestion = "omnibar_removeSuggestion"
    }

    private let configProvider: NewTabPageOmnibarConfigProviding
    private let suggestionsProvider: NewTabPageOmnibarSuggestionsProviding
    private let aiChatsProvider: NewTabPageOmnibarAiChatsProviding
    private let modelsProvider: NewTabPageOmnibarModelsProviding?
    private let actionHandler: NewTabPageOmnibarActionsHandling
    private let tabsProvider: NewTabPageOmnibarTabsProviding
    private let subscriptionDialogPresenter: NewTabPageOmnibarSubscriptionDialogPresenting?
    private var cancellables = Set<AnyCancellable>()

    @MainActor
    public init(configProvider: NewTabPageOmnibarConfigProviding,
                suggestionsProvider: NewTabPageOmnibarSuggestionsProviding,
                aiChatsProvider: NewTabPageOmnibarAiChatsProviding,
                modelsProvider: NewTabPageOmnibarModelsProviding? = nil,
                actionHandler: NewTabPageOmnibarActionsHandling,
                tabsProvider: NewTabPageOmnibarTabsProviding,
                subscriptionDialogPresenter: NewTabPageOmnibarSubscriptionDialogPresenting? = nil) {
        self.configProvider = configProvider
        self.suggestionsProvider = suggestionsProvider
        self.aiChatsProvider = aiChatsProvider
        self.modelsProvider = modelsProvider
        self.actionHandler = actionHandler
        self.tabsProvider = tabsProvider
        self.subscriptionDialogPresenter = subscriptionDialogPresenter
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
            configProvider.isAttachTabsEnabledPublisher.map { _ in () }.eraseToAnyPublisher(),
            configProvider.isAIChatDeletionEnabledPublisher.map { _ in () }.eraseToAnyPublisher(),
            configProvider.isSearchSuggestionDeletionEnabledPublisher.map { _ in () }.eraseToAnyPublisher(),
            configProvider.customizeResponsesStatePublisher.map { _ in () }.eraseToAnyPublisher()
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

        modelsProvider?.modelsDidChangePublisher
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
            MessageName.openCustomizeResponses.rawValue: { [weak self] in try await self?.openCustomizeResponses(params: $0, original: $1) },
            MessageName.setCustomizeResponsesActive.rawValue: { [weak self] in try await self?.setCustomizeResponsesActive(params: $0, original: $1) },
            MessageName.getOpenTabs.rawValue: { [weak self] in try await self?.getOpenTabs(params: $0, original: $1) },
            MessageName.getTabContent.rawValue: { [weak self] in try await self?.getTabContent(params: $0, original: $1) },
            MessageName.showSubscriptionUpsell.rawValue: { [weak self] in try await self?.showSubscriptionUpsell(params: $0, original: $1) },
            MessageName.showSubscriptionUpgrade.rawValue: { [weak self] in try await self?.showSubscriptionUpgrade(params: $0, original: $1) },
            MessageName.confirmDeleteAiChat.rawValue: { [weak self] in try await self?.confirmDeleteAiChat(params: $0, original: $1) },
            MessageName.removeSuggestion.rawValue: { [weak self] in try await self?.removeSuggestion(params: $0, original: $1) }
        ])
    }

    @MainActor
    private func getConfig(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        let aiModelSections = await modelsProvider?.fetchAIModelSections()
        let customize = configProvider.customizeResponsesState(requestingWebView: original.webView)
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
            enableCustomizeResponses: configProvider.isCustomizeResponsesEnabled,
            customizeSubLabel: customize.hasCustomization ? customize.subLabel : nil,
            hasCustomization: customize.hasCustomization,
            customizationActive: customize.active,
            enableVoiceChatAccess: configProvider.isVoiceChatAccessEnabled,
            enableAskAiSuggestion: configProvider.showAskAiSuggestion,
            selectedModelId: configProvider.selectedModelId,
            aiModelSections: sectionsForWeb(aiModelSections),
            selectedReasoningEffort: configProvider.selectedReasoningEffort,
            enableAttachTabs: configProvider.isAttachTabsEnabled,
            attachmentLimits: modelsProvider?.attachmentLimits,
            isEligibleForFreeTrial: modelsProvider?.isEligibleForFreeTrial,
            enableAiChatDeletion: configProvider.isAIChatDeletionEnabled,
            enableSearchSuggestionDeletion: configProvider.isSearchSuggestionDeletionEnabled
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
            let item = matchedItem(forModelId: selectedModelId)
            // Reject a model we know is gated; an unmatched id (sections not fetched yet) passes through.
            if item?.isAvailable != false {
                // Only refresh the cached short name when the id changes, so echoing back the same
                // id doesn't null out a valid cache before `lastFetchedSections` is populated.
                let didChangeModelId = configProvider.selectedModelId != selectedModelId
                configProvider.selectedModelId = selectedModelId
                if didChangeModelId {
                    configProvider.selectedModelShortName = item?.shortName
                }
            }
        }
        persistReasoningEffort(from: config)
        return nil
    }

    /// Only persists when the feature is on, the selected model isn't gated, and the value is
    /// supported by that model — guards against a stale value surviving a model/tier change.
    @MainActor
    private func persistReasoningEffort(from config: NewTabPageDataModel.OmnibarConfig) {
        guard configProvider.isReasoningEffortEnabled else { return }
        let incoming = config.selectedReasoningEffort
        guard let incoming else {
            configProvider.selectedReasoningEffort = nil
            return
        }
        let item = matchedItem(forModelId: configProvider.selectedModelId)
        guard item?.isAvailable != false,
              item?.reasoningEfforts.filter(\.isAvailable).map(\.id).contains(incoming) == true
        else { return }
        configProvider.selectedReasoningEffort = incoming
    }

    @MainActor
    private func refreshModelsAndNotify() async {
        _ = await modelsProvider?.fetchAIModelSections()
        notifyConfigUpdated()
    }

    @MainActor
    private func notifyConfigUpdated() {
        let customize = configProvider.customizeResponsesState(requestingWebView: nil)
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
            enableCustomizeResponses: configProvider.isCustomizeResponsesEnabled,
            customizeSubLabel: customize.hasCustomization ? customize.subLabel : nil,
            hasCustomization: customize.hasCustomization,
            customizationActive: customize.active,
            enableVoiceChatAccess: configProvider.isVoiceChatAccessEnabled,
            enableAskAiSuggestion: configProvider.showAskAiSuggestion,
            selectedModelId: configProvider.selectedModelId,
            aiModelSections: sectionsForWeb(modelsProvider?.lastFetchedSections),
            selectedReasoningEffort: configProvider.selectedReasoningEffort,
            enableAttachTabs: configProvider.isAttachTabsEnabled,
            attachmentLimits: modelsProvider?.attachmentLimits,
            isEligibleForFreeTrial: modelsProvider?.isEligibleForFreeTrial,
            enableAiChatDeletion: configProvider.isAIChatDeletionEnabled,
            enableSearchSuggestionDeletion: configProvider.isSearchSuggestionDeletionEnabled
        )
        pushMessage(named: MessageName.onConfigUpdate.rawValue, params: config)
    }

    /// Strips `reasoningEfforts` when the feature is off, so the web hides the picker with no
    /// flag check of its own.
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
                        isAvailable: item.isAvailable,
                        supportsImageUpload: item.supportsImageUpload,
                        supportedTools: item.supportedTools,
                        accessTier: item.accessTier,
                        reasoningEfforts: [],
                        supportedFileTypes: item.supportedFileTypes,
                        upsell: item.upsell
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
            modelId: modelIdForSubmission(action: action),
            images: action.images,
            mode: action.mode,
            toolChoice: action.toolChoice,
            reasoningEffort: reasoningEffortForSubmission(action: action),
            pageContexts: action.pageContext,
            files: action.files
        )
        return nil
    }

    /// Single shared lookup for the gating checks below — avoids re-flattening
    /// `lastFetchedSections` at every call site.
    @MainActor
    private func matchedItem(forModelId modelId: String?) -> NewTabPageDataModel.AIModelItem? {
        modelsProvider?.lastFetchedSections?
            .flatMap(\.items)
            .first(where: { $0.id == modelId })
    }

    /// `nil` if the model is gated — guards a stale or forged `modelId` from reaching a model the
    /// user's tier doesn't grant.
    @MainActor
    private func modelIdForSubmission(action: NewTabPageDataModel.SubmitChatAction) -> String? {
        guard let modelId = action.modelId else { return nil }
        return matchedItem(forModelId: modelId)?.isAvailable == false ? nil : modelId
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

    /// `nil` if the feature is off, no value was sent, the model is gated, or the value isn't
    /// supported by that model — catches stale web state from between a selection and a submission.
    @MainActor
    private func reasoningEffortForSubmission(action: NewTabPageDataModel.SubmitChatAction) -> String? {
        guard configProvider.isReasoningEffortEnabled else { return nil }
        guard let incoming = action.reasoningEffort else { return nil }
        let modelId = action.modelId ?? configProvider.selectedModelId
        let item = matchedItem(forModelId: modelId)
        guard item?.isAvailable != false else { return nil }
        let available = item?.reasoningEfforts.filter(\.isAvailable).map(\.id) ?? []
        return available.contains(incoming) ? incoming : nil
    }

    private func getAiChats(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let request: NewTabPageDataModel.OmnibarGetAiChatsRequest = DecodableHelper.decode(from: params) else {
            return nil
        }
        return await aiChatsProvider.aiChats(query: request.query, requestingWebView: original.webView)
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

    @MainActor
    private func showSubscriptionUpsell(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        let action: NewTabPageDataModel.ShowSubscriptionUpsellAction? = DecodableHelper.decode(from: params)
        await subscriptionDialogPresenter?.showSubscriptionUpsellDialog(source: action?.source ?? .model)
        return nil
    }

    @MainActor
    private func showSubscriptionUpgrade(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        let action: NewTabPageDataModel.ShowSubscriptionUpgradeAction? = DecodableHelper.decode(from: params)
        subscriptionDialogPresenter?.showSubscriptionUpgradeDialog(source: action?.source ?? .model)
        return nil
    }

    @MainActor
    private func confirmDeleteAiChat(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard configProvider.isAIChatDeletionEnabled,
              let action: NewTabPageDataModel.ConfirmDeleteAiChatAction = DecodableHelper.decode(from: params) else {
            return NewTabPageDataModel.ConfirmDeleteAiChatResponse(action: .none)
        }
        let confirmed = await actionHandler.confirmDeleteAiChat(chatId: action.chatId, title: action.title, sourceWindow: original.webView?.window)
        return NewTabPageDataModel.ConfirmDeleteAiChatResponse(action: confirmed ? .delete : .none)
    }

    @MainActor
    private func removeSuggestion(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard configProvider.isSearchSuggestionDeletionEnabled,
              let action: NewTabPageDataModel.RemoveSuggestionAction = DecodableHelper.decode(from: params) else {
            return nil
        }
        actionHandler.removeSuggestion(action.url)
        return nil
    }

    @MainActor
    private func openCustomizeResponses(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        actionHandler.openCustomizeResponses()
        return nil
    }

    @MainActor
    private func setCustomizeResponsesActive(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let action: NewTabPageDataModel.SetCustomizeResponsesActiveAction = DecodableHelper.decode(from: params) else {
            return nil
        }
        actionHandler.setCustomizeResponsesActive(action.active)
        return nil
    }

}
