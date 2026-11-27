//
//  BrowserToolAdapters.swift
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
import AppKit
import History

extension ListOpenTabsBrowserTool {
    convenience init(windowControllersManager: WindowControllersManagerProtocol) {
        self.init { context in
            guard let token = context.ownerWindowToken,
                  let collection = AIChatTabPickerSource.tabCollectionViewModel(forWindowToken: token,
                                                                               in: windowControllersManager) else {
                return nil
            }
            let tabs = (collection.pinnedTabsCollection?.tabs ?? []) + collection.tabCollection.tabs
            let entries: [TabEntry] = tabs.compactMap { tab in
                guard BrowserToolTargetTab.isListed(tab), case .url(let url, _, _) = tab.content else { return nil }
                return TabEntry(id: tab.uuid, title: tab.title ?? url.host ?? "", url: url)
            }
            // The window's selection, not the chat's owner: a sidebar's host tab may be backgrounded.
            return (entries, collection.selectedTabViewModel?.tab.uuid)
        }
    }
}

extension SwitchToTabBrowserTool {
    convenience init(windowControllersManager: WindowControllersManagerProtocol) {
        self.init { targetTabID, context in
            // A pinned tab can belong to several windows. Select it in the chat's own window.
            guard let token = context.ownerWindowToken,
                  let collection = AIChatTabPickerSource.tabCollectionViewModel(forWindowToken: token,
                                                                               in: windowControllersManager),
                  BrowserToolTargetTab.actionableTab(withID: targetTabID, in: collection) != nil,
                  let index = collection.indexInAllTabs(where: { $0.uuid == targetTabID }),
                  let tab = collection.selectTab(at: index) else {
                return .failure(.notFound)
            }
            windowControllersManager.windowController(for: collection)?.window?.makeKeyAndOrderFront(nil)
            return .success((tab.title ?? "", tab.content.userEditableUrl?.absoluteString ?? ""))
        }
    }
}

extension OpenTabBrowserTool {
    convenience init(windowControllersManager: WindowControllersManagerProtocol) {
        self.init { url, context in
            guard let collection = Self.targetCollection(for: context, in: windowControllersManager) else { return nil }

            let tab = Tab(content: .url(url, credential: nil, source: .link), shouldLoadInBackground: true, burnerMode: collection.burnerMode)
            collection.insertOrAppend(tab: tab, selected: false)
            guard collection.indexInAllTabs(of: tab) != nil else { return nil }
            return tab.uuid
        }
    }

    private static func targetCollection(for context: BrowserToolCallContext, in windowControllersManager: WindowControllersManagerProtocol) -> TabCollectionViewModel? {
        if context.isDetached,
           let collection = windowControllersManager.lastKeyMainWindowController(where: { !$0.mainViewController.isBurner })?
            .mainViewController.tabCollectionViewModel {
            return collection
        }
        guard let token = context.ownerWindowToken else { return nil }
        return AIChatTabPickerSource.tabCollectionViewModel(forWindowToken: token, in: windowControllersManager)
    }
}

extension CloseTabsBrowserTool {
    convenience init(windowControllersManager: WindowControllersManagerProtocol) {
        self.init(prepareBatch: { requestedIDs, context in
            guard let token = context.ownerWindowToken,
                  let collection = AIChatTabPickerSource.tabCollectionViewModel(forWindowToken: token, in: windowControllersManager) else {
                return .failure(.unavailable)
            }
            guard let tabs = BrowserToolTargetTab.actionableTabs(withIDs: requestedIDs, ownerTabID: context.ownerTabID, in: collection) else {
                return .failure(.notFound)
            }
            return .success(PreparedBatch(ids: tabs.map(\.uuid)) {
                Set(tabs.compactMap { tab in
                    let id = tab.uuid
                    // Pinned tabs stay open.
                    guard let index = collection.indexInAllTabs(where: { $0.uuid == id }), index.isUnpinnedTab else { return nil }
                    collection.close(at: index)
                    return collection.indexInAllTabs(where: { $0.uuid == id }) == nil ? id : nil
                })
            })
        })
    }
}

extension ReadTabContentBrowserTool {
    convenience init(windowControllersManager: WindowControllersManagerProtocol, reader: BrowserToolPageContentReading) {
        self.init(readPage: pageLoader(windowControllersManager: windowControllersManager, reader: reader))
    }
}

extension FindInPageBrowserTool {
    convenience init(windowControllersManager: WindowControllersManagerProtocol, reader: BrowserToolPageContentReading) {
        self.init(readPage: pageLoader(windowControllersManager: windowControllersManager, reader: reader))
    }
}

extension SearchHistoryBrowserTool {
    convenience init(historyCoordinator: HistoryCoordinating) {
        self.init { _ in historyCoordinator.allHistoryVisits ?? [] }
    }
}

private func pageLoader(windowControllersManager: WindowControllersManagerProtocol, reader: BrowserToolPageContentReading) -> BrowserToolPageLoader {
    { tabIDArgument, context in
        switch BrowserToolTargetTab.resolve(tabIDArgument: tabIDArgument, context: context, in: windowControllersManager) {
        case .failure(let failure):
            return .failure(failure)
        case .resolved(let tabID, let collection):
            guard let page = await reader.pageContext(forTabID: tabID, in: collection) else {
                return .failure(.unavailable)
            }
            return .success(page.withTabId(tabID))
        }
    }
}

extension SearchBookmarksBrowserTool {
    convenience init(bookmarkManager: BookmarkManager) {
        self.init { search, _ in
            guard let list = bookmarkManager.list else { return nil }
            return search.matches(in: list.topLevelEntities) { entity in
                guard let folder = entity as? BookmarkFolder else { return nil }
                return (folder.title, { folder.children })
            } bookmark: { entity in
                guard let bookmark = entity as? Bookmark, let url = bookmark.urlObject, url.isHttpOrHttps else { return nil }
                return (bookmark.title, url)
            }
        }
    }
}
