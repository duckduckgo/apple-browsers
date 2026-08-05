//
//  SubscriptionOnboardingDuckAIViewModel.swift
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
import Subscription

/// A seam over the `/models` fetch and the persisted selection, so both can be mocked in tests.
@MainActor
protocol SubscriptionOnboardingAIModelProviding: AnyObject {
    /// Fetches the available models. An empty result signals "no models"; the underlying error is swallowed,
    /// so failure is inferred from emptiness.
    func fetchModels() async -> [AIChatModel]
    func updateSelectedModel(_ modelID: String)
}

@MainActor
final class DefaultSubscriptionOnboardingAIModelProvider: SubscriptionOnboardingAIModelProviding {

    private let modelsService: AIChatModelsProviding
    private var preferences: AIChatPreferencesPersisting
    private let subscriptionManager: any SubscriptionManager

    private var models: [AIChatModel] = []

    init(modelsService: AIChatModelsProviding? = nil,
         preferences: AIChatPreferencesPersisting = AIChatPreferencesPersistor(),
         subscriptionManager: any SubscriptionManager = AppDependencyProvider.shared.subscriptionManager) {
        self.modelsService = modelsService ?? AIChatModelsService()
        self.preferences = preferences
        self.subscriptionManager = subscriptionManager
    }

    func fetchModels() async -> [AIChatModel] {
        let userTier = await AIChatUserTier.resolve(from: subscriptionManager)
        do {
            let response = try await modelsService.fetchModels()
            models = UTIModelStore.resolveModels(from: response.models, userTier: userTier)
        } catch {
            models = []
        }
        return models
    }

    /// Persists the selection the launched chat opens with, mirroring `UTIModelStore`'s new-chat write.
    func updateSelectedModel(_ modelID: String) {
        preferences.selectedModelId = modelID
        preferences.selectedModelShortName = models.first { $0.id == modelID }?.shortName
    }
}

/// Backs the Duck.ai onboarding screen: reads the available AI models from the shared
/// ``SubscriptionOnboardingPrefetcher`` (retrying on appearance if the fetch hasn't resolved yet), tracks the
/// selected one, and persists it so the launched chat opens with it.
@MainActor
final class SubscriptionOnboardingDuckAIViewModel: ObservableObject {

    /// The display-ready model list: only those the customer can access, advanced (paid-tier) ones first.
    /// Derived once when the prefetcher resolves rather than recomputed on every read.
    @Published private(set) var availableModels: [AIChatModel] = []
    @Published private(set) var selectedModelID: String?

    private let prefetcher: SubscriptionOnboardingPrefetcher
    private weak var delegate: SubscriptionOnboardingSectionDelegate?
    private var cancellables = Set<AnyCancellable>()

    init(prefetcher: SubscriptionOnboardingPrefetcher,
         delegate: SubscriptionOnboardingSectionDelegate? = nil) {
        self.prefetcher = prefetcher
        self.delegate = delegate
    }

    private func observePrefetcher() {
        guard cancellables.isEmpty else { return }
        prefetcher.$models
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self, case .loaded(let models) = state else { return }
                self.availableModels = Self.displayModels(from: models)
                if self.selectedModelID == nil {
                    self.selectedModelID = self.availableModels.first?.id
                }
            }
            .store(in: &cancellables)
    }

    /// Drops models the customer has no access to, then puts the advanced ones first.
    private static func displayModels(from models: [AIChatModel]) -> [AIChatModel] {
        let accessible = models.filter { $0.entityHasAccess }
        return accessible.filter(\.isAdvanced) + accessible.filter { !$0.isAdvanced }
    }

    func onAppear() {
        observePrefetcher()
        prefetcher.fetchModelsIfNeeded()
    }

    func onDisappear() {
        cancellables.removeAll()
    }

    /// Updates the on-screen selection only.
    func select(_ modelID: String) {
        selectedModelID = modelID
    }

    /// Persists the committed model (default or tapped) so the launched chat opens with it, then requests
    /// the chat.
    func startChat() {
        if let selectedModelID {
            prefetcher.updateSelectedModel(selectedModelID)
        }
        delegate?.sectionDidRequestDuckAIChat(modelID: selectedModelID)
    }

    /// Skips this (currently last) section, finishing the flow.
    func skip() {
        delegate?.sectionDidRequestAdvance()
    }

    /// Leaves this section, going back to the previous one.
    func goBack() {
        delegate?.sectionDidRequestGoBack()
    }
}
