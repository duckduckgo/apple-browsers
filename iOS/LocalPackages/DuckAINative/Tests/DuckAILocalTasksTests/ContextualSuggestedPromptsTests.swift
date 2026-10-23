//
//  ContextualSuggestedPromptsTests.swift
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
import DuckAIChatProviders
import DuckAILocalTasks
import Foundation
import Testing

@Suite struct ContextualSuggestedPromptsTests {
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func pageSpecificQuestionsSurviveDisplayLengthLimits() async {
        let question = "How do solar panels compare with wind turbines for this region?"
        let provider = StubProvider(configuration: .init(reply: question, wordsPerSecond: 10_000, loadTime: .zero, readTime: .zero))
        let page = PageSnapshot(title: "Solar and wind energy", url: nil, content: "", language: "en")
        let run = await SuggestedPromptsGenerator(provider: provider, uiLanguageName: "English").run(for: page)
        #expect(run.result == .generated([SuggestedPrompt(question)], stats: run.stats))
        #expect(SuggestedPromptsPrompt.parse(question, max: 3).first?.text == question)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func displayLabelKeepsWholeWordsAndFullPrompt() {
        let text = "Compare solar panels with wind turbines for electricity generation"
        let prompt = SuggestedPrompt(text)
        #expect(prompt.displayLabel == "Compare solar panels with wind turbines…")
        #expect(prompt.text == text)
        #expect(SuggestedPrompt("What are the main risks to ducks?").displayLabel == "What are the main risks to…")
        #expect(SuggestedPrompt("Compare international renewable energy technologies").displayLabel == "Compare international renewable energy…")
        #expect(SuggestedPrompt("Compare solar and wind energy").displayLabel == "Compare solar and wind energy")
        let unbroken = SuggestedPrompt(String(repeating: "界", count: 70))
        #expect(unbroken.displayLabel == String(repeating: "界", count: 44) + "…")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func parserRejectsExcessiveOutputWithoutTruncatingItIntoAQuestion() {
        let question = "How do solar panels compare with wind turbines?"
        let raw = String(repeating: "x", count: 301) + "\n" + question + "\n" + question.uppercased()
        #expect(SuggestedPromptsPrompt.parse(raw, max: 3) == [SuggestedPrompt(question)])
        #expect(SuggestedPromptsPrompt.parse(String(repeating: "x", count: 300), max: 3).count == 1)
    }

    @MainActor
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func failedAndUnusableRunsCanRegenerateForTheSameDocument() async {
        let key = SuggestionsKey(document: UUID(), url: URL(string: "https://example.com")!,
                                 variant: SuggestionsVariant(modelID: "stub", locale: "en"))
        let question = SuggestedPrompt("How do solar panels compare with wind turbines for this region?")
        let failures: [SuggestedPromptsResult] = [.failed(.modelNotDownloaded), .unusable(raw: "Sure:")]
        for failure in failures {
            let cache = CurrentDocumentSuggestions()
            cache.start(key: key) { _ in SuggestedPromptsRun(result: failure, raw: "", total: .zero) }
            _ = await cache.resolve { _ in Issue.record("Failure must not publish suggestions") }
            cache.start(key: key) { _ in
                SuggestedPromptsRun(result: .generated([question], stats: nil), raw: question.text, total: .zero)
            }
            let retry = await cache.resolve { #expect($0 == [question]) }
            #expect(retry?.result == .generated([question], stats: nil))
            #expect(cache.prompts == [question])
        }
    }
}
