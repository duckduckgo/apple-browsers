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

/// Which open tabs a Duck.ai picker may offer: the origin window's pinned then unpinned URL tabs.
@MainActor
enum AIChatTabPickerSource {

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

    /// `AnyTab` so metadata is available for suspended/unloaded tabs too.
    static func attachableTabs(forOrigin origin: TabCollectionViewModel) -> [AnyTab] {
        let pinned = origin.pinnedTabsCollection?.tabs ?? []
        return (pinned + origin.tabCollection.tabs).filter { tab in
            guard case .url(let url, _, _) = tab.content else { return false }
            return !AIChatTabMetadata.shouldExcludeFromTabPicker(url)
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
                                         forOrigin origin: TabCollectionViewModel) -> ResolvedTab? {
        guard let index = origin.indexInAllTabs(where: { $0.uuid == id }),
              let anyTab = anyTab(at: index, in: origin) else { return nil }
        guard case .url(let url, _, _) = anyTab.content,
              !AIChatTabMetadata.shouldExcludeFromTabPicker(url) else { return nil }
        let wasUnloaded: Bool = { if case .unloaded = anyTab { return true } else { return false } }()
        guard let tab = origin.materialize(at: index) else { return nil }
        return ResolvedTab(tab: tab, wasMaterialized: wasUnloaded)
    }

    private static func anyTab(at index: TabIndex, in collection: TabCollectionViewModel) -> AnyTab? {
        switch index {
        case .pinned(let i): return collection.pinnedTabsCollection?.tabs[safe: i]
        case .unpinned(let i): return collection.tabCollection.tabs[safe: i]
        }
    }
}
