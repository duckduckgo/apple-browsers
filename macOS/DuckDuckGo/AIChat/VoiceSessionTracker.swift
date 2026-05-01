//
//  VoiceSessionTracker.swift
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
import Foundation
import WebKit

/// Tracks which `Tab`s currently host an active Duck.ai voice session.
///
/// Source of truth is the `aiChatVoiceSessionStarted` / `aiChatVoiceSessionEnded` user-script
/// messages Duck.ai dispatches when a voice session actually begins/ends — independent of
/// the URL, which Duck.ai may rewrite after load. Each notification's `object` is the source
/// `WKWebView`; the tracker resolves that webView back to its owning `Tab` via
/// `WindowControllersManagerProtocol.allTabCollectionViewModels`.
///
/// Lookups are window-scoped: callers pass the source `TabCollectionViewModel` (each window
/// has its own), so opening a new voice chat in one window doesn't pull the user across to a
/// voice tab in a different window — matching the Windows-browser behavior. Pinned tabs are
/// shared across windows; a pinned voice tab is treated as visible from any source window.
/// Closed tabs auto-evict because the storage uses weak references.
@MainActor
final class VoiceSessionTracker: NSObject {

    /// Tabs with an active voice session. `NSHashTable.weakObjects()` keeps weak references —
    /// closed tabs disappear without explicit cleanup, so we don't need to subscribe to a
    /// "tab removed" event.
    private let activeTabs: NSHashTable<Tab> = .weakObjects()

    private let notificationCenter: NotificationCenter
    private weak var windowControllersManager: WindowControllersManagerProtocol?

    init(notificationCenter: NotificationCenter = .default,
         windowControllersManager: WindowControllersManagerProtocol) {
        self.notificationCenter = notificationCenter
        self.windowControllersManager = windowControllersManager
        super.init()
        notificationCenter.addObserver(self, selector: #selector(voiceSessionStarted(_:)), name: .aiChatVoiceSessionStarted, object: nil)
        notificationCenter.addObserver(self, selector: #selector(voiceSessionEnded(_:)), name: .aiChatVoiceSessionEnded, object: nil)
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    /// Returns any tracked active voice tab visible from `sourceCollection`'s window.
    /// A candidate matches when it's an unpinned tab in `sourceCollection` (same window) or
    /// when it's a pinned tab (pinned tabs are shared across all windows, so any source window
    /// is allowed to focus a pinned voice tab). Returns `nil` when no source is supplied.
    func findActiveVoiceTab(in sourceCollection: TabCollectionViewModel?) -> Tab? {
        guard let sourceCollection else { return nil }
        let unpinned = sourceCollection.unpinnedLoadedTabs
        let pinned = sourceCollection.pinnedTabsCollection?.tabs.compactMap { anyTab -> Tab? in
            if case .loaded(let tab) = anyTab { return tab }
            return nil
        } ?? []

        for case let candidate as Tab in activeTabs.allObjects {
            if unpinned.contains(where: { $0 === candidate }) || pinned.contains(where: { $0 === candidate }) {
                return candidate
            }
        }
        return nil
    }

    @objc private func voiceSessionStarted(_ note: Notification) {
        guard let webView = note.object as? WKWebView,
              let tab = tab(for: webView) else { return }
        activeTabs.add(tab)
    }

    @objc private func voiceSessionEnded(_ note: Notification) {
        guard let webView = note.object as? WKWebView,
              let tab = tab(for: webView) else { return }
        activeTabs.remove(tab)
    }

    /// Resolves a webView to its owning main-browser `Tab`, if any.
    private func tab(for webView: WKWebView) -> Tab? {
        guard let manager = windowControllersManager else { return nil }
        for tabCollectionViewModel in manager.allTabCollectionViewModels {
            for tab in allLoadedTabs(in: tabCollectionViewModel) where tab.webView === webView {
                return tab
            }
        }
        return nil
    }

    /// Concrete `Tab`s in both pinned and unpinned collections. `AnyTab` is an enum
    /// (`.loaded(Tab)` / `.unloaded(UnloadedTab)`) — only `.loaded` has a `WKWebView`, and
    /// voice sessions require a webview, so unloaded entries are skipped.
    private func allLoadedTabs(in tabCollectionViewModel: TabCollectionViewModel) -> [Tab] {
        var result = tabCollectionViewModel.unpinnedLoadedTabs
        for anyTab in tabCollectionViewModel.pinnedTabsCollection?.tabs ?? [] {
            if case .loaded(let tab) = anyTab { result.append(tab) }
        }
        return result
    }
}

// MARK: - TabCollectionViewModel helpers

private extension TabCollectionViewModel {
    /// Unpinned tabs that have a materialized webview (excludes `.unloaded`).
    var unpinnedLoadedTabs: [Tab] {
        tabs.compactMap { anyTab in
            if case .loaded(let tab) = anyTab { return tab }
            return nil
        }
    }
}
