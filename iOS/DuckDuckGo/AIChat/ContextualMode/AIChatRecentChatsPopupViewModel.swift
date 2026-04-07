//
//  AIChatRecentChatsPopupViewModel.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Foundation

/// View model for the recent chats popup, extracting presentation logic from the view controller.
@MainActor
final class AIChatRecentChatsPopupViewModel {

    // MARK: - Constants

    static let maxVisibleChats = 5

    // MARK: - Properties

    /// Whether the "View all chats" footer should be shown.
    let showViewAll: Bool

    /// The chat suggestions (up to maxVisibleChats).
    let suggestions: [AIChatSuggestion]

    // MARK: - Initialization

    /// Creates a view model from raw fetched data.
    /// - Parameters:
    ///   - suggestions: The chat suggestions to display (will be capped at maxVisibleChats).
    ///   - hasMore: Whether there are more chats beyond the displayed ones.
    init(suggestions: [AIChatSuggestion], hasMore: Bool) {
        self.suggestions = Array(suggestions.prefix(Self.maxVisibleChats))
        self.showViewAll = hasMore
    }

    // MARK: - Queries

    /// Whether the popup has any content to display.
    var hasContent: Bool {
        !suggestions.isEmpty
    }

    /// Returns the suggestion at the given index, or nil if out of bounds.
    func suggestion(at index: Int) -> AIChatSuggestion? {
        guard index >= 0, index < suggestions.count else { return nil }
        return suggestions[index]
    }
}

// MARK: - Fetching

extension AIChatRecentChatsPopupViewModel {

    /// Fetches recent chats from the reader and creates a view model.
    /// Returns nil if the reader is nil or there are no suggestions.
    static func fetch(using reader: AIChatSuggestionsReading?) async -> AIChatRecentChatsPopupViewModel? {
        guard let reader else { return nil }
        let result = await reader.fetchSuggestions(query: nil, maxChats: maxVisibleChats + 1)
        let all = result.pinned + result.recent
        let hasMore = all.count > maxVisibleChats
        let capped = Array(all.prefix(maxVisibleChats))
        guard !capped.isEmpty else { return nil }
        return AIChatRecentChatsPopupViewModel(suggestions: capped, hasMore: hasMore)
    }
}
