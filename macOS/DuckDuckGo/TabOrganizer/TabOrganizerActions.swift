//
//  TabOrganizerActions.swift
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

/// Applies a reviewed proposal to the window's tabs. Pinned tabs are never closed or moved.
@MainActor
struct TabOrganizerActions {

    let tabCollectionViewModel: TabCollectionViewModel
    var bookmarkManager: BookmarkManager = NSApp.delegateTyped.bookmarkManager
    var windowControllersManager: WindowControllersManagerProtocol = NSApp.delegateTyped.windowControllersManager

    /// `groups` hold only the tabs the user kept selected.
    func apply(_ groups: [ProposedGroup]) {
        for group in groups {
            switch group.action {
            case .bookmark: bookmark(group)
            case .addToFavorites: addToFavorites(group)
            case .createTabGroup: createTabGroup(group)
            case .ungroup: ungroup(group)
            case .keep, .close, .moveToNewWindow: break
            }
        }
        moveToNewWindow(groups.filter { $0.action == .moveToNewWindow })
        close(groups.filter { $0.action == .close }.flatMap(\.tabIDs))
    }

    private var unpinnedTabs: [AnyTab] {
        tabCollectionViewModel.tabCollection.tabs
    }

    private func unpinnedTabs(withIDs ids: [String]) -> [AnyTab] {
        ids.compactMap { id in unpinnedTabs.first { $0.uuid == id } }
    }

    /// Unpinned duplicates (same URL; the current tab, else the leftmost, stays) and empty new tabs. No AI.
    func cleanupCandidateIDs() -> [String] {
        let selectedID = tabCollectionViewModel.selectedTabViewModel?.tab.uuid
        var keptByURL: [URL: String] = [:]
        var candidates: [String] = []
        var hasKeptNewTab = false

        for tab in unpinnedTabs {
            switch tab.content {
            case .newtab:
                if tab.uuid == selectedID, !hasKeptNewTab {
                    hasKeptNewTab = true
                } else {
                    candidates.append(tab.uuid)
                }
            case .url(let url, _, _):
                guard let keptID = keptByURL[url] else {
                    keptByURL[url] = tab.uuid
                    continue
                }
                if tab.uuid == selectedID {
                    candidates.append(keptID)
                    keptByURL[url] = tab.uuid
                } else {
                    candidates.append(tab.uuid)
                }
            default:
                continue
            }
        }
        return candidates
    }

    /// Goes through `close(at:)` so Reopen Closed Tab can bring them back.
    func close(_ ids: [String]) {
        for tab in unpinnedTabs(withIDs: ids) {
            if let index = tabCollectionViewModel.indexInAllTabs(of: tab) {
                tabCollectionViewModel.close(at: index)
            }
        }
    }

    /// All "New window" groups go into one new window; with more than one, each becomes a tab group there.
    private func moveToNewWindow(_ groups: [ProposedGroup]) {
        let groupedTabs = groups.map { (group: $0, tabs: unpinnedTabs(withIDs: $0.tabIDs)) }.filter { !$0.tabs.isEmpty }
        let tabs = groupedTabs.flatMap(\.tabs)
        guard !tabs.isEmpty else { return }

        let burnerMode = tabCollectionViewModel.burnerMode
        let newCollection = TabCollectionViewModel(tabCollection: TabCollection(tabs: tabs, isPopup: false), burnerMode: burnerMode)
        if groupedTabs.count > 1 {
            for (index, entry) in groupedTabs.enumerated() {
                let color = TabGroupColor.allCases[index % TabGroupColor.allCases.count]
                let tabGroup = newCollection.tabGroupManager.createGroup(name: entry.group.name, color: color)
                for tab in entry.tabs {
                    newCollection.tabGroupManager.setGroup(tabGroup.id, for: tab)
                }
            }
        }
        for tab in tabs {
            tabCollectionViewModel.tabGroupManager.setGroup(nil, for: tab)
        }
        windowControllersManager.openNewWindow(with: newCollection, burnerMode: burnerMode, showWindow: true)

        let indices = tabs.compactMap { tabCollectionViewModel.indexInAllTabs(of: $0) }.sorted(by: >)
        for index in indices {
            tabCollectionViewModel.remove(at: index)
        }
    }

    private func websites(for group: ProposedGroup) -> [WebsiteInfo] {
        let allTabs = (tabCollectionViewModel.pinnedTabsCollection?.tabs ?? []) + unpinnedTabs
        return group.tabIDs.compactMap { id in
            guard let tab = allTabs.first(where: { $0.uuid == id }), case .url(let url, _, _) = tab.content else { return nil }
            return WebsiteInfo(url: url, title: tab.title)
        }
    }

    private func bookmark(_ group: ProposedGroup) {
        let websites = websites(for: group)
        guard !websites.isEmpty else { return }
        bookmarkManager.makeBookmarks(for: websites, inNewFolderNamed: group.name, withinParentFolder: .root)
    }

    /// Joins the window's tab group with the same name, otherwise creates one in the next unused colour.
    private func createTabGroup(_ group: ProposedGroup) {
        let tabs = unpinnedTabs(withIDs: group.tabIDs)
        guard !tabs.isEmpty else { return }

        let tabGroupManager = tabCollectionViewModel.tabGroupManager
        let tabGroup = tabGroupManager.groups.first { $0.name.caseInsensitiveCompare(group.name) == .orderedSame }
            ?? tabGroupManager.createGroup(name: group.name, color: nextColor(in: tabGroupManager))
        for tab in tabs {
            tabGroupManager.setGroup(tabGroup.id, for: tab)
        }
        tabCollectionViewModel.arrangeTabsByGroup()
    }

    private func ungroup(_ group: ProposedGroup) {
        let tabGroupManager = tabCollectionViewModel.tabGroupManager
        for tab in unpinnedTabs(withIDs: group.tabIDs) {
            tabGroupManager.setGroup(nil, for: tab)
        }
        if let tabGroup = tabGroupManager.groups.first(where: { $0.name == group.name }),
           tabGroupManager.tabs(in: tabGroup, from: unpinnedTabs).isEmpty {
            tabGroupManager.unregisterGroup(tabGroup)
        }
    }

    private func nextColor(in tabGroupManager: TabGroupManager) -> TabGroupColor {
        let used = Set(tabGroupManager.groups.map(\.color))
        return TabGroupColor.allCases.first { !used.contains($0) }
            ?? TabGroupColor.allCases[tabGroupManager.groups.count % TabGroupColor.allCases.count]
    }

    private func addToFavorites(_ group: ProposedGroup) {
        for website in websites(for: group) {
            if let bookmark = bookmarkManager.getBookmark(for: website.url) {
                bookmark.isFavorite = true
                bookmarkManager.update(bookmark: bookmark)
            } else {
                bookmarkManager.makeBookmark(for: website.url, title: website.title, isFavorite: true)
            }
        }
    }
}
