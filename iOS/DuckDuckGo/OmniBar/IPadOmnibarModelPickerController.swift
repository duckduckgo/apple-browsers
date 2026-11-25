//
//  IPadOmnibarModelPickerController.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import Combine
import PrivacyConfig
import Subscription
import UIKit

/// Drives the Duck.ai model picker shown in the iPad address bar's expanded
/// AI-chat input area.
///
/// This is a thin wrapper around the shared `UTIModelStore` and
/// `UnifiedToggleInputModelMenuFactory` used by the iPhone picker — the iPad
/// reuses the same model fetch / selection / persistence logic so the chosen
/// model is remembered and stays consistent across all Duck.ai surfaces.
@MainActor
final class IPadOmnibarModelPickerController {

    private let store: UTIModelStore
    private let menuFactory: UnifiedToggleInputModelMenuFactory
    private let upsellPresenter: DuckAISubscriptionUpselling
    let startsNewChatsOnDefault: Bool
    var onModelsUpdated: (() -> Void)?

    /// A model whose selection was blocked behind an upsell; re-applied once a
    /// subscription refresh grants the user access.
    private var pendingGatedModelId: String?

    /// The shared model store. Exposed so the sibling reasoning picker can read the same
    /// selected model / subscription state and avoid a second `/models` fetch.
    var modelStore: UTIModelStore { store }

    private let duckAiNativeStorageHandler: DuckAiNativeStorageHandling?
    private let duckAiFireModeStorageHandler: DuckAiNativeStorageHandling?

    init(
        modelsService: AIChatModelsProviding? = nil,
        preferences: AIChatPreferencesPersisting = AIChatPreferencesPersistor(),
        subscriptionManager: any SubscriptionManager = AppDependencyProvider.shared.subscriptionManager,
        aiChatSettings: AIChatSettingsProvider = AIChatSettings(),
        upsellPresenter: DuckAISubscriptionUpselling? = nil,
        updatedModelPickerFeature: UpdatedModelPickerFeatureProviding = UpdatedModelPickerFeature(),
        startsNewChatsOnDefault: Bool = false,
        duckAiNativeStorageHandler: DuckAiNativeStorageHandling? = nil,
        duckAiFireModeStorageHandler: DuckAiNativeStorageHandling? = nil,
        featureFlagger: FeatureFlagger
    ) {
        self.duckAiNativeStorageHandler = duckAiNativeStorageHandler
        self.duckAiFireModeStorageHandler = duckAiFireModeStorageHandler
        let isUpdatedModelPickerEnabled = updatedModelPickerFeature.isAvailable
        self.startsNewChatsOnDefault = startsNewChatsOnDefault
        self.upsellPresenter = upsellPresenter ?? DuckAISubscriptionUpsellPresenter(
            policy: DuckAISubscriptionUpsellPolicy(subscriptionManager: subscriptionManager))
        self.menuFactory = UnifiedToggleInputModelMenuFactory(isUpdatedModelPickerEnabled: isUpdatedModelPickerEnabled)
        store = UTIModelStore(
            modelsService: modelsService ?? AIChatModelsService(
                baseURL: AIChatModelsService.baseURL(forChatURL: aiChatSettings.aiChatURL),
                accessTokenProvider: subscriptionManager
            ),
            preferences: preferences,
            subscriptionManager: subscriptionManager,
            isUpdatedModelPickerEnabled: isUpdatedModelPickerEnabled,
            startsNewChatsOnDefault: startsNewChatsOnDefault,
            overLimitNewChatDefaults: Self.overLimitNewChatDefaults(from: duckAiNativeStorageHandler, featureFlagger: featureFlagger),
            userDefaultModelStorage: duckAiNativeStorageHandler
        )
        store.onModelsUpdated = { [weak self] in
            self?.onModelsUpdated?()
        }
    }

    /// Follows the user default in the tab's own storage, so a fire tab sees what was changed in it.
    func refreshFireMode(_ fireMode: Bool) {
        store.observeUserDefaultModel(in: fireMode ? duckAiFireModeStorageHandler : duckAiNativeStorageHandler)
    }

    /// Over the usage limit, new chats start on the default web sends in the usage-limits snapshot.
    private static func overLimitNewChatDefaults(
        from storageHandler: DuckAiNativeStorageHandling?,
        featureFlagger: FeatureFlagger
    ) -> AnyPublisher<AIChatOverLimitNewChatDefault, Never>? {
        storageHandler.map {
            DuckAiUsageLimitsStore(storageHandler: $0, featureFlagger: featureFlagger)
                .overLimitNewChatDefaultPublisher(receivingUpdatesOn: DispatchQueue.main)
        }
    }

    var currentModelLabel: String? {
        menuFactory.selectedShortName(models: store.models, selectedId: store.persistedModelId)
            ?? store.displayShortName
    }

    var hasModels: Bool {
        !store.models.isEmpty
    }

    var currentModelId: String? {
        store.persistedModelId
    }

    func activate() {
        store.fetchModels()
    }

    var liveSelection: UTIModelSelection {
        store.liveSelection
    }

    func apply(_ selection: UTIModelSelection) {
        store.applyPersistedSelection(modelID: selection.modelID, reasoningMode: selection.reasoningMode)
    }

    func makeMenu(onSelect: @escaping (String) -> Void) -> UIMenu? {
        guard hasModels else { return nil }

        return menuFactory.makeMenu(
            models: store.models,
            selectedId: store.persistedModelId,
            userTier: store.subscriptionState.userTier,
            freeTrialEligibility: store.freeTrialEligibility,
            allowsSubscriptionUpsell: store.allowsSubscriptionUpsell,
            onSelect: onSelect
        )
    }

    /// Selects the model if the user has access; otherwise routes to the matching subscription
    /// upsell (mirrors the iPhone `UnifiedToggleInputCoordinator.handleModelSelection`).
    func handleModelSelection(_ modelId: String) {
        guard let model = store.models.first(where: { $0.id == modelId }) else { return }

        if model.entityHasAccess {
            pendingGatedModelId = nil
            let isNewSelection = modelId != store.persistedModelId
            store.updateSelectedModel(modelId, isNewChatContext: true)
            if isNewSelection {
                UnifiedToggleInputCoordinatorPixelHelper.fireModelSelectedPixel(modelId: modelId, surface: .addressBar)
            }
        } else if routeGatedModelSelection(model) {
            // Remember the gated model so a post-purchase `/models` refresh can apply it.
            pendingGatedModelId = modelId
        }
    }

    /// Re-applies a model selection that was blocked behind an upsell once a subscription
    /// refresh has granted the user access. Invoked after `/models` re-fetches.
    func handleModelsUpdated() {
        applyPendingGatedModelSelectionIfPossible()
    }

    // MARK: - Private

    @discardableResult
    private func routeGatedModelSelection(_ model: AIChatModel) -> Bool {
        guard let requiredTier = model.lowestPublicAccessTier else { return false }
        return upsellPresenter.routeGatedSelection(
            requiredTier: requiredTier,
            userTier: store.subscriptionState.userTier,
            source: .modelPicker,
            isAITabState: false
        )
    }

    private func applyPendingGatedModelSelectionIfPossible() {
        guard let modelId = pendingGatedModelId,
              store.models.first(where: { $0.id == modelId })?.entityHasAccess == true else {
            return
        }
        pendingGatedModelId = nil
        let isNewSelection = modelId != store.persistedModelId
        store.updateSelectedModel(modelId, isNewChatContext: true)
        if isNewSelection {
            UnifiedToggleInputCoordinatorPixelHelper.fireModelSelectedPixel(modelId: modelId, surface: .addressBar)
        }
    }
}
