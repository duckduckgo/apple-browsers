//
//  IPadOmnibarReasoningPickerController.swift
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
import Core
import UIKit
import PixelKit

/// Drives the Duck.ai reasoning-level picker
@MainActor
final class IPadOmnibarReasoningPickerController {

    private let store: UTIModelStore
    private let menuFactory: UnifiedToggleInputReasoningMenuFactory
    private let accessResolver: ReasoningModeAccessResolving
    private let upsellPresenter: DuckAISubscriptionUpselling

    /// A reasoning mode whose selection was blocked behind an upsell; re-applied once a
    /// subscription refresh grants the user access
    private var pendingGatedSelection: (modelId: String, mode: AIChatReasoningMode)?

    /// Invoked whenever the reasoning state changes so the host can refresh the chip
    /// (icon, menu and visibility).
    var onReasoningUpdated: (() -> Void)?

    init(
        store: UTIModelStore,
        accessResolver: ReasoningModeAccessResolving = ReasoningModeAccessResolver(),
        upsellPresenter: DuckAISubscriptionUpselling = DuckAISubscriptionUpsellPresenter(),
        updatedModelPickerFeature: UpdatedModelPickerFeatureProviding = UpdatedModelPickerFeature()
    ) {
        self.store = store
        self.menuFactory = UnifiedToggleInputReasoningMenuFactory(isUpdatedModelPickerEnabled: updatedModelPickerFeature.isAvailable)
        self.accessResolver = accessResolver
        self.upsellPresenter = upsellPresenter
    }

    var isReasoningPickerAvailable: Bool {
        store.selectedModel?.supportsReasoningPicker ?? false
    }

    var currentReasoningMode: AIChatReasoningMode? {
        guard let model = store.selectedModel else { return nil }
        return model.resolvedReasoningMode(from: store.selectedReasoningMode)
    }

    var selectedReasoningEffort: AIChatReasoningEffort? {
        store.submissionReasoningEffort
    }

    func makeMenu() -> UIMenu? {
        guard let model = store.selectedModel else { return nil }

        let onSelect: (AIChatReasoningMode) -> Void = { [weak self] mode in
            self?.handleReasoningModeSelection(mode)
        }

        return menuFactory.makeMenu(
            model: model,
            selectedMode: currentReasoningMode,
            userTier: store.subscriptionState.userTier,
            freeTrialEligibility: store.freeTrialEligibility,
            onSelect: onSelect
        )
    }

    func handleReasoningModeSelection(_ mode: AIChatReasoningMode) {
        guard let model = store.selectedModel else { return }

        guard let requiredTier = accessResolver.requiredPublicTier(for: mode, model: model) else {
            pendingGatedSelection = nil
            select(mode)
            return
        }

        if accessResolver.canSelect(modeRequiring: requiredTier, userTier: store.subscriptionState.userTier) {
            pendingGatedSelection = nil
            select(mode)
        } else {
            if routeGatedReasoningSelection(requiredTier: requiredTier) {
                pendingGatedSelection = (model.id, mode)
            }
            // The selection was rejected — refresh so the chip restores the previous mode.
            onReasoningUpdated?()
        }
    }

    func handleModelsUpdated() {
        applyPendingGatedSelectionIfPossible()
    }

    // MARK: - Private

    private func select(_ mode: AIChatReasoningMode) {
        store.updateSelectedReasoningMode(mode)
        PixelKit.fire(Pixel.Event.unifiedToggleInputReasoningEffortSelected, options: .parameters(["effort_level": mode.rawValue, "surface": UnifiedToggleInputPixelSurface.addressBar.rawValue]))
        onReasoningUpdated?()
    }

    @discardableResult
    private func routeGatedReasoningSelection(requiredTier: AIChatModelPublicAccessTier) -> Bool {
        upsellPresenter.routeGatedSelection(
            requiredTier: requiredTier,
            userTier: store.subscriptionState.userTier,
            source: .reasoningPicker,
            isAITabState: false
        )
    }

    private func applyPendingGatedSelectionIfPossible() {
        guard let pending = pendingGatedSelection else { return }
        guard let model = store.selectedModel, model.id == pending.modelId else {
            pendingGatedSelection = nil
            return
        }

        if let requiredTier = accessResolver.requiredPublicTier(for: pending.mode, model: model),
           !accessResolver.canSelect(modeRequiring: requiredTier, userTier: store.subscriptionState.userTier) {
            return
        }

        pendingGatedSelection = nil
        select(pending.mode)
    }
}
