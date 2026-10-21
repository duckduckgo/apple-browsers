//
//  LocalAIPromptBuilderTests.swift
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
import Testing
@testable import LocalAI

@Suite("Prompt building")
struct LocalAIPromptBuilderTests {

    @available(iOS 16, macOS 13, *)
    @Test("A page summary carries the title, URL and content, in the user's language", .timeLimit(.minutes(1)))
    func pageSummary() {
        let page = LocalAIPage(title: "Coffee", url: "https://example.com/coffee", content: "Coffee is a drink.")
        let prompt = LocalAIPromptBuilder.prompt(for: LocalAIRequest(task: .summarize, source: .page(page), language: "German"))

        #expect(prompt.instructions.contains("Write in German."))
        #expect(prompt.message == "Summarize this page.\n\nTitle: Coffee\nURL: https://example.com/coffee\nContent:\nCoffee is a drink.")
        #expect(prompt.maxTokens == 512)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Several selections are numbered", .timeLimit(.minutes(1)))
    func multipleSelections() {
        let prompt = LocalAIPromptBuilder.prompt(for: LocalAIRequest(task: .summarize, source: .selection(["One", "Two"]), language: "English"))

        #expect(prompt.message == "Summarize this selection.\n\nSelection 1:\nOne\n\nSelection 2:\nTwo")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A translation names the target language and scales its token budget with the input", .timeLimit(.minutes(1)))
    func translation() {
        let short = LocalAIPromptBuilder.prompt(for: LocalAIRequest(task: .translate, source: .selection(["Hallo"]), language: "English"))
        let long = LocalAIPromptBuilder.prompt(for: LocalAIRequest(task: .translate, source: .selection([String(repeating: "a", count: 9_500)]), language: "English"))
        let huge = LocalAIPromptBuilder.prompt(for: LocalAIRequest(task: .translate, source: .selection([String(repeating: "a", count: 50_000)]), language: "English"))

        #expect(short.message == "Translate this selection into English.\n\nSelection:\nHallo")
        #expect(short.instructions.contains("into English"))
        #expect(short.maxTokens == 256)
        #expect(long.maxTokens == 9_500 / 3 + 128)
        #expect(huge.maxTokens == 4_096)
    }
}

@Suite("Model catalog")
struct LocalAIModelCatalogTests {

    @available(iOS 16, macOS 13, *)
    @Test("Devices with 6 GB or more get Qwen3.5 2B, smaller ones 0.8B", .timeLimit(.minutes(1)))
    func recommendation() {
        let sixGBiPhone: UInt64 = 5_900_000_000
        let fourGBiPhone: UInt64 = 3_900_000_000
        #expect(LocalAIModelCatalog.recommended(physicalMemory: sixGBiPhone) == LocalAIModelCatalog.qwen35)
        #expect(LocalAIModelCatalog.recommended(physicalMemory: fourGBiPhone) == LocalAIModelCatalog.qwen35Mini)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Ids are unique", .timeLimit(.minutes(1)))
    func uniqueIDs() {
        #expect(Set(LocalAIModelCatalog.all.map(\.id)).count == LocalAIModelCatalog.all.count)
    }
}

@Suite("Benchmark set")
struct LocalAIBenchmarkSetTests {

    @available(iOS 16, macOS 13, *)
    @Test("English articles get two summaries, other languages also two translations", .timeLimit(.minutes(1)))
    func caseShape() {
        let text = (1...20).map { "Paragraph \($0) " + String(repeating: "word ", count: 40) }.joined(separator: "\n")
        let texts = LocalAIBenchmarkSet.articles.map { (article: $0, text: text) }
        let cases = LocalAIBenchmarkSet.makeCases(texts: texts, language: "English")

        #expect(cases.count == 6 * 2 + 4 * 4)
        #expect(Set(cases.map(\.id)).count == cases.count)
        #expect(cases.allSatisfy { $0.request.source.characterCount <= LocalAIBenchmarkSet.pageCharacterLimit })
    }
}

@Suite("Translating in pieces")
struct LocalAITranslationPiecesTests {

    @available(iOS 16, macOS 13, *)
    @Test("A long page becomes a short first piece and longer ones after it, losing no text", .timeLimit(.minutes(1)))
    func piecesCoverTheWholeText() {
        let paragraphs = (1...30).map { "Absatz \($0): " + String(repeating: "Wort ", count: 30) }
        let text = paragraphs.joined(separator: "\n")
        let pieces = LocalAIPromptBuilder.translationPieces(of: text)

        #expect(pieces.count > 2)
        #expect(pieces[0].count <= LocalAIPromptBuilder.firstPieceCharacterLimit)
        #expect(pieces.dropFirst().allSatisfy { $0.count <= LocalAIPromptBuilder.pieceCharacterLimit })
        #expect(pieces.joined().filter { !$0.isWhitespace } == text.filter { !$0.isWhitespace })
    }

    @available(iOS 16, macOS 13, *)
    @Test("A paragraph longer than a piece is split at a sentence end", .timeLimit(.minutes(1)))
    func longParagraphSplitsAtSentence() {
        let sentence = String(repeating: "x", count: 250) + ". "
        let pieces = LocalAIPromptBuilder.translationPieces(of: String(repeating: sentence, count: 6))

        #expect(pieces.count > 1)
        #expect(pieces[0].hasSuffix("."))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A short selection and any summary stay a single prompt", .timeLimit(.minutes(1)))
    func shortInputsStayWhole() {
        let selection = LocalAIRequest(task: .translate, source: .selection(["Hallo Welt"]), language: "English")
        let page = LocalAIPage(title: "T", url: "", content: String(repeating: "Satz. ", count: 1_000))
        let summary = LocalAIRequest(task: .summarize, source: .page(page), language: "English")
        let translation = LocalAIRequest(task: .translate, source: .page(page), language: "English")

        #expect(LocalAIPromptBuilder.prompts(for: selection) == [LocalAIPromptBuilder.prompt(for: selection)])
        #expect(LocalAIPromptBuilder.prompts(for: summary).count == 1)
        #expect(LocalAIPromptBuilder.prompts(for: translation).count > 1)
        #expect(LocalAIPromptBuilder.prompts(for: translation)[0].message.hasPrefix("Translate this text into English."))
    }
}
