//
//  AddressBarSharedTextState.swift
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

import AppKit
import Combine

/// Manages shared text state between search mode and duck.ai mode in the address bar.
/// This allows text content and selection to be preserved when switching between modes.
final class AddressBarSharedTextState: ObservableObject {

    /// The current text content shared between modes
    @Published private(set) var text: String = ""

    /// The current selection range in the text
    @Published private(set) var selectionRange: NSRange = NSRange(location: 0, length: 0)

    /// Whether the user has typed anything (triggers text sharing between modes)
    @Published private(set) var hasUserInteractedWithText: Bool = false

    /// Whether the user has type anything after switching modes
    private(set) var hasUserInteractedWithTextAfterSwitchingModes: Bool = false

    /// Resets the shared state to initial values
    func reset() {
        text = ""
        selectionRange = NSRange(location: 0, length: 0)
        hasUserInteractedWithText = false
    }

    func resetUserInteraction() {
        hasUserInteractedWithText = false
    }

    func setHasUserInteractedWithTextAfterSwitchingModes(_ value: Bool) {
        hasUserInteractedWithTextAfterSwitchingModes = value
    }

    func resetUserInteractionAfterSwitchingModes() {
        hasUserInteractedWithTextAfterSwitchingModes = false
    }

    /// Updates the shared text content
    /// - Parameters:
    ///   - newText: The new text value
    ///   - markInteraction: Whether to mark this as a user interaction (defaults to true)
    func updateText(_ newText: String, markInteraction: Bool = true) {
        if markInteraction && !newText.isEmpty {
            hasUserInteractedWithText = true
            hasUserInteractedWithTextAfterSwitchingModes = true
        }

        text = newText

        // Adjust selection range if it's now beyond the text length
        if selectionRange.location > newText.count {
            selectionRange = NSRange(location: newText.count, length: 0)
        } else if selectionRange.upperBound > newText.count {
            selectionRange = NSRange(location: selectionRange.location, length: max(0, newText.count - selectionRange.location))
        }
    }

    /// Updates the selection range
    /// - Parameter range: The new selection range
    func updateSelection(_ range: NSRange) {
        // Validate the range
        let validatedRange: NSRange
        if range.location > text.count {
            validatedRange = NSRange(location: text.count, length: 0)
        } else if range.upperBound > text.count {
            validatedRange = NSRange(location: range.location, length: max(0, text.count - range.location))
        } else {
            validatedRange = range
        }

        selectionRange = validatedRange
    }
}
