//
//  UTIModelSelector.swift
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
import UIKit
import os.log

/// Owns the omnibar UTI's model / reasoning selection: the picker menus + chip presentation, the
/// selection handlers, and the subscription-gating decisions (including the transient "picked a
/// gated model/mode, retry once it becomes accessible" latches). It owns its menu factories,
/// reasoning-access resolver and upsell presenter; reads the model state off the shared
/// `UTIModelStore` / `UTIToolsController`; and reaches the coordinator only through four live
/// `Environment` reads and four `Callbacks` (the coordinator remains the owner of the shared state
/// those touch — see the decomposition spec's behaviour-vs-state framing).
@MainActor
final class UTIModelSelector {

    /// The chip / reasoning-picker mutations the selector drives on the input bar.
    struct ViewSurface {
        let setModelName: (String) -> Void
        let setModelPickerMenu: (UIMenu?) -> Void
        let setModelChipHidden: (Bool) -> Void
        let setSelectedReasoningMode: (AIChatReasoningMode?) -> Void
        let setReasoningButtonHidden: (Bool) -> Void
        let setReasoningPickerMenu: (UIMenu?) -> Void
    }

    /// Cross-cutting coordinator state read live at decision time (never captured). `host` and
    /// `isModelPickerForcedVisible` stay coordinator-owned (the pin is bound to per-tab persistence).
    struct Environment {
        let isDuckAISurfaceForAttribution: () -> Bool
        let hasSubmittedPrompt: () -> Bool
        let host: () -> UnifiedToggleInputHost?
        let isModelPickerForcedVisible: () -> Bool
    }

    /// Coordinator-owned effects a selection triggers. `onModelsUpdated` re-enters the coordinator's
    /// reconcile hub (which calls `applyPendingGated*` back here); `onModelApplied` lets the
    /// coordinator push the change to the active chat's frontend bridge.
    struct Callbacks {
        let onModelsUpdated: () -> Void
        let onUserChoiceRecorded: () -> Void
        let clearSubmitRecoveryBlock: () -> Void
        let onModelApplied: (String) -> Void
    }

    private let modelStore: UTIModelStore
    private let toolsController: UTIToolsController
    private let pixelReporter: UTIPixelReporter
    private let view: ViewSurface
    private let environment: Environment
    private let callbacks: Callbacks

    private let modelMenuFactory = UnifiedToggleInputModelMenuFactory()
    private let reasoningMenuFactory = UnifiedToggleInputReasoningMenuFactory()
    private let reasoningAccessResolver: ReasoningModeAccessResolving
    private let subscriptionUpsellPresenter: DuckAISubscriptionUpselling

    private var pendingGatedModelId: String?
    private var pendingGatedReasoningSelection: (modelId: String, mode: AIChatReasoningMode)?

    init(modelStore: UTIModelStore,
         toolsController: UTIToolsController,
         pixelReporter: UTIPixelReporter,
         view: ViewSurface,
         environment: Environment,
         callbacks: Callbacks,
         reasoningAccessResolver: ReasoningModeAccessResolving = ReasoningModeAccessResolver(),
         subscriptionUpsellPresenter: DuckAISubscriptionUpselling = DuckAISubscriptionUpsellPresenter()) {
        self.modelStore = modelStore
        self.toolsController = toolsController
        self.pixelReporter = pixelReporter
        self.view = view
        self.environment = environment
        self.callbacks = callbacks
        self.reasoningAccessResolver = reasoningAccessResolver
        self.subscriptionUpsellPresenter = subscriptionUpsellPresenter
    }

    // MARK: - Model selection

    func handleModelSelection(_ modelId: String) {
        guard let model = modelStore.models.first(where: { $0.id == modelId }) else {
            return
        }

        if model.entityHasAccess {
            let isNewSelection = modelId != modelStore.persistedModelId
            pendingGatedModelId = nil
            // Supported model picked in the native picker — the recovery card's reason to block
            // submit is gone, so drop the block (no-op when it wasn't set).
            callbacks.clearSubmitRecoveryBlock()
            updateSelectedModel(modelId)
            if isNewSelection {
                pixelReporter.reportModelSelected(modelId: modelId)
            }
            callbacks.onModelApplied(modelId)
        } else {
            if routeGatedModelSelection(model) {
                pendingGatedModelId = modelId
            }
            refreshModelPickerMenuAfterRejectedSelection()
        }
    }

#if DEBUG || ALPHA
    func handleModelPickerSubscriptionCallToAction(flowType: UpsellFlowType) {
        let userTier: AIChatUserTier
        let requiredTier: AIChatModelPublicAccessTier
        switch flowType {
        case .purchase:
            userTier = .free
            requiredTier = .plus
        case .upgrade:
            userTier = .plus
            requiredTier = .pro
        }

        subscriptionUpsellPresenter.routeGatedSelection(
            requiredTier: requiredTier,
            userTier: userTier,
            source: .modelPicker,
            isAITabState: environment.isDuckAISurfaceForAttribution()
        )
    }
#endif

    func updateSelectedModel(_ modelId: String) {
        modelStore.updateSelectedModel(modelId, isNewChatContext: !environment.hasSubmittedPrompt())
        callbacks.onModelsUpdated()
        callbacks.onUserChoiceRecorded()
    }

    @discardableResult
    private func routeGatedModelSelection(_ model: AIChatModel) -> Bool {
        guard let requiredPublicTier = model.lowestPublicAccessTier else {
            Logger.unifiedInputState.debug("Gated model has no public access tier: \(model.id, privacy: .public)")
            return false
        }

        return routeModelPickerSubscriptionUpsell(requiredTier: requiredPublicTier)
    }

    @discardableResult
    private func routeModelPickerSubscriptionUpsell(requiredTier: AIChatModelPublicAccessTier) -> Bool {
        subscriptionUpsellPresenter.routeGatedSelection(
            requiredTier: requiredTier,
            userTier: modelStore.subscriptionState.userTier,
            source: .modelPicker,
            isAITabState: environment.isDuckAISurfaceForAttribution()
        )
    }

    /// Retries a previously-gated model selection once the model has become accessible (e.g. after
    /// purchase); driven from the coordinator's models-updated reconcile hub.
    @discardableResult
    func applyPendingGatedModelSelectionIfPossible() -> Bool {
        guard let modelId = pendingGatedModelId,
              modelStore.models.first(where: { $0.id == modelId })?.entityHasAccess == true else {
            return false
        }

        let isNewSelection = modelId != modelStore.persistedModelId
        pendingGatedModelId = nil
        // Mirror the direct-selection path: the gated model in the recovery-card
        // is now accessible (post-purchase), so drop the recovery-card submit block.
        callbacks.clearSubmitRecoveryBlock()
        updateSelectedModel(modelId)
        if isNewSelection {
            pixelReporter.reportModelSelected(modelId: modelId)
        }
        callbacks.onModelApplied(modelId)
        return true
    }

    // MARK: - Reasoning selection

    func updateSelectedReasoningMode(_ mode: AIChatReasoningMode) {
        modelStore.updateSelectedReasoningMode(mode)
        updateReasoningPicker()
        callbacks.onUserChoiceRecorded()
    }

    func handleReasoningModeSelection(_ mode: AIChatReasoningMode) {
        guard let selectedModel = modelStore.selectedModel else { return }
        guard let requiredPublicTier = requiredPublicTier(for: mode, model: selectedModel) else {
            pendingGatedReasoningSelection = nil
            updateSelectedReasoningMode(mode)
            pixelReporter.reportReasoningEffortSelected(mode: mode)
            return
        }

        if canSelectReasoningModeRequiringTier(requiredPublicTier) {
            pendingGatedReasoningSelection = nil
            updateSelectedReasoningMode(mode)
            pixelReporter.reportReasoningEffortSelected(mode: mode)
        } else {
            if routeGatedReasoningModeSelection(requiredPublicTier: requiredPublicTier) {
                pendingGatedReasoningSelection = (selectedModel.id, mode)
            }
            refreshReasoningPickerMenuAfterRejectedSelection()
        }
    }

    /// Retries a previously-gated reasoning selection once it has become accessible; driven from the
    /// coordinator's models-updated reconcile hub.
    func applyPendingGatedReasoningSelectionIfPossible() {
        guard let pendingSelection = pendingGatedReasoningSelection else { return }
        guard let selectedModel = modelStore.selectedModel, selectedModel.id == pendingSelection.modelId else {
            pendingGatedReasoningSelection = nil
            return
        }

        if let requiredPublicTier = requiredPublicTier(for: pendingSelection.mode, model: selectedModel),
           !canSelectReasoningModeRequiringTier(requiredPublicTier) {
            return
        }

        pendingGatedReasoningSelection = nil
        updateSelectedReasoningMode(pendingSelection.mode)
        pixelReporter.reportReasoningEffortSelected(mode: pendingSelection.mode)
    }

    private func requiredPublicTier(for mode: AIChatReasoningMode, model: AIChatModel) -> AIChatModelPublicAccessTier? {
        reasoningAccessResolver.requiredPublicTier(for: mode, model: model)
    }

    private func canSelectReasoningModeRequiringTier(_ requiredTier: AIChatModelPublicAccessTier) -> Bool {
        reasoningAccessResolver.canSelect(modeRequiring: requiredTier, userTier: modelStore.subscriptionState.userTier)
    }

    @discardableResult
    private func routeGatedReasoningModeSelection(requiredPublicTier: AIChatModelPublicAccessTier) -> Bool {
        subscriptionUpsellPresenter.routeGatedSelection(
            requiredTier: requiredPublicTier,
            userTier: modelStore.subscriptionState.userTier,
            source: .reasoningPicker,
            isAITabState: environment.isDuckAISurfaceForAttribution()
        )
    }

    // MARK: - Menus

    /// The reasoning mode to show as selected, resolved against the current model's supported modes.
    var resolvedSelectedReasoningMode: AIChatReasoningMode? {
        modelStore.selectedModel?.resolvedReasoningMode(from: modelStore.selectedReasoningMode)
    }

    func updateModelChipVisibility() {
        // Contextual chat only picks the model upstream after the first prompt reaches the web chat.
        // Before that first submit, the sheet-level UTI owns prompt composition and should expose the picker.
        // Image generation has no model picker either — when active, the chip is hidden until the tool is deselected.
        let hasSubmittedPrompt = environment.hasSubmittedPrompt()
        let isImageGenActive = toolsController.selectedTool == .imageGeneration
        let isContextualPostSubmit = environment.host() == .contextualChat && hasSubmittedPrompt
        // `isModelPickerForcedVisible` only relaxes the generic `hasSubmittedPrompt` hide reason —
        // contextual post-submit and image generation stay hidden regardless.
        let shouldHideModelChip = isContextualPostSubmit || isImageGenActive || (hasSubmittedPrompt && !environment.isModelPickerForcedVisible())
        view.setModelChipHidden(shouldHideModelChip)
        updateReasoningPicker()
    }

    func updateModelChipLabel() {
        let selectedId = modelStore.persistedModelId
        let shortName = modelMenuFactory.selectedShortName(models: modelStore.models, selectedId: selectedId)
        if let shortName {
            view.setModelName(shortName)
        }
        view.setModelPickerMenu(modelStore.models.isEmpty ? nil : modelMenuFactory.makeMenu(
            models: modelStore.models,
            selectedId: selectedId,
            plusSectionTitle: UserText.aiChatPlusModelsSectionHeader,
            proSectionTitle: UserText.aiChatProModelsSectionHeader
        ) { [weak self] modelId in
            self?.handleModelSelection(modelId)
        })
    }

    func updateReasoningPicker() {
        if toolsController.selectedTool == .imageGeneration {
            // Reasoning effort doesn't apply to image generation; hide the picker without touching the persisted
            // mode so the previous selection returns when the user deselects the image-gen tool.
            view.setReasoningButtonHidden(true)
            view.setReasoningPickerMenu(nil)
            return
        }
        let selectedMode = resolvedSelectedReasoningMode
        let shouldHide = !(modelStore.selectedModel?.supportsReasoningPicker ?? false)
        view.setSelectedReasoningMode(selectedMode)
        view.setReasoningButtonHidden(shouldHide)
        view.setReasoningPickerMenu(shouldHide ? nil : buildReasoningPickerMenu())
    }

    private func buildReasoningPickerMenu() -> UIMenu? {
        guard let selectedModel = modelStore.selectedModel else { return nil }

        return reasoningMenuFactory.makeMenu(
            model: selectedModel,
            selectedMode: resolvedSelectedReasoningMode
        ) { [weak self] mode in
            self?.handleReasoningModeSelection(mode)
        }
    }

    private func refreshModelPickerMenuAfterRejectedSelection() {
        DispatchQueue.main.async { [weak self] in
            self?.updateModelChipLabel()
        }
    }

    private func refreshReasoningPickerMenuAfterRejectedSelection() {
        DispatchQueue.main.async { [weak self] in
            self?.updateReasoningPicker()
        }
    }
}
