//
//  AIChatSuggestion.swift
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

/// Represents a chat suggestion displayed in the AI Chat omnibar.
/// Can be either a pinned chat or a recent chat.
public struct AIChatSuggestion: Identifiable, Equatable, Hashable {

    /// Unique identifier for the suggestion
    public let id: String

    /// The display title of the chat (typically the first message or a generated title)
    public let title: String

    /// Whether this chat is pinned by the user
    public let isPinned: Bool

    /// The chat ID used to restore/open this chat in duck.ai
    public let chatId: String

    /// Timestamp of the last interaction with this chat
    public let timestamp: Date?

    /// Content of the first user message in the chat
    public let firstUserMessageContent: String?

    /// The AI model the chat was conducted with (e.g. `"gpt-4o-mini"`, `"voice-mode"`,
    /// `"image-generation"`). Nil when the data source doesn't carry a model — the Duck.ai
    /// webview path (`getDuckAiChats`) doesn't include it today; the local-storage path does.
    /// Drives the chat's icon classification via `kind`.
    public let model: String?

    public init(
        id: String,
        title: String,
        isPinned: Bool,
        chatId: String,
        timestamp: Date? = nil,
        firstUserMessageContent: String? = nil,
        model: String? = nil
    ) {
        self.id = id
        self.title = Self.sanitize(title)
        self.isPinned = isPinned
        self.chatId = chatId
        self.timestamp = timestamp
        self.firstUserMessageContent = firstUserMessageContent
        self.model = model
    }
}

// MARK: - Kind

extension AIChatSuggestion {

    /// Coarse classification of a chat used to pick a list-row icon. Derived from `model`
    /// because the Duck.ai stored chat record persists the model used for the conversation.
    public enum Kind: Equatable {
        case voice
        case image
        case text
    }

    /// Returns the chat's kind based on its `model` string. Voice and image chats are matched
    /// against the canonical mode tokens Duck.ai persists (`AIChatNativePrompt.voiceMode` and
    /// `AIChatNativePrompt.imageGenerationMode`); everything else (including chats from data
    /// sources that don't carry a model yet) is treated as a regular text chat.
    public var kind: Kind {
        Self.kind(forModel: model)
    }

    /// Pure helper kept separate from the property so the mapping is easy to test and tune as
    /// new model identifiers ship from Duck.ai. Uses exact equality so a future model name that
    /// embeds the token (e.g. `"voice-mode-experimental-2"`) does not accidentally classify as
    /// `.voice` — Duck.ai persists the canonical mode tokens unmodified.
    public static func kind(forModel model: String?) -> Kind {
        guard let model, !model.isEmpty else { return .text }
        switch model {
        case AIChatNativePrompt.voiceMode: return .voice
        case AIChatNativePrompt.imageGenerationMode: return .image
        default: return .text
        }
    }

    /// Collapses any runs of whitespace (including newlines) into a single space and trims.
    static func sanitize(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Date Parsing

extension AIChatSuggestion {

    /// Shared ISO8601 date formatter for parsing chat timestamps.
    /// Configured to handle dates like "2026-01-19T11:48:10.903Z"
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Parses an ISO8601 date string into a Date object.
    /// - Parameter dateString: ISO8601 formatted date string (e.g., "2026-01-19T11:48:10.903Z")
    /// - Returns: Parsed Date, or nil if parsing fails
    public static func parseISO8601Date(_ dateString: String?) -> Date? {
        guard let dateString else { return nil }
        return iso8601Formatter.date(from: dateString)
    }

    /// Formats a Date into an ISO8601 string with fractional seconds.
    /// - Parameter date: Date to format.
    /// - Returns: ISO8601 formatted date string, or nil if date is nil.
    public static func formatISO8601Date(_ date: Date?) -> String? {
        guard let date else { return nil }
        return iso8601Formatter.string(from: date)
    }
}

// MARK: - Mock Data

extension AIChatSuggestion {

    /// Mock recent chats for development and testing.
    public static let mockRecentChats: [AIChatSuggestion] = [
        AIChatSuggestion(
            id: "recent-1",
            title: "What's the best way to learn Swift?",
            isPinned: false,
            chatId: "chat-recent-1",
            timestamp: Date().addingTimeInterval(-1800)
        ),
        AIChatSuggestion(
            id: "recent-2",
            title: "Explain quantum computing in simple terms",
            isPinned: false,
            chatId: "chat-recent-2",
            timestamp: Date().addingTimeInterval(-3600)
        ),
        AIChatSuggestion(
            id: "recent-3",
            title: "How do I make sourdough bread?",
            isPinned: false,
            chatId: "chat-recent-3",
            timestamp: Date().addingTimeInterval(-5400)
        )
    ]
}
