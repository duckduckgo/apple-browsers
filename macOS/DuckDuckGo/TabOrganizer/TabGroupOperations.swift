//
//  TabGroupOperations.swift
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

import AppKit

/// Direct edits on one of a window's tab groups, shared by the tab bar pill's menu and the organizer popover.
@MainActor
struct TabGroupOperations {

    enum Operation: CaseIterable {
        case toggleCollapsed
        case rename
        case ungroup
        case moveToNewWindow
        case bookmark
        case close

        func title(isCollapsed: Bool) -> String {
            switch self {
            case .toggleCollapsed: return isCollapsed ? "Expand Group" : "Collapse Group"
            case .rename: return "Rename Group…"
            case .ungroup: return "Ungroup"
            case .moveToNewWindow: return "Move Group to New Window"
            case .bookmark: return "Save Group as Bookmarks Folder"
            case .close: return "Close Group"
            }
        }
    }

    let tabCollectionViewModel: TabCollectionViewModel
    var windowControllersManager: WindowControllersManagerProtocol = NSApp.delegateTyped.windowControllersManager

    private var tabGroupManager: TabGroupManager { tabCollectionViewModel.tabGroupManager }

    func perform(_ operation: Operation, on group: TabGroup) {
        switch operation {
        case .toggleCollapsed:
            tabGroupManager.toggleCollapsed(group)
        case .rename:
            if let name = Self.askForName(current: group.name) {
                rename(group, to: name)
            }
        case .ungroup:
            ungroup(group)
        case .moveToNewWindow:
            moveToNewWindow(group)
        case .bookmark:
            TabOrganizerActions(tabCollectionViewModel: tabCollectionViewModel)
                .apply([ProposedGroup(name: group.name, tabIDs: tabIDs(in: group), action: .bookmark)])
        case .close:
            let ids = tabIDs(in: group)
            ungroup(group)
            TabOrganizerActions(tabCollectionViewModel: tabCollectionViewModel).close(ids)
        }
    }

    func rename(_ group: TabGroup, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tabGroupManager.updateGroup(group, name: trimmed, color: group.color)
    }

    func ungroup(_ group: TabGroup) {
        for tab in tabGroupManager.tabs(in: group, from: tabCollectionViewModel.tabCollection.tabs) {
            tabGroupManager.setGroup(nil, for: tab)
        }
        tabGroupManager.unregisterGroup(group)
    }

    /// The tabs leave this window and form the same group, name and colour, in a new one.
    func moveToNewWindow(_ group: TabGroup) {
        let tabs = tabGroupManager.tabs(in: group, from: tabCollectionViewModel.tabCollection.tabs)
        guard !tabs.isEmpty else { return }

        let burnerMode = tabCollectionViewModel.burnerMode
        let newCollection = TabCollectionViewModel(tabCollection: TabCollection(tabs: tabs, isPopup: false), burnerMode: burnerMode)
        let newGroup = newCollection.tabGroupManager.createGroup(name: group.name, color: group.color)
        for tab in tabs {
            newCollection.tabGroupManager.setGroup(newGroup.id, for: tab)
        }

        ungroup(group)
        let indices = tabs.compactMap { tabCollectionViewModel.indexInAllTabs(of: $0) }.sorted(by: >)
        windowControllersManager.openNewWindow(with: newCollection, burnerMode: burnerMode, showWindow: true)
        for index in indices {
            tabCollectionViewModel.remove(at: index)
        }
    }

    private func tabIDs(in group: TabGroup) -> [String] {
        tabGroupManager.tabs(in: group, from: tabCollectionViewModel.tabCollection.tabs).map(\.uuid)
    }

    static func askForName(current: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Rename group"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = current
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }
}
