//
//  ContextualOnboardingPath.swift
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

/// What a path wants after a dialog request or a "Got it". The manager writes the state from it.
enum ContextualOnboardingDecision: Equatable {
    /// Show this dialog.
    case next(ContextualDialogType)
    /// Show nothing for now; onboarding continues.
    case none
    /// Onboarding is over.
    case completed
}

/// The path picked at the junction, saved so it survives a relaunch.
enum ContextualOnboardingPathKind: String {
    case search
    case duckAI
}

/// The dialog sequence of one junction path, from its first dialog to its ending.
/// Paths read the saved progress but never write it.
protocol ContextualOnboardingPath: AnyObject {
    /// What the browser UI leaves usable while this path runs.
    var uiLock: UserInteractionLock { get }
    /// Called when a navigation finishes in `tab`.
    func dialog(for tab: Tab) -> ContextualOnboardingDecision
    /// Called when the user presses "Got it" on `lastDialog`.
    func gotItPressed(lastDialog: ContextualDialogType) -> ContextualOnboardingDecision
    /// Clears the state only this path saves. Called when onboarding restarts.
    func reset()
}
