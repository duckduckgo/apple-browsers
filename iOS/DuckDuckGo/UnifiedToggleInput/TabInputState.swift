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
    var attachments: [UnifiedToggleInputAttachment]
    var selectedModelID: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?
    /// Driven by FE `hideChatInput` / `showChatInput` user-script messages. Persisted per tab
    /// because FE does not re-emit when the user returns to a tab already in voice mode.
    var aiChatInputBoxVisibility: AIChatInputBoxVisibility
    /// Driven by FE `voiceSessionStarted` / `voiceSessionEnded` user-script messages. Hides the
    /// header chats/compose pill while voice is active; orthogonal to `aiChatInputBoxVisibility`.
    var isVoiceSessionActive: Bool

    init(
        text: String = "",
        toggleMode: TextEntryMode = .search,
        attachments: [UnifiedToggleInputAttachment] = [],
        selectedModelID: String? = nil,
        selectedReasoningMode: AIChatReasoningMode? = nil,
        selectedTool: AIChatRAGTool? = nil,
        aiChatInputBoxVisibility: AIChatInputBoxVisibility = .unknown,
        isVoiceSessionActive: Bool = false
    ) {
        self.text = text
        self.toggleMode = toggleMode
        self.attachments = attachments
        self.selectedModelID = selectedModelID
        self.selectedReasoningMode = selectedReasoningMode
        self.selectedTool = selectedTool
        self.aiChatInputBoxVisibility = aiChatInputBoxVisibility
        self.isVoiceSessionActive = isVoiceSessionActive
    }

    /// Leaving voice also restores the chat input if it was hidden for voice, so the user isn't
    /// left without an input bar when FE / URL teardown ends the session.
    func applyingVoiceSessionTransition(active: Bool) -> TabInputState {
        var copy = self
        copy.isVoiceSessionActive = active
        if !active, copy.aiChatInputBoxVisibility == .hidden {
            copy.aiChatInputBoxVisibility = .visible
        }
        return copy
    }

    static func == (lhs: TabInputState, rhs: TabInputState) -> Bool {
        lhs.text == rhs.text
            && lhs.toggleMode == rhs.toggleMode
            && lhs.attachments.map(\.id) == rhs.attachments.map(\.id)
            && lhs.selectedModelID == rhs.selectedModelID
            && lhs.selectedReasoningMode == rhs.selectedReasoningMode
            && lhs.selectedTool == rhs.selectedTool
            && lhs.aiChatInputBoxVisibility == rhs.aiChatInputBoxVisibility
            && lhs.isVoiceSessionActive == rhs.isVoiceSessionActive
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
        return "mode=\(mode) text.count=\(textLen) attachments=\(attachments) model=\(model) reasoning=\(reasoning) tool=\(tool) inputBox=\(aiChatInputBoxVisibility.rawValue) voice=\(isVoiceSessionActive)"
    }
}
