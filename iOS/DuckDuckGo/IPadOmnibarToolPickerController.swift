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
    private let displayState: UnifiedToggleInputDisplayState = .omnibar(.active)
    var onToolsUpdated: (() -> Void)?

    init(store: UTIModelStore) {
        self.store = store
    }

    var isToolPickerAvailable: Bool {
        !presentation.isToolsButtonHidden
    }

    var isToolSelected: Bool {
        toolsController.selectedTool != nil
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
        toolsController.toggleSelection(for: tool, modelStore: store)
        fireToggleTransitionPixel(previous: previousTool, current: toolsController.selectedTool)
        onToolsUpdated?()
    }

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
