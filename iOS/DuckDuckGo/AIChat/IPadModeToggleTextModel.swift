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

    /// Whether automatic text selection should be suppressed after the transfer.
    let suppressTextSelection: Bool
}

protocol IPadModeToggleTextModeling {
    var currentMode: TextEntryMode { get }
    var sharedText: String { get }
    var isTransitioning: Bool { get }
    var showPlaceholder: Bool { get }

    func updateText(_ text: String)
    func transition(to newMode: TextEntryMode) -> ModeToggleTransition?
    func beginTransition()
    func endTransition()
}

final class IPadModeToggleTextModel: IPadModeToggleTextModeling {

    private(set) var currentMode: TextEntryMode = .search
    private(set) var sharedText: String = ""
    private(set) var isTransitioning: Bool = false

    var showPlaceholder: Bool {
        sharedText.isEmpty
    }

    func updateText(_ text: String) {
        sharedText = text
    }

    /// Computes the transition actions for a mode change.
    /// Returns `nil` if the mode hasn't changed (no-op).
    func transition(to newMode: TextEntryMode) -> ModeToggleTransition? {
        guard newMode != currentMode else { return nil }

        let fromAIChatToSearch = currentMode == .aiChat && newMode == .search

        let action = ModeToggleTransition(
            text: sharedText,
            needsKeyboardTransfer: fromAIChatToSearch,
            suppressTextSelection: fromAIChatToSearch)

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
