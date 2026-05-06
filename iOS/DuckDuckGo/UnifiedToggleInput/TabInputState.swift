//
//  TabInputState.swift
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

typealias TabUID = String

struct TabInputState: Equatable {
    var text: String
    var toggleMode: TextEntryMode
    var attachments: [AIChatImageAttachment]
    var selectedModelID: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?

    init(
        text: String = "",
        toggleMode: TextEntryMode = .search,
        attachments: [AIChatImageAttachment] = [],
        selectedModelID: String? = nil,
        selectedReasoningMode: AIChatReasoningMode? = nil,
        selectedTool: AIChatRAGTool? = nil
    ) {
        self.text = text
        self.toggleMode = toggleMode
        self.attachments = attachments
        self.selectedModelID = selectedModelID
        self.selectedReasoningMode = selectedReasoningMode
        self.selectedTool = selectedTool
    }

    // AIChatImageAttachment is Identifiable but not Equatable, so compare attachments by id.
    static func == (lhs: TabInputState, rhs: TabInputState) -> Bool {
        lhs.text == rhs.text
            && lhs.toggleMode == rhs.toggleMode
            && lhs.attachments.map(\.id) == rhs.attachments.map(\.id)
            && lhs.selectedModelID == rhs.selectedModelID
            && lhs.selectedReasoningMode == rhs.selectedReasoningMode
            && lhs.selectedTool == rhs.selectedTool
    }

    /// Compact, privacy-aware description for debug logs. Reports text length and
    /// attachment count rather than the values themselves so user prompts and image
    /// data don't end up in `os_log` output.
    var summary: String {
        let mode = toggleMode.rawValue
        let textLen = text.count
        let attachments = self.attachments.count
        let model = selectedModelID ?? "nil"
        let reasoning = selectedReasoningMode?.rawValue ?? "nil"
        let tool = selectedTool?.rawValue ?? "nil"
        return "mode=\(mode) text.count=\(textLen) attachments=\(attachments) model=\(model) reasoning=\(reasoning) tool=\(tool)"
    }
}
