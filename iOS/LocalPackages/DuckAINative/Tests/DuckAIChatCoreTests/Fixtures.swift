//
//  Fixtures.swift
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
@testable import DuckAIChatCore

enum Fixture {
    static let page = PageContext(title: "Ducks", url: URL(string: "https://example.com/ducks"), content: "Ducks are waterfowl.")
    static let selection = Selection(title: "Ducks", url: URL(string: "https://example.com/ducks"), content: "Mallards dabble.")
    static let german = TargetLanguage(code: "de", name: "German")
    static let budget = PromptBudget(contextWindowTokens: 8_192)
    static let conversation = ConversationID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)

    static func time(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_000_000 + seconds)
    }

    static func state(page: PageContext? = nil,
                      opening: Opening? = nil,
                      availability: ProviderAvailability = .ready) throws -> ChatState {
        let context = try ChatContext(page: page, selections: [], opening: opening)
        return ChatState(conversation: conversation, context: context, budget: budget, availability: availability)
    }

    static func expectedTurn(for state: ChatState) throws -> ProviderTurn {
        try PromptBuilder.turn(conversation: conversation, messages: state.messages, budget: budget).get()
    }
}

extension MessageID {
    static func id(_ value: Int) -> MessageID {
        MessageID(rawValue: value)
    }
}

extension ChatState {
    var assistantMessages: [AssistantMessage] {
        messages.compactMap { if case .assistant(let message) = $0 { message } else { nil } }
    }

    var userMessages: [UserMessage] {
        messages.compactMap { if case .user(let message) = $0 { message } else { nil } }
    }
}
