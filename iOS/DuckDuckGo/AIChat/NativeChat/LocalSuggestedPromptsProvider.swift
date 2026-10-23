//
//  LocalSuggestedPromptsProvider.swift
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

import DuckAILocalTasks
import Foundation

struct LocalSuggestedPromptsProvider: ContextualSuggestedPromptsProviding {
    private let base: ContextualSuggestedPromptsProviding
    private let local: TabLocalSuggestions?

    init(base: ContextualSuggestedPromptsProviding = DefaultContextualSuggestedPromptsProvider(), local: TabLocalSuggestions? = nil) {
        self.base = base
        self.local = local
    }

    var maxSuggestedPrompts: Int { base.maxSuggestedPrompts }
    var prioritySuggestionIDs: Set<String> { base.prioritySuggestionIDs }

    @MainActor
    func requiresPageContext(for scope: ResolvePageSuggestionsInput.Scope) -> Bool {
        scope != .page || local == nil || !DuckAINativeSettings.shared.generatesSuggestedPromptsLocally
    }

    func resolveSuggestions(_ input: ResolvePageSuggestionsInput) async -> ResolvedPageSuggestions {
        await resolveSuggestions(input, onUpdate: { _ in })
    }

    @MainActor
    func resolveSuggestions(_ input: ResolvePageSuggestionsInput,
                            onUpdate: @escaping @MainActor (ResolvedPageSuggestions) -> Void) async -> ResolvedPageSuggestions {
        guard DuckAINativeSettings.shared.generatesSuggestedPromptsLocally, input.scope == .page else {
            return await base.resolveSuggestions(input)
        }
        guard let local, let run = await local.resolve(input, onUpdate: { _ in }),
              !Task.isCancelled, case .generated(let prompts, _) = run.result, !prompts.isEmpty else {
            return ResolvedPageSuggestions(suggestions: [ContextualSuggestedPrompt(id: "local-retry", label: "Retry suggestions", prompt: "", icon: nil)], isSmart: true, pageType: .none)
        }
        return Self.generated(prompts)

    }

    @MainActor
    func cachedSuggestions(scope: ResolvePageSuggestionsInput.Scope, locale: String) -> ResolvedPageSuggestions? {
        guard scope == .page, let cached = local?.cachedPrompts(locale: locale) else { return nil }
        return Self.generated(cached.prompts)
    }

    @MainActor
    func cancelPendingSuggestions() {
        local?.cancelGeneration()
    }

    private static func generated(_ prompts: [SuggestedPrompt]) -> ResolvedPageSuggestions {
        let suggestions = prompts.enumerated().map { index, prompt in
            ContextualSuggestedPrompt(id: "local-\(index)", label: prompt.text, prompt: prompt.text, icon: nil)
        }
        return ResolvedPageSuggestions(suggestions: suggestions, isSmart: true, pageType: .none)
    }
}
