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
///
/// Like the sibling `IPadOmnibarModelPickerController` and `IPadOmnibarReasoningPickerController`,
/// this is a thin wrapper around the shared UnifiedToggleInput tool components
/// (`UTIToolsController` + `UTIToolsMenuFactory`) so tools behave identically to the iPhone
/// Duck.ai bar. Tools are gated purely by the selected model's capabilities (no subscription
/// upsell), so this controller is simpler than the model / reasoning pickers. It shares the model
/// picker's `UTIModelStore` so a single `/models` fetch drives tool-support gating for every chip.
@MainActor
final class IPadOmnibarToolPickerController {

    private let store: UTIModelStore
    private let toolsController = UTIToolsController()
    private let menuFactory = UTIToolsMenuFactory()

    /// The iPad address bar is an omnibar surface (never an AI tab), so the tools menu never
    /// offers the AI-tab-only "Customize Responses" action.
    private let displayState: UnifiedToggleInputDisplayState = .omnibar(.active)

    /// Invoked whenever the tool selection changes so the host can refresh the chip (tint and
    /// menu) and re-evaluate the reasoning picker's visibility.
    var onToolsUpdated: (() -> Void)?

    init(store: UTIModelStore) {
        self.store = store
    }

    /// Whether the tools button should be shown — i.e. the selected model offers at least one
    /// actionable tool (mirrors the iPhone presentation rule for the omnibar surface).
    var isToolPickerAvailable: Bool {
        !presentation.isToolsButtonHidden
    }

    /// Whether a tool is currently selected — drives the chip's active tint.
    var isToolSelected: Bool {
        toolsController.selectedTool != nil
    }

    /// Whether the currently selected tool hides the reasoning picker (image generation), so the
    /// host can match the iPhone behavior of hiding reasoning while image generation is active.
    var selectedToolHidesReasoningPicker: Bool {
        guard let tool = toolsController.selectedTool,
              let identifier = UTIToolsMenu.Item.Identifier(tool: tool) else { return false }
        return identifier.hidesReasoningPicker
    }

    /// The tools to forward at submission (the single selected tool wrapped in an array, or `nil`).
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
            // Never offered on the omnibar surface — nothing to toggle.
            return
        }

        let previousTool = toolsController.selectedTool
        toolsController.toggleSelection(for: tool, modelStore: store)
        fireToggleTransitionPixel(previous: previousTool, current: toolsController.selectedTool)
        onToolsUpdated?()
    }

    /// Call when the selected model changes so a tool the new model doesn't support is cleared
    /// (mirrors the iPhone `UTIToolsController.clearSelectionIfUnsupported`).
    func handleModelChanged() {
        toolsController.clearSelectionIfUnsupported(for: store)
        onToolsUpdated?()
    }

    func resetSelection() {
        guard toolsController.selectedTool != nil else { return }
        toolsController.clearSelection()
        onToolsUpdated?()
    }

    // MARK: - Private

    private var presentation: UTIToolsController.Presentation {
        toolsController.presentation(displayState: displayState, modelStore: store)
    }

    /// Mirrors the iPhone coordinator's `fireToolToggleTransitionPixel`: a deselect pixel for the
    /// outgoing tool and a select pixel for the incoming one.
    private func fireToggleTransitionPixel(previous: AIChatRAGTool?, current: AIChatRAGTool?) {
        guard previous != current else { return }
        if let previous, current == nil || current != previous {
            UnifiedToggleInputCoordinatorPixelHelper.fireToolDeselectedPixel(for: previous)
        }
        if let current {
            UnifiedToggleInputCoordinatorPixelHelper.fireToolSelectedPixel(for: current)
        }
    }
}
