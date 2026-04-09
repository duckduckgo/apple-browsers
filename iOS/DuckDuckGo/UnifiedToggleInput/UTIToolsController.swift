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
        guard tool == .webSearch, modelStore.selectedModelSupports(tool: tool) else { return }
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
        guard let selectedTool, modelStore.selectedModelSupports(tool: selectedTool) == false else { return }
        self.selectedTool = nil
    }

    func selectedToolsForSubmission() -> [AIChatRAGTool]? {
        selectedTool.map { [$0] }
    }

    func presentation(
        displayState: UnifiedToggleInputDisplayState,
        inputMode: TextEntryMode,
        modelStore: UTIModelStore
    ) -> Presentation {
        guard canShowTools(displayState: displayState, inputMode: inputMode) else {
            return .hidden
        }

        return Presentation(
            isToolsButtonHidden: false,
            selectedTool: selectedTool,
            toolsMenu: buildToolsMenu(displayState: displayState, modelStore: modelStore)
        )
    }
}

private extension UTIToolsController {

    func canShowTools(
        displayState: UnifiedToggleInputDisplayState,
        inputMode: TextEntryMode
    ) -> Bool {
        guard displayState != .hidden else { return false }
        return inputMode == .aiChat
    }

    func buildToolsMenu(
        displayState: UnifiedToggleInputDisplayState,
        modelStore: UTIModelStore
    ) -> UTIToolsMenu {
        var items: [UTIToolsMenu.Item] = []

        if case .aiTab = displayState {
            items.append(.customizeResponses)
        }

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

        enum Identifier {
            case customizeResponses
            case webSearch
        }

        var identifier: Identifier {
            switch self {
            case .customizeResponses:
                return .customizeResponses
            case .webSearch:
                return .webSearch
            }
        }
    }

    let items: [Item]
}

struct UTIToolsMenuFactory {

    func makeMenu(_ menu: UTIToolsMenu, onSelect: @escaping (UTIToolsMenu.Item.Identifier) -> Void) -> UIMenu {
        let actions = menu.items.map { item in
            makeAction(item, onSelect: onSelect)
        }
        return UIMenu(children: actions)
    }

    private func makeAction(_ item: UTIToolsMenu.Item, onSelect: @escaping (UTIToolsMenu.Item.Identifier) -> Void) -> UIAction {
        switch item {
        case .customizeResponses:
            return UIAction(
                title: UserText.aiChatToolbarCustomizeResponsesMenuTitle,
                image: DesignSystemImages.Glyphs.Size24.options
            ) { _ in
                onSelect(item.identifier)
            }
        case let .webSearch(isSelected, isEnabled):
            return makeWebSearchAction(
                isSelected: isSelected,
                isEnabled: isEnabled,
                onSelect: onSelect
            )
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
}
