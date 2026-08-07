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
import os.log

/// A seam over the `/models` fetch and the persisted selection, so both can be mocked in tests.
@MainActor
protocol SubscriptionOnboardingAIModelProviding: AnyObject {
    /// Fetches the available models; empty result indicates failure.
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
            // TODO|htang: report this with a pixel in Step 3.
            Logger.subscription.error("Duck.ai onboarding model fetch failed: \(error.localizedDescription, privacy: .public)")
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

/// Backs the Duck.ai onboarding screen, persisting the selected model so the launched chat opens with it.
@MainActor
final class SubscriptionOnboardingDuckAIViewModel: ObservableObject {

    /// The display-ready model list: only those the customer can access, advanced (paid-tier) ones first.
    /// Derived once when the prefetcher resolves rather than recomputed on every read.
    @Published private(set) var availableModels: [AIChatModel] = []
    @Published private(set) var selectedModelID: String?

    /// Whether the progress interstitial is covering the picker while the chat is handed over.
    @Published private(set) var isShowingInterstitial = false

    private let prefetcher: SubscriptionOnboardingPrefetcher
    private weak var delegate: SubscriptionOnboardingSectionDelegate?
    private var cancellables = Set<AnyCancellable>()

    /// Prevents duplicate hand-offs when the interstitial's view is recreated.
    private var didHandOffToChat = false

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

    /// Persists the model selection, marks the step complete, then shows the interstitial. Completion is reported
    /// here (not at hand-off) so the checklist shows Duck.ai finished on the screen launching it.
    func startChat() {
        if let selectedModelID {
            prefetcher.updateSelectedModel(selectedModelID)
        }
        delegate?.sectionDidComplete(.duckAI)
        isShowingInterstitial = true
    }

    /// Requests the chat at most once. Leaves the interstitial up since the launcher dismisses the entire chain.
    func handOffToChat() {
        guard !didHandOffToChat else { return }

        // Nothing can present the chat, so drop the interstitial rather than stranding the customer on a
        // page with no back button and no footer. Deliberately not latched, so a later tap can retry.
        guard let delegate else {
            Logger.subscription.error("Duck.ai onboarding hand-off had no delegate; dismissing the interstitial")
            isShowingInterstitial = false
            return
        }

        didHandOffToChat = true
        delegate.sectionDidRequestDuckAIChat(modelID: selectedModelID)
    }

    /// Leaves Duck.ai without starting a chat, moving the flow to the next section.
    func skip() {
        delegate?.sectionDidRequestAdvance()
    }
}
