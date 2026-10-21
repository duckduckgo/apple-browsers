//
//  SuggestedPromptsTests.swift
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

@Suite struct SuggestedPromptsTests {

    private let page = PageSnapshot(title: "Duck", url: URL(string: "https://en.wikipedia.org/wiki/Duck"),
                                    content: String(repeating: "Ducks are waterfowl. ", count: 400), language: "en")

    private func stub(_ reply: String, wordsPerSecond: Double = 10_000, failure: ChatError? = nil) -> StubProvider {
        StubProvider(configuration: .init(reply: reply, wordsPerSecond: wordsPerSecond, loadTime: .zero, readTime: .zero, failure: failure))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func parseStripsListMarkersAndDropsNoise() {
        let raw = """
        Here are some questions:
        1. What do ducks eat?
        2) How long do ducks live?
        - "Why are duck feathers waterproof?"
        • What do ducks eat?
        Ok
        * Which ducks migrate the furthest, and how do they navigate across oceans and continents every single year?
        """

        #expect(SuggestedPromptsPrompt.parse(raw, max: 4) == [
            SuggestedPrompt("What do ducks eat?"),
            SuggestedPrompt("How long do ducks live?"),
            SuggestedPrompt("Why are duck feathers waterproof?")
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func parseStopsAtMax() {
        #expect(SuggestedPromptsPrompt.parse("Question one here\nQuestion two here\nQuestion three here", max: 2).count == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func turnReadsATrimmedPageAndAsksForTheCountInTheUILanguage() {
        let turn = SuggestedPromptsPrompt.turn(for: page, count: 4, uiLanguageName: "German")

        #expect(turn.input.contains("Duck"))
        #expect(turn.input.contains("https://en.wikipedia.org/wiki/Duck"))
        #expect(turn.input.count < SuggestedPromptsPrompt.contentCharacterLimit + 300)
        #expect(turn.instructions.contains("4"))
        #expect(turn.instructions.contains("German"))
        #expect(turn.history.isEmpty)
        #expect(turn.maxOutputTokens == 160)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func generatesParsedSuggestions() async {
        let generator = SuggestedPromptsGenerator(provider: stub("What do ducks eat?\nHow long do ducks live?\n"),
                                                  uiLanguageName: "English")

        guard case .generated(let suggestions, _) = await generator.suggestions(for: page) else {
            Issue.record("expected suggestions")
            return
        }
        #expect(suggestions == [SuggestedPrompt("What do ducks eat?"), SuggestedPrompt("How long do ducks live?")])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func returnsAsSoonAsEnoughSuggestionsHaveArrived() async {
        let lines = "What do ducks eat?\nHow long do ducks live?\nWhy do ducks quack?\nWhere do ducks nest?\n"
        let rambling = lines + String(repeating: "and then some more text ", count: 100)
        let generator = SuggestedPromptsGenerator(provider: stub(rambling, wordsPerSecond: 40),
                                                  budget: .seconds(20), uiLanguageName: "English")
        let started = ContinuousClock.now

        let result = await generator.suggestions(for: page)

        guard case .generated(let suggestions, _) = result else {
            Issue.record("expected suggestions, got \(result)")
            return
        }
        #expect(suggestions.map(\.text) == ["What do ducks eat?", "How long do ducks live?", "Why do ducks quack?", "Where do ducks nest?"])
        #expect(started.duration(to: .now) < .seconds(3))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func modelLoadingDoesNotCountAgainstTheBudget() async {
        let provider = StubProvider(configuration: .init(reply: "What do ducks eat?\nHow long do ducks live?\n", wordsPerSecond: 200,
                                                         loadTime: .milliseconds(600), readTime: .zero))
        let generator = SuggestedPromptsGenerator(provider: provider, budget: .milliseconds(300), uiLanguageName: "English")

        guard case .generated = await generator.suggestions(for: page) else {
            Issue.record("a slow load must not use up the budget")
            return
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func aModelThatNeverStartsReadingTimesOutAfterTheLoadBudget() async {
        let provider = StubProvider(configuration: .init(reply: "What do ducks eat?\n", loadTime: .seconds(30)))
        let generator = SuggestedPromptsGenerator(provider: provider, budget: .milliseconds(100), loadBudget: .milliseconds(200),
                                                  uiLanguageName: "English")
        let started = ContinuousClock.now

        #expect(await generator.suggestions(for: page) == .timedOut)
        #expect(started.duration(to: .now) < .seconds(2))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func aRunReportsWhatTheModelWroteAndWhenEvenOnATimeout() async {
        let provider = StubProvider(configuration: .init(reply: "What do ducks eat " + String(repeating: "and more ", count: 100),
                                                         wordsPerSecond: 20, loadTime: .milliseconds(200), readTime: .zero))
        let generator = SuggestedPromptsGenerator(provider: provider, budget: .milliseconds(400), uiLanguageName: "English")

        let run = await generator.run(for: page)

        #expect(run.result == .timedOut)
        #expect(run.raw.hasPrefix("What do ducks"))
        #expect((run.loadTime ?? .zero) >= .milliseconds(150))
        #expect(run.timeToFirstText != nil)
        #expect(run.total >= run.loadTime ?? .zero)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func parseStripsMarkdownEmphasis() {
        #expect(SuggestedPromptsPrompt.parse("1. **What do ducks eat?**\n- *How long do ducks live?*\n`Why do ducks quack?`", max: 4) == [
            SuggestedPrompt("What do ducks eat?"),
            SuggestedPrompt("How long do ducks live?"),
            SuggestedPrompt("Why do ducks quack?")
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func aSlowModelTimesOutWithinTheBudget() async {
        let generator = SuggestedPromptsGenerator(provider: stub(String(repeating: "word ", count: 200), wordsPerSecond: 5),
                                                  budget: .milliseconds(150), uiLanguageName: "English")
        let started = ContinuousClock.now

        let result = await generator.suggestions(for: page)

        #expect(result == .timedOut)
        #expect(started.duration(to: .now) < .seconds(1))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func providerErrorsAreReported() async {
        let generator = SuggestedPromptsGenerator(provider: stub("a b c d", failure: .modelNotDownloaded), uiLanguageName: "English")

        #expect(await generator.suggestions(for: page) == .failed(.modelNotDownloaded))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func unparseableOutputIsUnusable() async {
        let generator = SuggestedPromptsGenerator(provider: stub("Sure:"), uiLanguageName: "English")

        #expect(await generator.suggestions(for: page) == .unusable(raw: "Sure:"))
    }
}
