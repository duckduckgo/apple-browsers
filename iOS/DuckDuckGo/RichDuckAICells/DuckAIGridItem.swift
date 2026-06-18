//
//  DuckAIGridItem.swift
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

import Foundation
import AIChat

/// Describes how a Duck.ai chat tab should be rendered in the tab switcher grid.
enum DuckAIGridItem: Equatable {

    /// A text conversation: title plus the snippet of the last assistant message.
    case text(title: String, snippet: String)

    /// A conversation whose last assistant message is an image: title plus the file
    /// ref used to load the thumbnail from the native file store.
    case image(title: String, imageFileRef: String)

    /// A voice-mode chat (`chat.model == "voice-mode"`): title only; the dark
    /// voice-AI card variant from Figma is rendered around it.
    case voice(title: String)

    /// Empty-state card (centered Dax logo + "Duck.ai" label): a chat exists in
    /// native storage but has no assistant messages yet.
    case empty(title: String)
}

extension DuckAIGridItem {

    /// Chat content can be huge and we only need a few lines worth of content anyway for the snippet
    static let snippetCharacterCap = 500

    /// Maps a decoded chat (+ the text of its last message) to a grid item, or
    /// `nil` when the chat shouldn't be rendered as a rich card (callers fall back
    /// to the existing screenshot path). Pure; storage reads live in
    /// `DuckAIGridContentResolver`.
    static func from(chat: DuckAiChat, lastMessageContent: String?) -> DuckAIGridItem? {
        let title = chat.title.isEmpty ? UserText.aiChatTabSwitcherCardUntitledChat : chat.title

        switch chat.chatType {
        case .discussion:
            let trimmed = lastMessageContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { return nil }
            let snippet = String(trimmed.prefix(snippetCharacterCap))
            return .text(title: title, snippet: snippet)
        case .imageGeneration:
            guard let fileRef = chat.fileRefs.last else { return nil }
            return .image(title: title, imageFileRef: fileRef)
        case .voice:
            return nil
        }
    }
}
