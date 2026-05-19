//
//  UTIModelStore.swift
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
import os.log
import Subscription

@MainActor
final class UTIModelStore {

    var models: [AIChatModel] = []
    var subscriptionState: SubscriptionState = .free
    var attachmentLimits: AIChatAttachmentTierLimits?

    private let modelsService: AIChatModelsProviding
    private(set) var preferences: AIChatPreferencesPersisting
    private let subscriptionManager: any SubscriptionManager
    private var modelsFetchTask: Task<Void, Never>?

    var onModelsUpdated: (() -> Void)?

    init(
        modelsService: AIChatModelsProviding,
        preferences: AIChatPreferencesPersisting,
        subscriptionManager: any SubscriptionManager
    ) {
        self.modelsService = modelsService
        self.preferences = preferences
        self.subscriptionManager = subscriptionManager
    }

    var persistedModelId: String? {
        let id = preferences.selectedModelId
        if let id, !models.isEmpty {
            if let model = models.first(where: { $0.id == id }) {
                return model.entityHasAccess ? id : firstAccessibleModelId
            }
            return firstAccessibleModelId
        }
        return id ?? firstAccessibleModelId
    }

    var currentModelId: String? {
        preferences.selectedModelId
    }

    var selectedReasoningMode: AIChatReasoningMode? {
        preferences.selectedReasoningMode
    }

    var selectedModel: AIChatModel? {
        guard let persistedModelId else { return nil }
        return models.first(where: { $0.id == persistedModelId })
    }

    var selectedModelSupportsImageUpload: Bool {
        selectedModel?.supportsImageUpload ?? false
    }

    var selectedModelSupportsFileUpload: Bool {
        selectedModel?.supportsFileUpload ?? false
    }

    var selectedModelSupportedFileTypes: [String] {
        selectedModel?.supportedFileTypes ?? []
    }

    func selectedModelSupports(tool: AIChatRAGTool) -> Bool {
        guard !models.isEmpty else { return false }
        return models.first(where: { $0.id == persistedModelId })?.supportsTool(tool) ?? false
    }

    private var firstAccessibleModelId: String? {
        models.first(where: { $0.entityHasAccess })?.id
    }

    func fetchModels() {
        modelsFetchTask?.cancel()
        modelsFetchTask = Task { [weak self] in
            guard let self else { return }
            let state = await self.resolveSubscriptionState()
            guard !Task.isCancelled else { return }
            self.subscriptionState = state
            do {
                let response = try await modelsService.fetchModels()
                guard !Task.isCancelled else { return }
                self.models = Self.resolveModels(from: response.models, userTier: state.userTier)
                self.attachmentLimits = response.attachmentLimits?.limits(for: state.userTier)
                self.clearStaleModelSelectionIfNeeded()
                self.clearStaleReasoningModeIfNeeded()
                self.onModelsUpdated?()
            } catch {
                guard !Task.isCancelled else { return }
                self.attachmentLimits = nil
                self.onModelsUpdated?()
                os_log(.error, "Failed to fetch models: %{public}@", error.localizedDescription)
            }
        }
    }

    func updateSelectedModel(_ modelId: String) {
        preferences.selectedModelId = modelId
        preferences.selectedModelShortName = models.first(where: { $0.id == modelId })?.shortName
        clearStaleReasoningModeIfNeeded()
    }

    func updateSelectedReasoningMode(_ mode: AIChatReasoningMode) {
        guard selectedModel?.availableReasoningModes.contains(mode) == true else { return }
        preferences.selectedReasoningMode = mode
    }

    /// Applies a reasoning mode coming from a trusted source (e.g. a stored chat
    /// payload's `reasoningMode` field) without the model-supports validity check.
    /// Mirrors `applyPersistedSelection`'s bypass — both are safe to call before `models`
    /// has finished loading. `clearStaleReasoningModeIfNeeded()` in `fetchModels`
    /// will null this out if the resolved model turns out not to support `mode`.
    func applyChatPersistedReasoningMode(_ mode: AIChatReasoningMode?) {
        preferences.selectedReasoningMode = mode
    }

    /// Used by per-tab restoration to mirror a tab's stored selection into preferences,
    /// including nil values. Bypasses the validity checks of `updateSelectedModel`/
    /// `updateSelectedReasoningMode` so the live state matches the stored state exactly.
    func applyPersistedSelection(modelID: String?, reasoningMode: AIChatReasoningMode?) {
        preferences.selectedModelId = modelID
        // Always assign — including nil when the model isn't (yet) in `models` —
        // otherwise the previous tab's cached short name lingers in preferences
        // until handleModelsUpdated() corrects it.
        preferences.selectedModelShortName = modelID.flatMap { id in
            models.first(where: { $0.id == id })?.shortName
        }
        preferences.selectedReasoningMode = reasoningMode
    }

    static func resolveModels(from remoteModels: [AIChatRemoteModel], userTier: AIChatUserTier) -> [AIChatModel] {
        remoteModels.map { remote in
            if remote.accessTier.isEmpty {
                return AIChatModel(
                    id: remote.id,
                    name: remote.name,
                    shortName: remote.modelShortName,
                    provider: .from(id: remote.id, providerString: remote.provider),
                    supportsImageUpload: remote.supportsImageUpload,
                    supportedFileTypes: remote.supportedFileTypes ?? [],
                    supportedImageFormats: remote.supportsImageUpload ? ["png", "jpeg", "webp"] : [],
                    supportedTools: remote.supportedTools.compactMap(AIChatRAGTool.init(rawValue:)),
                    entityHasAccess: remote.entityHasAccess,
                    accessTier: remote.accessTier,
                    supportedReasoningEffort: remote.supportedReasoningEffort
                )
            }
            return AIChatModel(remoteModel: remote, userTier: userTier)
        }
    }

    nonisolated func resolveSubscriptionState() async -> SubscriptionState {
        do {
            let subscription = try await subscriptionManager.getSubscription(cachePolicy: .cacheFirst)
            guard subscription.isActive, let tier = subscription.tier else {
                return .free
            }
            let userTier: AIChatUserTier
            switch tier {
            case .plus: userTier = .plus
            case .pro: userTier = .pro
            }
            return SubscriptionState(userTier: userTier, hasActiveSubscription: true)
        } catch {
            return .free
        }
    }

    func cacheSelectedModelShortName(_ shortName: String) {
        preferences.selectedModelShortName = shortName
    }

    func clearStaleModelSelectionIfNeeded() {
        guard let selectedId = preferences.selectedModelId, !models.isEmpty else { return }

        let selectedModel = models.first(where: { $0.id == selectedId })
        let isStale = selectedModel == nil || selectedModel?.entityHasAccess == false

        if isStale {
            preferences.selectedModelId = nil
            preferences.selectedModelShortName = nil
        }
    }

    func clearStaleReasoningModeIfNeeded() {
        guard let selectedReasoningMode = preferences.selectedReasoningMode else { return }

        guard let selectedModel else {
            preferences.selectedReasoningMode = nil
            return
        }

        if !selectedModel.availableReasoningModes.contains(selectedReasoningMode) {
            preferences.selectedReasoningMode = nil
        }
    }
}
