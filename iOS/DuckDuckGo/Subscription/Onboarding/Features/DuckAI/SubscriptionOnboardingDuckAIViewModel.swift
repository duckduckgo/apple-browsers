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

/// A seam over ``UTIModelStore`` so the model fetch and persisted selection can be mocked in tests. The
/// default implementation wraps a live `UTIModelStore` (which fetches `/models`)
@MainActor
protocol SubscriptionOnboardingAIModelProviding: AnyObject {
    var persistedModelID: String? { get }
    /// Fetches the available models, resolving once. An empty result signals "no models"; `UTIModelStore` swallows the underlying error, so failure is inferred from emptiness.
    func fetchModels() async -> [AIChatModel]
    func updateSelectedModel(_ modelID: String)
}

@MainActor
final class DefaultSubscriptionOnboardingAIModelProvider: SubscriptionOnboardingAIModelProviding {
    /// Upper bound on how long the underlying `/models` fetch may run before it's treated as failed
    private static let fetchTimeout: TimeInterval = 10

    private let subscriptionManager: any SubscriptionManager

    private lazy var store = UTIModelStore(modelsService: AIChatModelsService(),
                                           preferences: AIChatPreferencesPersistor(),
                                           subscriptionManager: subscriptionManager)

    nonisolated init(subscriptionManager: any SubscriptionManager = AppDependencyProvider.shared.subscriptionManager) {
        self.subscriptionManager = subscriptionManager
    }

    var persistedModelID: String? { store.persistedModelId }

    /// Bridges `UTIModelStore`'s single-slot `onModelsUpdated` callback
    func fetchModels() async -> [AIChatModel] {
        let store = self.store
        return await withCheckedContinuation { continuation in
            var timeoutTask: Task<Void, Never>?
            @MainActor
            func resolve() {
                guard store.onModelsUpdated != nil else { return }
                store.onModelsUpdated = nil
                timeoutTask?.cancel()
                continuation.resume(returning: store.models)
            }
            store.onModelsUpdated = resolve
            store.fetchModels()
            timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(Self.fetchTimeout * 1_000_000_000))
                resolve()
            }
        }
    }

    func updateSelectedModel(_ modelID: String) { store.updateSelectedModel(modelID, isNewChatContext: true) }
}

/// Backs the Duck.ai onboarding screen: reads the available AI models from the shared
/// ``SubscriptionOnboardingPrefetcher`` (retrying on appearance if the fetch hasn't resolved yet), tracks the
/// selected one, and persists it so the launched chat opens with it.
final class SubscriptionOnboardingDuckAIViewModel: ObservableObject {

    @Published private(set) var models: [AIChatModel] = []
    @Published private(set) var selectedModelID: String?

    private let prefetcher: SubscriptionOnboardingPrefetcher
    private(set) weak var delegate: SubscriptionOnboardingSectionDelegate?
    private var cancellables = Set<AnyCancellable>()

    var availableModels: [AIChatModel] {
        let accessible = models.filter { $0.entityHasAccess }
        return accessible.filter(\.isAdvanced) + accessible.filter { !$0.isAdvanced }
    }

    init(prefetcher: SubscriptionOnboardingPrefetcher,
         delegate: SubscriptionOnboardingSectionDelegate? = nil) {
        self.prefetcher = prefetcher
        self.delegate = delegate
    }

    @MainActor
    private func observePrefetcher() {
        guard cancellables.isEmpty else { return }
        prefetcher.$models
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self, case .loaded(let models) = state else { return }
                self.models = models
                if self.selectedModelID == nil {
                    self.selectedModelID = self.availableModels.first?.id
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    func onAppear() {
        observePrefetcher()
        prefetcher.fetchModelsIfNeeded()
    }

    @MainActor
    func onDisappear() {
        cancellables.removeAll()
    }

    /// Updates the on-screen selection only.
    @MainActor
    func select(_ modelID: String) {
        selectedModelID = modelID
    }

    /// Persists the committed model (default or tapped) so the launched chat opens with it, then requests
    /// the chat. 
    @MainActor
    func startChat() {
        if let selectedModelID {
            prefetcher.updateSelectedModel(selectedModelID)
        }
        delegate?.sectionDidRequestDuckAIChat(modelID: selectedModelID)
    }

    /// Skips this (currently last) section, finishing the flow.
    @MainActor
    func skip() {
        delegate?.sectionDidRequestAdvance()
    }
}
