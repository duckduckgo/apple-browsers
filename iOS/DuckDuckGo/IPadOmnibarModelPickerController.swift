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
    var onModelsUpdated: (() -> Void)?

    init(
        modelsService: AIChatModelsProviding? = nil,
        preferences: AIChatPreferencesPersisting = AIChatPreferencesPersistor(),
        subscriptionManager: any SubscriptionManager = AppDependencyProvider.shared.subscriptionManager,
        aiChatSettings: AIChatSettingsProvider = AIChatSettings()
    ) {
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

    func selectModel(_ modelId: String) {
        store.updateSelectedModel(modelId, isNewChatContext: true)
    }
}
