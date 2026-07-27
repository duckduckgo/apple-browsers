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

/// A seam over ``UTIModelStore`` so the model fetch and persisted selection can be mocked in tests. The
/// default implementation wraps a live `UTIModelStore` (which fetches `/models`, resolves the customer's
/// tier, and persists the selection to `UserDefaults`), bridging its update callback into a one-shot
/// `async` fetch so callers get the same clean await-once shape as the connection-info service.
@MainActor
protocol SubscriptionOnboardingAIModelProviding: AnyObject {
    var persistedModelID: String? { get }
    /// Fetches the available models, resolving once. An empty result signals "no models" (a failed or empty
    /// `/models` fetch); `UTIModelStore` swallows the underlying error, so failure is inferred from emptiness.
    func fetchModels() async -> [AIChatModel]
    func updateSelectedModel(_ modelID: String)
}

@MainActor
final class DefaultSubscriptionOnboardingAIModelProvider: SubscriptionOnboardingAIModelProviding {
    /// Upper bound on how long the underlying `/models` fetch may run before it's treated as failed, so
    /// `fetchModels()` always resolves even if `UTIModelStore`'s completion callback never arrives.
    private static let fetchTimeout: TimeInterval = 10

    private lazy var store = UTIModelStore(modelsService: AIChatModelsService(),
                                           preferences: AIChatPreferencesPersistor(),
                                           subscriptionManager: AppDependencyProvider.shared.subscriptionManager)

    nonisolated init() {}

    var persistedModelID: String? { store.persistedModelId }

    /// Bridges `UTIModelStore`'s single-slot `onModelsUpdated` callback (which fires on both success and
    /// failure) into a one-shot continuation, racing it against a timeout so this always resolves even if
    /// the callback never arrives.
    func fetchModels() async -> [AIChatModel] {
        let store = self.store
        return await withCheckedContinuation { continuation in
            @MainActor
            func resolve() {
                guard store.onModelsUpdated != nil else { return }
                store.onModelsUpdated = nil
                continuation.resume(returning: store.models)
            }
            store.onModelsUpdated = resolve
            store.fetchModels()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(Self.fetchTimeout * 1_000_000_000))
                resolve()
            }
        }
    }

    func updateSelectedModel(_ modelID: String) { store.updateSelectedModel(modelID, isNewChatContext: true) }
}

/// Backs the Duck.ai onboarding screen: reads the available AI models from the shared
/// ``SubscriptionOnboardingPrefetcher`` (retrying on appearance if the fetch hasn't resolved yet), tracks the
/// selected one, and persists it so the launched web chat opens with it.
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

    /// The currently selected model, resolved from `selectedModelID`.
    var selectedModel: AIChatModel? {
        availableModels.first { $0.id == selectedModelID }
    }

    init(prefetcher: SubscriptionOnboardingPrefetcher,
         delegate: SubscriptionOnboardingSectionDelegate? = nil) {
        self.prefetcher = prefetcher
        self.delegate = delegate
    }

    @MainActor
    private func observePrefetcher() {
        // onAppear can fire more than once without an intervening onDisappear; avoid stacking duplicate sinks.
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

    /// Testing-only: persists the committed model, then asks the flow to dismiss the onboarding sheets and
    /// launch the chat from the main view controller, preselecting the same model.
    @MainActor
    func startChatViaMainViewController() {
        if let selectedModelID {
            prefetcher.updateSelectedModel(selectedModelID)
        }
        delegate?.sectionDidRequestDuckAIChatViaMainViewController(modelID: selectedModelID)
    }

    /// Skips this (currently last) section, finishing the flow.
    @MainActor
    func skip() {
        delegate?.sectionDidRequestAdvance()
    }
}
