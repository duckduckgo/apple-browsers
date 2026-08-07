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

    /// The type chip shown on a card. `chipKind` maps each item to one (or `nil` for no chip).
    enum ChipKind {
        case chat, transcript, voice
    }

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

    /// Empty card showing the centred Duck.ai logo. `title`/`chip` non-nil → an existing chat
    /// whose content is empty (logo replaces the snippet/thumbnail, keeping title + chip);
    /// both nil → the bare card for a Duck.ai tab with no chatID.
    case empty(title: String?, chip: ChipKind?)
}

extension DuckAIGridItem {

    /// The type chip to show for this item, or `nil` for no chip (the bare empty card).
    var chipKind: ChipKind? {
        switch self {
        case .text, .image: return .chat
        case .transcript: return .transcript
        case .voice: return .voice
        case .empty(_, let chip): return chip
        }
    }

    /// Chat content can be huge and we only need a few lines worth of content anyway for the snippet
    static let snippetCharacterCap = 500

    /// Maps a decoded chat (+ the text of its last message) to a grid item. Always succeeds: a chat
    /// with no renderable content maps to an `.empty` card rather than falling back to the screenshot.
    /// Pure; storage reads live in `DuckAIGridContentResolver`.
    static func from(chat: DuckAiChat, lastMessageContent: String?) -> DuckAIGridItem {
        let title = chat.title.isEmpty ? UserText.aiChatTabSwitcherCardUntitledChat : chat.title

        // Empty content keeps the card (title + type chip) but shows the Duck.ai logo instead of
        // the snippet/thumbnail — it no longer falls back to the screenshot.
        switch chat.chatType {
        case .discussion:
            guard let snippet = snippet(from: lastMessageContent) else { return .empty(title: title, chip: .chat) }
            return .text(title: title, snippet: snippet)
        case .imageGeneration:
            guard let fileRef = chat.fileRefs.last else { return .empty(title: title, chip: .chat) }
            return .image(title: title, imageFileRef: fileRef)
        case .voice:
            // A voice chat is only persisted after the session ends and is converted
            // to a transcript, so a persisted `.voice` chat carries its transcript in
            // `lastMessageContent`.
            guard let snippet = snippet(from: lastMessageContent) else { return .empty(title: title, chip: .transcript) }
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
