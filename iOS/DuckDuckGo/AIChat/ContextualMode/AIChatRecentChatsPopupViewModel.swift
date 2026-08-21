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

// MARK: - Delegate

/// Backs the chats menu: the recent chats to offer, capped, plus whether New Chat applies.
@MainActor
final class AIChatRecentChatsPopupViewModel {

    // MARK: - Constants

    static let maxVisibleChats = 5

    // MARK: - Properties

    /// The chat suggestions (up to maxVisibleChats).
    let suggestions: [AIChatSuggestion]

    // MARK: - Initialization

    /// Creates a view model from raw fetched data.
    /// - Parameters:
    ///   - suggestions: The chat suggestions to display (will be capped at maxVisibleChats).
    init(suggestions: [AIChatSuggestion]) {
        self.suggestions = Array(suggestions.prefix(Self.maxVisibleChats))
    }

}

// MARK: - Fetching

extension AIChatRecentChatsPopupViewModel {

    /// Fetches recent chats from the reader and creates a view model.
    /// Returns nil only if the reader is nil; the popup still opens with no suggestions.
    static func fetch(using reader: AIChatSuggestionsReading?) async -> AIChatRecentChatsPopupViewModel? {
        guard let reader else { return nil }
        let result = await reader.fetchSuggestions(query: nil, maxChats: maxVisibleChats + 1)
        let all = result.pinned + result.recent
        let capped = Array(all.prefix(maxVisibleChats))
        return AIChatRecentChatsPopupViewModel(suggestions: capped)
    }
}
