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

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func openTabsKeepCompleteRowsWhenProviderStalls() async {
        let tabs = [OpenTabMetadata(id: "0", title: "Ducks", host: "example.com")]
        let provider = StallingTabProvider("0 | Duck food | What do ducks eat?\n9 | Unknown | What is this source?\n0 | Partial | Why do ducks")
        let run = await OpenTabSuggestions.run(tabs: tabs, locale: "en", provider: provider, budget: .milliseconds(100))
        #expect(run.outcome == .timedOut)
        #expect(run.suggestions.map(\.prompt) == ["What do ducks eat?"])
        #expect(run.raw.contains("Why do ducks"))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func openTabsStopAfterThreeCompleteValidRows() async {
        let tabs = [OpenTabMetadata(id: "0", title: "Ducks", host: "example.com")]
        let provider = StallingTabProvider("0 | Duck food | What do ducks eat?\n0 | Duck homes | Where do ducks live?\n0 | Duck flight | How do ducks fly?\n")
        let started = ContinuousClock.now
        let run = await OpenTabSuggestions.run(tabs: tabs, locale: "en", provider: provider)
        #expect(run.outcome == .generated)
        #expect(run.suggestions.count == 3)
        #expect(started.duration(to: .now) < .seconds(2))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func openTabsUseBoundedMetadataAndRejectUnknownDuplicateSources() async {
        let tabs = (0..<9).map { OpenTabMetadata(id: String($0), title: String(repeating: "t", count: 200), host: "example.com") }
        let turn = OpenTabSuggestions.turn(tabs: tabs, locale: "en")
        #expect(!turn.input.contains("6 |"))
        #expect(!turn.input.contains(String(repeating: "t", count: 101)))
        #expect(!turn.input.contains("https://"))
        #expect(turn.instructions.contains("most recently viewed to least recently viewed"))
        #expect(turn.instructions.contains("first tab"))
        let raw = """
        9 | Unknown source | Explain this unknown source.
        0,0 | Repeated source | Explain these repeated sources.
        0,1 | Compare these tabs | Compare the topics of these two tabs.
        1 | Duplicate question | Compare the topics of these two tabs.
        2 | Explain this tab | Explain the main topic of this tab.
        """
        let parsed = OpenTabSuggestions.parse(raw, tabs: tabs)
        #expect(parsed.map(\.sourceIDs) == [["0", "1"], ["2"]])
        let generated = await OpenTabSuggestions.run(tabs: tabs, locale: "en", provider: stub(raw))
        #expect(generated.suggestions == parsed)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func openTabRequestIncludesBoundedRecentSearchAlongsideResultPage() {
        let tab = OpenTabMetadata(id: "0", title: "A shoe review", host: "example.com",
                                  recentSearchQuery: "walking shoes " + String(repeating: "x", count: 200))
        let turn = OpenTabSuggestions.turn(tabs: [tab], locale: "en")
        #expect(tab.recentSearchQuery?.count == 100)
        #expect(turn.input.contains("0 | A shoe review | example.com | Recent search: walking shoes"))
        #expect(!turn.input.contains(String(repeating: "x", count: 101)))
        #expect(turn.instructions.contains("relevant follow-up to that search"))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func openTabsDistinguishRefusalFailureAndUnusableOutput() async {
        let tabs = [OpenTabMetadata(id: "0", title: "Ducks", host: "example.com")]
        let failed = await OpenTabSuggestions.run(tabs: tabs, locale: "en", provider: StallingTabProvider("", failure: .network))
        #expect(failed.outcome == .failed(.network))
        #expect(failed.suggestions.isEmpty)
        let refused = await OpenTabSuggestions.run(tabs: tabs, locale: "en", provider: StallingTabProvider(
            "0 | Duck food | What do ducks eat?\n", refusal: true))
        #expect(refused.outcome == .refused)
        #expect(refused.suggestions.isEmpty)
        let unusable = await OpenTabSuggestions.run(tabs: tabs, locale: "en", provider: stub("9 | Unknown | What is this source?"))
        #expect(unusable.outcome == .unusable)
        #expect(unusable.suggestions.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func cancelledOpenTabsDiscardCompletedRowsAndReturnPromptly() async {
        let tabs = [OpenTabMetadata(id: "0", title: "Ducks", host: "example.com")]
        let provider = StallingTabProvider("0 | Duck food | What do ducks eat?\n")
        let task = Task { await OpenTabSuggestions.run(tabs: tabs, locale: "en", provider: provider) }
        var iterator = provider.started.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        let run = await task.value
        #expect(run.outcome == .cancelled)
        #expect(run.suggestions.isEmpty)
        #expect(run.total < .seconds(2))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func openTabsAcceptTrailingRowOnlyAfterNormalCompletion() async {
        let tabs = [OpenTabMetadata(id: "0", title: "Ducks", host: "example.com")]
        let run = await OpenTabSuggestions.run(tabs: tabs, locale: "en", provider: stub("0 | Duck food | What do ducks eat?"))
        #expect(run.outcome == .generated)
        #expect(run.suggestions.map(\.prompt) == ["What do ducks eat?"])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func openTabsShowTheGeneratedQuestionInsteadOfAnEchoedTitle() {
        let tabs = [OpenTabMetadata(id: "0", title: "Walking shoes", host: "example.com")]
        let parsed = OpenTabSuggestions.parse("0 | Walking shoes | Which shoes suit long walks?", tabs: tabs)
        #expect(parsed.first?.label == "Which shoes suit long walks?")
        #expect(OpenTabSuggestions.parse("0 | Walking shoes | walking shoes", tabs: tabs).isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func openTabsAllowModelLoadingBeforeTheGenerationBudget() async {
        let tabs = [OpenTabMetadata(id: "0", title: "Ducks", host: "example.com")]
        let provider = StubProvider(configuration: .init(reply: "0 | Duck food | What do ducks eat?",
                                                        wordsPerSecond: 10_000, loadTime: .milliseconds(200), readTime: .zero))
        for _ in 0..<2 {
            let run = await OpenTabSuggestions.run(tabs: tabs, locale: "en", provider: provider, budget: .milliseconds(100))
            #expect(run.outcome == .generated)
            #expect(run.suggestions.first?.prompt == "What do ducks eat?")
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func openTabsBoundWaitingForAProviderThatNeverStarts() async {
        let tabs = [OpenTabMetadata(id: "0", title: "Ducks", host: "example.com")]
        let run = await OpenTabSuggestions.run(tabs: tabs, locale: "en", provider: StallingTabProvider("", emitsText: false),
                                              budget: .seconds(10), loadBudget: .milliseconds(50))
        #expect(run.outcome == .timedOut)
        #expect(run.suggestions.isEmpty)
        #expect(run.total < .seconds(2))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func openTabsBoundReadingInputAfterLoading() async {
        let tabs = [OpenTabMetadata(id: "0", title: "Ducks", host: "example.com")]
        let provider = StallingTabProvider("", emitsText: false, emitsReading: true)
        let run = await OpenTabSuggestions.run(tabs: tabs, locale: "en", provider: provider,
                                              budget: .milliseconds(50), loadBudget: .seconds(10))
        #expect(run.outcome == .timedOut)
        #expect(run.suggestions.isEmpty)
        #expect(run.total < .seconds(2))
    }

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
        #expect(turn.input.contains("en.wikipedia.org"))
        #expect(turn.input.count < SuggestedPromptsPrompt.contentCharacterLimit + 300)
        #expect(turn.instructions.contains("4"))
        #expect(turn.instructions.contains("German"))
        #expect(turn.history.isEmpty)
        #expect(turn.instructions.contains("at most 8 words"))
        #expect(turn.maxOutputTokens == 80)
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
                                                  budget: .seconds(20), maxSuggestions: 4, uiLanguageName: "English")
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
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func inputVariantsBoundAllPageFieldsAndHideURLSecrets() {
        let page = PageSnapshot(title: String(repeating: "t", count: 2_000),
                                url: URL(string: "https://example.com/private?secret=123#token"),
                                content: String(repeating: "b", count: 8_000), language: nil,
                                description: String(repeating: "d", count: 2_000),
                                headings: Array(repeating: String(repeating: "h", count: 1_000), count: 100))
        for variant in SuggestionsVariant.Input.allCases {
            let input = SuggestedPromptsPrompt.boundedInput(for: page, variant: variant)
            #expect(!input.contains("secret"))
            #expect(!input.contains("private"))
            #expect(input.count < (variant == .body ? 1_400 : 500))
            #expect(input.contains("Content:") == (variant == .body))
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func updatesContainOnlyCompleteUniqueLinesAndTimeoutPreservesThem() async {
        let updates = PromptUpdates()
        let generator = SuggestedPromptsGenerator(
            provider: stub("What do ducks eat?\nWhat do ducks eat?\n" + String(repeating: "unfinished ", count: 100), wordsPerSecond: 80),
            budget: .milliseconds(500), uiLanguageName: "English")
        let run = await generator.run(for: page) { await updates.append($0) }
        #expect(await updates.values == [[SuggestedPrompt("What do ducks eat?")]])
        guard case .generated(let prompts, _) = run.result else { Issue.record("Expected partial result"); return }
        #expect(prompts == [SuggestedPrompt("What do ducks eat?")])
    }

    @MainActor
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func failedSameDocumentCanRetryAndPublishesOnlyTheFinalSet() async {
        let cache = CurrentDocumentSuggestions()
        let key = SuggestionsKey(document: UUID(), url: URL(string: "https://example.com")!,
                                 variant: SuggestionsVariant(modelID: "stub", locale: "en"))
        cache.start(key: key) { _ in SuggestedPromptsRun(result: .timedOut, raw: "", total: .zero) }
        _ = await cache.resolve { _ in Issue.record("Failure must not publish chips") }
        cache.start(key: key) { update in
            await update([SuggestedPrompt("Temporary partial question")])
            return SuggestedPromptsRun(result: .generated([SuggestedPrompt("Complete final question")], stats: nil), raw: "", total: .zero)
        }
        var updates: [[SuggestedPrompt]] = []
        _ = await cache.resolve { updates.append($0) }
        #expect(updates == [[SuggestedPrompt("Complete final question")]])
    }

    @MainActor
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func replacedDocumentRejectsLateCallbacksAndReusesMatchingRequest() async {
        let cache = CurrentDocumentSuggestions()
        let variant = SuggestionsVariant(modelID: "stub", locale: "en")
        let first = SuggestionsKey(document: UUID(), url: URL(string: "https://example.com")!, variant: variant)
        let second = SuggestionsKey(document: UUID(), url: first.url, variant: variant)
        cache.start(key: first) { update in
            try? await Task.sleep(for: .seconds(1))
            await update([SuggestedPrompt("Old document question")])
            return SuggestedPromptsRun(result: .generated([SuggestedPrompt("Old document question")], stats: nil), raw: "", total: .zero)
        }
        cache.start(key: second) { update in
            await update([SuggestedPrompt("New document question")])
            return SuggestedPromptsRun(result: .generated([SuggestedPrompt("New document question")], stats: nil), raw: "", total: .zero)
        }
        _ = await cache.resolve { _ in }
        cache.start(key: second) { _ in
            Issue.record("Identical request must reuse cached result")
            return SuggestedPromptsRun(result: .timedOut, raw: "", total: .zero)
        }
        #expect(cache.prompts == [SuggestedPrompt("New document question")])
        cache.invalidate()
        #expect(cache.prompts.isEmpty)
        #expect(cache.key == nil)
        var changed = variant
        changed.budgetSeconds = 10
        #expect(SuggestionsKey(document: first.document, url: first.url, variant: changed) != first)
        changed = variant
        changed.locale = "de"
        #expect(SuggestionsKey(document: first.document, url: first.url, variant: changed) != first)
    }

    @MainActor
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func sameKeyRestartRejectsCanceledOperationUpdates() async {
        let cache = CurrentDocumentSuggestions()
        let key = SuggestionsKey(document: UUID(), url: URL(string: "https://example.com")!,
                                 variant: SuggestionsVariant(modelID: "stub", locale: "en"))
        let gate = SuggestionsGate()
        cache.start(key: key) { update in
            await gate.wait()
            await update([SuggestedPrompt("Canceled old question")])
            await gate.markFinished()
            return SuggestedPromptsRun(result: .generated([SuggestedPrompt("Canceled old question")], stats: nil), raw: "", total: .zero)
        }
        await Task.yield()
        cache.invalidate()
        cache.start(key: key) { update in
            await update([SuggestedPrompt("Current new question")])
            return SuggestedPromptsRun(result: .generated([SuggestedPrompt("Current new question")], stats: nil), raw: "", total: .zero)
        }
        _ = await cache.resolve { _ in }
        await gate.release()
        await gate.waitUntilFinished()
        #expect(cache.prompts == [SuggestedPrompt("Current new question")])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func canceledGeneratorReturnsWithoutPublishingLateLines() async {
        let updates = PromptUpdates()
        let generator = SuggestedPromptsGenerator(provider: stub("What do ducks eat?\nHow long do ducks live?\n", wordsPerSecond: 5),
                                                  budget: .seconds(10), uiLanguageName: "English")
        let task = Task { await generator.run(for: page) { await updates.append($0) } }
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()
        _ = await task.value
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await updates.values.isEmpty)
    }

}

private actor PromptUpdates {
    var values: [[SuggestedPrompt]] = []
    func append(_ prompts: [SuggestedPrompt]) { values.append(prompts) }
}

private actor SuggestionsGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private var finished = false
    private var finishedContinuation: CheckedContinuation<Void, Never>?
    func markFinished() {
        finished = true
        finishedContinuation?.resume()
        finishedContinuation = nil
    }
    func waitUntilFinished() async {
        if !finished { await withCheckedContinuation { finishedContinuation = $0 } }
    }
    func wait() async {
        if !released { await withCheckedContinuation { continuation = $0 } }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private final class StallingTabProvider: ChatProvider {
    let descriptor = ProviderDescriptor(id: ProviderID(rawValue: "stall"), displayName: "Stall", modelName: "Stall", contextWindowTokens: 4096)
    let availability: ProviderAvailability = .ready
    let text: String
    let failure: ChatError?
    let refusal: Bool
    let emitsText: Bool
    let emitsReading: Bool
    let started: AsyncStream<Void>
    let start: AsyncStream<Void>.Continuation
    init(_ text: String, failure: ChatError? = nil, refusal: Bool = false, emitsText: Bool = true, emitsReading: Bool = false) {
        self.text = text
        self.failure = failure
        self.refusal = refusal
        self.emitsText = emitsText
        self.emitsReading = emitsReading
        (started, start) = AsyncStream<Void>.makeStream()
    }
    func availabilityUpdates() -> AsyncStream<ProviderAvailability> { AsyncStream { $0.finish() } }
    func download() async throws { }
    func prepare() async { }
    func unload() { }
    func reply(to turn: ProviderTurn, stop: StopSignal) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { continuation in
            if emitsReading { continuation.yield(.stage(.readingInput(estimatedTokens: 1, fraction: nil))) }
            if emitsText { continuation.yield(.textDelta(text)) }
            start.yield(())
            start.finish()
            if refusal { continuation.yield(.refusal(Refusal(detectedBy: "test"))) }
            if let failure { continuation.finish(throwing: failure) }
        }
    }
}
