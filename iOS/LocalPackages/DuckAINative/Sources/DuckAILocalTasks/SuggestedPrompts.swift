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

/// One generation, with what it produced and when, for diagnosing why suggestions fell back.
public struct SuggestedPromptsRun: Sendable {
    public let result: SuggestedPromptsResult
    /// Everything the model wrote, including partial text when the run timed out.
    public let raw: String
    /// From the request until the model started reading the page.
    public let loadTime: Duration?
    public let timeToFirstText: Duration?
    public let total: Duration
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

    /// `uiLanguageName` is the language suggestions are written in, e.g. "English".
    public init(provider: any ChatProvider,
                budget: Duration = SuggestedPromptsGenerator.defaultBudget,
                loadBudget: Duration = SuggestedPromptsGenerator.defaultLoadBudget,
                maxSuggestions: Int = 4,
                uiLanguageName: String) {
        self.provider = provider
        self.budget = budget
        self.loadBudget = loadBudget
        self.maxSuggestions = maxSuggestions
        self.uiLanguageName = uiLanguageName
    }

    /// Streams one reply and parses it, returning as soon as `maxSuggestions` whole lines have arrived. `budget` starts when
    /// the model starts reading the page, so loading it does not count; `loadBudget` caps the wait before that. When a budget elapses first, raises the reply's `StopSignal` and returns
    /// `.timedOut` at once; the provider drains on its own (Core's stop contract). Never throws.
    public func suggestions(for page: PageSnapshot) async -> SuggestedPromptsResult {
        await run(for: page).result
    }

    public func run(for page: PageSnapshot) async -> SuggestedPromptsRun {
        let trace = RunTrace()
        let stop = StopSignal()
        let turn = SuggestedPromptsPrompt.turn(for: page, count: maxSuggestions, uiLanguageName: uiLanguageName)
        let (results, continuation) = AsyncStream<SuggestedPromptsResult>.makeStream()
        let (reading, readingContinuation) = AsyncStream<Void>.makeStream()
        Task.detached {
            continuation.yield(await result(for: turn, stop: stop, trace: trace, onReading: { readingContinuation.finish() }))
            continuation.finish()
            readingContinuation.finish()
        }
        let timeout = Task.detached { [budget, loadBudget] in
            // Loading the model is excluded from `budget`; it has its own, longer cap.
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
            continuation.yield(.timedOut)
            continuation.finish()
        }
        var iterator = results.makeAsyncIterator()
        let result = await iterator.next() ?? .timedOut
        timeout.cancel()
        return trace.run(result)
    }

    private func result(for turn: ProviderTurn, stop: StopSignal, trace: RunTrace, onReading: () -> Void) async -> SuggestedPromptsResult {
        var raw = ""
        var stats: GenerationStats?
        var refused = false
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
                    // Models often keep writing past the suggestions; stop as soon as enough whole lines have arrived.
                    if let lastNewline = raw.lastIndex(of: "\n") {
                        let complete = SuggestedPromptsPrompt.parse(String(raw[..<lastNewline]), max: maxSuggestions)
                        if complete.count == maxSuggestions {
                            stop.raise()
                            return .generated(complete, stats: nil)
                        }
                    }
                case .refusal: refused = true
                case .finished(let generationStats): stats = generationStats
                case .stage, .reasoningDelta: break
                }
            }
        } catch let error as ChatError {
            return .failed(error)
        } catch {
            return .failed(.unknown(String(describing: error)))
        }
        if refused { return .unusable(raw: "") }
        let parsed = SuggestedPromptsPrompt.parse(raw, max: maxSuggestions)
        return parsed.isEmpty ? .unusable(raw: raw.trimmingCharacters(in: .whitespacesAndNewlines)) : .generated(parsed, stats: stats)
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
        let instructions = """
        Write exactly \(count) short questions or requests a reader of this page might ask an assistant.
        Write in \(uiLanguageName), one suggestion per line, with no numbering, bullets or preamble.
        """
        var lines = ["Title: \(page.title)"]
        if let url = page.url { lines.append("URL: \(url.absoluteString)") }
        lines.append("Content: \(page.content.prefix(contentCharacterLimit))")
        let input = lines.joined(separator: "\n")
        let estimatedInputTokens = Int((Double((instructions + input).count) / 3.5).rounded(.up))
        return ProviderTurn(conversation: conversation, instructions: instructions, history: [], input: input,
                            maxOutputTokens: 160, estimatedInputTokens: estimatedInputTokens)
    }

    /// Lenient: one suggestion per non-empty line. Strips bullets ("-", "*", "•"), numbering ("1.", "1)"), surrounding
    /// quotes and whitespace. Drops lines that are headings or preambles (ending in ":"), shorter than 8 or longer than
    /// 80 characters, and case-insensitive duplicates. Keeps order and returns at most `max`.
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
            guard (8...80).contains(text.count), !text.hasSuffix(":"), seen.insert(text.lowercased()).inserted else { continue }
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

    func run(_ result: SuggestedPromptsResult) -> SuggestedPromptsRun {
        lock.withLock {
            SuggestedPromptsRun(result: result, raw: raw,
                                loadTime: readingAt.map { started.duration(to: $0) },
                                timeToFirstText: firstTextAt.map { started.duration(to: $0) },
                                total: started.duration(to: .now))
        }
    }
}
