//
//  SuggestionsEngine.swift
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
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

public enum SuggestionsEngine {
    public static func run(page: PageSnapshot, variant: SuggestionsVariant, provider: any ChatProvider,
                           onUpdate: @escaping @Sendable ([SuggestedPrompt]) async -> Void = { _ in }) async -> SuggestedPromptsRun {
        switch variant.method {
        case .model:
            return await SuggestedPromptsGenerator(provider: provider, budget: .seconds(variant.budgetSeconds),
                                                    maxSuggestions: variant.count, input: variant.input,
                                                    uiLanguageName: Locale(identifier: "en").localizedString(forIdentifier: variant.locale) ?? variant.locale)
                .run(for: page, onUpdate: onUpdate)
        case .templates:
            return await TemplateSuggestions.run(page: page, variant: variant, onUpdate: onUpdate)
        case .foundationModels:
#if canImport(FoundationModels)
            if #available(iOS 26, macOS 26, *) {
                return await guided(page: page, variant: variant, onUpdate: onUpdate)
            }
#endif
            return SuggestedPromptsRun(result: .failed(.modelUnavailable(reason: "Foundation Models requires iOS 26 or macOS 26")),
                                       raw: "", total: .zero)
        }
    }

#if canImport(FoundationModels)
    @available(iOS 26, macOS 26, *)
    @Generable
    struct Questions {
        @Guide(description: "Short questions or requests, each at most six words and 45 characters, without numbering")
        var questions: [String]
    }

    @available(iOS 26, macOS 26, *)
    private static func guided(page: PageSnapshot, variant: SuggestionsVariant,
                               onUpdate: @escaping @Sendable ([SuggestedPrompt]) async -> Void) async -> SuggestedPromptsRun {
        let started = ContinuousClock.now
        guard case .available = SystemLanguageModel.default.availability else {
            return SuggestedPromptsRun(result: .failed(.modelUnavailable(reason: "Foundation Models unavailable on this device")), raw: "", total: .zero)
        }
        do {
            let turn = SuggestedPromptsPrompt.turn(for: page, count: variant.count, uiLanguageName: variant.locale, input: variant.input)
            let response = try await withThrowingTaskGroup(of: Questions.self) { group in
                group.addTask {
                    let session = LanguageModelSession(instructions: turn.instructions)
                    return try await session.respond(to: turn.input, generating: Questions.self,
                                                     options: GenerationOptions(maximumResponseTokens: 160)).content
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(variant.budgetSeconds))
                    throw CancellationError()
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else { throw CancellationError() }
                return result
            }
            try Task.checkCancellation()
            let raw = response.questions.joined(separator: "\n")
            let prompts = SuggestedPromptsPrompt.parse(raw, max: variant.count)
            await onUpdate(prompts)
            let elapsed = started.duration(to: .now)
            return SuggestedPromptsRun(result: prompts.isEmpty ? .unusable(raw: raw) : .generated(prompts, stats: nil),
                                       raw: raw, total: elapsed, firstChipTime: prompts.isEmpty ? nil : elapsed)
        } catch {
            return SuggestedPromptsRun(result: error is CancellationError ? .timedOut : .failed(.unknown(error.localizedDescription)),
                                       raw: "", total: started.duration(to: .now))
        }
    }
#endif
}

private actor TemplateSuggestions {
    private static let shared = TemplateSuggestions()
    private var vectors: [[Double]]?
    private var embedding: NLEmbedding?

    static func run(page: PageSnapshot, variant: SuggestionsVariant,
                    onUpdate: @escaping @Sendable ([SuggestedPrompt]) async -> Void) async -> SuggestedPromptsRun {
        let result = await shared.rank(page: page, variant: variant)
        if case .generated(let prompts, _) = result.result, !Task.isCancelled { await onUpdate(prompts) }
        return result
    }

    private func rank(page: PageSnapshot, variant: SuggestionsVariant) -> SuggestedPromptsRun {
        let started = ContinuousClock.now
        guard Locale(identifier: variant.locale).language.languageCode?.identifier == "en" else {
            return SuggestedPromptsRun(result: .failed(.modelUnavailable(reason: "Templates currently support English UI only")), raw: "", total: .zero)
        }
        if embedding == nil { embedding = NLEmbedding.sentenceEmbedding(for: .english) }
        let input = SuggestedPromptsPrompt.boundedInput(for: page, variant: variant.input)
        let pageVector = embedding?.vector(for: input)
        if vectors == nil, let embedding {
            vectors = Self.bank.map { embedding.vector(for: $0.signal) ?? [] }
        }
        let words = Set(input.lowercased().split { !$0.isLetter }.map(String.init))
        var ranked: [(index: Int, score: Double)] = []
        for (index, item) in Self.bank.enumerated() {
            let score: Double
            if let pageVector, let vectors, !vectors[index].isEmpty {
                let vector = vectors[index]
                var dot = 0.0
                var pageNorm = 0.0
                var templateNorm = 0.0
                for (left, right) in zip(pageVector, vector) {
                    dot += left * right
                    pageNorm += left * left
                    templateNorm += right * right
                }
                let norm = sqrt(pageNorm * templateNorm)
                score = norm > 0 ? dot / norm : 0
            } else {
                let keywords = Set(item.signal.lowercased().split { !$0.isLetter }.map(String.init))
                score = Double(words.intersection(keywords).count)
            }
            ranked.append((index, score))
        }
        ranked.sort { $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score }
        let topic = page.title.split(whereSeparator: \.isWhitespace).prefix(3).joined(separator: " ").prefix(30)
        let lines = ranked.map { Self.bank[$0.0].question.replacingOccurrences(of: "{topic}", with: topic.isEmpty ? "this topic" : String(topic)) }
        let prompts = SuggestedPromptsPrompt.parse(lines.joined(separator: "\n"), max: variant.count)
        let elapsed = started.duration(to: .now)
        return SuggestedPromptsRun(result: .generated(prompts, stats: nil),
                                   raw: pageVector == nil ? "Lexical ranking (sentence embeddings unavailable)" : "NaturalLanguage English sentence embeddings",
                                   total: elapsed, firstChipTime: elapsed)
    }

    private struct Template {
        let signal: String
        let question: String
    }

    private static let bank: [Template] = {
        let groups: [(String, [String])] = [
            ("article news research evidence report", ["What changed in {topic}?", "Why does this matter?", "What evidence supports this?", "Who is affected?", "What is still uncertain?", "What happened before this?", "What happens next?", "Which claims need checking?", "What are the main findings?", "Explain the background simply"]),
            ("recipe food cooking ingredients meal", ["How do I make {topic}?", "What ingredients can I substitute?", "Can I prepare this ahead?", "How should I store leftovers?", "What equipment do I need?", "How can I adjust portions?", "What could go wrong?", "Which steps matter most?", "Suggest a vegetarian alternative", "What goes well with this?"]),
            ("product buying price features comparison review", ["Is {topic} worth buying?", "What are the alternatives?", "What are the hidden costs?", "Who is this best for?", "Which features matter most?", "What are the drawbacks?", "Compare the main options", "What should I check before buying?", "How durable is this?", "Explain the warranty terms"]),
            ("software programming code API developer tutorial", ["How does {topic} work?", "Show a simple example", "What are common mistakes?", "Explain the prerequisites", "How can I test this?", "What are the security risks?", "How do I debug this?", "What are the performance tradeoffs?", "Explain the API simply", "What should I learn next?"]),
            ("travel destination hotel city transport vacation", ["When should I visit {topic}?", "How do I get there?", "What should I budget?", "Suggest a short itinerary", "What should I book ahead?", "What are the local customs?", "Which areas should I explore?", "How accessible is this destination?", "What should I pack?", "Suggest nearby alternatives"]),
            ("science animal nature species biology habitat", ["What makes {topic} distinctive?", "Where does it occur naturally?", "How does it survive?", "What threatens this species?", "Explain its life cycle", "How do scientists study this?", "What are common misconceptions?", "Compare related species", "What role does it play?", "Explain this to a beginner"]),
            ("history biography person culture art book", ["Why is {topic} significant?", "What influenced this work?", "Describe the historical context", "What are the central themes?", "Who were the key figures?", "How was this received?", "What changed over time?", "Suggest related reading", "Explain the main argument", "What perspectives are missing?"]),
            ("health exercise fitness symptoms treatment medicine", ["Explain {topic} in simple terms", "What questions should I ask?", "What evidence is available?", "What risks are mentioned?", "Who might benefit?", "What are the limitations?", "Which terms need explaining?", "What alternatives are discussed?", "How recent is this evidence?", "Summarize the practical advice"]),
            ("finance money savings budget business investment", ["What affects {topic}?", "Explain the costs involved", "What are the main risks?", "Compare the possible outcomes", "What assumptions are being made?", "How do the numbers compare?", "Explain the financial terms", "What questions remain unanswered?", "What would change the conclusion?", "Summarize the key tradeoffs"]),
            ("course job learning career event instructions", ["How do I start with {topic}?", "What skills do I need?", "What are the requirements?", "Summarize the important dates", "What should I prepare?", "Suggest a learning plan", "What should I practice first?", "How can I evaluate progress?", "Explain the next steps", "What resources would help?"])
        ]
        return groups.flatMap { signal, questions in questions.map { Template(signal: signal + " " + $0, question: $0) } }
    }()
}
