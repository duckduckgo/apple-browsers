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
import OSLog
import WebKit

/// Tracks which `Tab`s currently host an active Duck.ai voice session.
///
/// Source of truth is the `aiChatVoiceSessionStarted` / `aiChatVoiceSessionEnded` user-script
/// messages Duck.ai dispatches when a voice session actually begins/ends — independent of
/// the URL, which Duck.ai may rewrite after load. Each notification's `object` is the source
/// `WKWebView`; the tracker resolves that webView back to its owning `Tab` via
/// `WindowControllersManagerProtocol.allTabCollectionViewModels`.
///
/// Lookups are window-scoped (`findActiveVoiceTab(inWindowOf:)`), so opening a new voice chat
/// in one window doesn't pull the user across to a voice tab in a different window — matching
/// the Windows-browser behavior. Closed tabs auto-evict because the storage uses weak references.
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

    /// Returns any tracked active voice tab that lives in the same window as `sourceTab`.
    /// Returns `nil` when no source is supplied (no window context available — better to
    /// open a new tab than to focus an arbitrary one).
    func findActiveVoiceTab(inWindowOf sourceTab: Tab?) -> Tab? {
        let activeCount = activeTabs.count
        Logger.aiChat.log("[VoiceSessionTracker] findActiveVoiceTab — sourceTab=\(sourceTab.map { ObjectIdentifier($0).hashValue } ?? 0, privacy: .public) activeCount=\(activeCount, privacy: .public)")
        guard let sourceTab else {
            Logger.aiChat.log("[VoiceSessionTracker] findActiveVoiceTab — no sourceTab, returning nil")
            return nil
        }
        guard let manager = windowControllersManager else {
            Logger.aiChat.log("[VoiceSessionTracker] findActiveVoiceTab — windowControllersManager nil")
            return nil
        }
        guard let sourceCollection = tabCollectionViewModel(containing: sourceTab, in: manager) else {
            Logger.aiChat.log("[VoiceSessionTracker] findActiveVoiceTab — sourceTab not found in any window's collection")
            return nil
        }
        for case let candidate as Tab in activeTabs.allObjects {
            let candidateCollection = tabCollectionViewModel(containing: candidate, in: manager)
            let candidateInSameWindow = candidateCollection === sourceCollection
            Logger.aiChat.log("[VoiceSessionTracker]   candidate id=\(ObjectIdentifier(candidate).hashValue, privacy: .public) sameWindow=\(candidateInSameWindow, privacy: .public)")
            if candidateInSameWindow {
                Logger.aiChat.log("[VoiceSessionTracker] findActiveVoiceTab — match found")
                return candidate
            }
        }
        Logger.aiChat.log("[VoiceSessionTracker] findActiveVoiceTab — no match in source window")
        return nil
    }

    @objc private func voiceSessionStarted(_ note: Notification) {
        guard let webView = note.object as? WKWebView else {
            Logger.aiChat.log("[VoiceSessionTracker] received `started` notification with non-WKWebView object=\(String(describing: note.object), privacy: .public)")
            return
        }
        let webViewID = ObjectIdentifier(webView).hashValue
        guard let tab = tab(for: webView) else {
            Logger.aiChat.log("[VoiceSessionTracker] no Tab found for webView id=\(webViewID, privacy: .public) on `started` — known webViews=\(self.knownWebViewIDs(), privacy: .public)")
            return
        }
        Logger.aiChat.log("[VoiceSessionTracker] tracking tab id=\(ObjectIdentifier(tab).hashValue, privacy: .public) webView=\(webViewID, privacy: .public) (active count → \(self.activeTabs.count + 1, privacy: .public))")
        activeTabs.add(tab)
    }

    @objc private func voiceSessionEnded(_ note: Notification) {
        guard let webView = note.object as? WKWebView else {
            Logger.aiChat.log("[VoiceSessionTracker] received `ended` notification with non-WKWebView object=\(String(describing: note.object), privacy: .public)")
            return
        }
        let webViewID = ObjectIdentifier(webView).hashValue
        guard let tab = tab(for: webView) else {
            Logger.aiChat.log("[VoiceSessionTracker] no Tab found for webView id=\(webViewID, privacy: .public) on `ended`")
            return
        }
        Logger.aiChat.log("[VoiceSessionTracker] clearing tab id=\(ObjectIdentifier(tab).hashValue, privacy: .public) webView=\(webViewID, privacy: .public)")
        activeTabs.remove(tab)
    }

    private func tab(for webView: WKWebView) -> Tab? {
        guard let manager = windowControllersManager else {
            Logger.aiChat.log("[VoiceSessionTracker] tab(for:) — windowControllersManager is nil")
            return nil
        }
        for tabCollectionViewModel in manager.allTabCollectionViewModels {
            if let tab = allTabs(in: tabCollectionViewModel).first(where: { $0.webView === webView }) {
                return tab
            }
        }
        return nil
    }

    /// Diagnostic — comma-separated list of all currently-known tab webView identity hashes.
    /// Used in logs when a `started` notification's webView can't be matched to a tab.
    private func knownWebViewIDs() -> String {
        guard let manager = windowControllersManager else { return "<nil mgr>" }
        var ids: [Int] = []
        for tcvm in manager.allTabCollectionViewModels {
            for tab in allTabs(in: tcvm) {
                ids.append(ObjectIdentifier(tab.webView).hashValue)
            }
        }
        return ids.map(String.init).joined(separator: ",")
    }

    private func tabCollectionViewModel(containing tab: Tab, in manager: WindowControllersManagerProtocol) -> TabCollectionViewModel? {
        manager.allTabCollectionViewModels.first(where: { tcvm in
            allTabs(in: tcvm).contains(where: { $0 === tab })
        })
    }

    /// Concrete `Tab`s in both pinned and unpinned collections. `AnyTab` is an enum
    /// (`.loaded(Tab)` / `.unloaded(UnloadedTab)`) — only `.loaded` has a `WKWebView`, and
    /// voice sessions require a webview, so unloaded entries are skipped.
    private func allTabs(in tabCollectionViewModel: TabCollectionViewModel) -> [Tab] {
        var result: [Tab] = []
        for anyTab in tabCollectionViewModel.tabs {
            if case .loaded(let tab) = anyTab { result.append(tab) }
        }
        for anyTab in tabCollectionViewModel.pinnedTabsCollection?.tabs ?? [] {
            if case .loaded(let tab) = anyTab { result.append(tab) }
        }
        return result
    }
}
