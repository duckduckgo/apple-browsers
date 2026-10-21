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
            case .keep, .close, .moveToNewWindow: break
            }
        }
        for group in groups where group.action == .moveToNewWindow {
            moveToNewWindow(group.tabIDs)
        }
        close(groups.filter { $0.action == .close }.flatMap(\.tabIDs))
    }

    private var unpinnedTabs: [AnyTab] {
        tabCollectionViewModel.tabCollection.tabs
    }

    private func unpinnedTabs(withIDs ids: [String]) -> [AnyTab] {
        ids.compactMap { id in unpinnedTabs.first { $0.uuid == id } }
    }

    /// Goes through `close(at:)` so Reopen Closed Tab can bring them back.
    private func close(_ ids: [String]) {
        for tab in unpinnedTabs(withIDs: ids) {
            if let index = tabCollectionViewModel.indexInAllTabs(of: tab) {
                tabCollectionViewModel.close(at: index)
            }
        }
    }

    private func moveToNewWindow(_ ids: [String]) {
        let tabs = unpinnedTabs(withIDs: ids)
        guard !tabs.isEmpty else { return }

        let burnerMode = tabCollectionViewModel.burnerMode
        let newCollection = TabCollectionViewModel(tabCollection: TabCollection(tabs: tabs, isPopup: false), burnerMode: burnerMode)
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
