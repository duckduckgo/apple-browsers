//
//  IPadModeToggleTextModel.swift
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

import Foundation

struct ModeToggleTransition: Equatable {
    /// The text to apply to the destination control.
    let text: String

    /// Whether the keyboard should transfer from the duckAITextView to the textField.
    let needsKeyboardTransfer: Bool

    /// Select all the destination text after the transition — true when restoring the page URL, so it
    /// reads as the unedited address and a later switch to duck.ai clears it again.
    let selectAllText: Bool
}

protocol IPadModeToggleTextModeling {
    var currentMode: TextEntryMode { get }
    var sharedText: String { get }
    var isTransitioning: Bool { get }
    var showPlaceholder: Bool { get }
    var hasSubmittableText: Bool { get }

    func updateText(_ text: String)
    func rememberSearchTextToRestore(_ text: String)
    func invalidateSearchTextToRestore()
    func transition(to newMode: TextEntryMode) -> ModeToggleTransition?
    func beginTransition()
    func endTransition()
}

final class IPadModeToggleTextModel: IPadModeToggleTextModeling {

    private(set) var currentMode: TextEntryMode = .search
    private(set) var sharedText: String = ""
    private(set) var isTransitioning: Bool = false

    /// Page URL cleared when switching to duck.ai, to restore on the way back to search if the user
    /// didn't type anything in duck.ai. Consumed on the next return-to-search transition.
    private var searchTextToRestore: String?

    var showPlaceholder: Bool {
        sharedText.isEmpty
    }

    var hasSubmittableText: Bool {
        !sharedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func updateText(_ text: String) {
        sharedText = text
    }

    func rememberSearchTextToRestore(_ text: String) {
        searchTextToRestore = text
    }

    func invalidateSearchTextToRestore() {
        searchTextToRestore = nil
    }

    /// Computes the transition actions for a mode change.
    /// Returns `nil` if the mode hasn't changed (no-op).
    func transition(to newMode: TextEntryMode) -> ModeToggleTransition? {
        guard newMode != currentMode else { return nil }

        let fromAIChatToSearch = currentMode == .aiChat && newMode == .search

        // Returning to search without typing in duck.ai → restore the cleared page URL (and reselect
        // it, so it reads as the unedited address).
        var text = sharedText
        var restoredPageURL = false
        if fromAIChatToSearch {
            if sharedText.isEmpty, let restore = searchTextToRestore {
                text = restore
                sharedText = restore
                restoredPageURL = true
            }
            searchTextToRestore = nil
        }

        let action = ModeToggleTransition(
            text: text,
            needsKeyboardTransfer: fromAIChatToSearch,
            selectAllText: restoredPageURL)

        currentMode = newMode
        return action
    }

    func beginTransition() {
        isTransitioning = true
    }

    func endTransition() {
        isTransitioning = false
    }
}
