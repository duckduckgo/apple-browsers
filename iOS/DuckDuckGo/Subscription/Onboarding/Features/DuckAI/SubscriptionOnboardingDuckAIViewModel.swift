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
    /// Fetches the available models, resolving once. An empty result signals "no models"; `UTIModelStore` swallows the underlying error, so failure is inferred from emptiness.
    func fetchModels() async -> [AIChatModel]
    func updateSelectedModel(_ modelID: String)
}

@MainActor
final class DefaultSubscriptionOnboardingAIModelProvider: SubscriptionOnboardingAIModelProviding {
    /// Upper bound on how long the underlying `/models` fetch may run before it's treated as failed
    private static let fetchTimeout: TimeInterval = 10

    private let store: UTIModelStore

    /// Callers awaiting the in-flight fetch, keyed so a cancelled caller can be resolved on its own.
    /// `UTIModelStore` has a single `onModelsUpdated` slot, so a second fetch would overwrite the first's
    /// callback and leave it suspended forever; instead the callback is armed once below and callers queue here.
    private var pendingContinuations: [UUID: CheckedContinuation<[AIChatModel], Never>] = [:]
    private var isFetching = false
    private var timeoutTask: Task<Void, Never>?

    init(modelsService: AIChatModelsProviding? = nil,
         preferences: AIChatPreferencesPersisting = AIChatPreferencesPersistor(),
         subscriptionManager: any SubscriptionManager = AppDependencyProvider.shared.subscriptionManager) {
        store = UTIModelStore(modelsService: modelsService ?? AIChatModelsService(),
                              preferences: preferences,
                              subscriptionManager: subscriptionManager)
        store.onModelsUpdated = { [weak self] in
            self?.resolvePending()
        }
    }

    deinit {
        timeoutTask?.cancel()
    }

    /// Bridges `UTIModelStore`'s `onModelsUpdated` callback. Concurrent calls share one underlying fetch, and a
    /// caller whose task is cancelled resolves on its own rather than waiting out the timeout.
    func fetchModels() async -> [AIChatModel] {
        let callerID = UUID()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                pendingContinuations[callerID] = continuation
                if Task.isCancelled {
                    resolve(callerID)
                } else {
                    startFetchIfNeeded()
                }
            }
        }, onCancel: {
            Task { @MainActor [weak self] in
                self?.resolve(callerID)
            }
        })
    }

    private func startFetchIfNeeded() {
        guard !isFetching else { return }
        isFetching = true
        store.fetchModels()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.fetchTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.resolvePending()
        }
    }

    /// Resolves a single caller, leaving the shared fetch running for anyone still waiting.
    private func resolve(_ callerID: UUID) {
        pendingContinuations.removeValue(forKey: callerID)?.resume(returning: store.models)
    }

    /// Resumes every queued caller with whatever the store currently holds. Whichever of the store callback
    /// or the timeout arrives first wins; the other becomes a no-op.
    private func resolvePending() {
        guard isFetching else { return }
        isFetching = false
        timeoutTask?.cancel()
        timeoutTask = nil
        let continuations = Array(pendingContinuations.values)
        pendingContinuations.removeAll()
        continuations.forEach { $0.resume(returning: store.models) }
    }

    func updateSelectedModel(_ modelID: String) { store.updateSelectedModel(modelID, isNewChatContext: true) }
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
