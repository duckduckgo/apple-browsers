//
//  SuggestedPrompts.swift
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

import DuckAIChatCore
import Foundation

/// What the suggested-prompts model sees of a page. The app caps `content`; `turn` trims it further.
public struct PageSnapshot: Equatable, Sendable {
    public let title: String
    public let url: URL?
    public let content: String
    /// BCP 47 code of the page language when known, e.g. "de". Suggestions are written in the UI language regardless.
    public let language: String?

    public init(title: String, url: URL?, content: String, language: String?) {
        self.title = title
        self.url = url
        self.content = content
        self.language = language
    }
}

public struct SuggestedPrompt: Hashable, Sendable {
    public let text: String

    public init(_ text: String) {
        self.text = text
    }
}

public enum SuggestedPromptsResult: Equatable, Sendable {
    case generated([SuggestedPrompt], stats: GenerationStats?)
    /// The budget ran out first. The caller shows its static suggestions.
    case timedOut
    case failed(ChatError)
    /// The model answered but nothing in it parsed as a usable suggestion.
    case unusable(raw: String)
}

/// One-shot suggested prompts for the contextual sheet, from any `ChatProvider`.
public struct SuggestedPromptsGenerator: Sendable {
    public static let defaultBudget: Duration = .milliseconds(1_500)

    private let provider: any ChatProvider
    private let budget: Duration
    private let maxSuggestions: Int
    private let uiLanguageName: String

    /// `uiLanguageName` is the language suggestions are written in, e.g. "English".
    public init(provider: any ChatProvider,
                budget: Duration = SuggestedPromptsGenerator.defaultBudget,
                maxSuggestions: Int = 4,
                uiLanguageName: String) {
        self.provider = provider
        self.budget = budget
        self.maxSuggestions = maxSuggestions
        self.uiLanguageName = uiLanguageName
    }

    /// Streams one reply and parses it. When `budget` elapses first, raises the reply's `StopSignal` and returns
    /// `.timedOut` at once; the provider drains on its own (Core's stop contract). Never throws.
    public func suggestions(for page: PageSnapshot) async -> SuggestedPromptsResult {
        fatalError("not implemented")
    }
}

/// The prompt and the parser, pure so they can be tested and evaluated without a model.
public enum SuggestedPromptsPrompt {
    /// Page content beyond this is dropped: suggestions need the gist, and a short read keeps the first token fast.
    public static let contentCharacterLimit = 2_000

    /// Instructions ask for exactly `count` short questions or requests a reader of this page might ask an assistant,
    /// one per line, no numbering, written in `uiLanguageName`. The input is "Title:", "URL:" (when known) and the first
    /// `contentCharacterLimit` characters of content. `maxOutputTokens` is 160. `history` is empty.
    public static func turn(for page: PageSnapshot, count: Int, uiLanguageName: String,
                            conversation: ConversationID = ConversationID()) -> ProviderTurn {
        fatalError("not implemented")
    }

    /// Lenient: one suggestion per non-empty line. Strips bullets ("-", "*", "•"), numbering ("1.", "1)"), surrounding
    /// quotes and whitespace. Drops lines that are headings or preambles (ending in ":"), shorter than 8 or longer than
    /// 80 characters, and case-insensitive duplicates. Keeps order and returns at most `max`.
    public static func parse(_ raw: String, max: Int) -> [SuggestedPrompt] {
        fatalError("not implemented")
    }
}
