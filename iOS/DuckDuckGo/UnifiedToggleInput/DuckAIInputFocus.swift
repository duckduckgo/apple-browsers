//
//  DuckAIInputFocus.swift
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

/// Hands the Duck.ai input's focus to a menu or screen that covers it, and back if that closes in place.
/// A focused input left behind raises its keyboard over the screen, and UIKit refocuses it, unanimated, on dismissal.
@MainActor
final class DuckAIInputFocus {

    private let isFocused: () -> Bool
    private let resign: () -> Void
    private let refocus: () -> Void

    private(set) var isSetAside = false

    /// `isFocused` answers only for the Duck.ai input, so other inputs are never touched.
    init(isFocused: @escaping () -> Bool, resign: @escaping () -> Void, refocus: @escaping () -> Void) {
        self.isFocused = isFocused
        self.resign = resign
        self.refocus = refocus
    }

    /// Takes the focus away for good, for a screen that returns with the keyboard down, like the tab manager.
    func release() {
        isSetAside = false
        resignIfFocused()
    }

    /// Takes the focus away until `restore`, if the input had it.
    func setAside() {
        isSetAside = isFocused()
        resignIfFocused()
    }

    /// Gives back focus that was set aside; the keyboard slides back in.
    func restore() {
        guard isSetAside else { return }
        isSetAside = false
        refocus()
    }

    /// The chat is being replaced, so the set-aside focus has nothing to return to.
    func forget() {
        isSetAside = false
    }

    private func resignIfFocused() {
        guard isFocused() else { return }
        resign()
    }
}
