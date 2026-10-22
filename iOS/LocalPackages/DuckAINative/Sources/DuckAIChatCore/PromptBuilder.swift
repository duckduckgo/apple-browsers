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
    ///   numbered, pasted text, then typed text. Image attachments travel separately on each provider message.
    /// - `history`: earlier messages; user messages rendered the same way, assistant messages as their text parts joined
    ///   (reasoning, tools, sources and refusals never re-enter the prompt).
    /// - `maxOutputTokens`: summarize 512; translate min(4096, max(256, sourceCharacters / 3 + 128)); chat 1024.
    /// - Budget: while estimated tokens of instructions + history + input + maxOutputTokens exceed the window, drop the
    ///   oldest exchange after the first user message. The first user message is never dropped: it holds the page.
    ///   If it still does not fit, fail with `.conversationTooLong`.
    /// - `estimatedInputTokens`: estimate of instructions + history + input.
    public static func turn(conversation: ConversationID, messages: [Message], budget: PromptBudget) -> Result<ProviderTurn, ChatError> {
        guard let firstUser = messages.first(where: { if case .user = $0 { true } else { false } }),
              case .user(let first) = firstUser,
              let lastIndex = messages.lastIndex(where: { if case .user = $0 { true } else { false } }),
              case .user(let last) = messages[lastIndex] else { return .failure(.conversationTooLong) }
        let request = first.parts.compactMap { part -> ChatRequest? in
            if case .context(.request(let request)) = part { request } else { nil }
        }.first
        let instructions: String
        let maxOutputTokens: Int
        switch request {
        case .summarize:
            instructions = "Summarize the provided content clearly and concisely."
            maxOutputTokens = 512
        case .translate(let language):
            instructions = "Translate the provided content into \(language.name)."
            let sourceCharacters = first.parts.reduce(0) { $0 + sourceLength($1) }
            maxOutputTokens = min(4_096, max(256, sourceCharacters / 3 + 128))
        case nil:
            instructions = "You are a helpful assistant."
            maxOutputTokens = 1_024
        }

        let input = renderedUser(last)
        var history = messages[..<lastIndex].map { message -> ProviderMessage in
            switch message {
            case .user(let user):
                ProviderMessage(role: .user, text: renderedUser(user), attachments: user.attachments)
            case .assistant(let assistant):
                ProviderMessage(role: .assistant, text: assistant.parts.compactMap { part in
                    if case .text(let text) = part { text } else { nil }
                }.joined())
            }
        }
        var estimatedInputTokens = budget.estimatedTokens(instructions + history.map(\.text).joined() + input) + (history.flatMap(\.attachments).count + last.attachments.count) * 1_024
        while estimatedInputTokens + maxOutputTokens > budget.contextWindowTokens {
            guard let start = history.indices.dropFirst().first(where: { history[$0].role == .user }) else {
                return .failure(.conversationTooLong)
            }
            let end = history.indices.dropFirst(start + 1).first(where: { history[$0].role == .user }) ?? history.endIndex
            history.removeSubrange(start..<end)
            estimatedInputTokens = budget.estimatedTokens(instructions + history.map(\.text).joined() + input) + (history.flatMap(\.attachments).count + last.attachments.count) * 1_024
        }
        return .success(ProviderTurn(conversation: conversation, instructions: instructions, history: history,
                                     input: input, maxOutputTokens: maxOutputTokens, estimatedInputTokens: estimatedInputTokens, attachments: last.attachments))
    }
}

private func sourceLength(_ part: UserPart) -> Int {
    switch part {
    case .context(.page(let page)): page.content.count
    case .context(.selection(let selection)): selection.content.count
    case .context(.pastedText(let text)): text.count
    default: 0
    }
}

private func renderedSource(title: String, url: URL?, content: String) -> String {
    var lines = ["Title: \(title)"]
    if let url { lines.append("URL: \(url.absoluteString)") }
    lines.append("Content: \(content)")
    return lines.joined(separator: "\n")
}

private func renderedUser(_ message: UserMessage) -> String {
    var requests: [String] = []
    var pages: [String] = []
    var selections: [String] = []
    var pasted: [String] = []
    var texts: [String] = []
    for part in message.parts {
        switch part {
        case .context(.request(.summarize)):
            requests.append("Summarize the following content.")
        case .context(.request(.translate(let language))):
            requests.append("Translate the following content into \(language.name).")
        case .context(.page(let page)):
            pages.append(renderedSource(title: page.title, url: page.url, content: page.content))
        case .context(.selection(let selection)):
            selections.append("Selection \(selections.count + 1):\n" + renderedSource(title: selection.title, url: selection.url, content: selection.content))
        case .context(.pastedText(let text)):
            pasted.append(text)
        case .text(let text):
            texts.append(text)
        case .attachment:
            break
        }
    }
    return (requests + pages + selections + pasted + texts).joined(separator: "\n\n")
}
