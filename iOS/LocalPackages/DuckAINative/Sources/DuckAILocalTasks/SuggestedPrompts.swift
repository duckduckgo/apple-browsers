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

public struct PageSnapshot: Equatable, Sendable {
    public let title: String
    public let url: URL?
    public let description: String
    public let headings: [String]
    public let content: String
    /// BCP 47 code of the page language when known, e.g. "de". Suggestions are written in the UI language regardless.
    public let language: String?

    public init(title: String, url: URL?, content: String, language: String?, description: String = "", headings: [String] = []) {
        self.description = description
        self.headings = headings
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

/// One generation, with what it produced and when, for diagnosing why suggestions fell back.
public struct SuggestedPromptsRun: Sendable {
    public let result: SuggestedPromptsResult
    /// Everything the model wrote, including partial text when the run timed out.
    public let raw: String
    /// Preparation, including queue wait, until reading starts. Actual model load comes from `stats`.
    public let loadTime: Duration?
    public let timeToFirstText: Duration?
    public let total: Duration
    public let firstChipTime: Duration?
    public let stats: GenerationStats?

    public init(result: SuggestedPromptsResult, raw: String, loadTime: Duration? = nil,
                timeToFirstText: Duration? = nil, total: Duration, firstChipTime: Duration? = nil,
                stats: GenerationStats? = nil) {
        self.result = result
        self.raw = raw
        self.loadTime = loadTime
        self.timeToFirstText = timeToFirstText
        self.total = total
        self.firstChipTime = firstChipTime
        self.stats = stats
    }
}

/// One-shot suggested prompts for the contextual sheet, from any `ChatProvider`.
public struct SuggestedPromptsGenerator: Sendable {
    public static let defaultBudget: Duration = .milliseconds(1_500)
    public static let defaultLoadBudget: Duration = .seconds(10)

    private let provider: any ChatProvider
    private let budget: Duration
    private let loadBudget: Duration
    private let maxSuggestions: Int
    private let uiLanguageName: String
    private let input: SuggestionsVariant.Input

    /// `uiLanguageName` is the language suggestions are written in, e.g. "English".
    public init(provider: any ChatProvider,
                budget: Duration = SuggestedPromptsGenerator.defaultBudget,
                loadBudget: Duration = SuggestedPromptsGenerator.defaultLoadBudget,
                maxSuggestions: Int = 3,
                input: SuggestionsVariant.Input = .headings,
                uiLanguageName: String) {
        self.input = input
        self.provider = provider
        self.budget = budget
        self.loadBudget = loadBudget
        self.maxSuggestions = maxSuggestions
        self.uiLanguageName = uiLanguageName
    }

    public func suggestions(for page: PageSnapshot) async -> SuggestedPromptsResult {
        await run(for: page).result
    }

    public func run(for page: PageSnapshot,
                    onUpdate: @escaping @Sendable ([SuggestedPrompt]) async -> Void = { _ in }) async -> SuggestedPromptsRun {
        let trace = RunTrace()
        let stop = StopSignal()
        let turn = SuggestedPromptsPrompt.turn(for: page, count: maxSuggestions, uiLanguageName: uiLanguageName, input: input)
        let (results, continuation) = AsyncStream<SuggestedPromptsResult>.makeStream()
        let (reading, readingContinuation) = AsyncStream<Void>.makeStream()
        let worker = Task.detached {
            continuation.yield(await result(for: turn, stop: stop, trace: trace,
                                             onReading: { readingContinuation.finish() }, onUpdate: onUpdate))
            continuation.finish()
            readingContinuation.finish()
        }
        let timeout = Task.detached { [budget, loadBudget] in
            let startedReading = await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    for await _ in reading {}
                    return !Task.isCancelled
                }
                group.addTask {
                    try? await Task.sleep(for: loadBudget)
                    return false
                }
                let first = await group.next() ?? false
                group.cancelAll()
                return first
            }
            if startedReading {
                try? await Task.sleep(for: budget)
            }
            guard !Task.isCancelled else { return }
            stop.raise()
            continuation.yield(trace.partialResult(max: maxSuggestions))
            continuation.finish()
        }
        return await withTaskCancellationHandler {
            var iterator = results.makeAsyncIterator()
            let result = await iterator.next() ?? .timedOut
            timeout.cancel()
            stop.raise()
            worker.cancel()
            return trace.run(result)
        } onCancel: {
            stop.raise()
            worker.cancel()
            timeout.cancel()
            continuation.finish()
        }
    }

    private func result(for turn: ProviderTurn, stop: StopSignal, trace: RunTrace, onReading: () -> Void,
                        onUpdate: @escaping @Sendable ([SuggestedPrompt]) async -> Void) async -> SuggestedPromptsResult {
        var raw = ""
        var stats: GenerationStats?
        var refused = false
        var emitted: [SuggestedPrompt] = []
        do {
            for try await event in provider.reply(to: turn, stop: stop) {
                switch event {
                case .stage(.readingInput):
                    trace.markReading()
                    onReading()
                case .textDelta(let text):
                    trace.markReading()
                    trace.append(text)
                    onReading()
                    raw += text
                    if let lastNewline = raw.lastIndex(of: "\n") {
                        let complete = SuggestedPromptsPrompt.parse(String(raw[..<lastNewline]), max: maxSuggestions)
                        if !Task.isCancelled, complete != emitted {
                            emitted = complete
                            trace.markChip()
                            await onUpdate(complete)
                        }
                        if complete.count == maxSuggestions { stop.raise() }
                    }
                case .refusal: refused = true
                case .finished(let generationStats):
                    stats = generationStats
                    trace.record(stats)
                case .stage, .reasoningDelta: break
                }
            }
        } catch let error as ChatError {
            if !emitted.isEmpty { return .generated(emitted, stats: stats) }
            return .failed(error)
        } catch {
            if !emitted.isEmpty { return .generated(emitted, stats: stats) }
            return .failed(.unknown(String(describing: error)))
        }
        if refused { return .unusable(raw: "") }
        let parsed = SuggestedPromptsPrompt.parse(raw, max: maxSuggestions)
        if !Task.isCancelled, !parsed.isEmpty, parsed != emitted { trace.markChip(); await onUpdate(parsed) }
        return parsed.isEmpty ? .unusable(raw: raw.trimmingCharacters(in: .whitespacesAndNewlines)) : .generated(parsed, stats: stats)
    }
}

/// The prompt and the parser, pure so they can be tested and evaluated without a model.
public enum SuggestedPromptsPrompt {
    /// Page content beyond this is dropped: suggestions need the gist, and a short read keeps the first token fast.
    public static let contentCharacterLimit = 1_200

    public static func turn(for page: PageSnapshot, count: Int, uiLanguageName: String,
                            conversation: ConversationID = ConversationID(), input variant: SuggestionsVariant.Input = .headings) -> ProviderTurn {
        let instructions = """
        Suggest \(count) things a reader of this page might ask an AI assistant about it.
        Each one is a short question or request of at most 8 words and 60 characters, like a button label.
        Write in \(uiLanguageName). One per line. No numbering, bullets, quotes or other text.
        """
        let input = boundedInput(for: page, variant: variant)
        let estimatedInputTokens = Int((Double((instructions + input).count) / 3.5).rounded(.up))
        return ProviderTurn(conversation: conversation, instructions: instructions, history: [], input: input,
                            maxOutputTokens: 80, estimatedInputTokens: estimatedInputTokens)
    }

    public static func boundedInput(for page: PageSnapshot, variant: SuggestionsVariant.Input) -> String {
        var lines = ["Title: \(page.title.prefix(100))"]
        if let host = page.url?.host { lines.append("Site: \(host.prefix(60))") }
        switch variant {
        case .title: break
        case .headings:
            lines.append("Description: \(page.description.prefix(120))")
            lines.append("Headings: \(page.headings.prefix(6).joined(separator: "; ").prefix(160))")
        case .body: lines.append("Content: \(page.content.prefix(contentCharacterLimit))")
        }
        return lines.joined(separator: "\n")
    }

    /// Lenient: one suggestion per non-empty line. Strips bullets ("-", "*", "•"), numbering ("1.", "1)"), surrounding
    /// quotes and whitespace. Drops lines that are headings or preambles (ending in ":"), shorter than 8 or longer than
    /// 60 characters, and case-insensitive duplicates. Keeps order and returns at most `max`.
    public static func parse(_ raw: String, max: Int) -> [SuggestedPrompt] {
        guard max > 0 else { return [] }
        let surroundingCharacters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'“”‘’"))
        var seen: Set<String> = []
        var suggestions: [SuggestedPrompt] = []
        for line in raw.components(separatedBy: .newlines) {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"^(?:[-*•]\s*|\d+[.)]\s*)"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: surroundingCharacters)
                .replacingOccurrences(of: #"^[*_`]+|[*_`]+$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: surroundingCharacters)
            guard (8...60).contains(text.count), text.split(whereSeparator: \.isWhitespace).count <= 8, !text.hasSuffix(":"), seen.insert(text.lowercased()).inserted else { continue }
            suggestions.append(SuggestedPrompt(text))
            if suggestions.count == max { break }
        }
        return suggestions
    }
}

private final class RunTrace: @unchecked Sendable {
    private let lock = NSLock()
    private let started = ContinuousClock.now
    private var raw = ""
    private var readingAt: ContinuousClock.Instant?
    private var firstTextAt: ContinuousClock.Instant?
    private var firstChipAt: ContinuousClock.Instant?
    private var stats: GenerationStats?

    func markReading() {
        lock.withLock {
            if readingAt == nil { readingAt = .now }
        }
    }

    func append(_ text: String) {
        lock.withLock {
            if firstTextAt == nil { firstTextAt = .now }
            raw += text
        }
    }

    func markChip() {
        lock.withLock { if firstChipAt == nil { firstChipAt = .now } }
    }

    func record(_ stats: GenerationStats?) {
        lock.withLock { self.stats = stats }
    }

    func partialResult(max: Int) -> SuggestedPromptsResult {
        lock.withLock {
            guard let newline = raw.lastIndex(of: "\n") else { return .timedOut }
            let prompts = SuggestedPromptsPrompt.parse(String(raw[..<newline]), max: max)
            return prompts.isEmpty ? .timedOut : .generated(prompts, stats: stats)
        }
    }

    func run(_ result: SuggestedPromptsResult) -> SuggestedPromptsRun {
        lock.withLock {
            SuggestedPromptsRun(result: result, raw: raw,
                                loadTime: readingAt.map { started.duration(to: $0) },
                                timeToFirstText: firstTextAt.map { started.duration(to: $0) },
                                total: started.duration(to: .now),
                                firstChipTime: firstChipAt.map { started.duration(to: $0) }, stats: stats)
        }
    }
}
