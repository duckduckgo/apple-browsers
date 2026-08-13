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

/// Which open tabs a Duck.ai picker may offer.
///
/// Scope depends on the window the picker was opened from:
/// - **Regular window** → every regular window's tabs, that window's first.
/// - **Fire Window** → only its own tabs; each Fire Window is an isolated session.
///
/// Pinned tabs come before unpinned ones, URL tabs only, filtered by
/// `AIChatTabMetadata.shouldExcludeFromTabPicker` and deduplicated by uuid, since a shared pinned
/// collection appears in every window.
@MainActor
enum AIChatTabPickerSource {

    /// Resolves the tab collection of the window that owns `webView`.
    static func originTabCollectionViewModel(for webView: WKWebView?,
                                             in windowControllersManager: WindowControllersManagerProtocol) -> TabCollectionViewModel? {
        guard let webView else {
            return windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel
        }
        if let window = webView.window,
           let controller = windowControllersManager.mainWindowControllers.first(where: { $0.window === window }) {
            return controller.mainViewController.tabCollectionViewModel
        }
        // A detached Duck.ai window belongs to the tab it was opened from, which is not necessarily
        // in the key window — resolving to that one would hand a Fire Window chat regular tabs.
        guard let tabID = hostingAIChatViewController(of: webView)?.tabID else {
            return webView.window == nil
                ? windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel
                : nil
        }
        return windowControllersManager.allTabCollectionViewModels.first { collection in
            collection.indexInAllTabs(where: { $0.uuid == tabID }) != nil
        }
    }

    private static func hostingAIChatViewController(of webView: WKWebView) -> AIChatViewController? {
        var responder: NSResponder? = webView
        while let current = responder {
            if let viewController = current as? AIChatViewController { return viewController }
            responder = current.nextResponder
        }
        return nil
    }

    /// The collections to source from, the origin's first. A regular window sees every other
    /// regular window; a Fire Window sees only itself.
    static func tabCollections(forOrigin origin: TabCollectionViewModel,
                               in windowControllersManager: WindowControllersManagerProtocol) -> [TabCollectionViewModel] {
        guard !origin.isBurner else { return [origin] }
        let others = windowControllersManager.allTabCollectionViewModels.filter { !$0.isBurner && $0 !== origin }
        return [origin] + others
    }

    /// `AnyTab` so metadata is available for suspended/unloaded tabs too.
    static func attachableTabs(forOrigin origin: TabCollectionViewModel,
                               in windowControllersManager: WindowControllersManagerProtocol) -> [AnyTab] {
        var seen = Set<String>()
        return tabCollections(forOrigin: origin, in: windowControllersManager)
            .flatMap { collection in (collection.pinnedTabsCollection?.tabs ?? []) + collection.tabCollection.tabs }
            .filter { tab in
                guard case .url(let url, _, _) = tab.content, !AIChatTabMetadata.shouldExcludeFromTabPicker(url) else { return false }
                return seen.insert(tab.uuid).inserted
            }
    }

    /// The result of resolving a picked tab id to a live `Tab`.
    struct ResolvedTab {
        let tab: Tab
        /// True when the tab was `.unloaded` (suspended or never-loaded) and we just materialized it.
        let wasMaterialized: Bool

        /// True when the web view has no page yet. A pinned tab restored at launch is already `.loaded`
        /// but unloaded until first selection, so `wasMaterialized` alone misses it.
        var needsLoad: Bool {
            wasMaterialized || tab.webView.url == nil
        }
    }

    /// Materializes the attached tab without selecting it; `nil` unless the picker could offer it.
    static func materializeAttachableTab(withId id: String,
                                         forOrigin origin: TabCollectionViewModel,
                                         in windowControllersManager: WindowControllersManagerProtocol) -> ResolvedTab? {
        for collection in tabCollections(forOrigin: origin, in: windowControllersManager) {
            guard let index = collection.indexInAllTabs(where: { $0.uuid == id }),
                  let anyTab = anyTab(at: index, in: collection) else { continue }
            guard case .url(let url, _, _) = anyTab.content,
                  !AIChatTabMetadata.shouldExcludeFromTabPicker(url) else { return nil }
            let wasUnloaded: Bool = { if case .unloaded = anyTab { return true } else { return false } }()
            guard let tab = collection.materialize(at: index) else { return nil }
            return ResolvedTab(tab: tab, wasMaterialized: wasUnloaded)
        }
        return nil
    }

    private static func anyTab(at index: TabIndex, in collection: TabCollectionViewModel) -> AnyTab? {
        switch index {
        case .pinned(let i): return collection.pinnedTabsCollection?.tabs[safe: i]
        case .unpinned(let i): return collection.tabCollection.tabs[safe: i]
        }
    }
}
