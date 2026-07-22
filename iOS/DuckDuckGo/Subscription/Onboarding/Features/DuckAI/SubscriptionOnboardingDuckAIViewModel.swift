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
    var persistedModelID: String? { get }
    var onModelsUpdated: (() -> Void)? { get set }
    func fetchModels()
    func updateSelectedModel(_ modelID: String)
}

@MainActor
final class DefaultSubscriptionOnboardingAIModelProvider: SubscriptionOnboardingAIModelProviding {
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

/// Backs the Duck.ai onboarding screen: fetches the available AI models, tracks the selected one, and persists it so the launched web chat opens with it.
final class SubscriptionOnboardingDuckAIViewModel: ObservableObject {

    @Published private(set) var models: [AIChatModel] = []
    @Published private(set) var selectedModelID: String?

    private let modelProvider: SubscriptionOnboardingAIModelProviding
    private weak var delegate: SubscriptionOnboardingSectionDelegate?

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

    /// Updates the on-screen selection only.
    @MainActor
    func select(_ modelID: String) {
        selectedModelID = modelID
    }

    /// Persists the committed model (default or tapped) so the launched chat opens with it
    @MainActor
    func startChat() {
        if let selectedModelID {
            modelProvider.updateSelectedModel(selectedModelID)
        }
        delegate?.sectionDidComplete(.duckAI)
        delegate?.launchDuckAIChat(modelID: selectedModelID)
    }
}
