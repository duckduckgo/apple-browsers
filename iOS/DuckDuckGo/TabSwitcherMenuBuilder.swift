//
//  TabSwitcherMenuBuilder.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import UIKit
import Core
import DesignResourcesKitIcons

// MARK: - State

struct TabSwitcherMultiSelectMenuState {
    let selectedCount: Int
    let totalCount: Int
    let selectedContainsWebPages: Bool
    let allContainsWebPages: Bool

    var canShowDeselectAll: Bool { selectedCount > 0 && selectedCount == totalCount }
    var canShowSelectAll: Bool { selectedCount < totalCount }
    var canShare: Bool { selectedContainsWebPages }
    var canAddBookmarks: Bool { selectedContainsWebPages }
    var canCloseOther: Bool { selectedCount > 0 && selectedCount < totalCount }
    var canBookmarkAll: Bool { selectedCount == 0 && allContainsWebPages }
    var canClose: Bool { selectedCount > 0 }

    var canShowSelectionMenu: Bool {
        canShowDeselectAll || canShowSelectAll || canShare || canAddBookmarks ||
        canCloseOther || canBookmarkAll || canClose
    }
}

struct TabSwitcherLongPressMenuState {
    let pressedCount: Int
    let totalCount: Int
    let pressedContainsWebPages: Bool
    let isEditing: Bool
    let title: String

    var canShare: Bool { pressedContainsWebPages }
    var canAddBookmarks: Bool { pressedContainsWebPages }
    // Show "Select" for any single tab when not already in selection mode.
    // The "not if it's the home page in selection mode" comment in the original code referred
    // to hiding the option when isEditing is already true — covered by !isEditing.
    // See: https://app.asana.com/0/1209499866654340/1209424833903137
    // See: https://app.asana.com/0/1209499866654340/1209424833902043
    // See: https://app.asana.com/0/1209499866654340/1209503836757555
    var canSelect: Bool { !isEditing && pressedCount == 1 }
    var canCloseOthers: Bool { pressedCount < totalCount }
}

// MARK: - Actions

struct TabSwitcherMultiSelectMenuActions {
    var onDeselectAll: () -> Void
    var onSelectAll: () -> Void
    var onShare: () -> Void
    var onBookmarkSelected: () -> Void
    var onCloseOther: () -> Void
    var onCloseSelected: () -> Void
    var onBookmarkAll: () -> Void
}

struct TabSwitcherLongPressMenuActions {
    var onShare: () -> Void
    var onBookmark: () -> Void
    var onSelect: () -> Void
    var onClose: () -> Void
    var onCloseOther: () -> Void
}

struct TabSwitcherEditMenuActions {
    var onEnterSelectMode: () -> Void
    var onCloseAll: () -> Void
}

// MARK: - Protocol

protocol TabSwitcherMenuBuilding {
    func multiSelectionMenu(state: TabSwitcherMultiSelectMenuState,
                            actions: TabSwitcherMultiSelectMenuActions) -> UIMenu
    func editMenu(actions: TabSwitcherEditMenuActions) -> UIMenu
    func longPressMenu(state: TabSwitcherLongPressMenuState,
                       actions: TabSwitcherLongPressMenuActions) -> UIMenu
}

// MARK: - Default Implementation

class DefaultTabSwitcherMenuBuilder: TabSwitcherMenuBuilding {

    func multiSelectionMenu(state: TabSwitcherMultiSelectMenuState,
                            actions: TabSwitcherMultiSelectMenuActions) -> UIMenu {
        let items = multiSelectionMenuItems(state: state, actions: actions)
        let deferredElement = UIDeferredMenuElement.uncached { completion in
            Pixel.fire(pixel: .tabSwitcherSelectModeMenuClicked)
            completion(items)
        }
        return UIMenu(title: "", children: [deferredElement])
    }

    func editMenu(actions: TabSwitcherEditMenuActions) -> UIMenu {
        let items = editMenuItems(actions: actions)
        let deferredElement = UIDeferredMenuElement.uncached { completion in
            Pixel.fire(pixel: .tabSwitcherEditMenuClicked)
            completion(items)
        }
        return UIMenu(children: [deferredElement])
    }

    func longPressMenu(state: TabSwitcherLongPressMenuState,
                       actions: TabSwitcherLongPressMenuActions) -> UIMenu {
        return UIMenu(title: state.title, children: longPressMenuItems(state: state, actions: actions))
    }

    // MARK: - Internal item builders (exposed for testing)

    func multiSelectionMenuItems(state: TabSwitcherMultiSelectMenuState,
                                 actions: TabSwitcherMultiSelectMenuActions) -> [UIMenuElement] {
        return [
            UIMenu(title: "", options: .displayInline, children: [
                state.canShowDeselectAll ? action(UserText.deselectAllTabs,
                                                  DesignSystemImages.Glyphs.Size16.checkCircle,
                                                  actions.onDeselectAll) : nil,
                state.canShowSelectAll ? action(UserText.selectAllTabs,
                                                DesignSystemImages.Glyphs.Size16.checkCircle,
                                                actions.onSelectAll) : nil,
            ].compactMap { $0 }),

            UIMenu(title: "", options: .displayInline, children: [
                state.canShare ? action(UserText.shareLinks(withCount: state.selectedCount),
                                        DesignSystemImages.Glyphs.Size16.shareApple,
                                        actions.onShare) : nil,
                state.canAddBookmarks ? action(UserText.bookmarkSelectedTabs(withCount: state.selectedCount),
                                               DesignSystemImages.Glyphs.Size16.bookmarkAdd,
                                               actions.onBookmarkSelected) : nil,
            ].compactMap { $0 }),

            UIMenu(title: "", options: .displayInline, children: [
                // Always use plural here
                state.canCloseOther ? destructive(UserText.tabSwitcherCloseOtherTabs(withCount: 2),
                                                  DesignSystemImages.Glyphs.Size16.tabCloseAlt,
                                                  actions.onCloseOther) : nil,
            ].compactMap { $0 }),

            UIMenu(title: "", options: .displayInline, children: [
                state.canClose ? destructive(UserText.closeTabs(withCount: state.selectedCount),
                                             imageForCloseTabs(state.selectedCount),
                                             actions.onCloseSelected) : nil,
            ].compactMap { $0 }),

            UIMenu(title: "", options: .displayInline, children: [
                state.canBookmarkAll ? action(UserText.tabSwitcherBookmarkAllTabs,
                                              DesignSystemImages.Glyphs.Size16.bookmarkAll,
                                              actions.onBookmarkAll) : nil,
            ].compactMap { $0 }),
        ]
    }

    func editMenuItems(actions: TabSwitcherEditMenuActions) -> [UIMenuElement] {
        return [
            // Force plural version - this really means "switch to select tabs mode"
            action(UserText.tabSwitcherSelectTabs(withCount: 2),
                   DesignSystemImages.Glyphs.Size16.checkCircle,
                   actions.onEnterSelectMode),

            UIMenu(title: "", options: [.displayInline], children: [
                destructive(UserText.closeAllTabs,
                            DesignSystemImages.Glyphs.Size16.tabCloseAlt,
                            actions.onCloseAll),
            ]),
        ]
    }

    func longPressMenuItems(state: TabSwitcherLongPressMenuState,
                            actions: TabSwitcherLongPressMenuActions) -> [UIMenuElement] {
        return [
            UIMenu(title: "", options: .displayInline, children: [
                state.canShare ? action(UserText.shareLinks(withCount: state.pressedCount),
                                        DesignSystemImages.Glyphs.Size16.shareApple,
                                        actions.onShare) : nil,
                state.canAddBookmarks ? action(UserText.bookmarkSelectedTabs(withCount: state.pressedCount),
                                               DesignSystemImages.Glyphs.Size16.bookmarkAdd,
                                               actions.onBookmark) : nil,
                state.canSelect ? action(UserText.tabSwitcherSelectTabs(withCount: 1),
                                         DesignSystemImages.Glyphs.Size16.checkCircle,
                                         actions.onSelect) : nil,
            ].compactMap { $0 }),

            UIMenu(title: "", options: .displayInline, children: [
                destructive(UserText.closeTabs(withCount: state.pressedCount),
                            imageForCloseTabs(state.pressedCount),
                            actions.onClose),
            ]),

            UIMenu(title: "", options: .displayInline, children: [
                // Always use plural here
                state.canCloseOthers ? destructive(UserText.tabSwitcherCloseOtherTabs(withCount: 2),
                                                   imageForCloseTabs(2),
                                                   actions.onCloseOther) : nil,
            ].compactMap { $0 }),
        ].compactMap { $0 }
    }

    private func imageForCloseTabs(_ count: Int) -> UIImage {
        return count < 2 ?
            DesignSystemImages.Glyphs.Size16.closeOutline :
            DesignSystemImages.Glyphs.Size16.tabCloseAlt
    }

    private func action(_ title: String, _ image: UIImage? = nil, _ handler: @escaping () -> Void) -> UIAction {
        return UIAction(title: title, image: image) { _ in handler() }
    }

    private func destructive(_ title: String, _ image: UIImage, _ handler: @escaping () -> Void) -> UIAction {
        return UIAction(title: title, image: image, attributes: .destructive) { _ in handler() }
    }
}
