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

/// Drives the Duck.ai reasoning-level picker shown to the left of the model picker in the
/// iPad address bar's expanded AI-chat input area.
///
/// Like `IPadOmnibarModelPickerController`, this is a thin wrapper around the shared
/// `UTIModelStore` — it reuses the same selection / persistence logic as the iPhone
/// `UnifiedToggleInputCoordinator` (the reasoning menu factory, the tier-access resolver
/// and the subscription upsell presenter) so reasoning behaves identically across
/// Duck.ai surfaces. The store is shared with the model picker so both chips reflect the
/// same selected model and a single `/models` fetch.
@MainActor
final class IPadOmnibarReasoningPickerController {

    private let store: UTIModelStore
    private let menuFactory: UnifiedToggleInputReasoningMenuFactory
    private let accessResolver: ReasoningModeAccessResolving
    private let upsellPresenter: DuckAISubscriptionUpselling

    /// A reasoning mode whose selection was blocked behind an upsell; re-applied once a
    /// subscription refresh grants the user access (mirrors the iPhone coordinator).
    private var pendingGatedSelection: (modelId: String, mode: AIChatReasoningMode)?

    /// Invoked whenever the reasoning state changes so the host can refresh the chip
    /// (icon, menu and visibility).
    var onReasoningUpdated: (() -> Void)?

    init(
        store: UTIModelStore,
        menuFactory: UnifiedToggleInputReasoningMenuFactory = UnifiedToggleInputReasoningMenuFactory(),
        accessResolver: ReasoningModeAccessResolving = ReasoningModeAccessResolver(),
        upsellPresenter: DuckAISubscriptionUpselling = DuckAISubscriptionUpsellPresenter()
    ) {
        self.store = store
        self.menuFactory = menuFactory
        self.accessResolver = accessResolver
        self.upsellPresenter = upsellPresenter
    }

    /// Whether the reasoning picker should be shown for the selected model. Matches the
    /// iPhone rule: the model must expose more than one accessible reasoning mode. (The iPad
    /// omnibar input has no image-generation tool, so that iPhone hide-case doesn't apply.)
    var isReasoningPickerAvailable: Bool {
        store.selectedModel?.supportsReasoningPicker ?? false
    }

    /// The reasoning mode currently in effect, resolved against the model's accessible modes.
    /// Drives the chip icon and the menu checkmark.
    var currentReasoningMode: AIChatReasoningMode? {
        guard let model = store.selectedModel else { return nil }
        return model.resolvedReasoningMode(from: store.selectedReasoningMode)
    }

    /// The reasoning effort to forward at submission. Delegates to the shared store so the iPad
    /// picker forwards exactly what the iPhone coordinator does (see `submissionReasoningEffort`).
    var selectedReasoningEffort: AIChatReasoningEffort? {
        store.submissionReasoningEffort
    }

    func makeMenu() -> UIMenu? {
        guard let model = store.selectedModel else { return nil }
        return menuFactory.makeMenu(model: model, selectedMode: currentReasoningMode) { [weak self] mode in
            self?.handleReasoningModeSelection(mode)
        }
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
            if routeGatedSelection(requiredTier: requiredTier) {
                pendingGatedSelection = (model.id, mode)
            }
            // The selection was rejected — refresh so the chip restores the previous mode.
            onReasoningUpdated?()
        }
    }

    /// Call from the shared store's `onModelsUpdated` so a pending gated selection is applied
    /// once a subscription refresh grants access.
    func handleModelsUpdated() {
        applyPendingGatedSelectionIfPossible()
    }

    // MARK: - Private

    private func select(_ mode: AIChatReasoningMode) {
        store.updateSelectedReasoningMode(mode)
        Pixel.fire(pixel: .unifiedToggleInputReasoningEffortSelected, withAdditionalParameters: ["effort_level": mode.rawValue])
        onReasoningUpdated?()
    }

    @discardableResult
    private func routeGatedSelection(requiredTier: AIChatModelPublicAccessTier) -> Bool {
        let userTier = store.subscriptionState.userTier

        if userTier == .free, requiredTier == .plus || requiredTier == .pro {
            UnifiedToggleInputCoordinatorPixelHelper.fireSubscriptionUpsellTriggeredPixel(
                source: .reasoningPicker,
                currentTier: userTier,
                requiredTier: requiredTier,
                flowType: .purchase
            )
            upsellPresenter.presentPurchaseFlow(source: .reasoningPicker, isAITabState: false)
            return true
        }

        if userTier == .plus, requiredTier == .pro {
            UnifiedToggleInputCoordinatorPixelHelper.fireSubscriptionUpsellTriggeredPixel(
                source: .reasoningPicker,
                currentTier: userTier,
                requiredTier: requiredTier,
                flowType: .upgrade
            )
            upsellPresenter.presentUpgradeFlow(source: .reasoningPicker, isAITabState: false)
            return true
        }

        return false
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
