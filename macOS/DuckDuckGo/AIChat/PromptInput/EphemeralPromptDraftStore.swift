//
//  EphemeralPromptDraftStore.swift
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

import AIChat
import Combine
import Foundation

/// In-memory prompt draft with no tab to persist against. Used by the Prompt Bar, which starts
/// from a clean slate on every presentation — `reset()` is called when the bar is dismissed.
final class EphemeralPromptDraftStore: DuckAIPromptDraftStoring {

    @Published private(set) var text: String = ""
    @Published private(set) var aiChatPanelAttachments: [AIChatPanelAttachment] = []

    private(set) var hasUserInteractedWithText: Bool = false
    private(set) var selectionRange = NSRange(location: 0, length: 0)
    private(set) var aiChatToolMode: AIChatToolMode?
    private(set) var aiChatAttachments: [AIChatImageAttachment] = []
    private(set) var aiChatTabAttachments: [AIChatTabAttachment] = []
    private(set) var aiChatFileAttachments: [AIChatFileAttachment] = []

    var textPublisher: AnyPublisher<String, Never> {
        $text.eraseToAnyPublisher()
    }

    var panelAttachmentsPublisher: AnyPublisher<[AIChatPanelAttachment], Never> {
        $aiChatPanelAttachments.eraseToAnyPublisher()
    }

    func updateText(_ newText: String, markInteraction: Bool) {
        if markInteraction && !newText.isEmpty {
            hasUserInteractedWithText = true
        }
        text = newText
        selectionRange = selectionRange.clamped(toTextLength: newText.count)
    }

    func updateSelection(_ range: NSRange) {
        selectionRange = range.clamped(toTextLength: text.count)
    }

    func setAIChatToolMode(_ mode: AIChatToolMode?) {
        guard aiChatToolMode != mode else { return }
        aiChatToolMode = mode
    }

    func setAIChatAttachments(_ attachments: [AIChatImageAttachment]) {
        guard attachments != aiChatAttachments else { return }
        aiChatAttachments = attachments
        aiChatPanelAttachments = DuckAIPanelAttachmentReconciler.reconciled(aiChatPanelAttachments, replacingImagesWith: attachments)
    }

    func setAIChatTabAttachments(_ attachments: [AIChatTabAttachment]) {
        guard attachments != aiChatTabAttachments else { return }
        aiChatTabAttachments = attachments
        aiChatPanelAttachments = DuckAIPanelAttachmentReconciler.reconciled(aiChatPanelAttachments, replacingTabsWith: attachments)
    }

    func setAIChatFileAttachments(_ attachments: [AIChatFileAttachment]) {
        guard attachments != aiChatFileAttachments else { return }
        aiChatFileAttachments = attachments
        aiChatPanelAttachments = DuckAIPanelAttachmentReconciler.reconciled(aiChatPanelAttachments, replacingFilesWith: attachments)
    }

    /// Clears the draft. Emits on both publishers only when something actually changed, so a
    /// reset of an already-empty store doesn't churn the carousel.
    func reset() {
        hasUserInteractedWithText = false
        selectionRange = NSRange(location: 0, length: 0)
        aiChatToolMode = nil
        aiChatAttachments = []
        aiChatTabAttachments = []
        aiChatFileAttachments = []
        if !text.isEmpty {
            text = ""
        }
        if !aiChatPanelAttachments.isEmpty {
            aiChatPanelAttachments = []
        }
    }
}
