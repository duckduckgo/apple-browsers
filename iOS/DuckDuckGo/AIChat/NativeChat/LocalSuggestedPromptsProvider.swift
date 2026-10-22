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

    func resolveSuggestions(_ input: ResolvePageSuggestionsInput) async -> ResolvedPageSuggestions {
        await resolveSuggestions(input, onUpdate: { _ in })
    }

    @MainActor
    func resolveSuggestions(_ input: ResolvePageSuggestionsInput,
                            onUpdate: @escaping @MainActor (ResolvedPageSuggestions) -> Void) async -> ResolvedPageSuggestions {
        let resolved = await base.resolveSuggestions(input)
        guard DuckAINativeSettings.shared.generatesSuggestedPromptsLocally, input.scope == .page, let local else { return resolved }
        onUpdate(resolved)
        let run = await local.resolve(input) { prompts in
            onUpdate(Self.merging(prompts, into: resolved))
        }
        guard !Task.isCancelled, case .generated(let prompts, _) = run?.result else { return resolved }
        return Self.merging(prompts, into: resolved)
    }

    @MainActor
    func cachedSuggestions(scope: ResolvePageSuggestionsInput.Scope, locale: String) -> ResolvedPageSuggestions? {
        guard scope == .page, let cached = local?.cachedPrompts(locale: locale), let catalog = SuggestionCatalog.bundled else { return nil }
        let input = ResolvePageSuggestionsInput(pageTypeSignals: nil, url: cached.url.absoluteString, uiLocale: locale)
        return Self.merging(cached.prompts, into: ContextualSuggestionsMatcher.resolve(input, catalog: catalog))
    }

    @MainActor
    func cancelPendingSuggestions() {
        local?.cancelGeneration()
    }

    private static func merging(_ prompts: [SuggestedPrompt], into resolved: ResolvedPageSuggestions) -> ResolvedPageSuggestions {
        let actions = resolved.suggestions.filter { ["summarize-page", "translate-page"].contains($0.id) }
        let local = prompts.enumerated().map { index, prompt in
            ContextualSuggestedPrompt(id: "local-\(index)", label: prompt.text, prompt: prompt.text, icon: nil)
        }
        return ResolvedPageSuggestions(suggestions: actions + local, isSmart: true, pageType: resolved.pageType)
    }
}
