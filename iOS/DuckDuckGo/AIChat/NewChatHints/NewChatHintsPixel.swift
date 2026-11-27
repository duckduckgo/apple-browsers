//
//  NewChatHintsPixel.swift
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
import PixelKit

enum NewChatHintsPixel: PixelKit.Event {

    struct FirstPrompt: Equatable {
        var hasImageAttachment = false
        var hasFileAttachment = false
        var selectedTool: AIChatRAGTool?
    }

    /// A full-tab Duck.ai new chat came on screen, whether or not the hints flag is on.
    case newChatShown(isFeatureEnabled: Bool)
    case firstPromptSent(isFeatureEnabled: Bool, hintsShown: Bool, tappedHint: NewChatHint?, prompt: FirstPrompt)
    /// `hints` in the order the row shows them.
    case hintsShown([NewChatHint])
    /// `position` is 1-based.
    case hintTapped(NewChatHint, position: Int)
    case capReached
    /// The file picker opened by the documents hint closed without a file chosen.
    case filePickerCancelled

    var name: String {
        switch self {
        case .newChatShown: return "aichat_new_chat_shown"
        case .firstPromptSent: return "aichat_new_chat_first_prompt_sent"
        case .hintsShown: return "aichat_new_chat_hints_shown"
        case .hintTapped: return "aichat_new_chat_hint_tapped"
        case .capReached: return "aichat_new_chat_hints_cap_reached_u"
        case .filePickerCancelled: return "aichat_new_chat_hint_file_picker_cancelled"
        }
    }

    var frequency: PixelKit.Frequency {
        switch self {
        case .capReached: return .uniqueByName
        default: return .dailyAndCount
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .newChatShown(let isFeatureEnabled):
            return [Parameter.isFeatureEnabled: String(isFeatureEnabled)]
        case .firstPromptSent(let isFeatureEnabled, let hintsShown, let tappedHint, let prompt):
            return [
                Parameter.isFeatureEnabled: String(isFeatureEnabled),
                Parameter.hintsShown: String(hintsShown),
                Parameter.hintTapped: tappedHint?.pixelValue ?? "none",
                Parameter.hasImageAttachment: String(prompt.hasImageAttachment),
                Parameter.hasFileAttachment: String(prompt.hasFileAttachment),
                Parameter.selectedTool: UnifiedPromptSubmittedSelectedToolPixelValue(selectedTool: prompt.selectedTool).rawValue,
            ]
        case .hintsShown(let hints):
            // Every hint reports its slot, 0 when the row left it out.
            return Dictionary(uniqueKeysWithValues: NewChatHint.allCases.map { hint in
                ("\(hint.pixelValue)_position", String((hints.firstIndex(of: hint) ?? -1) + 1))
            })
        case .hintTapped(let hint, let position):
            return [Parameter.hint: hint.pixelValue, Parameter.position: String(position)]
        case .capReached, .filePickerCancelled:
            return nil
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }

    private enum Parameter {
        static let isFeatureEnabled = "newchathints_enabled"
        static let hintsShown = "hints_shown"
        static let hintTapped = "hint_tapped"
        static let hasImageAttachment = "has_image_attachment"
        static let hasFileAttachment = "has_file_attachment"
        static let selectedTool = "selected_tool"
        static let hint = "hint"
        static let position = "position"
    }
}
