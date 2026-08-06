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

/// Per-tab de-duplication state, keyed pixel×param×source within a tab.
///
/// Owned by `EventHub` rather than by the parameters that consult it, because dedup is *page*-scoped,
/// not *period*-scoped: it must survive both a period rollover and the window where a period fires
/// while backgrounded, each of which destroys the owning `Telemetry` and its parameters. It is cleared
/// only when a tab navigates to a genuinely different URL, when a tab closes, or when the whole feature
/// is disabled — never at a period boundary, which would let a long-lived page inflate the first count
/// of every new period.
///
/// In-memory only, never persisted: after a restart a page counts once more, which is intended.
///
/// Not thread-safe on its own — like all other EventHub state, access is confined to the hub's serial
/// queue.
final class DedupStore {
    private var seenByTab: [EventHubTabID: Set<String>] = [:]

    /// Records `key` as seen for `tabID`, returning `true` when it was *not* already present — i.e.
    /// this is the first occurrence on the tab's current page, so the caller should count it.
    func markSeen(key: String, tabID: EventHubTabID) -> Bool {
        seenByTab[tabID, default: []].insert(key).inserted
    }

    /// Drops everything recorded for a tab — used on navigation to a different URL and on tab close.
    func clear(tabID: EventHubTabID) {
        seenByTab.removeValue(forKey: tabID)
    }

    func clearAll() {
        seenByTab.removeAll()
    }
}
