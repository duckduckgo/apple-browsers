//
//  SuggestionRowMapper.swift
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
import Foundation
import Suggestions

/// Pure mapping of existing suggestion models to the unified `SuggestionRow`.
/// Title/subtitle/icon logic mirrors the legacy renderers so output is identical.
enum SuggestionRowMapper {

    /// `includesDeleteAccessory` adds the X-to-remove affordance to history rows. The Search
    /// autocomplete enables it; the Duck.ai suggestions list does not (matches the legacy surface).
    static func row(for suggestion: Suggestion,
                    query: String?,
                    idPrefix: String,
                    includesDeleteAccessory: Bool = false) -> SuggestionRow {
        switch suggestion {
        case .website(let url):
            return SuggestionRow(
                id: "\(idPrefix)-website-\(url.absoluteString)",
                icon: .globe,
                title: url.formattedForSuggestion(),
                query: nil,
                accessibilityID: "Autocomplete.Suggestions.ListItem.Website-\(url.formattedForSuggestion())")

        case .bookmark(let title, let url, let isFavorite, _):
            return SuggestionRow(
                id: "\(idPrefix)-bookmark-\(url.absoluteString)",
                icon: isFavorite ? .favorite : .bookmark,
                title: title,
                query: nil,
                subtitle: url.formattedForSuggestion(),
                accessibilityID: isFavorite
                    ? "Autocomplete.Suggestions.ListItem.Favorite-\(url.formattedForSuggestion())"
                    : "Autocomplete.Suggestions.ListItem.Bookmark-\(url.formattedForSuggestion())")

        case .historyEntry(_, let url, _) where url.isDuckDuckGoSearch:
            return SuggestionRow(
                id: "\(idPrefix)-serp-\(url.absoluteString)",
                icon: .history,
                title: url.searchQuery ?? "",
                query: nil,
                subtitle: UserText.autocompleteSearchDuckDuckGo,
                accessory: includesDeleteAccessory ? .delete : .none,
                accessibilityID: "Autocomplete.Suggestions.ListItem.SERPHistory-\(url.searchQuery ?? "")")

        case .historyEntry(let title, let url, _):
            return SuggestionRow(
                id: "\(idPrefix)-history-\(url.absoluteString)",
                icon: .history,
                title: title ?? url.formattedForSuggestion(),
                query: nil,
                subtitle: title == nil ? nil : url.formattedForSuggestion(),
                accessory: includesDeleteAccessory ? .delete : .none,
                accessibilityID: "Autocomplete.Suggestions.ListItem.History-\(url.formattedForSuggestion())")

        case .openTab(let title, let url, _, _):
            return SuggestionRow(
                id: "\(idPrefix)-openTab-\(url.absoluteString)",
                icon: .openTab,
                title: title,
                query: nil,
                subtitle: "\(UserText.autocompleteSwitchToTab) · \(url.formattedForSuggestion())",
                accessibilityID: "Autocomplete.Suggestions.ListItem.OpenTab-\(url.formattedForSuggestion())")

        case .phrase(let phrase):
            return SuggestionRow(
                id: "\(idPrefix)-phrase-\(phrase)",
                icon: .search,
                title: phrase,
                query: query,
                accessory: .tapAhead,
                accessibilityID: "Autocomplete.Suggestions.ListItem.SearchPhrase-\(phrase)")

        case .askAIChat(let value):
            return SuggestionRow(
                id: "\(idPrefix)-askAIChat-\(value)",
                icon: .aiChat,
                title: value,
                query: nil,
                subtitle: UserText.autocompleteAskAIChat,
                accessibilityID: "Autocomplete.Suggestions.ListItem.AskAIChat-\(value)")

        case .internalPage, .unknown:
            assertionFailure("Unsupported suggestion type in unified list: \(suggestion)")
            return SuggestionRow(
                id: "\(idPrefix)-unknown",
                icon: .globe,
                title: "",
                accessibilityID: "Autocomplete.Suggestions.ListItem.Unknown")
        }
    }

    static func row(for chat: AIChatSuggestion, includesFireDelete: Bool = false) -> SuggestionRow {
        SuggestionRow(
            id: "chat-\(chat.id)",
            icon: chat.isPinned ? .aiChatPinned : .aiChat,
            title: chat.title,
            accessory: includesFireDelete ? .fire : .none,
            accessibilityID: "DuckAISuggestions.Chat-\(chat.id)")
    }

    static func viewAllChatsRow(id: String) -> SuggestionRow {
        SuggestionRow(
            id: id,
            icon: .chats,
            title: UserText.aiChatViewAllChats,
            accessibilityID: "DuckAISuggestions.ViewAllChats")
    }

    static func searchRow(query: String, idPrefix: String) -> SuggestionRow {
        SuggestionRow(
            id: "\(idPrefix)-searchDuckDuckGo",
            icon: .search,
            title: query,
            subtitle: UserText.autocompleteSearchDuckDuckGo,
            accessibilityID: "DuckAISuggestions.SearchDuckDuckGo")
    }
}
