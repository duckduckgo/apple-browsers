//
//  AnyTab.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Combine
import Foundation
import History

/// A tab that is either fully loaded (has a `WKWebView`) or unloaded (data-only).
///
/// `TabCollection` stores `[AnyTab]`. Consumers use computed properties to access
/// common fields without pattern matching. Selection always materializes first,
/// so code receiving a "selected tab" always gets a `.loaded` tab.
enum AnyTab: Identifiable {
    case unloaded(UnloadedTab)
    case loaded(Tab)

    // MARK: - Common Properties

    var uuid: TabIdentifier {
        switch self {
        case .unloaded(let s): s.uuid
        case .loaded(let t): t.uuid
        }
    }

    var id: TabIdentifier { uuid }

    var content: Tab.TabContent {
        switch self {
        case .unloaded(let s): s.content
        case .loaded(let t): t.content
        }
    }

    var title: String? {
        switch self {
        case .unloaded(let s): s.title
        case .loaded(let t): t.title
        }
    }

    var favicon: NSImage? {
        switch self {
        case .unloaded(let s): s.favicon
        case .loaded(let t): t.favicon
        }
    }

    var lastSelectedAt: Date? {
        switch self {
        case .unloaded(let s): s.lastSelectedAt
        case .loaded(let t): t.lastSelectedAt
        }
    }

    var burnerMode: BurnerMode {
        switch self {
        case .unloaded(let s): s.burnerMode
        case .loaded(let t): t.burnerMode
        }
    }

    var interactionStateData: Data? {
        switch self {
        case .unloaded(let s): s.interactionStateData
        case .loaded(let t): t.getActualInteractionStateData()
        }
    }

    var isSuspended: Bool {
        switch self {
        case .unloaded(let unloadedTab): return unloadedTab.isSuspended
        case .loaded: return false
        }
    }

    var isUrl: Bool { content.isExternalUrl }
    var url: URL? { content.urlForWebView }

    var parentTab: Tab? {
        switch self {
        case .loaded(let tab): tab.parentTab
        case .unloaded: nil
        }
    }

    var parentTabID: String? {
        switch self {
        case .loaded(let tab): tab.parentTabID
        case .unloaded: nil
        }
    }

    func reload() {
        // Unloaded tabs have no web view — intentionally a no-op.
        if case .loaded(let tab) = self {
            tab.reload()
        }
    }

    func muteUnmuteTab() {
        // Unloaded tabs have no audio — intentionally a no-op.
        if case .loaded(let tab) = self {
            tab.muteUnmuteTab()
        }
    }

    @MainActor
    func clearNavigationHistory(keepingCurrent: Bool) {
        switch self {
        case .loaded(let tab): tab.clearNavigationHistory(keepingCurrent: keepingCurrent)
        case .unloaded(let unloaded): unloaded.clearNavigationHistory(keepingCurrent: keepingCurrent)
        }
    }

    @MainActor
    var localHistory: [Visit] {
        switch self {
        case .loaded(let t):
            return t.localHistory
        case .unloaded(let unloaded):
            guard let ids = unloaded.localHistoryIDs, !ids.isEmpty else { return [] }
            return NSApp.delegateTyped.historyCoordinator.visits(matching: ids)
        }
    }

    var tabSnapshotIdentifier: UUID? {
        switch self {
        case .loaded(let tab): tab.tabSnapshotIdentifier
        case .unloaded(let s): s.tabSnapshotIdentifier.flatMap(UUID.init)
        }
    }

    var localHistoryDomains: Set<String> {
        switch self {
        case .loaded(let tab):
            tab.localHistoryDomains
        case .unloaded(let unloaded):
            Set(unloaded.localHistoryIDs?.compactMap(\.host) ?? [])
        }
    }

    // MARK: - Publishers for AppStateChangedPublisher

    /// Emits when content, favicon, or title change.
    /// Returns `Empty` for unloaded tabs (no observable state changes).
    var stateChanged: AnyPublisher<Void, Never> {
        switch self {
        case .unloaded: Empty().eraseToAnyPublisher()
        case .loaded(let tab): tab.stateChanged
        }
    }

    /// Emits when tab content changes.
    var contentChanged: AnyPublisher<Void, Never> {
        switch self {
        case .unloaded: Empty().eraseToAnyPublisher()
        case .loaded(let tab): tab.$content.asVoid().eraseToAnyPublisher()
        }
    }
}

// MARK: - TabDataClearing

extension AnyTab: TabDataClearing {
    @MainActor
    func prepareForDataClearing(caller: TabCleanupPreparer) {
        switch self {
        case .loaded(let tab):
            tab.prepareForDataClearing(caller: caller)
        case .unloaded:
            // Unloaded tabs have no WebView — nothing to flush.
            // Signal immediate completion so TabCleanupPreparer doesn't hang.
            caller.reportNoWebViewToClear()
        }
    }
}

// MARK: - Hashable (identity-based, using inner object identity)
//
// Explicit implementation is required because:
// 1. `NestedObjectChanges` uses `Set<Element>` internally for diffing
// 2. Auto-synthesized equality would compare enum cases + associated values by value,
//    but we need identity semantics (two `.loaded` wrapping the same `Tab` instance are equal)
// 3. When materialization swaps `.unloaded` → `.loaded`, the different hash values
//    cause `NestedObjectChanges` to re-subscribe (correct behavior)

extension AnyTab: Hashable {
    static func == (lhs: AnyTab, rhs: AnyTab) -> Bool {
        switch (lhs, rhs) {
        case (.unloaded(let a), .unloaded(let b)): a === b
        case (.loaded(let a), .loaded(let b)): a === b
        default: false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .unloaded(let s): hasher.combine(ObjectIdentifier(s))
        case .loaded(let t): hasher.combine(ObjectIdentifier(t))
        }
    }
}
