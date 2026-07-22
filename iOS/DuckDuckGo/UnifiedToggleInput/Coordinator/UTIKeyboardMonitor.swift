//
//  UTIKeyboardMonitor.swift
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

/// Guards the window between activating a top-positioned omnibar and the keyboard actually appearing:
/// suppresses the spurious "keyboard hidden → collapse" while awaiting, and forces the bar inactive
/// via a fallback timer if the keyboard never arrives. State is read live through `Environment` so a
/// timer that fires late always decides against current conditions, never a stale snapshot.
@MainActor
final class UTIKeyboardMonitor {

    struct Environment {
        let isOmnibarActiveTopCard: () -> Bool
        let isInputVisibleForKeyboard: () -> Bool
        let isInputFirstResponder: () -> Bool
    }

    private static let presentationTimeout: TimeInterval = 0.35

    private(set) var isAwaitingPresentation = false
    private var fallback: DispatchWorkItem?
    private let environment: Environment

    /// Called when the fallback fires and the keyboard never presented — the caller drives the
    /// `.omnibar(.active) → .inactive` transition (it owns display state + intent emission).
    var onTimeoutRequiresInactive: (() -> Void)?

    init(environment: Environment) {
        self.environment = environment
    }

    /// Cancels any pending fallback and sets whether we're awaiting the keyboard (top card only).
    func arm(awaiting: Bool) {
        cancelFallback()
        isAwaitingPresentation = awaiting
    }

    /// Cancels the fallback and clears the latch — the default at every non-activation transition.
    func disarm() {
        arm(awaiting: false)
    }

    /// Cancels only the pending fallback, leaving the latch untouched (hardware-keyboard in-use case).
    func cancelFallback() {
        fallback?.cancel()
        fallback = nil
    }

    /// Clears the latch without touching the fallback (after a transition already handled the timer).
    func clearAwaiting() {
        isAwaitingPresentation = false
    }

    func scheduleFallback() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.environment.isOmnibarActiveTopCard(),
                  self.isAwaitingPresentation else {
                return
            }
            self.fallback = nil
            if !self.environment.isInputVisibleForKeyboard(), !self.environment.isInputFirstResponder() {
                self.onTimeoutRequiresInactive?()
            } else {
                self.isAwaitingPresentation = false
            }
        }
        fallback = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.presentationTimeout, execute: workItem)
    }
}
