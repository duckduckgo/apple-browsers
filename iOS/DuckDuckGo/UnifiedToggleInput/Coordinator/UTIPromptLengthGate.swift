//
//  UTIPromptLengthGate.swift
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

import AIChat
import Foundation

extension AIChatPromptLimits {

    func evaluate(prompt: String,
                  attachments: [UnifiedToggleInputAttachment],
                  attachmentLimits: AIChatAttachmentTierLimits?) -> AIChatPromptLength {
        evaluate(prompt: prompt,
                 pastedTexts: attachments.compactMap(\.pastedText),
                 hasImage: attachments.contains(where: \.isImage),
                 maxCharactersWithImage: attachmentLimits?.images.maxInputCharsWithAttachments)
    }
}

@MainActor
final class UTIPromptLengthGate {

    struct Inputs {
        let promptText: () -> String
        let attachments: () -> [UnifiedToggleInputAttachment]
        let attachmentLimits: () -> AIChatAttachmentTierLimits?
        let isEnabled: () -> Bool
    }

    /// Each sink ignores a repeated value, so `refresh()` reports every time.
    struct Outputs {
        let onOverLimitChanged: (AIChatPromptLength?) -> Void
        let onPromptOverLimitChanged: (Bool) -> Void
    }

    private let limits: AIChatPromptLimits
    private let inputs: Inputs
    private let outputs: Outputs

    private(set) var promptLength: AIChatPromptLength?

    init(limits: AIChatPromptLimits = .current, inputs: Inputs, outputs: Outputs) {
        self.limits = limits
        self.inputs = inputs
        self.outputs = outputs
    }

    var isSubmitBlocked: Bool { promptLength?.isOverLimit == true }

    /// `refresh()` measures the typed draft. A submit may send other text (Paste & Go clears the draft, a quick action
    /// replaces it), so the prompt that is actually sent is measured here with the attachments it carries.
    func blocksSubmission(of text: String) -> Bool {
        guard inputs.isEnabled() else { return false }
        return limits.evaluate(prompt: text, attachments: inputs.attachments(), attachmentLimits: inputs.attachmentLimits()).isOverLimit
    }

    func sheetLimit(for paste: AIChatPastedText) -> Int {
        let length = promptLength ?? limits.evaluate(prompt: inputs.promptText(), attachments: inputs.attachments(),
                                                     attachmentLimits: inputs.attachmentLimits())
        return max(0, length.limit(forEditing: paste))
    }

    func refresh() {
        promptLength = inputs.isEnabled()
            ? limits.evaluate(prompt: inputs.promptText(), attachments: inputs.attachments(), attachmentLimits: inputs.attachmentLimits())
            : nil
        let overLimit = promptLength.flatMap { $0.isOverLimit ? $0 : nil }
        outputs.onOverLimitChanged(overLimit)
        outputs.onPromptOverLimitChanged(overLimit != nil)
    }
}
