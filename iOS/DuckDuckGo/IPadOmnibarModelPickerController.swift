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
    private let menuFactory = UnifiedToggleInputModelMenuFactory()
    private let upsellPresenter: DuckAISubscriptionUpselling
    var onModelsUpdated: (() -> Void)?

    /// A model whose selection was blocked behind an upsell; re-applied once a
    /// subscription refresh grants the user access.
    private var pendingGatedModelId: String?

    /// The shared model store. Exposed so the sibling reasoning picker can read the same
    /// selected model / subscription state and avoid a second `/models` fetch.
    var modelStore: UTIModelStore { store }

    init(
        modelsService: AIChatModelsProviding? = nil,
        preferences: AIChatPreferencesPersisting = AIChatPreferencesPersistor(),
        subscriptionManager: any SubscriptionManager = AppDependencyProvider.shared.subscriptionManager,
        aiChatSettings: AIChatSettingsProvider = AIChatSettings(),
        upsellPresenter: DuckAISubscriptionUpselling = DuckAISubscriptionUpsellPresenter()
    ) {
        self.upsellPresenter = upsellPresenter
        store = UTIModelStore(
            modelsService: modelsService ?? AIChatModelsService(
                baseURL: aiChatModelsBaseURL(forChatURL: aiChatSettings.aiChatURL)
            ),
            preferences: preferences,
            subscriptionManager: subscriptionManager
        )
        store.onModelsUpdated = { [weak self] in
            self?.onModelsUpdated?()
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

    func makeMenu(onSelect: @escaping (String) -> Void) -> UIMenu? {
        guard hasModels else { return nil }
        return menuFactory.makeMenu(
            models: store.models,
            selectedId: store.persistedModelId,
            plusSectionTitle: UserText.aiChatPlusModelsSectionHeader,
            proSectionTitle: UserText.aiChatProModelsSectionHeader,
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
                UnifiedToggleInputCoordinatorPixelHelper.fireModelSelectedPixel(modelId: modelId)
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
            UnifiedToggleInputCoordinatorPixelHelper.fireModelSelectedPixel(modelId: modelId)
        }
    }
}
