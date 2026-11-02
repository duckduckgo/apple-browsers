//
//  AIChatRecentChatsMenuViewModel.swift
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
import DesignResourcesKitIcons
import Foundation
import UIKit

/// Backs the chats menu: the recent chats to offer, capped.
@MainActor
final class AIChatRecentChatsMenuViewModel {

    // MARK: - Constants

    static let maxVisibleChats = 5

    // MARK: - Properties

    /// The chat suggestions (up to maxVisibleChats).
    let suggestions: [AIChatSuggestion]

    // MARK: - Initialization

    /// - Parameter suggestions: The chat suggestions to display (will be capped at maxVisibleChats).
    init(suggestions: [AIChatSuggestion]) {
        self.suggestions = Array(suggestions.prefix(Self.maxVisibleChats))
    }

}

// MARK: - Fetching

extension AIChatRecentChatsMenuViewModel {

    /// Fetches recent chats from the reader and creates a view model.
    /// Returns nil only if the reader is nil; the menu still opens with no suggestions.
    static func fetch(using reader: AIChatSuggestionsReading?) async -> AIChatRecentChatsMenuViewModel? {
        guard let reader else { return nil }
        let result = await reader.fetchSuggestions(query: nil, maxChats: maxVisibleChats + 1)
        let all = result.pinned + result.recent
        return AIChatRecentChatsMenuViewModel(suggestions: Array(all.prefix(maxVisibleChats)))
    }
}

// MARK: - Menu

extension AIChatRecentChatsMenuViewModel {

    enum MenuStyle {
        /// Contextual sheet: Open Duck.ai, New Chat while a chat is active, and a titled Recent Chats section.
        case contextual(showsNewChat: Bool)
        /// Tab switcher: New Chat, then the chats without a section title.
        case compact
    }

    struct MenuActions {
        var openDuckAI: () -> Void = {}
        let newChat: () -> Void
        let selectChat: (AIChatSuggestion) -> Void
        let viewAll: () -> Void
    }

    /// Fetches the chats each time the menu opens, rather than once when the menu is built.
    static func deferredMenuElement(reader: @escaping () -> AIChatSuggestionsReading?,
                                    sections: @escaping (AIChatRecentChatsMenuViewModel) -> [UIMenuElement]) -> UIMenuElement {
        UIDeferredMenuElement.uncached { completion in
            Task { @MainActor in
                let viewModel = await fetch(using: reader()) ?? AIChatRecentChatsMenuViewModel(suggestions: [])
                completion(sections(viewModel))
            }
        }
    }

    /// Sections in top-down order.
    func makeMenuSections(style: MenuStyle, actions: MenuActions) -> [UIMenuElement] {
        var sections = Self.leadingSections(style: style, actions: actions)
        if let chats = makeChatsSection(style: style, actions: actions) {
            sections.append(chats)
        }
        let viewAll = UIAction(title: UserText.aiChatViewAllChats, image: DesignSystemImages.Glyphs.Size16.openIn) { _ in actions.viewAll() }
        sections.append(UIMenu(options: .displayInline, children: [viewAll]))
        return sections
    }

    private static func leadingSections(style: MenuStyle, actions: MenuActions) -> [UIMenuElement] {
        let newChat = UIAction(title: UserText.actionNewAIChat, image: DesignSystemImages.Glyphs.Size16.compose) { _ in actions.newChat() }
        switch style {
        case .contextual(let showsNewChat):
            let openDuckAI = UIAction(title: UserText.duckAiContextualOpenDuckAi, image: DesignSystemImages.Glyphs.Size16.aiChat) { _ in actions.openDuckAI() }
            let openDuckAISection = UIMenu(options: .displayInline, children: [openDuckAI])
            return showsNewChat ? [openDuckAISection, UIMenu(options: .displayInline, children: [newChat])] : [openDuckAISection]
        case .compact:
            return [UIMenu(options: .displayInline, children: [newChat])]
        }
    }

    private func makeChatsSection(style: MenuStyle, actions: MenuActions) -> UIMenu? {
        guard !suggestions.isEmpty else { return nil }
        let chats = suggestions.map { suggestion in
            UIAction(title: suggestion.title,
                     image: suggestion.isPinned ? DesignSystemImages.Glyphs.Size16.pin : DesignSystemImages.Glyphs.Size16.chat) { _ in
                actions.selectChat(suggestion)
            }
        }
        switch style {
        case .contextual:
            return UIMenu(title: UserText.aiChatRecentChatsSectionTitle, options: .displayInline, children: chats)
        case .compact:
            return UIMenu(options: .displayInline, children: chats)
        }
    }
}
