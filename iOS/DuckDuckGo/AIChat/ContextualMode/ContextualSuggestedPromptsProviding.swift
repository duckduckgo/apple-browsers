//
//  ContextualSuggestedPromptsProviding.swift
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

struct ResolvePageSuggestionsInput {
    let pageTypeSignals: AIChatPageTypeSignals?
    let url: String?
    let uiLocale: String
}

protocol ContextualSuggestedPromptsProviding {
    func resolveSuggestions(_ input: ResolvePageSuggestionsInput) async -> [ContextualSuggestedPrompt]
}

struct StubContextualSuggestedPromptsProvider: ContextualSuggestedPromptsProviding {
    func resolveSuggestions(_ input: ResolvePageSuggestionsInput) async -> [ContextualSuggestedPrompt] {
        Self.cannedSuggestions
    }

    private static let cannedSuggestions: [ContextualSuggestedPrompt] = [
        ContextualSuggestedPrompt(id: "summarize-page", label: "Summarize this page", prompt: "Summarize this page.", icon: "summary"),
        ContextualSuggestedPrompt(id: "translate-page", label: "Translate this page", prompt: "Translate this page.", icon: "translate"),
        ContextualSuggestedPrompt(id: "key-takeaways", label: "Key takeaways", prompt: "What are the key takeaways from this page?", icon: "note"),
    ]
}
