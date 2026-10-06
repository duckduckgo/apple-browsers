//
//  DedupStore.swift
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

import Foundation
import os.log

/// Per-tab de-duplication state for web events, keyed `event type × event data` within a tab.
///
/// Owned and consulted by `EventHub` itself: the decision is taken once at ingestion, before any
/// handler runs, so a duplicate reaches no handler at all and a first occurrence reaches every one of
/// them. That is deliberately *not* per-handler — handlers must not each reimplement it, and a single
/// page load firing the same event from several frames would otherwise inflate every consumer's count.
///
/// State is *page*-scoped, not *period*-scoped: it survives both a period rollover and the window
/// where a period fires while backgrounded. It is cleared only when a tab navigates to a genuinely
/// different URL, when a tab closes, or when the whole feature is disabled — never at a period
/// boundary, which would let a long-lived page inflate the first count of every new period.
///
/// The per-tab key set is unbounded, since it is cleared on every navigation and tab close: the
/// ceiling is the distinct `(type, data)` pairs one page emits before it navigates away.
///
/// In-memory only, never persisted: after a restart a page counts once more, which is intended.
///
/// Not thread-safe on its own — like all other EventHub state, access is confined to the hub's serial
/// queue.
final class DedupStore {
    /// A struct rather than a joined string: event types come from remote config, so any separator
    /// character could in principle appear in one and collide with a different `(type, data)` pair.
    private struct Key: Hashable {
        let type: String
        /// The payload as canonical JSON, or `""` when there is no payload. See `canonicalPayload`.
        let payload: String
    }

    private var seenByTab: [EventHubTabID: Set<Key>] = [:]

    /// Records this event as seen for `tabID`, returning `true` when it was *not* already present —
    /// i.e. this is the first occurrence on the tab's current page, so the caller should deliver it.
    func markSeen(type: String, data: [String: Any]?, tabID: EventHubTabID) -> Bool {
        guard let payload = Self.canonicalPayload(data) else {
            // A payload we cannot canonicalise is delivered but not recorded. Under-de-duplicating is
            // the safe failure here: payloads reach us as JSON from the content-scope-scripts bridge,
            // so this is defence only, and dropping the event would lose data outright.
            Logger.eventHub.error("event \(type, privacy: .private) payload could not be canonicalised, event not de-duplicated")
            return true
        }
        return seenByTab[tabID, default: []].insert(Key(type: type, payload: payload)).inserted
    }

    /// Drops everything recorded for a tab — used on navigation to a different URL and on tab close.
    func clear(tabID: EventHubTabID) {
        seenByTab.removeValue(forKey: tabID)
    }

    func clearAll() {
        seenByTab.removeAll()
    }

    /// Payloads equal as JSON values are one key: `.sortedKeys` orders object members (recursively,
    /// so nested objects compare irrespective of order too) while leaving array elements in place. An
    /// omitted payload and an empty one are both `""`, so they are the same key.
    ///
    /// `nil` means "not canonicalisable", which is distinct from the empty `""` payload.
    private static func canonicalPayload(_ data: [String: Any]?) -> String? {
        guard let data, !data.isEmpty else { return "" }
        guard let encoded = try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: encoded, encoding: .utf8)
    }
}
