//
//  LocalAIPromptBuilder.swift
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

import Foundation

public struct LocalAIPrompt: Equatable, Sendable {
    public let instructions: String
    public let message: String
    /// Upper bound on generated tokens: summaries are short, translations are as long as their input.
    public let maxTokens: Int
}

public enum LocalAIPromptBuilder {

    public static func prompt(for request: LocalAIRequest) -> LocalAIPrompt {
        switch request.task {
        case .summarize:
            LocalAIPrompt(
                instructions: """
                You summarize web content for a reader in a browser. Use only the text you are given. \
                Write in \(request.language). Reply with a one-sentence overview followed by 3 to 6 short \
                Markdown bullet points. Do not add a title or any closing remarks.
                """,
                message: "\(summarizeLead(for: request.source))\n\n\(body(of: request.source))",
                maxTokens: 512
            )
        case .translate:
            LocalAIPrompt(
                instructions: """
                You translate web content into \(request.language). Translate everything you are given, \
                keep its paragraphs and lists, and reply with the translation only. Do not summarize, \
                explain or add notes.
                """,
                message: "\(translateLead(for: request.source, language: request.language))\n\n\(body(of: request.source))",
                maxTokens: translationTokenBudget(for: request.source)
            )
        }
    }

    /// What to send for a request's first answer. A translation goes out in pieces, translated one after
    /// another, so the first words appear once the model has read one short piece instead of the whole page.
    /// Everything else is a single prompt.
    public static func prompts(for request: LocalAIRequest) -> [LocalAIPrompt] {
        guard request.task == .translate else { return [prompt(for: request)] }
        let pieces = translationPieces(of: translatableText(of: request.source))
        guard pieces.count > 1 else { return [prompt(for: request)] }
        let instructions = prompt(for: request).instructions
        return pieces.map { piece in
            LocalAIPrompt(instructions: instructions,
                          message: "Translate this text into \(request.language).\n\nText:\n\(piece)",
                          maxTokens: translationTokenBudget(for: .selection([piece])))
        }
    }

    /// The first piece is short so the first words come quickly; the rest are longer, so fewer of them.
    static let firstPieceCharacterLimit = 600
    static let pieceCharacterLimit = 1_800

    /// Splits at paragraph breaks, then at sentence ends or spaces when a paragraph alone is too long.
    static func translationPieces(of text: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var limit = firstPieceCharacterLimit

        func close() {
            guard !current.isEmpty else { return }
            pieces.append(current)
            current = ""
            limit = pieceCharacterLimit
        }

        for paragraph in text.components(separatedBy: "\n") where !paragraph.trimmingCharacters(in: .whitespaces).isEmpty {
            var rest = Substring(paragraph)
            while !rest.isEmpty {
                let room = limit - current.count - (current.isEmpty ? 0 : 1)
                if rest.count <= room {
                    current += (current.isEmpty ? "" : "\n") + rest
                    break
                }
                if !current.isEmpty {
                    close()
                    continue
                }
                let cut = splitPoint(in: rest, maxLength: limit)
                current = String(rest[..<cut]).trimmingCharacters(in: .whitespaces)
                rest = rest[cut...].drop { $0 == " " }
                close()
            }
        }
        close()
        return pieces
    }

    /// The last sentence end, else the last space, within `maxLength`; a hard cut if there's neither.
    private static func splitPoint(in text: Substring, maxLength: Int) -> Substring.Index {
        let window = text.prefix(maxLength)
        if let sentenceEnd = window.range(of: ". ", options: .backwards) {
            return sentenceEnd.upperBound
        }
        if let space = window.lastIndex(of: " ") {
            return text.index(after: space)
        }
        return window.endIndex
    }

    /// A translation sent in pieces leaves the chat without the page, so the first follow-up carries it.
    public static func followUpContext(for request: LocalAIRequest) -> String {
        "For context, here is what you just translated:\n\n\(body(of: request.source))\n\n"
    }

    static func translatableText(of source: LocalAISource) -> String {
        switch source {
        case .page(let page): page.content
        case .selection(let texts): texts.joined(separator: "\n\n")
        }
    }

    static func summarizeLead(for source: LocalAISource) -> String {
        switch source {
        case .page: "Summarize this page."
        case .selection: "Summarize this selection."
        }
    }

    static func translateLead(for source: LocalAISource, language: String) -> String {
        switch source {
        case .page: "Translate this page into \(language)."
        case .selection: "Translate this selection into \(language)."
        }
    }

    static func body(of source: LocalAISource) -> String {
        switch source {
        case .page(let page):
            var lines = ["Title: \(page.title)"]
            if !page.url.isEmpty {
                lines.append("URL: \(page.url)")
            }
            lines.append("Content:\n\(page.content)")
            return lines.joined(separator: "\n")
        case .selection(let texts) where texts.count == 1:
            return "Selection:\n\(texts[0])"
        case .selection(let texts):
            return texts.enumerated()
                .map { "Selection \($0.offset + 1):\n\($0.element)" }
                .joined(separator: "\n\n")
        }
    }

    /// About one token per three characters of input, plus headroom, capped so a runaway generation stops.
    static func translationTokenBudget(for source: LocalAISource) -> Int {
        min(4096, max(256, source.characterCount / 3 + 128))
    }
}
