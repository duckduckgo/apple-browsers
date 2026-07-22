//
//  UTITextModel.swift
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

import Combine
import Foundation

/// Owns the input's text together: `currentText` (persisted draft) and `textState` (what's visible)
/// so they can't drift, plus the dismiss-cleanup latch that keeps the draft while the field is scrubbed.
@MainActor
final class UTITextModel {

    struct SideEffects {
        let applyTextToView: (String) -> Void
        let persistDraft: () -> Void
        let updateFloatingReturnKey: () -> Void
        let clearAttachmentValidationErrorIfPossible: () -> Void
    }

    private(set) var currentText: String = ""
    private(set) var textState: InputTextState = .empty
    var omnibarPrefilledText: String?
    private(set) var isPerformingDismissCleanup = false

    private let textChangeSubject = PassthroughSubject<String, Never>()
    var textChangePublisher: AnyPublisher<String, Never> {
        textChangeSubject.eraseToAnyPublisher()
    }

    private let sideEffects: SideEffects

    init(sideEffects: SideEffects) {
        self.sideEffects = sideEffects
    }

    /// Programmatic set: pushes the text into the visible field.
    func setText(_ text: String) {
        currentText = text
        textState = text.isEmpty ? .empty : .userTyped
        sideEffects.applyTextToView(text)
        sideEffects.persistDraft()
        sideEffects.updateFloatingReturnKey()
    }

    /// User typed in the field (from the view delegate); does not push back into the view.
    func handleUserTextChange(_ text: String) {
        if UnifiedInputTextChangeGate.shouldIgnore(text: text, duringDismissCleanup: isPerformingDismissCleanup) {
            return
        }
        currentText = text
        textState = text.isEmpty ? .empty : .userTyped
        sideEffects.persistDraft()
        sideEffects.clearAttachmentValidationErrorIfPossible()
        sideEffects.updateFloatingReturnKey()
        textChangeSubject.send(text)
    }

    /// Marks the current text as an untouched prefill (shown selected so the first keystroke replaces it).
    func markPrefilledSelected() {
        textState = .prefilledSelected
    }

    /// Post-submission reset: clears the draft and the visible state together.
    func resetToEmpty() {
        currentText = ""
        textState = .empty
    }

    /// Dismiss-time clear: scrub the visible field but keep `currentText` so re-activating the same
    /// tab restores the draft. The flag clears one runloop later, covering the queued blanking sink.
    func clearForDismiss() {
        isPerformingDismissCleanup = true
        textState = .empty
        omnibarPrefilledText = nil
        sideEffects.applyTextToView("")
        DispatchQueue.main.async { [weak self] in
            self?.isPerformingDismissCleanup = false
        }
    }
}
