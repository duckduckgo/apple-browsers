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
import AIChat

/// Manages shared text state between search mode and duck.ai mode in the address bar.
/// This allows text content and selection to be preserved when switching between modes.
final class AddressBarSharedTextState: ObservableObject {

    /// The current text content shared between modes
    @Published private(set) var text: String = ""

    /// `text` with every newline (LF, CR, CRLF, line/paragraph separators — anything in
    /// `CharacterSet.newlines`) collapsed to a single space, suitable for rendering in the
    /// single-line address bar. The Duck.ai panel's prompt editor consumes the raw `text`
    /// instead. Centralized here so every bar consumer gets the same transformation; without
    /// this, a multi-line prompt would render with broken vertical alignment in the unfocused
    /// bar (the field tries to lay out two lines and only the first peeks through).
    var textForSingleLineDisplay: String {
        text.components(separatedBy: .newlines).joined(separator: " ")
    }

    /// The current selection range in the text
    @Published private(set) var selectionRange: NSRange = NSRange(location: 0, length: 0)

    /// Whether the user has typed anything (triggers text sharing between modes)
    @Published private(set) var hasUserInteractedWithText: Bool = false

    /// Whether the user has type anything after switching modes
    private(set) var hasUserInteractedWithTextAfterSwitchingModes: Bool = false

    /// Whether duck.ai mode is the currently selected mode for this tab.
    /// Persists across focus changes and tab switches; cleared on navigation, submit, or explicit switch back to search.
    @Published private(set) var isInDuckAIMode: Bool = false

    /// The duck.ai tool selection for this tab (image generation / web search).
    /// Persists across tab switches; cleared alongside text on navigation, submit, or explicit reset.
    @Published private(set) var aiChatToolMode: AIChatToolMode?

    /// The duck.ai image attachments for this tab.
    /// Persists across tab switches so the user doesn't lose a prepared prompt's attachments when bouncing between tabs.
    @Published private(set) var aiChatAttachments: [AIChatImageAttachment] = []

    /// The duck.ai tab attachments (Attach Page Content) for this tab.
    /// Persists across tab switches alongside the prompt text and image attachments so the user
    /// can keep curating the prompt when bouncing between browser tabs.
    @Published private(set) var aiChatTabAttachments: [AIChatTabAttachment] = []

    /// The duck.ai file attachments (PDFs etc.) for this tab. Persists across tab switches.
    @Published private(set) var aiChatFileAttachments: [AIChatFileAttachment] = []

    /// Unified, insertion-ordered list of duck.ai panel attachments — both image uploads and
    /// page-content tabs. The omnibar carousel renders directly from this list to preserve the
    /// chronological order in which the user attached items (e.g. tab, image, tab, tab); the
    /// per-type lists above are derived from this list for the image-side and submit-side code
    /// paths that already work with one type at a time.
    @Published private(set) var aiChatPanelAttachments: [AIChatPanelAttachment] = []

    /// Resets the shared state to initial values.
    /// - Parameter clearingDuckAIState: Pass `false` from tab-switch restore paths. Tab switches must not
    ///   wipe per-tab duck.ai state — that includes the prompt text, selection, interaction flag, mode,
    ///   tool mode and attachments, all of which belong to the tab and are only cleared on explicit user
    ///   action (toggle off, submit, navigation). The unfocused duck.ai bar relies on `text` surviving
    ///   tab switches because `applyDuckAIUnfocusedValue` reads from it. Default `true` preserves the
    ///   navigation semantics for callers that do want a full reset.
    func reset(clearingDuckAIState: Bool = true) {
        guard clearingDuckAIState else { return }
        text = ""
        selectionRange = NSRange(location: 0, length: 0)
        hasUserInteractedWithText = false
        if isInDuckAIMode {
            isInDuckAIMode = false
        }
        if aiChatToolMode != nil {
            aiChatToolMode = nil
        }
        if !aiChatAttachments.isEmpty {
            aiChatAttachments = []
        }
        if !aiChatTabAttachments.isEmpty {
            aiChatTabAttachments = []
        }
        if !aiChatFileAttachments.isEmpty {
            aiChatFileAttachments = []
        }
        if !aiChatPanelAttachments.isEmpty {
            aiChatPanelAttachments = []
        }
    }

    /// Sets the duck.ai mode flag for this tab without touching text state.
    func setDuckAIMode(_ enabled: Bool) {
        guard isInDuckAIMode != enabled else { return }
        isInDuckAIMode = enabled
    }

    /// Sets the duck.ai tool selection for this tab. No-op when the value is unchanged to avoid
    /// spurious publisher emissions (and subscription loops between controller ↔ shared state).
    func setAIChatToolMode(_ mode: AIChatToolMode?) {
        guard aiChatToolMode != mode else { return }
        aiChatToolMode = mode
    }

    /// Replaces the duck.ai attachment list for this tab. Skips the write when both the id AND the
    /// image instance are unchanged — id alone isn't enough because `replaceAttachment` swaps in a
    /// resized `NSImage` while keeping the same id, and we need that resized version to land in
    /// shared state so a subsequent tab switch restores the resized image, not the placeholder.
    ///
    /// Also reconciles `aiChatPanelAttachments` so the carousel's chronological order is preserved:
    /// existing image entries keep their slots (or get refreshed in place for resize replacements),
    /// removed images drop out, and new images are appended at the end.
    func setAIChatAttachments(_ attachments: [AIChatImageAttachment]) {
        // `AIChatImageAttachment: Equatable` compares by `id` + image instance identity (see
        // its own conformance), which is exactly the change-detection rule we want here.
        guard attachments != aiChatAttachments else { return }
        aiChatAttachments = attachments
        aiChatPanelAttachments = reconcilePanelAttachments(updatedImages: attachments)
    }

    /// Replaces the duck.ai tab attachment list for this tab. Skips the write when the list is
    /// element-wise equal to the current one to avoid spurious publisher emissions during the
    /// tab-switch restore path (which echoes the current list back through the same setter).
    ///
    /// Also reconciles `aiChatPanelAttachments` to keep insertion order — see the equivalent doc
    /// on `setAIChatAttachments(_:)`.
    func setAIChatTabAttachments(_ attachments: [AIChatTabAttachment]) {
        guard attachments != aiChatTabAttachments else { return }
        aiChatTabAttachments = attachments
        aiChatPanelAttachments = reconcilePanelAttachments(updatedTabs: attachments)
    }

    /// Replaces the duck.ai file attachment list for this tab. Same idempotency + reconcile
    /// semantics as the image and tab setters — id-equality is the change check (`AIChatFileAttachment`
    /// is immutable once attached).
    func setAIChatFileAttachments(_ attachments: [AIChatFileAttachment]) {
        // `AIChatFileAttachment: Equatable` is id-only (files are immutable post-init), which
        // matches the change-detection rule we want here.
        guard attachments != aiChatFileAttachments else { return }
        aiChatFileAttachments = attachments
        aiChatPanelAttachments = reconcilePanelAttachments(updatedFiles: attachments)
    }

    /// Walks the current panel attachment list and produces a new one based on a fresh list of
    /// one attachment kind (images, tabs, or files). Entries of the *other* kinds keep their
    /// positions; entries of *this* kind are replaced from the new list (preserving order,
    /// dropping removed ones), and any genuinely new ids are appended.
    /// Exactly one parameter should be non-nil per call.
    private func reconcilePanelAttachments(
        updatedImages: [AIChatImageAttachment]? = nil,
        updatedTabs: [AIChatTabAttachment]? = nil,
        updatedFiles: [AIChatFileAttachment]? = nil
    ) -> [AIChatPanelAttachment] {
        if let updatedImages {
            return reconcile(
                replacingKindWith: updatedImages.map(AIChatPanelAttachment.image),
                matchesKind: { if case .image = $0 { return true } else { return false } }
            )
        }
        if let updatedTabs {
            return reconcile(
                replacingKindWith: updatedTabs.map(AIChatPanelAttachment.tab),
                matchesKind: { if case .tab = $0 { return true } else { return false } }
            )
        }
        if let updatedFiles {
            return reconcile(
                replacingKindWith: updatedFiles.map(AIChatPanelAttachment.file),
                matchesKind: { if case .file = $0 { return true } else { return false } }
            )
        }
        return aiChatPanelAttachments
    }

    /// Replaces all entries of a single kind in the panel attachment list with a fresh list of
    /// that kind, preserving the position of *other-kind* entries. Newly-introduced ids of the
    /// replaced kind are appended at the end. Used by `reconcilePanelAttachments` once per
    /// kind so the cyclomatic complexity stays linear.
    private func reconcile(
        replacingKindWith updatedOfKind: [AIChatPanelAttachment],
        matchesKind: (AIChatPanelAttachment) -> Bool
    ) -> [AIChatPanelAttachment] {
        let updatedById: [String: AIChatPanelAttachment] = Dictionary(
            uniqueKeysWithValues: updatedOfKind.map { ($0.attachmentId, $0) }
        )
        var consumed = Set<String>()
        var result: [AIChatPanelAttachment] = []
        for entry in aiChatPanelAttachments {
            if matchesKind(entry) {
                if let updated = updatedById[entry.attachmentId] {
                    result.append(updated)
                    consumed.insert(entry.attachmentId)
                }
                // else: dropped from the new list — omit.
            } else {
                result.append(entry)
            }
        }
        for entry in updatedOfKind where !consumed.contains(entry.attachmentId) {
            result.append(entry)
        }

        return result
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
