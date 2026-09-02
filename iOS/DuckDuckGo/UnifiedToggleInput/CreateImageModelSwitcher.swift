//
//  CreateImageModelSwitcher.swift
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

/// Turns Create Image on, moving the user onto an image-capable model first when the selected one
/// can't generate images.
@MainActor
struct CreateImageModelSwitcher {
    private let isFeatureEnabled: Bool

    init(isFeatureEnabled: Bool) {
        self.isFeatureEnabled = isFeatureEnabled
    }

    /// Selects Create Image, switching the model first when needed.
    @discardableResult
    func select(
        toolsController: UTIToolsController,
        modelStore: UTIModelStore,
        canSwitchModel: Bool,
        applyModel: (String) -> Void
    ) -> CreateImageModelSwitchNotice? {
        let notice = switchModelIfNeeded(
            modelStore: modelStore,
            canSwitchModel: canSwitchModel,
            applyModel: applyModel
        )
        toolsController.select(.imageGeneration, for: modelStore)
        return notice
    }

    /// Toggles Create Image, switching the model only when turning it on. Deselecting is the user
    /// asking for the opposite, so it leaves the model alone.
    @discardableResult
    func toggle(
        toolsController: UTIToolsController,
        modelStore: UTIModelStore,
        canSwitchModel: Bool,
        applyModel: (String) -> Void
    ) -> CreateImageModelSwitchNotice? {
        let isSelecting = toolsController.selectedTool != .imageGeneration
        let notice = isSelecting
            ? switchModelIfNeeded(modelStore: modelStore, canSwitchModel: canSwitchModel, applyModel: applyModel)
            : nil
        toolsController.toggleSelection(for: .imageGeneration, modelStore: modelStore)
        return notice
    }

    // MARK: - Private

    private func switchModelIfNeeded(
        modelStore: UTIModelStore,
        canSwitchModel: Bool,
        applyModel: (String) -> Void
    ) -> CreateImageModelSwitchNotice? {
        guard isFeatureEnabled,
              !modelStore.selectedModelSupports(tool: .imageGeneration),
              canSwitchModel,
              let previousModel = modelStore.selectedModel,
              let fallbackModel = modelStore.imageGenerationFallbackModel else {
            return nil
        }

        applyModel(fallbackModel.id)
        return CreateImageModelSwitchNotice(previousModel: previousModel, newModel: fallbackModel)
    }
}
