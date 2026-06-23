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

    /// A finished voice chat converted to a transcript: title plus the transcript
    /// snippet. Renders as a light card identical to `.text`, distinguished only by
    /// a "Transcript" chip. The live (in-progress) voice state is `.voice` instead.
    case transcript(title: String, snippet: String)

    /// A conversation whose last assistant message is an image: title plus the file
    /// ref used to load the thumbnail from the native file store.
    case image(title: String, imageFileRef: String)

    /// A live (in-progress) voice session — surfaced by the resolver's live-voice override,
    /// not the persisted classifier. Rendered as the dark voice card. Carries no payload: the
    /// card is fully static ("Listening…" status + mascot + "Voice" chip).
    case voice

    /// Empty-state card (centered Dax logo + "Duck.ai" label): a chat exists in
    /// native storage but has no assistant messages yet.
    case empty
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
            guard let snippet = snippet(from: lastMessageContent) else { return nil }
            return .text(title: title, snippet: snippet)
        case .imageGeneration:
            guard let fileRef = chat.fileRefs.last else { return nil }
            return .image(title: title, imageFileRef: fileRef)
        case .voice:
            // A voice chat is only persisted after the session ends and is converted
            // to a transcript, so a persisted `.voice` chat carries its transcript in
            // `lastMessageContent`.
            guard let snippet = snippet(from: lastMessageContent) else { return nil }
            return .transcript(title: title, snippet: snippet)
        }
    }

    /// Trims and caps `content`, returning `nil` when there's nothing meaningful to show.
    private static func snippet(from content: String?) -> String? {
        let trimmed = content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(snippetCharacterCap))
    }
}
