//
//  AIChatTabPickerSource.swift
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

import AIChat
import AppKit
import WebKit

/// Single source of truth for which open tabs a Duck.ai "attach tabs" picker may offer, shared by
/// all three surfaces (address bar omnibar, Duck.ai sidebar, New Tab Page omnibar).
///
/// Scope depends on the window where the picker was opened:
/// - **Regular window** → tabs from every regular (non–Fire) window; Fire Window tabs are excluded.
/// - **Fire Window** → only that same Fire Window's tabs (each Fire Window is an isolated session).
///
/// Returned tabs are URL tabs only, run through `AIChatTabMetadata.shouldExcludeFromTabPicker`,
/// pinned-tab- and uuid-deduplicated, and ordered with the origin window first. Callers map the
/// `Tab`s to their own output type and apply any surface-specific filtering / current-tab handling.
@MainActor
enum AIChatTabPickerSource {

    /// The tab collections to source from, given the picker's origin window.
    static func tabCollections(forOrigin origin: TabCollectionViewModel,
                               in windowControllersManager: WindowControllersManagerProtocol) -> [TabCollectionViewModel] {
        guard !origin.isBurner else {
            // A Fire Window only ever sees its own tabs — never other windows, regular or fire.
            return [origin]
        }
        return windowControllersManager.allTabCollectionViewModels.filter { !$0.isBurner }
    }

    /// Resolves the tab collection of the window that owns `webView`, falling back to the key main
    /// window when the webView can't be mapped to a main window (e.g. a floating AI chat window).
    static func originTabCollectionViewModel(for webView: WKWebView?,
                                             in windowControllersManager: WindowControllersManagerProtocol) -> TabCollectionViewModel? {
        if let window = webView?.window,
           let controller = windowControllersManager.mainWindowControllers.first(where: { $0.window === window }) {
            return controller.mainViewController.tabCollectionViewModel
        }
        return windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel
    }

    /// All attachable tabs (including suspended/unloaded) across the origin-scoped collections,
    /// origin window first. Returns `AnyTab` so metadata is available even for unloaded tabs.
    static func attachableTabs(forOrigin origin: TabCollectionViewModel,
                               in windowControllersManager: WindowControllersManagerProtocol) -> [AnyTab] {
        let collections = originFirst(tabCollections(forOrigin: origin, in: windowControllersManager), origin: origin)
        var seen = Set<String>()
        var result: [AnyTab] = []
        for collection in collections {
            let pinned = collection.pinnedTabsCollection?.tabs ?? []
            for tab in pinned + collection.tabCollection.tabs {
                guard case .url(let url, _, _) = tab.content else { continue }
                guard !AIChatTabMetadata.shouldExcludeFromTabPicker(url) else { continue }
                guard seen.insert(tab.uuid).inserted else { continue }
                result.append(tab)
            }
        }
        return result
    }

    /// Loaded tabs across the origin-scoped collections (for content extraction), origin first.
    static func attachableLoadedTabs(forOrigin origin: TabCollectionViewModel,
                                     in windowControllersManager: WindowControllersManagerProtocol) -> [Tab] {
        let collections = originFirst(tabCollections(forOrigin: origin, in: windowControllersManager), origin: origin)
        var seen = Set<String>()
        var result: [Tab] = []
        for collection in collections {
            let pinned = collection.pinnedTabsCollection?.loadedTabs ?? []
            for tab in pinned + collection.tabCollection.loadedTabs where seen.insert(tab.uuid).inserted {
                result.append(tab)
            }
        }
        return result
    }

    /// Loaded tab matching `id`, scoped the same way — for extracting content by tab id.
    static func attachableLoadedTab(withId id: String,
                                    forOrigin origin: TabCollectionViewModel,
                                    in windowControllersManager: WindowControllersManagerProtocol) -> Tab? {
        attachableLoadedTabs(forOrigin: origin, in: windowControllersManager).first { $0.uuid == id }
    }

    private static func originFirst(_ collections: [TabCollectionViewModel], origin: TabCollectionViewModel) -> [TabCollectionViewModel] {
        guard let index = collections.firstIndex(where: { $0 === origin }), index != 0 else {
            return collections
        }
        var reordered = collections
        let originCollection = reordered.remove(at: index)
        reordered.insert(originCollection, at: 0)
        return reordered
    }
}
