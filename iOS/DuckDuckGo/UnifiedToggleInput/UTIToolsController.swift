//
//  UTIToolsController.swift
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
import DesignResourcesKitIcons
import UIKit

@MainActor
final class UTIToolsController {

    struct Presentation {
        let isToolsButtonHidden: Bool
        let selectedTool: AIChatRAGTool?
        let toolsMenu: UTIToolsMenu?

        static let hidden = Presentation(
            isToolsButtonHidden: true,
            selectedTool: nil,
            toolsMenu: nil
        )
    }

    private(set) var selectedTool: AIChatRAGTool?

    func select(_ tool: AIChatRAGTool, for modelStore: UTIModelStore) {
        guard modelStore.selectedModelSupports(tool: tool) else { return }
        selectedTool = tool
    }

    func toggleSelection(for tool: AIChatRAGTool, modelStore: UTIModelStore) {
        if selectedTool == tool {
            clearSelection()
            return
        }
        select(tool, for: modelStore)
    }

    func clearSelection() {
        selectedTool = nil
    }

    func clearSelectionIfUnsupported(for modelStore: UTIModelStore) {
        guard let selectedTool, !modelStore.selectedModelSupports(tool: selectedTool) else { return }
        self.selectedTool = nil
    }

    func selectedToolsForSubmission() -> [AIChatRAGTool]? {
        selectedTool.map { [$0] }
    }

    func presentation(
        displayState: UnifiedToggleInputDisplayState,
        modelStore: UTIModelStore,
        canShowCustomizeResponses: Bool
    ) -> Presentation {
        let toolsMenu = buildToolsMenu(
            modelStore: modelStore,
            canShowCustomizeResponses: canShowCustomizeResponses
        )
        guard canShowTools(displayState: displayState),
              hasActionableMenuItem(modelStore: modelStore, toolsMenu: toolsMenu) else {
            return .hidden
        }

        return Presentation(
            isToolsButtonHidden: false,
            selectedTool: selectedTool,
            toolsMenu: toolsMenu
        )
    }

    private func hasActionableMenuItem(modelStore: UTIModelStore, toolsMenu: UTIToolsMenu) -> Bool {
        toolsMenu.items.contains { item in
            guard let tool = item.tool else {
                // Non-tool actions (e.g. Customize Responses) are always available and keep the tools button visible.
                return true
            }
            return modelStore.selectedModelSupports(tool: tool)
        }
    }
}

private extension UTIToolsController {

    // Mode-gating lives at the toolbar-container level; toggling `isHidden` per-button would step-vanish before the toolbar's alpha fade completes.
    func canShowTools(displayState: UnifiedToggleInputDisplayState) -> Bool {
        return displayState != .hidden
    }

    func buildToolsMenu(modelStore: UTIModelStore, canShowCustomizeResponses: Bool) -> UTIToolsMenu {
        var items: [UTIToolsMenu.Item] = []

        if canShowCustomizeResponses {
            items.append(.customizeResponses)
        }

        items.append(.imageGeneration(
            isSelected: selectedTool == .imageGeneration,
            isEnabled: modelStore.selectedModelSupports(tool: .imageGeneration)
        ))
        items.append(.webSearch(
            isSelected: selectedTool == .webSearch,
            isEnabled: modelStore.selectedModelSupports(tool: .webSearch)
        ))

        return UTIToolsMenu(items: items)
    }
}

struct UTIToolsMenu {

    enum Item: Equatable {
        case customizeResponses
        case webSearch(isSelected: Bool, isEnabled: Bool)
        case imageGeneration(isSelected: Bool, isEnabled: Bool)

        enum Identifier {
            case customizeResponses
            case webSearch
            case imageGeneration
        }

        var identifier: Identifier {
            switch self {
            case .customizeResponses:
                return .customizeResponses
            case .webSearch:
                return .webSearch
            case .imageGeneration:
                return .imageGeneration
            }
        }

        /// The model-gated RAG tool this item toggles, or `nil` for actions (e.g. Customize Responses)
        /// that aren't model-dependent and don't participate in tool selection.
        var tool: AIChatRAGTool? {
            switch self {
            case .customizeResponses:
                return nil
            case .webSearch:
                return .webSearch
            case .imageGeneration:
                return .imageGeneration
            }
        }
    }

    let items: [Item]
}

struct UTIToolsMenuFactory {

    func makeMenu(_ menu: UTIToolsMenu, onSelect: @escaping (UTIToolsMenu.Item.Identifier) -> Void) -> UIMenu {
        let customizeActions = menu.items
            .filter { $0.identifier == .customizeResponses }
            .map { makeAction($0, onSelect: onSelect) }
        let toolActions = menu.items
            .filter { $0.identifier != .customizeResponses }
            .map { makeAction($0, onSelect: onSelect) }

        var children: [UIMenuElement] = customizeActions
        if !toolActions.isEmpty {
            children.append(UIMenu(options: .displayInline, children: toolActions))
        }
        return UIMenu(children: children)
    }

    private func makeAction(_ item: UTIToolsMenu.Item, onSelect: @escaping (UTIToolsMenu.Item.Identifier) -> Void) -> UIAction {
        switch item {
        case .customizeResponses:
            return makeCustomizeResponsesAction(onSelect: onSelect)
        case let .webSearch(isSelected, isEnabled):
            return makeWebSearchAction(
                isSelected: isSelected,
                isEnabled: isEnabled,
                onSelect: onSelect
            )
        case let .imageGeneration(isSelected, isEnabled):
            return makeImageGenerationAction(
                isSelected: isSelected,
                isEnabled: isEnabled,
                onSelect: onSelect
            )
        }
    }

    private func makeCustomizeResponsesAction(
        onSelect: @escaping (UTIToolsMenu.Item.Identifier) -> Void
    ) -> UIAction {
        return UIAction(
            title: UserText.aiChatToolbarCustomizeResponsesMenuTitle,
            subtitle: UserText.aiChatToolbarCustomizeResponsesMenuSubtitle
        ) { _ in
            onSelect(.customizeResponses)
        }
    }

    private func makeWebSearchAction(
        isSelected: Bool,
        isEnabled: Bool,
        onSelect: @escaping (UTIToolsMenu.Item.Identifier) -> Void
    ) -> UIAction {
        let state: UIMenuElement.State = isSelected ? .on : .off
        let attributes: UIMenuElement.Attributes = isEnabled ? [] : .disabled

        return UIAction(
            title: UserText.aiChatToolbarWebSearchToolTitle,
            subtitle: UserText.aiChatToolbarWebSearchToolSubtitle,
            image: DesignSystemImages.Glyphs.Size24.globe,
            attributes: attributes,
            state: state
        ) { _ in
            onSelect(.webSearch)
        }
    }

    private func makeImageGenerationAction(
        isSelected: Bool,
        isEnabled: Bool,
        onSelect: @escaping (UTIToolsMenu.Item.Identifier) -> Void
    ) -> UIAction {
        let state: UIMenuElement.State = isSelected ? .on : .off
        let attributes: UIMenuElement.Attributes = isEnabled ? [] : .disabled

        return UIAction(
            title: UserText.aiChatToolbarImageGenerationToolTitle,
            subtitle: UserText.aiChatToolbarImageGenerationToolSubtitle,
            image: DesignSystemImages.Glyphs.Size24.images,
            attributes: attributes,
            state: state
        ) { _ in
            onSelect(.imageGeneration)
        }
    }
}
