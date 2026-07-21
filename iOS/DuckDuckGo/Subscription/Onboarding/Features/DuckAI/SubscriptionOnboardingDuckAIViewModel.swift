//
//  SubscriptionOnboardingDuckAIActivationViewModel.swift
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

import Foundation
import Combine
import AIChat

/// A seam over ``UTIModelStore`` so the model list, persisted selection, and update callback can be mocked
/// in tests. The default implementation wraps a live `UTIModelStore` (which fetches `/models`, resolves the
/// customer's tier, and persists the selection to `UserDefaults`).
@MainActor
protocol SubscriptionOnboardingAIModelProviding: AnyObject {
    var models: [AIChatModel] { get }
    /// The currently persisted (or best-default) model id, once models have resolved.
    var persistedModelID: String? { get }
    /// Called whenever the resolved model list changes.
    var onModelsUpdated: (() -> Void)? { get set }
    func fetchModels()
    func updateSelectedModel(_ modelID: String)
}

@MainActor
final class DefaultSubscriptionOnboardingAIModelProvider: SubscriptionOnboardingAIModelProviding {
    // Built lazily so `init()` stays non-isolated (the default view-model argument is constructed from a
    // non-isolated context); `UTIModelStore` is `@MainActor`, so it's created on first access here.
    private lazy var store = UTIModelStore(modelsService: AIChatModelsService(),
                                           preferences: AIChatPreferencesPersistor(),
                                           subscriptionManager: AppDependencyProvider.shared.subscriptionManager)

    nonisolated init() {}

    var models: [AIChatModel] { store.models }
    var persistedModelID: String? { store.persistedModelId }
    var onModelsUpdated: (() -> Void)? {
        get { store.onModelsUpdated }
        set { store.onModelsUpdated = newValue }
    }

    func fetchModels() { store.fetchModels() }
    func updateSelectedModel(_ modelID: String) { store.updateSelectedModel(modelID, isNewChatContext: true) }
}

/// Backs the Duck.ai onboarding screen: fetches the available AI models, tracks the selected one, and — on
/// "Start Duck.ai Chat" — persists it so the launched web chat opens with it.
final class SubscriptionOnboardingDuckAIViewModel: ObservableObject {

    @Published private(set) var models: [AIChatModel] = []
    @Published private(set) var selectedModelID: String?

    private let modelProvider: SubscriptionOnboardingAIModelProviding
    private weak var delegate: SubscriptionOnboardingSectionDelegate?

    // TODO: display all models, not just those the customer can access. Pending a design decision on how
    // locked (higher-tier) models should appear — e.g. dimmed / non-selectable — before dropping this filter.
    /// The models to show, filtered to those the customer can use and ordered premium-first to match the design.
    var availableModels: [AIChatModel] {
        let accessible = models.filter { $0.entityHasAccess }
        return accessible.filter(\.isAdvanced) + accessible.filter { !$0.isAdvanced }
    }

    init(modelProvider: SubscriptionOnboardingAIModelProviding = DefaultSubscriptionOnboardingAIModelProvider(),
         delegate: SubscriptionOnboardingSectionDelegate? = nil) {
        self.modelProvider = modelProvider
        self.delegate = delegate
    }

    @MainActor
    func onAppear() {
        guard models.isEmpty else { return }
        modelProvider.onModelsUpdated = { [weak self] in
            guard let self else { return }
            self.models = self.modelProvider.models
            if self.selectedModelID == nil {
                self.selectedModelID = self.modelProvider.persistedModelID
            }
        }
        modelProvider.fetchModels()
    }

    /// Updates the on-screen selection only. The choice is persisted on ``startChat()``, so tapping a row and
    /// then skipping never mutates the customer's global model.
    @MainActor
    func select(_ modelID: String) {
        selectedModelID = modelID
    }

    /// Persists the committed model (default or tapped) so the launched chat opens with it, reports the
    /// section complete, and asks the flow to launch Duck.ai chat.
    @MainActor
    func startChat() {
        if let selectedModelID {
            modelProvider.updateSelectedModel(selectedModelID)
        }
        delegate?.sectionDidComplete(.duckAI)
        delegate?.launchDuckAIChat(modelID: selectedModelID)
    }
}
