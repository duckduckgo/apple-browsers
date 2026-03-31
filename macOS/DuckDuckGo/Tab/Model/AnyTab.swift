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

/// A tab that is either fully loaded (has a `WKWebView`) or suspended (data-only).
///
/// `TabCollection` stores `[AnyTab]`. Consumers use computed properties to access
/// common fields without pattern matching. Selection always materializes first,
/// so code receiving a "selected tab" always gets a `.loaded` tab.
enum AnyTab: Identifiable {
    case suspended(SuspendedTab)
    case loaded(Tab)

    // MARK: - Common Properties

    var uuid: TabIdentifier {
        switch self {
        case .suspended(let s): s.uuid
        case .loaded(let t): t.uuid
        }
    }

    var id: TabIdentifier { uuid }

    var content: Tab.TabContent {
        switch self {
        case .suspended(let s): s.content
        case .loaded(let t): t.content
        }
    }

    var title: String? {
        switch self {
        case .suspended(let s): s.title
        case .loaded(let t): t.title
        }
    }

    var favicon: NSImage? {
        switch self {
        case .suspended(let s): s.favicon
        case .loaded(let t): t.favicon
        }
    }

    var lastSelectedAt: Date? {
        switch self {
        case .suspended(let s): s.lastSelectedAt
        case .loaded(let t): t.lastSelectedAt
        }
    }

    var burnerMode: BurnerMode {
        switch self {
        case .suspended(let s): s.burnerMode
        case .loaded(let t): t.burnerMode
        }
    }

    var interactionStateData: Data? {
        switch self {
        case .suspended(let s): s.interactionStateData
        case .loaded(let t): t.getActualInteractionStateData()
        }
    }

    var isUrl: Bool { content.isExternalUrl }
    var url: URL? { content.urlForWebView }

    /// Returns the loaded `Tab`, or `nil` if suspended.
    var tab: Tab? {
        if case .loaded(let t) = self { t } else { nil }
    }

    func reload() {
        // Suspended tabs have no web view — intentionally a no-op.
        if case .loaded(let tab) = self {
            tab.reload()
        }
    }

    var localHistory: [Visit] {
        switch self {
        case .suspended: []
        case .loaded(let t): t.localHistory
        }
    }

    // MARK: - Publishers for AppStateChangedPublisher

    /// Emits when content, favicon, or title change.
    /// Returns `Empty` for suspended tabs (no observable state changes).
    var stateChanged: AnyPublisher<Void, Never> {
        switch self {
        case .suspended: Empty().eraseToAnyPublisher()
        case .loaded(let tab): tab.stateChanged
        }
    }

    /// Emits when tab content changes.
    var contentChanged: AnyPublisher<Void, Never> {
        switch self {
        case .suspended: Empty().eraseToAnyPublisher()
        case .loaded(let tab): tab.$content.asVoid().eraseToAnyPublisher()
        }
    }
}

// MARK: - Hashable (identity-based, using inner object identity)
//
// Explicit implementation is required because:
// 1. `NestedObjectChanges` uses `Set<Element>` internally for diffing
// 2. Auto-synthesized equality would compare enum cases + associated values by value,
//    but we need identity semantics (two `.loaded` wrapping the same `Tab` instance are equal)
// 3. When materialization swaps `.suspended` → `.loaded`, the different hash values
//    cause `NestedObjectChanges` to re-subscribe (correct behavior)

extension AnyTab: Hashable {
    static func == (lhs: AnyTab, rhs: AnyTab) -> Bool {
        switch (lhs, rhs) {
        case (.suspended(let a), .suspended(let b)): a === b
        case (.loaded(let a), .loaded(let b)): a === b
        default: false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .suspended(let s): hasher.combine(ObjectIdentifier(s))
        case .loaded(let t): hasher.combine(ObjectIdentifier(t))
        }
    }
}
