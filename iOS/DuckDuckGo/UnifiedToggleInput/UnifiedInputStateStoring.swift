//
//  UnifiedInputStateStoring.swift
//  DuckDuckGo
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

struct LastUsedInputDefaults: Equatable {
    var toggleMode: TextEntryMode
    var selectedModelID: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?
}

@MainActor
protocol UnifiedInputStateStoring: AnyObject {
    /// Returns the current state for `uid`. If no entry exists, returns a fresh state
    /// seeded from `lastUsed` (or `tab.preferredTextEntryMode` for the toggle slice
    /// when seeded via `TabsModel` observation).
    func state(for uid: TabUID) -> TabInputState

    /// Replaces the entry for `uid` without affecting `lastUsed` or global preference
    /// homes. Use during tab-switch flush.
    func update(_ state: TabInputState, for uid: TabUID)

    /// Records a user-deliberate choice. Updates the entry for `uid`, the `lastUsed`
    /// snapshot used to seed new tabs, and writes through the seedable fields to
    /// their canonical global homes.
    func recordUserChoice(_ state: TabInputState, for uid: TabUID)

    /// Removes the entry for `uid`. No-op if absent.
    func remove(for uid: TabUID)

    /// The seedable defaults used for new tabs. Reflects the user's most recent
    /// deliberate choice — not affected by tab switching.
    var lastUsed: LastUsedInputDefaults { get }
}
