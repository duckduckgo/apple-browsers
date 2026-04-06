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

private let utiLog = OSLog(subsystem: "com.duckduckgo", category: "UTI")

@MainActor
final class UTIModelStore {

    var models: [AIChatModel] = []
    var subscriptionState: SubscriptionState = .free

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
        os_log(.debug, log: utiLog, "ModelStore.init")
        self.modelsService = modelsService
        self.preferences = preferences
        self.subscriptionManager = subscriptionManager
    }

    var persistedModelId: String? {
        os_log(.debug, log: utiLog, "ModelStore.persistedModelId")
        let id = preferences.selectedModelId
        if let id, !models.isEmpty {
            if let model = models.first(where: { $0.id == id }) {
                let result = model.entityHasAccess ? id : firstAccessibleModelId
                os_log(.debug, log: utiLog, "ModelStore.persistedModelId 🔀 found model, hasAccess=%{public}@, returning=%{public}@", String(describing: model.entityHasAccess), result ?? "nil")
                return result
            }
            os_log(.debug, log: utiLog, "ModelStore.persistedModelId 🔀 selectedId not in models, falling back to firstAccessible")
            return firstAccessibleModelId
        }
        let result = id ?? firstAccessibleModelId
        os_log(.debug, log: utiLog, "ModelStore.persistedModelId 🔀 id=%{public}@, returning=%{public}@", id ?? "nil", result ?? "nil")
        return result
    }

    var currentModelId: String? {
        preferences.selectedModelId
    }

    var selectedModelSupportsImageUpload: Bool {
        os_log(.debug, log: utiLog, "ModelStore.selectedModelSupportsImageUpload")
        guard !models.isEmpty else {
            os_log(.debug, log: utiLog, "ModelStore.selectedModelSupportsImageUpload ↩️ guard: models is empty")
            return false
        }
        let supports = models.first(where: { $0.id == persistedModelId })?.supportsImageUpload ?? false
        os_log(.debug, log: utiLog, "ModelStore.selectedModelSupportsImageUpload 🔀 result=%{public}@", String(describing: supports))
        return supports
    }

    private var firstAccessibleModelId: String? {
        models.first(where: { $0.entityHasAccess })?.id
    }

    func fetchModels() {
        os_log(.debug, log: utiLog, "ModelStore.fetchModels")
        os_log(.debug, log: utiLog, "ModelStore.fetchModels → cancelling previous task")
        modelsFetchTask?.cancel()
        modelsFetchTask = Task { [weak self] in
            guard let self else {
                os_log(.debug, log: utiLog, "ModelStore.fetchModels ↩️ guard: self is nil")
                return
            }
            let state = await self.resolveSubscriptionState()
            guard !Task.isCancelled else {
                os_log(.debug, log: utiLog, "ModelStore.fetchModels ↩️ guard: task cancelled after resolveSubscriptionState")
                return
            }
            os_log(.debug, log: utiLog, "ModelStore.fetchModels 🔀 subscriptionState resolved, userTier=%{public}@", String(describing: state.userTier))
            self.subscriptionState = state
            do {
                let remoteModels = try await modelsService.fetchModels()
                guard !Task.isCancelled else {
                    os_log(.debug, log: utiLog, "ModelStore.fetchModels ↩️ guard: task cancelled after fetchModels")
                    return
                }
                os_log(.debug, log: utiLog, "ModelStore.fetchModels 🔀 fetched %{public}d remote models", remoteModels.count)
                self.models = Self.resolveModels(from: remoteModels, userTier: state.userTier)
                os_log(.debug, log: utiLog, "ModelStore.fetchModels → calling clearStaleModelSelectionIfNeeded")
                self.clearStaleModelSelectionIfNeeded()
                os_log(.debug, log: utiLog, "ModelStore.fetchModels → calling onModelsUpdated")
                self.onModelsUpdated?()
            } catch {
                os_log(.debug, log: utiLog, "ModelStore.fetchModels 🔀 error: %{public}@", error.localizedDescription)
                os_log(.error, "Failed to fetch models: %{public}@", error.localizedDescription)
            }
        }
    }

    func updateSelectedModel(_ modelId: String) {
        os_log(.debug, log: utiLog, "ModelStore.updateSelectedModel - modelId: %{public}@", modelId)
        preferences.selectedModelId = modelId
        preferences.selectedModelShortName = models.first(where: { $0.id == modelId })?.shortName
    }

    static func resolveModels(from remoteModels: [AIChatRemoteModel], userTier: AIChatUserTier) -> [AIChatModel] {
        os_log(.debug, log: utiLog, "ModelStore.resolveModels - count: %{public}d, userTier: %{public}@", remoteModels.count, String(describing: userTier))
        return remoteModels.map { remote in
            if remote.accessTier.isEmpty {
                os_log(.debug, log: utiLog, "ModelStore.resolveModels 🔀 model %{public}@ has empty accessTier, using manual init", remote.id)
                return AIChatModel(
                    id: remote.id,
                    name: remote.name,
                    shortName: remote.modelShortName,
                    provider: .from(id: remote.id, providerString: remote.provider),
                    supportsImageUpload: remote.supportsImageUpload,
                    supportedImageFormats: remote.supportsImageUpload ? ["png", "jpeg", "webp"] : [],
                    entityHasAccess: remote.entityHasAccess,
                    accessTier: remote.accessTier
                )
            }
            os_log(.debug, log: utiLog, "ModelStore.resolveModels 🔀 model %{public}@ using remoteModel init", remote.id)
            return AIChatModel(remoteModel: remote, userTier: userTier)
        }
    }

    nonisolated func resolveSubscriptionState() async -> SubscriptionState {
        os_log(.debug, log: utiLog, "ModelStore.resolveSubscriptionState")
        do {
            let subscription = try await subscriptionManager.getSubscription(cachePolicy: .cacheFirst)
            guard subscription.isActive, let tier = subscription.tier else {
                os_log(.debug, log: utiLog, "ModelStore.resolveSubscriptionState ↩️ guard: inactive or no tier → free")
                return .free
            }
            let userTier: AIChatUserTier
            switch tier {
            case .plus:
                os_log(.debug, log: utiLog, "ModelStore.resolveSubscriptionState 🔀 tier=plus")
                userTier = .plus
            case .pro:
                os_log(.debug, log: utiLog, "ModelStore.resolveSubscriptionState 🔀 tier=pro")
                userTier = .pro
            }
            os_log(.debug, log: utiLog, "ModelStore.resolveSubscriptionState 🔀 active subscription, userTier=%{public}@", String(describing: userTier))
            return SubscriptionState(userTier: userTier, hasActiveSubscription: true)
        } catch {
            os_log(.debug, log: utiLog, "ModelStore.resolveSubscriptionState 🔀 error: %{public}@ → free", error.localizedDescription)
            return .free
        }
    }

    func cacheSelectedModelShortName(_ shortName: String) {
        os_log(.debug, log: utiLog, "ModelStore.cacheSelectedModelShortName - shortName: %{public}@", shortName)
        preferences.selectedModelShortName = shortName
    }

    func clearStaleModelSelectionIfNeeded() {
        os_log(.debug, log: utiLog, "ModelStore.clearStaleModelSelectionIfNeeded")
        guard let selectedId = preferences.selectedModelId, !models.isEmpty else {
            os_log(.debug, log: utiLog, "ModelStore.clearStaleModelSelectionIfNeeded ↩️ guard: no selectedId or models empty")
            return
        }

        let selectedModel = models.first(where: { $0.id == selectedId })
        let isStale = selectedModel == nil || selectedModel?.entityHasAccess == false
        os_log(.debug, log: utiLog, "ModelStore.clearStaleModelSelectionIfNeeded 🔀 selectedId=%{public}@, isStale=%{public}@", selectedId, String(describing: isStale))

        if isStale {
            os_log(.debug, log: utiLog, "ModelStore.clearStaleModelSelectionIfNeeded 📐 clearing stale selection")
            preferences.selectedModelId = nil
            preferences.selectedModelShortName = nil
        }
    }
}
