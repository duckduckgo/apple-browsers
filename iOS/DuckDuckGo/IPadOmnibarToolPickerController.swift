//
//  IPadOmnibarToolPickerController.swift
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

/// Drives the Duck.ai tool picker shown on the far left of the iPad address bar's expanded
/// AI-chat input area.

@MainActor
final class IPadOmnibarToolPickerController {

    private let store: UTIModelStore
    private let toolsController = UTIToolsController()
    private let menuFactory = UTIToolsMenuFactory()
    private let isUpdatedCreateImageEnabled: Bool
    private let createImagePixelFiring: CreateImagePixelFiring
    private lazy var createImageModelSwitcher = CreateImageModelSwitcher(
        isFeatureEnabled: isUpdatedCreateImageEnabled,
        pixelFiring: createImagePixelFiring)
    private var modelSwitchNotice: CreateImageModelSwitchNotice?
    var onToolsUpdated: (() -> Void)?
    var onModelSwitchNoticeUpdated: ((CreateImageModelSwitchNotice?) -> Void)?

    init(store: UTIModelStore,
         isUpdatedCreateImageEnabled: Bool = false,
         createImagePixelFiring: CreateImagePixelFiring = CreateImagePixelAdapter(surface: { .addressBar })) {
        self.store = store
        self.isUpdatedCreateImageEnabled = isUpdatedCreateImageEnabled
        self.createImagePixelFiring = createImagePixelFiring
    }

    var isToolPickerAvailable: Bool {
        !presentation.isToolsButtonHidden
    }

    var isToolSelected: Bool {
        toolsController.selectedTool != nil
    }

    /// The currently selected tool, or `nil` when none is active. Drives the iPad selected-tool badge.
    var selectedTool: AIChatRAGTool? {
        toolsController.selectedTool
    }

    var selectedToolHidesReasoningPicker: Bool {
        guard let tool = toolsController.selectedTool,
              let identifier = UTIToolsMenu.Item.Identifier(tool: tool) else { return false }
        return identifier.hidesReasoningPicker
    }

    var selectedToolsForSubmission: [AIChatRAGTool]? {
        toolsController.selectedToolsForSubmission()
    }

    func makeMenu() -> UIMenu? {
        guard let toolsMenu = presentation.toolsMenu else { return nil }
        return menuFactory.makeMenu(toolsMenu) { [weak self] identifier in
            self?.handleToolSelection(identifier)
        }
    }

    func handleToolSelection(_ identifier: UTIToolsMenu.Item.Identifier) {
        let tool: AIChatRAGTool
        switch identifier {
        case .webSearch:
            tool = .webSearch
        case .imageGeneration:
            tool = .imageGeneration
        case .customizeResponses:
            return
        }

        let previousTool = toolsController.selectedTool
        let notice: CreateImageModelSwitchNotice?
        if tool == .imageGeneration {
            notice = toggleImageGenerationSelection()
        } else {
            toolsController.toggleSelection(for: tool, modelStore: store)
            notice = nil
        }
        updateModelSwitchNotice(notice)
        fireToggleTransitionPixel(previous: previousTool, current: toolsController.selectedTool)
        onToolsUpdated?()
    }

    func handleModelChanged() {
        updateModelSwitchNotice(nil)
        handleModelsUpdated()
    }

    func handleModelsUpdated() {
        toolsController.clearSelectionIfUnsupported(for: store)
        if toolsController.selectedTool != .imageGeneration {
            updateModelSwitchNotice(nil)
        }
        onToolsUpdated?()
    }

    func resetSelection(isUserInitiated: Bool = false) {
        updateModelSwitchNotice(nil)
        guard let previousTool = toolsController.selectedTool else { return }
        toolsController.clearSelection()
        if isUserInitiated {
            UnifiedToggleInputCoordinatorPixelHelper.fireToolDeselectedPixel(for: previousTool, surface: .addressBar)
        }
        onToolsUpdated?()
    }

    func dismissModelSwitchNotice() {
        guard modelSwitchNotice != nil else { return }
        createImagePixelFiring.modelSwitchNoticeDismissed()
        clearModelSwitchNotice()
    }

    func clearModelSwitchNotice() {
        updateModelSwitchNotice(nil)
    }

    // MARK: - Private

    private var presentation: UTIToolsController.Presentation {
        toolsController.presentation(
            isActive: true,
            modelStore: store,
            canShowCustomizeResponses: false,
            createImagePolicy: createImageMenuPolicy
        )
    }

    private var createImageMenuPolicy: CreateImageMenuPolicy {
        guard isUpdatedCreateImageEnabled else { return .legacy }
        return .updated(canSwitchModel: canSwitchModelForImageGeneration)
    }

    private var canSwitchModelForImageGeneration: Bool {
        store.imageGenerationFallbackModel != nil
    }

    private func toggleImageGenerationSelection() -> CreateImageModelSwitchNotice? {
        createImageModelSwitcher.toggle(
            toolsController: toolsController,
            modelStore: store,
            canSwitchModel: canSwitchModelForImageGeneration,
            entryPoint: .toolsMenu,
            applyModel: { store.updateSelectedModel($0, isNewChatContext: true) })
    }

    private func updateModelSwitchNotice(_ notice: CreateImageModelSwitchNotice?) {
        guard notice != modelSwitchNotice else { return }
        modelSwitchNotice = notice
        onModelSwitchNoticeUpdated?(notice)
    }

    private func fireToggleTransitionPixel(previous: AIChatRAGTool?, current: AIChatRAGTool?) {
        guard previous != current else { return }
        if let previous, current == nil || current != previous {
            UnifiedToggleInputCoordinatorPixelHelper.fireToolDeselectedPixel(for: previous, surface: .addressBar)
        }
        if let current {
            UnifiedToggleInputCoordinatorPixelHelper.fireToolSelectedPixel(for: current, surface: .addressBar)
        }
    }
}
