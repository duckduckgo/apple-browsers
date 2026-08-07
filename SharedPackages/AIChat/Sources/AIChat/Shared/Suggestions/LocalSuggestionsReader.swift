//
//  LocalSuggestionsReader.swift
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
import os.log

/// Reads AI chat suggestions directly from the native local database,
/// bypassing the headless webview used by `SuggestionsReader`.
@MainActor
public final class LocalSuggestionsReader: SuggestionsReading {

    // MARK: - Properties

    private let storageHandler: DuckAiNativeStorageHandling

    /// One week in seconds.
    private static let oneWeekInterval: TimeInterval = 7 * 24 * 60 * 60

    // MARK: - Initialization

    public init(storageHandler: DuckAiNativeStorageHandling) {
        self.storageHandler = storageHandler
    }

    // MARK: - SuggestionsReading

    @MainActor
    public func fetchSuggestions(query: String?, maxChats: Int) async -> Result<(pinned: [AIChatSuggestion], recent: [AIChatSuggestion]), Error> {
        do {
            let records = try storageHandler.getAllChats()
            let decoded = records.compactMap { try? DuckAiChat.decode(from: $0.data) }

            let trimmedQuery = query?.trimmingCharacters(in: .whitespaces)
            let filtered: [(chat: DuckAiChat, firstUserMessageContent: String?, lastMessageContent: String?)]

            if let trimmedQuery, !trimmedQuery.isEmpty {
                filtered = decoded.filter { $0.chat.title.localizedCaseInsensitiveContains(trimmedQuery) }
            } else {
                let oneWeekAgo = Date().addingTimeInterval(-Self.oneWeekInterval)
                filtered = decoded.filter { item in
                    if item.chat.pinned { return true }
                    guard let date = AIChatSuggestion.parseISO8601Date(item.chat.lastEdit) else { return false }
                    return date >= oneWeekAgo
                }
            }

            let suggestions = filtered.map { item in
                AIChatSuggestion(
                    id: item.chat.chatId,
                    title: item.chat.title,
                    isPinned: item.chat.pinned,
                    chatId: item.chat.chatId,
                    timestamp: AIChatSuggestion.parseISO8601Date(item.chat.lastEdit),
                    firstUserMessageContent: item.firstUserMessageContent,
                    model: item.chat.model
                )
            }

            let pinned = suggestions.filter { $0.isPinned }
            var recent = suggestions.filter { !$0.isPinned }

            recent.sort { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
            recent = Array(recent.prefix(maxChats))

            return .success((pinned: pinned, recent: recent))
        } catch {
            Logger.aiChat.error("LocalSuggestionsReader: Failed to fetch chats: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    @MainActor
    public func tearDown() {
        // No-op — local storage does not require teardown.
    }
}
