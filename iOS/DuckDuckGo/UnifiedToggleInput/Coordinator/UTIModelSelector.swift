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
import Core
import UIKit

/// Owns the omnibar UTI's model / reasoning selection: the picker menus, the chip/reasoning view
/// presentation, and (added incrementally) the selection + subscription-gating decisions. It reads
/// the model state off the shared `UTIModelStore` / `UTIToolsController` and pushes menu + label
/// updates through a `ViewSurface` so the view layer just renders.
@MainActor
final class UTIModelSelector {

    /// The chip / reasoning-picker mutations the selector drives on the input bar.
    struct ViewSurface {
        let setModelName: (String) -> Void
        let setModelPickerMenu: (UIMenu?) -> Void
        let setSelectedReasoningMode: (AIChatReasoningMode?) -> Void
        let setReasoningButtonHidden: (Bool) -> Void
        let setReasoningPickerMenu: (UIMenu?) -> Void
    }

    private let modelStore: UTIModelStore
    private let toolsController: UTIToolsController
    private let modelMenuFactory: UnifiedToggleInputModelMenuFactory
    private let reasoningMenuFactory: UnifiedToggleInputReasoningMenuFactory
    private let view: ViewSurface

    // Selection routing still lives in the coordinator at this step; the menu actions call back out
    // through these. They are removed once the selection handlers move into this type.
    private let onModelChosen: (String) -> Void
    private let onReasoningChosen: (AIChatReasoningMode) -> Void

    init(modelStore: UTIModelStore,
         toolsController: UTIToolsController,
         modelMenuFactory: UnifiedToggleInputModelMenuFactory,
         reasoningMenuFactory: UnifiedToggleInputReasoningMenuFactory,
         view: ViewSurface,
         onModelChosen: @escaping (String) -> Void,
         onReasoningChosen: @escaping (AIChatReasoningMode) -> Void) {
        self.modelStore = modelStore
        self.toolsController = toolsController
        self.modelMenuFactory = modelMenuFactory
        self.reasoningMenuFactory = reasoningMenuFactory
        self.view = view
        self.onModelChosen = onModelChosen
        self.onReasoningChosen = onReasoningChosen
    }

    /// The reasoning mode to show as selected, resolved against the current model's supported modes.
    var resolvedSelectedReasoningMode: AIChatReasoningMode? {
        modelStore.selectedModel?.resolvedReasoningMode(from: modelStore.selectedReasoningMode)
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
            self?.onModelChosen(modelId)
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
            self?.onReasoningChosen(mode)
        }
    }
}
