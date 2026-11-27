//
//  ContextualOnboardingProgress.swift
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
import Persistence

protocol ContextualOnboardingProgressReading: AnyObject {
    func hasSeen(_ dialog: ContextualDialogType) -> Bool
    var fireButtonUsedOnce: Bool { get }
}

struct ContextualOnboardingSettings: StoringKeys {
    let pathKind = StorageKey<ContextualOnboardingPathKind>(.contextualOnboardingPathKind)
    let duckAIPrompt = StorageKey<String>(.contextualOnboardingDuckAIPrompt)
}

/// Saved contextual onboarding state. Paths read it through `ContextualOnboardingProgressReading`; only the manager writes.
final class ContextualOnboardingProgress: ContextualOnboardingProgressReading {
    private let storage: ContextualOnboardingStateStoring
    private let settings: any ThrowingKeyedStoring<ContextualOnboardingSettings>

    init(storage: ContextualOnboardingStateStoring,
         settings: any ThrowingKeyedStoring<ContextualOnboardingSettings>) {
        self.storage = storage
        self.settings = settings
    }

    var state: ContextualOnboardingState {
        get { ContextualOnboardingState(rawValue: storage.stateString) ?? .onboardingCompleted }
        set { storage.stateString = newValue.rawValue }
    }

    var fireButtonUsedOnce: Bool {
        get { storage.fireButtonUsedOnce }
        set { storage.fireButtonUsedOnce = newValue }
    }

    /// `nil` when no path was chosen, which means search.
    var pathKind: ContextualOnboardingPathKind? {
        get { try? settings.pathKind }
        set { try? settings.set(newValue, for: \.pathKind) }
    }

    /// The prompt sent from the junction, kept until Fire so the Duck.ai tab can be opened again.
    var duckAIPrompt: String? {
        get { try? settings.duckAIPrompt }
        set { try? settings.set(newValue, for: \.duckAIPrompt) }
    }

    func hasSeen(_ dialog: ContextualDialogType) -> Bool {
        storage.contextualDialogsSeen.contains(dialog.stringRepresentation)
    }

    func markSeen(_ dialog: ContextualDialogType) {
        guard !hasSeen(dialog) else { return }
        storage.contextualDialogsSeen.append(dialog.stringRepresentation)
    }

    func markUnseen(_ dialog: ContextualDialogType) {
        storage.contextualDialogsSeen.removeAll { $0 == dialog.stringRepresentation }
    }

    /// Clears everything a restarted onboarding must not inherit. The state itself is set by the caller.
    func reset() {
        storage.contextualDialogsSeen = []
        storage.fireButtonUsedOnce = false
        try? settings.removeValue(for: \.pathKind)
        try? settings.removeValue(for: \.duckAIPrompt)
    }
}
