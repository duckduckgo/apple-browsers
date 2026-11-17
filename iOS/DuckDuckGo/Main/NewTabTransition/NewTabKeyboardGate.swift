//
//  NewTabKeyboardGate.swift
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

/// Decides when a keyboard the new tab asks for may rise: once the entrance reaches the keyboard's moment
/// and nothing holds it back, such as a screen still being dismissed, which would show it without its slide.
@MainActor
final class NewTabKeyboardGate {

    private var isMomentReached = false
    private var isForcedOpen = false
    private var holds = 0
    private var waitingFocus: [() -> Void] = []

    var isOpen: Bool { isForcedOpen || (isMomentReached && holds == 0) }

    /// Runs `focus` now if the keyboard may rise, otherwise as soon as it may.
    func whenOpen(_ focus: @escaping () -> Void) {
        guard isOpen else {
            waitingFocus.append(focus)
            return
        }
        focus()
    }

    func reachMoment() {
        isMomentReached = true
        runWaitingFocus()
    }

    /// Keeps the keyboard down until the returned release runs. Releasing more than once has no effect.
    func hold() -> () -> Void {
        holds += 1
        var isReleased = false
        return { [weak self] in
            guard let self, !isReleased else { return }
            isReleased = true
            holds -= 1
            runWaitingFocus()
        }
    }

    /// Lets everything through for good, so no focus is left waiting once the entrance is over.
    func open() {
        isForcedOpen = true
        runWaitingFocus()
    }

    private func runWaitingFocus() {
        guard isOpen else { return }
        let focus = waitingFocus
        waitingFocus = []
        focus.forEach { $0() }
    }
}
