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
import os.log

/// Demo branch: the catalog's suggestions, with the generic prompts replaced by ones a local model writes for this page
/// when the routing asks for it. Falls back to the catalog whenever the model is slow, fails or writes nothing usable.
struct LocalSuggestedPromptsProvider: ContextualSuggestedPromptsProviding {
    private static let actionSuggestionIDs: Set<String> = ["summarize-page", "translate-page"]
    private static let logger = Logger(subsystem: "com.duckduckgo.mobile.ios", category: "NativeDuckAI")

    private let base: ContextualSuggestedPromptsProviding

    init(base: ContextualSuggestedPromptsProviding = DefaultContextualSuggestedPromptsProvider()) {
        self.base = base
    }

    var maxSuggestedPrompts: Int { base.maxSuggestedPrompts }
    var prioritySuggestionIDs: Set<String> { base.prioritySuggestionIDs }

    func resolveSuggestions(_ input: ResolvePageSuggestionsInput) async -> ResolvedPageSuggestions {
        let resolved = await base.resolveSuggestions(input)
        guard await DuckAINativeSettings.shared.generatesSuggestedPromptsLocally else { return resolved }
        guard input.scope == .page else {
            await LocalSuggestionsDiagnostics.shared.record(outcome: "Skipped: selection scope uses the catalog")
            return resolved
        }
        guard let content = input.pageContent, !content.isEmpty else {
            await LocalSuggestionsDiagnostics.shared.record(outcome: "Skipped: no page content when suggestions resolved")
            return resolved
        }

        let provider = await NativeChatProviderFactory.makeProvider(for: .suggestedPrompts)
        let budget = await DuckAINativeSettings.shared.suggestionsBudgetSeconds
        let generator = SuggestedPromptsGenerator(provider: provider,
                                                  budget: .milliseconds(Int(budget * 1_000)),
                                                  uiLanguageName: ContextualSuggestionsMatcher.languageDisplayName(input.uiLocale))
        let page = PageSnapshot(title: input.pageTitle ?? "", url: input.url.flatMap(URL.init(string:)), content: content, language: nil)
        let run = await generator.run(for: page)
        let details = [
            "Budget \(budget) s after loading",
            "Load \(Self.seconds(run.loadTime)) · first word \(Self.seconds(run.timeToFirstText)) · total \(Self.seconds(run.total))",
            "Page \(content.count) characters"
        ]
        Self.logger.notice("Local suggested prompts: \(String(describing: run.result), privacy: .public) \(details.joined(separator: " | "), privacy: .public)")
        await LocalSuggestionsDiagnostics.shared.record(outcome: Self.outcome(run.result), modelName: provider.descriptor.modelName,
                                                        details: details, raw: run.raw)

        guard case .generated(let prompts, _) = run.result else { return resolved }
        let actions = resolved.suggestions.filter { Self.actionSuggestionIDs.contains($0.id) }
        let local = prompts.enumerated().map { index, prompt in
            ContextualSuggestedPrompt(id: "local-\(index)", label: prompt.text, prompt: prompt.text, icon: nil)
        }
        return ResolvedPageSuggestions(suggestions: actions + local, isSmart: true, pageType: resolved.pageType)
    }

    private static func outcome(_ result: SuggestedPromptsResult) -> String {
        switch result {
        case .generated(let prompts, _): "Generated \(prompts.count) prompts"
        case .timedOut: "Fell back: timed out"
        case .failed(let error): "Fell back: failed (\(error))"
        case .unusable: "Fell back: nothing usable in the reply"
        }
    }

    private static func seconds(_ duration: Duration?) -> String {
        guard let duration else { return "–" }
        return String(format: "%.2f s", Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
    }
}
