//
//  PromptBuilderTests.swift
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
import Testing
@testable import DuckAIChatCore

@Suite struct PromptBuilderTests {

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func summarizeRendersThePageAndCapsTheReply() throws {
        let messages: [Message] = [.user(UserMessage(id: .id(1), createdAt: Fixture.time(0),
                                                     parts: [.context(.request(.summarize)), .context(.page(Fixture.page))]))]

        let turn = try PromptBuilder.turn(conversation: Fixture.conversation, messages: messages, budget: Fixture.budget).get()

        #expect(turn.conversation == Fixture.conversation)
        #expect(turn.instructions.localizedCaseInsensitiveContains("summar"))
        #expect(turn.input.contains("Ducks"))
        #expect(turn.input.contains("https://example.com/ducks"))
        #expect(turn.input.contains("Ducks are waterfowl."))
        #expect(turn.history.isEmpty)
        #expect(turn.maxOutputTokens == 512)
        #expect(turn.estimatedInputTokens > 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func translateNamesTheTargetLanguageAndScalesTheReply() throws {
        let source = String(repeating: "a", count: 3_000)
        let selection = Selection(title: "Ducks", url: nil, content: source)
        let messages: [Message] = [.user(UserMessage(id: .id(1), createdAt: Fixture.time(0),
                                                     parts: [.context(.request(.translate(into: Fixture.german))), .context(.selection(selection))]))]

        let turn = try PromptBuilder.turn(conversation: Fixture.conversation, messages: messages, budget: Fixture.budget).get()

        #expect(turn.instructions.contains("German") || turn.input.contains("German"))
        #expect(turn.input.contains(source))
        #expect(turn.maxOutputTokens == 3_000 / 3 + 128)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func followUpSendsEarlierMessagesAsHistoryWithoutReasoning() throws {
        let messages: [Message] = [
            .user(UserMessage(id: .id(1), createdAt: Fixture.time(0), parts: [.context(.page(Fixture.page)), .text("Hi")])),
            .assistant(AssistantMessage(id: .id(2), createdAt: Fixture.time(1),
                                        parts: [.reasoning(Reasoning(text: "secret", timing: .done(.seconds(1)))), .text("Hello")],
                                        ending: .completed(nil))),
            .user(UserMessage(id: .id(3), createdAt: Fixture.time(2), parts: [.text("Tell me more")]))
        ]

        let turn = try PromptBuilder.turn(conversation: Fixture.conversation, messages: messages, budget: Fixture.budget).get()

        #expect(turn.history.map(\.role) == [.user, .assistant])
        #expect(turn.history[0].text.contains("Ducks are waterfowl."))
        #expect(turn.history[0].text.contains("Hi"))
        #expect(turn.history[1].text == "Hello")
        #expect(turn.input == "Tell me more")
        #expect(turn.maxOutputTokens == 1_024)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func overBudgetDropsTheOldestMiddleExchangeButKeepsTheFirst() throws {
        let long = String(repeating: "x", count: 7_000)
        let messages: [Message] = [
            .user(UserMessage(id: .id(1), createdAt: Fixture.time(0), parts: [.context(.page(Fixture.page)), .text("First")])),
            .assistant(AssistantMessage(id: .id(2), createdAt: Fixture.time(1), parts: [.text("A1")], ending: .completed(nil))),
            .user(UserMessage(id: .id(3), createdAt: Fixture.time(2), parts: [.text(long)])),
            .assistant(AssistantMessage(id: .id(4), createdAt: Fixture.time(3), parts: [.text(long)], ending: .completed(nil))),
            .user(UserMessage(id: .id(5), createdAt: Fixture.time(4), parts: [.text("Last")]))
        ]
        let budget = PromptBudget(contextWindowTokens: 3_000)

        let turn = try PromptBuilder.turn(conversation: Fixture.conversation, messages: messages, budget: budget).get()

        #expect(turn.history.first?.text.contains("First") == true)
        #expect(!turn.history.contains { $0.text == long })
        #expect(turn.input == "Last")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func inputThatCannotFitIsConversationTooLong() {
        let messages: [Message] = [
            .user(UserMessage(id: .id(1), createdAt: Fixture.time(0), parts: [.text(String(repeating: "x", count: 20_000))]))
        ]

        let result = PromptBuilder.turn(conversation: Fixture.conversation, messages: messages, budget: PromptBudget(contextWindowTokens: 1_000))

        #expect(result == .failure(.conversationTooLong))
    }
}
