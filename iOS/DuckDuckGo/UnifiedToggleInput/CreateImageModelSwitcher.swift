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
    private let pixelFiring: CreateImagePixelFiring

    init(isFeatureEnabled: Bool, pixelFiring: CreateImagePixelFiring) {
        self.isFeatureEnabled = isFeatureEnabled
        self.pixelFiring = pixelFiring
    }

    /// Selects Create Image, switching the model first when needed.
    @discardableResult
    func select(
        toolsController: UTIToolsController,
        modelStore: UTIModelStore,
        canSwitchModel: Bool,
        entryPoint: CreateImageEntryPoint?,
        applyModel: (String) -> Void
    ) -> CreateImageModelSwitchNotice? {
        let notice = switchModelIfNeeded(
            modelStore: modelStore,
            canSwitchModel: canSwitchModel,
            entryPoint: entryPoint,
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
        entryPoint: CreateImageEntryPoint?,
        applyModel: (String) -> Void
    ) -> CreateImageModelSwitchNotice? {
        let isSelecting = toolsController.selectedTool != .imageGeneration
        let notice = isSelecting
            ? switchModelIfNeeded(modelStore: modelStore,
                                  canSwitchModel: canSwitchModel,
                                  entryPoint: entryPoint,
                                  applyModel: applyModel)
            : nil
        toolsController.toggleSelection(for: .imageGeneration, modelStore: modelStore)
        return notice
    }

    // MARK: - Private

    private func switchModelIfNeeded(
        modelStore: UTIModelStore,
        canSwitchModel: Bool,
        entryPoint: CreateImageEntryPoint?,
        applyModel: (String) -> Void
    ) -> CreateImageModelSwitchNotice? {
        guard isFeatureEnabled else { return nil }
        guard !modelStore.selectedModelSupports(tool: .imageGeneration) else { return nil }

        guard let fallbackModel = modelStore.imageGenerationFallbackModel else {
            pixelFiring.createImageUnavailable()
            return nil
        }

        guard canSwitchModel else { return nil }
        guard let previousModel = modelStore.selectedModel else { return nil }

        applyModel(fallbackModel.id)
        let notice = CreateImageModelSwitchNotice(previousModel: previousModel, newModel: fallbackModel)
        reportSwitch(notice: notice, from: previousModel, to: fallbackModel, entryPoint: entryPoint)
        return notice
    }

    private func reportSwitch(
        notice: CreateImageModelSwitchNotice,
        from previousModel: AIChatModel,
        to newModel: AIChatModel,
        entryPoint: CreateImageEntryPoint?
    ) {
        guard let entryPoint else { return }
        pixelFiring.modelSwitched(CreateImageModelSwitch(
            fromModelId: previousModel.id,
            toModelId: newModel.id,
            fromModelHasExtraPrivacyProtections: notice.previousModelHasExtraPrivacyProtections,
            entryPoint: entryPoint
        ))
    }
}
