//
//  PromptBuilder.swift
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

/// How much input a turn may carry, derived from the provider.
public struct PromptBudget: Equatable, Sendable {
    public let contextWindowTokens: Int
    /// About 3.5 characters per token for the languages we test. Estimation only.
    public let charactersPerToken: Double

    public init(contextWindowTokens: Int, charactersPerToken: Double = 3.5) {
        self.contextWindowTokens = contextWindowTokens
        self.charactersPerToken = charactersPerToken
    }

    public init(_ descriptor: ProviderDescriptor) {
        self.init(contextWindowTokens: descriptor.contextWindowTokens)
    }

    func estimatedTokens(_ text: String) -> Int {
        Int((Double(text.count) / charactersPerToken).rounded(.up))
    }
}

/// Pure: finished messages in, the provider turn for a reply to the last user message out.
public enum PromptBuilder {

    /// - `instructions`: from the first user message's request part. Summarize and translate get task instructions
    ///   (translate names the target language); otherwise a general assistant instruction.
    /// - `input`: the last user message rendered: request lead line, page as "Title: / URL: / Content:", selections
    ///   numbered, pasted text, attachments skipped, then typed text.
    /// - `history`: earlier messages; user messages rendered the same way, assistant messages as their text parts joined
    ///   (reasoning, tools, sources and refusals never re-enter the prompt).
    /// - `maxOutputTokens`: summarize 512; translate min(4096, max(256, sourceCharacters / 3 + 128)); chat 1024.
    /// - Budget: while estimated tokens of instructions + history + input + maxOutputTokens exceed the window, drop the
    ///   oldest exchange after the first user message. The first user message is never dropped: it holds the page.
    ///   If it still does not fit, fail with `.conversationTooLong`.
    /// - `estimatedInputTokens`: estimate of instructions + history + input.
    public static func turn(conversation: ConversationID, messages: [Message], budget: PromptBudget) -> Result<ProviderTurn, ChatError> {
        fatalError("not implemented")
    }
}
