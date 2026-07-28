//
//  DuckAIPromptDraftStoring.swift
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

/// Storage for one in-progress Duck.ai prompt: text, selection, tool selection and attachments.
///
/// The address bar backs this per browser tab (`AddressBarSharedTextState`) so drafts survive tab
/// switches; the Prompt Bar backs it with a single in-memory store cleared on each dismissal.
protocol DuckAIPromptDraftStoring: AnyObject {

    var text: String { get }
    var textPublisher: AnyPublisher<String, Never> { get }

    /// Whether the user has typed anything. Guards restore paths from overwriting live input
    /// with an empty draft.
    var hasUserInteractedWithText: Bool { get }

    var selectionRange: NSRange { get }
    var aiChatToolMode: AIChatToolMode? { get }
    var aiChatAttachments: [AIChatImageAttachment] { get }
    var aiChatTabAttachments: [AIChatTabAttachment] { get }
    var aiChatFileAttachments: [AIChatFileAttachment] { get }

    /// Insertion-ordered union of image, file and tab attachments — the carousel renders from this.
    var aiChatPanelAttachments: [AIChatPanelAttachment] { get }
    var panelAttachmentsPublisher: AnyPublisher<[AIChatPanelAttachment], Never> { get }

    func updateText(_ newText: String, markInteraction: Bool)
    func updateSelection(_ range: NSRange)
    func setAIChatToolMode(_ mode: AIChatToolMode?)
    func setAIChatAttachments(_ attachments: [AIChatImageAttachment])
    func setAIChatTabAttachments(_ attachments: [AIChatTabAttachment])
    func setAIChatFileAttachments(_ attachments: [AIChatFileAttachment])
}

extension AddressBarSharedTextState: DuckAIPromptDraftStoring {

    var textPublisher: AnyPublisher<String, Never> {
        $text.eraseToAnyPublisher()
    }

    var panelAttachmentsPublisher: AnyPublisher<[AIChatPanelAttachment], Never> {
        $aiChatPanelAttachments.eraseToAnyPublisher()
    }
}
