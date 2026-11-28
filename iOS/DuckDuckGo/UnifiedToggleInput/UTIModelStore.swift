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
import Combine
import os.log
import Subscription

/// Free trial eligibility used to label gated models and reasoning efforts.
enum FreeTrialEligibility: Equatable {
    case unknown
    case eligible
    case ineligible
}

/// A model and reasoning mode picked in an input; `nil` fields mean the defaults.
struct UTIModelSelection: Equatable {
    var modelID: String?
    var reasoningMode: AIChatReasoningMode?
}

@MainActor
final class UTIModelStore {

    var models: [AIChatModel] = [] {
        didSet { newChatDefaults?.models = models }
    }
    var subscriptionState: SubscriptionState = .free {
        didSet { newChatDefaults?.userTier = subscriptionState.userTier }
    }
    var attachmentLimits: AIChatAttachmentTierLimits?
    private(set) var freeTrialEligibility: FreeTrialEligibility = .unknown

    let upsellPolicy: DuckAISubscriptionUpsellPolicy

    var allowsSubscriptionUpsell: Bool {
        upsellPolicy.allowsUpsell(for: subscriptionState.userTier)
    }

    var shouldShowHeaderUpsell: Bool {
        upsellPolicy.shouldShowHeaderUpsell(for: subscriptionState.userTier)
    }

    var isReasoningPickerAvailable: Bool {
        guard let selectedModel else { return false }
        return ReasoningPickerAvailability.isAvailable(for: selectedModel, allowsSubscriptionUpsell: allowsSubscriptionUpsell)
    }

    private let modelsService: AIChatModelsProviding
    private let subscriptionManager: any SubscriptionManager
    private let isUpdatedModelPickerEnabled: Bool
    private let pickStore: UTIModelPickStoring
    /// `nil` while new chats start on the last pick instead of the default.
    let newChatDefaults: AIChatNewChatDefaultSource?
    private var modelsFetchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// The tab's own pick.
    private var userModelId: String?
    /// A model this chat moved to without the user picking it, such as for a new chat hint. It wins over the
    /// user's pick until the chat changes, and is never saved or kept as their pick.
    private(set) var chatOnlyModelId: String?

    private var liveModelId: String? { chatOnlyModelId ?? userModelId }

    var onModelsUpdated: (() -> Void)?

    init(
        modelsService: AIChatModelsProviding,
        preferences: AIChatPreferencesPersisting,
        subscriptionManager: any SubscriptionManager,
        isUpdatedModelPickerEnabled: Bool,
        startsNewChatsOnDefault: Bool = false,
        overLimitNewChatDefaults: AnyPublisher<AIChatOverLimitNewChatDefault, Never>? = nil,
        userDefaultModelStorage: DuckAiNativeStorageHandling? = nil
    ) {
        self.modelsService = modelsService
        self.subscriptionManager = subscriptionManager
        self.upsellPolicy = DuckAISubscriptionUpsellPolicy(subscriptionManager: subscriptionManager)
        self.isUpdatedModelPickerEnabled = isUpdatedModelPickerEnabled
        self.pickStore = makeModelPickStore(startsNewChatsOnDefault: startsNewChatsOnDefault, preferences: preferences)
        self.newChatDefaults = startsNewChatsOnDefault ? AIChatNewChatDefaultSource() : nil
        if isUpdatedModelPickerEnabled {
            updateFreeTrialEligibilityFromSubscriptionCache()
        }
        subscribeToAppStoreProductAvailability()
        observeNewChatDefaults(overLimitDefaults: overLimitNewChatDefaults, userDefaultModelStorage: userDefaultModelStorage)
    }

    private func observeNewChatDefaults(overLimitDefaults: AnyPublisher<AIChatOverLimitNewChatDefault, Never>?,
                                        userDefaultModelStorage: DuckAiNativeStorageHandling?) {
        guard let newChatDefaults else { return }
        newChatDefaults.defaultChanges
            .sink { [weak self] in self?.onModelsUpdated?() }
            .store(in: &cancellables)
        if let overLimitDefaults {
            newChatDefaults.observeOverLimitDefaults(overLimitDefaults)
        }
        observeUserDefaultModel(in: userDefaultModelStorage)
    }

    /// Follows the user default in `storage` instead of any earlier one, such as when the tab turns fire.
    func observeUserDefaultModel(in storage: DuckAiNativeStorageHandling?) {
        guard let newChatDefaults else { return }
        newChatDefaults.observeUserDefaultModel(in: storage, receivingUpdatesOn: DispatchQueue.main)
        onModelsUpdated?()
    }

    var persistedModelId: String? {
        persistedModelId(live: liveModelId)
    }

    private func persistedModelId(live modelId: String?) -> String? {
        if let resolved = resolve(modelId: modelId) { return resolved }
        if let resolved = resolve(modelId: newChatModelId) { return resolved }
        return firstAccessibleModelId
    }

    /// The model and effort a new chat starts on when nothing was picked on this tab.
    var newChatDefaultSelection: AIChatNewChatSelection? {
        newChatDefaults?.selectionOrLocalDefaultBeforeModelsLoad
    }

    private var newChatModelId: String? {
        pickStore.newChatModelId ?? newChatDefaultSelection?.modelId
    }

    var currentModelId: String? {
        liveModelId
    }

    /// Where a new chat's first prompt model came from; `nil` while new chats don't start on the default.
    func newChatModelSource(onboardingModelId: String?) -> DuckAINewChatModelSource? {
        guard let sentModelId = persistedModelId, let newChatDefault = newChatDefaultSelection else { return nil }
        return DuckAINewChatModelSource.resolve(sentModelId: sentModelId,
                                                sendsDefaultEffort: sendsNewChatDefaultEffort,
                                                isPicked: hasLivePick,
                                                onboardingModelId: onboardingModelId,
                                                newChatDefault: newChatDefault)
    }

    /// Voice prompts carry the effort only for chats that start on the new-chat default.
    var voicePromptReasoningEffort: AIChatReasoningEffort? {
        guard newChatDefaults != nil else { return nil }
        return submissionReasoningEffort
    }

    private var hasLivePick: Bool {
        liveModelId != nil || pickStore.reasoningMode != nil
    }

    private var sendsNewChatDefaultEffort: Bool {
        guard let pickedMode = pickStore.reasoningMode, let selectedModel else { return true }
        return selectedModel.resolvedReasoningEffort(from: pickedMode) == selectedModel.resolvedReasoningEffort(from: newChatDefaultReasoningMode(on: selectedModel))
    }

    /// The tab's own pick, without the new-chat default filled in.
    var liveSelection: UTIModelSelection {
        UTIModelSelection(modelID: liveModelId, reasoningMode: pickStore.reasoningMode)
    }

    /// What a tab keeps as the user's pick, and what the last-used defaults copy: without a chat-only model.
    func selectionKeptOnTab(isNewChat: Bool) -> UTIModelSelection {
        let shownModelId = persistedModelId(live: userModelId)
        let userModel = models.first { $0.id == shownModelId }
        let shown = UTIModelSelection(modelID: shownModelId,
                                      reasoningMode: pickStore.reasoningMode ?? newChatDefaultReasoningMode(on: userModel))
        guard isNewChat else { return shown }
        return pickStore.newChatSelectionKeptOnTab(ownPick: UTIModelSelection(modelID: userModelId, reasoningMode: pickStore.reasoningMode),
                                                   shown: shown)
    }

    /// The pick a different chat on this tab starts on; `nil` keeps the current one.
    func pickForNewChat(openedWithModelId modelId: String?) -> UTIModelSelection? {
        pickStore.pickForNewChat(openedWithModelId: modelId)
    }

    var selectedReasoningMode: AIChatReasoningMode? {
        // A chat-only model may not offer the user's mode; the mode stays theirs for their own model.
        if let mode = pickStore.reasoningMode,
           chatOnlyModelId == nil || selectedModel?.availableReasoningModes.contains(mode) != false {
            return mode
        }
        return newChatDefaultReasoningMode(on: selectedModel)
    }

    private func newChatDefaultReasoningMode(on model: AIChatModel?) -> AIChatReasoningMode? {
        guard let model, let selection = newChatDefaultSelection else { return nil }
        return model.reasoningMode(for: selection.reasoningEffort(onModelId: model.id))
    }

    var submissionReasoningEffort: AIChatReasoningEffort? {
        guard let selectedModel else { return newChatDefaultReasoningEffortBeforeModelsLoad }
        guard selectedReasoningMode != nil || selectedModel.supportsReasoningPicker else { return nil }
        return selectedModel.resolvedReasoningEffort(from: selectedReasoningMode)
    }

    /// Before `/models` loads, only the new-chat default's own effort is known to fit the model it names.
    private var newChatDefaultReasoningEffortBeforeModelsLoad: AIChatReasoningEffort? {
        guard models.isEmpty, pickStore.reasoningMode == nil else { return nil }
        return newChatDefaultSelection?.reasoningEffort(onModelId: persistedModelId)
    }

    var selectedModel: AIChatModel? {
        guard let persistedModelId else { return nil }
        return models.first(where: { $0.id == persistedModelId })
    }

    var displayShortName: String? {
        if let liveModelId,
           let shortName = models.first(where: { $0.id == liveModelId })?.shortName {
            return shortName
        }
        return pickStore.newChatModelShortName ?? newChatDefaultModel?.shortName
    }

    private var newChatDefaultModel: AIChatModel? {
        let modelId = newChatDefaultSelection?.modelId
        return models.first { $0.id == modelId }
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

    /// The model to switch to when the user picks Create Image on a model that can't generate images.
    /// `entityHasAccess` is part of the predicate on purpose: `persistedModelId` runs every id through
    /// `resolve(modelId:)`, which drops an inaccessible model and falls back to `firstAccessibleModelId`
    /// — so switching to one would leave the user on a third model while the footer card names this one.
    var imageGenerationFallbackModel: AIChatModel? {
        AIChatModel.preferredImageGenerationModel(in: models)
    }

    private var firstAccessibleModelId: String? {
        models.first(where: { $0.entityHasAccess })?.id
    }

    private func resolve(modelId id: String?) -> String? {
        guard let id else { return nil }
        guard !models.isEmpty else { return id }
        guard let model = models.first(where: { $0.id == id }) else { return nil }
        return model.entityHasAccess ? id : nil
    }

    func fetchModels() {
        if isUpdatedModelPickerEnabled {
            updateFreeTrialEligibilityFromSubscriptionCache()
        }
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
                self.newChatDefaults?.serverDefault = response.newChatDefault
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

    private func subscribeToAppStoreProductAvailability() {
        subscriptionManager.hasAppStoreProductsAvailablePublisher
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.isUpdatedModelPickerEnabled {
                        self.updateFreeTrialEligibilityFromSubscriptionCache()
                    }
                    self.onModelsUpdated?()
                }
            }
            .store(in: &cancellables)
    }

    private func updateFreeTrialEligibilityFromSubscriptionCache() {
        let updatedEligibility: FreeTrialEligibility
        if !subscriptionManager.isSubscriptionPurchaseEligible {
            updatedEligibility = .unknown
        } else {
            updatedEligibility = subscriptionManager.isUserEligibleForFreeTrial() ? .eligible : .ineligible
        }

        freeTrialEligibility = updatedEligibility
    }

    func updateSelectedModel(_ modelId: String, isNewChatContext: Bool) {
        userModelId = modelId
        chatOnlyModelId = nil
        if isNewChatContext {
            pickStore.saveNewChatModel(id: modelId, shortName: models.first(where: { $0.id == modelId })?.shortName)
        }
        clearStaleReasoningModeIfNeeded()
    }

    func updateSelectedReasoningMode(_ mode: AIChatReasoningMode) {
        guard selectedModel?.availableReasoningModes.contains(mode) == true else { return }
        pickStore.reasoningMode = mode
    }

    /// Applies a reasoning mode coming from a trusted source (e.g. a stored chat
    /// payload's `reasoningMode` field) without the model-supports validity check.
    /// Mirrors `applyPersistedSelection`'s bypass — both are safe to call before `models`
    /// has finished loading. `clearStaleReasoningModeIfNeeded()` in `fetchModels`
    /// will null this out if the resolved model turns out not to support `mode`.
    func applyChatPersistedReasoningMode(_ mode: AIChatReasoningMode?) {
        pickStore.reasoningMode = mode
    }

    func applyPersistedSelection(modelID: String?, reasoningMode: AIChatReasoningMode?, chatOnlyModelID: String? = nil) {
        userModelId = modelID
        chatOnlyModelId = chatOnlyModelID
        pickStore.reasoningMode = reasoningMode
    }

    /// Moves this chat to `modelId` without making it the user's pick: new chats keep starting on theirs.
    func switchModelForThisChat(_ modelId: String) {
        chatOnlyModelId = modelId
    }

    /// A different chat goes back to the user's pick.
    func endChatOnlyModel() {
        chatOnlyModelId = nil
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
                    supportedReasoningEffort: remote.supportedReasoningEffort,
                    label: remote.label
                )
            }
            return AIChatModel(remoteModel: remote, userTier: userTier)
        }
    }

    nonisolated func resolveSubscriptionState() async -> SubscriptionState {
        do {
            guard let subscription = try await subscriptionManager.getSubscription() else {
                return .free
            }
            guard subscription.isActive,
                  let tier = subscription.tier else {
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

    func clearStaleModelSelectionIfNeeded() {
        guard !models.isEmpty else { return }

        if let id = userModelId, !models.contains(where: { $0.id == id && $0.entityHasAccess }) {
            userModelId = nil
        }
        if let id = chatOnlyModelId, !models.contains(where: { $0.id == id && $0.entityHasAccess }) {
            chatOnlyModelId = nil
        }

        if let newChatModelId = pickStore.newChatModelId,
           !models.contains(where: { $0.id == newChatModelId && $0.entityHasAccess }) {
            pickStore.saveNewChatModel(id: nil, shortName: nil)
        }
    }

    /// Checks the user's mode against their own model, not a chat-only one, so a hint never clears it.
    func clearStaleReasoningModeIfNeeded() {
        guard let pickedMode = pickStore.reasoningMode else { return }

        guard let userModel = models.first(where: { $0.id == persistedModelId(live: userModelId) }) else {
            pickStore.reasoningMode = nil
            return
        }

        if !userModel.availableReasoningModes.contains(pickedMode) {
            pickStore.reasoningMode = nil
        }
    }
}
