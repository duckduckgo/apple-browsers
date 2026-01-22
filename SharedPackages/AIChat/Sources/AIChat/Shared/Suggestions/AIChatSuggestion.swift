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

    public init(
        id: String,
        title: String,
        isPinned: Bool,
        chatId: String,
        timestamp: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.isPinned = isPinned
        self.chatId = chatId
        self.timestamp = timestamp
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
