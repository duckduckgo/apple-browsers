//
//  DuckAIRouting.swift
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

/// Which Duck.ai features a local model answers. One value, read by every entry point, so the debug screen's choices
/// mean the same thing on every surface.
public struct DuckAIRouting: Equatable, Sendable {

    public enum Chat: String, CaseIterable, Sendable {
        case web
        case native
    }

    public enum SuggestedPrompts: String, CaseIterable, Sendable {
        case staticCatalog
        case localModel
    }

    public enum Action: String, CaseIterable, Sendable {
        case web
        case local
    }

    /// Where a request comes from.
    public enum Entry: Equatable, Sendable {
        /// A typed prompt, a Duck.ai entry point, or a suggested prompt that starts a conversation.
        case chat
        /// Summarize or Translate on the page, from the contextual sheet.
        case pageAction
        /// Summarize or Translate on selected text.
        case selectionAction
    }

    public var chat: Chat
    public var suggestedPrompts: SuggestedPrompts
    public var pageActions: Action
    public var selectionActions: Action

    public init(chat: Chat = .web, suggestedPrompts: SuggestedPrompts = .staticCatalog,
                pageActions: Action = .web, selectionActions: Action = .web) {
        self.chat = chat
        self.suggestedPrompts = suggestedPrompts
        self.pageActions = pageActions
        self.selectionActions = selectionActions
    }

    public func answersNatively(_ entry: Entry) -> Bool {
        switch entry {
        case .chat: chat == .native
        case .pageAction: pageActions == .local
        case .selectionAction: selectionActions == .local
        }
    }

    public var generatesSuggestedPromptsLocally: Bool {
        suggestedPrompts == .localModel
    }

    /// The contextual sheet's suggestion ids. Anything else is a prompt that starts a chat.
    public static func entry(forSuggestionID id: String) -> Entry {
        switch id {
        case "summarize-page", "translate-page": .pageAction
        case "summarize-selection", "translate-selection": .selectionAction
        default: .chat
        }
    }
}
