//
//  DuckAiChat.swift
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

/// Represents a Duck.ai chat as stored in the native local database.
public struct DuckAiChat: Equatable {

    public let chatId: String

    /// The display title of the chat.
    public let title: String

    /// The AI model used for this chat (e.g. "gpt-4o-mini").
    public let model: String

    /// ISO-8601 string as stored by the FE, e.g. "2026-04-01T21:31:54.260Z".
    public let lastEdit: String

    /// Whether this chat is pinned by the user.
    public let pinned: Bool

    /// UUIDs of files referenced by this chat, stored in the native file store.
    public let fileRefs: [String]

    /// Raw FE-supplied reasoning-mode string for this chat.
    public let reasoningMode: String?

    /// True when any assistant message in the chat carries a `ui-component` part named
    /// `generate-image` — i.e. the chat produced generated images via a tool call,
    /// regardless of the chat's `model` field.
    public let isImageGeneration: Bool

    public init(
        chatId: String,
        title: String,
        model: String,
        lastEdit: String,
        pinned: Bool,
        fileRefs: [String] = [],
        reasoningMode: String? = nil,
        isImageGeneration: Bool = false
    ) {
        self.chatId = chatId
        self.title = title
        self.model = model
        self.lastEdit = lastEdit
        self.pinned = pinned
        self.fileRefs = fileRefs
        self.reasoningMode = reasoningMode
        self.isImageGeneration = isImageGeneration
    }
}

// MARK: - Mutation helpers

public extension DuckAiChat {
    /// Returns a copy with `pinned` set to the supplied value.
    func withPinned(_ newValue: Bool) -> DuckAiChat {
        DuckAiChat(
            chatId: chatId,
            title: title,
            model: model,
            lastEdit: lastEdit,
            pinned: newValue,
            fileRefs: fileRefs,
            reasoningMode: reasoningMode,
            isImageGeneration: isImageGeneration
        )
    }
}

// MARK: - JSON Decoding

extension DuckAiChat {

    /// Decodes a `DuckAiChat`, the text of the first user message, and the text of the last
    /// message (regardless of role) from a raw JSON data blob as stored in the native data
    /// store's `duck_ai_chats` table. Throws on invalid JSON or missing required fields.
    public static func decode(from data: Data) throws -> (chat: DuckAiChat,
                                                          firstUserMessageContent: String?,
                                                          lastMessageContent: String?) {
        let blob = try JSONDecoder().decode(ChatBlob.self, from: data)

        let chat = DuckAiChat(
            chatId: blob.chatId,
            title: blob.title ?? "Untitled Chat",
            model: blob.model ?? "",
            lastEdit: blob.lastEdit ?? "",
            pinned: blob.pinned ?? false,
            fileRefs: blob.fileRefs ?? [],
            reasoningMode: blob.reasoningMode,
            isImageGeneration: blob.hasGenerateImageUiComponent
        )

        let firstUserMessage = blob.messages?
            .first(where: { $0.role == "user" })?
            .effectiveTextContent

        let lastMessage = blob.messages?.last?.effectiveTextContent

        return (chat: chat,
                firstUserMessageContent: firstUserMessage,
                lastMessageContent: lastMessage)
    }
}

// MARK: - Private Decodable Types

private struct ChatBlob: Decodable {
    let chatId: String
    let title: String?
    let model: String?
    let lastEdit: String?
    let pinned: Bool?
    let fileRefs: [String]?
    let messages: [MessageBlob]?
    let reasoningMode: String?

    /// True when any assistant message carries a `ui-component` part named `generate-image`.
    var hasGenerateImageUiComponent: Bool {
        guard let messages else { return false }
        return messages.contains { message in
            guard message.role == "assistant" else { return false }
            return message.parts?.contains { part in
                part.type == "ui-component" && part.name == "generate-image"
            } ?? false
        }
    }
}

private struct MessageBlob: Decodable {
    let role: String
    /// Assistant tool-call messages can ship without a `content` string — they carry the
    /// payload in `parts` instead. Keeping this optional means we still decode the message
    /// (and can inspect `parts` to detect image-gen chats) instead of failing the whole
    /// `messages` array.
    let content: MessageContent?
    let parts: [MessagePart]?

    /// Returns the visible text of the message. Prefers `content` (used by most chats and
    /// by all user messages); falls back to concatenating `parts[].text` of `type == "text"`
    /// because reasoning-model assistant messages (e.g. `gpt-5-mini`) ship with `content == ""`
    /// and carry the actual response in `parts`. Returns `nil` when neither path produces text.
    var effectiveTextContent: String? {
        if let direct = content?.textValue, !direct.isEmpty {
            return direct
        }
        guard let parts else { return nil }
        let textParts = parts.compactMap { part -> String? in
            guard part.type == "text", let text = part.text, !text.isEmpty else { return nil }
            return text
        }
        guard !textParts.isEmpty else { return nil }
        return textParts.joined(separator: "\n\n")
    }
}

private struct MessagePart: Decodable {
    let type: String?
    let name: String?
    /// Visible text payload of a `type == "text"` part. Other part types (`reasoning`,
    /// `ui-component`, `tool-invocation`) don't carry user-visible text and leave this nil.
    let text: String?
}

/// Handles polymorphic message content: either a plain string or a rich object with a `text` field.
private enum MessageContent: Decodable {
    case text(String)
    case rich(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else {
            let rich = try container.decode(RichContent.self)
            self = .rich(rich.text)
        }
    }

    var textValue: String {
        switch self {
        case .text(let text): return text
        case .rich(let text): return text
        }
    }
}

private struct RichContent: Decodable {
    let text: String
}
