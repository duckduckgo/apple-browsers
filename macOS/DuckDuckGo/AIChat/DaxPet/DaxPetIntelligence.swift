//
//  DaxPetIntelligence.swift
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

import AIChat
import Foundation
import FoundationModels
import NaturalLanguage
import PDFKit

/// Apple Intelligence's on-device model, for Dax's own small decisions; nothing it reads leaves the Mac.
/// Real answers stay with Duck.ai.
@MainActor
protocol DaxPetIntelligence {
    /// Whether the on-device model is there at all.
    var isOnDevice: Bool { get }
    /// A few short questions the user might ask Duck.ai about what they dropped on Dax.
    func suggestions(for attachments: [DaxPetAttachment]) async -> [String]
    /// Other ways for Dax to say `line`, meaning the same.
    func variations(of line: String) async -> [String]
    /// What kind of thing was dropped, when there's text to tell from.
    func kind(of attachments: [DaxPetAttachment]) async -> DaxPetDropKind?
    /// A one-sentence gist of a web page, and what the reader might want to ask about it next.
    func pageGlance(title: String, content: String) async -> DaxPetPageGlance?
    /// Whether answering `prompt` needs to see what the user has open in `appName`.
    func refersToScreen(_ prompt: String, appName: String) async -> Bool
    /// What to look up in the browser for `prompt`; `nil` when it's a question for Duck.ai.
    func lookup(_ prompt: String) async -> DaxPetLookup?
    /// The positions in `pages` of the ones `prompt` is after, best first, at most `maximum`.
    func pick(_ prompt: String, from pages: [String], maximum: Int) async -> [Int]
    /// What the user is looking at, from the text in the app in front.
    func screenTopic(_ text: String, appName: String) async -> DaxPetScreenTopic?
}

/// What's on the user's screen, and words to find pages about it.
struct DaxPetScreenTopic: Equatable {
    let topic: String
    let terms: [String]
}

struct DaxPetPageGlance: Equatable {
    let summary: String
    let followUps: [String]
    /// Words on the page the gist comes from, for Dax to point at.
    var quote: String?
}

/// Finds where on the page the on-device model's sentence came from, since it doesn't always copy it exactly.
enum DaxPetPageQuote {

    /// WebKit's find lights up one string, so a few words from the start of the sentence stand for it.
    static let fragmentWordCount = 8
    /// How much of the model's sentence a page sentence must share to be the one it came from.
    static let minimumShare = 0.6
    static let minimumSharedWords = 3

    /// The start of the page sentence `quote` came from, as written on the page.
    static func fragment(matching quote: String, in text: String) -> String? {
        let quoteWords = words(in: quote)
        guard quoteWords.count >= minimumSharedWords else { return nil }
        var best: (sentence: String, shared: Int)?
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range])
            let shared = quoteWords.intersection(words(in: sentence)).count
            if shared > best?.shared ?? 0 { best = (sentence, shared) }
            return true
        }
        guard let best, best.shared >= minimumSharedWords,
              Double(best.shared) / Double(quoteWords.count) >= minimumShare else { return nil }
        return leadingWords(of: best.sentence)
    }

    private static func words(in text: String) -> Set<String> {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        return Set(tokenizer.tokens(for: text.startIndex..<text.endIndex).map { text[$0].lowercased() })
    }

    /// The sentence's first few words, without heading or list marks.
    private static func leadingWords(of sentence: String) -> String? {
        let text = String(sentence.drop { $0.isWhitespace || "#*->•".contains($0) })
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        let wordRanges = tokenizer.tokens(for: text.startIndex..<text.endIndex)
        guard let last = wordRanges.prefix(fragmentWordCount).last else { return nil }
        let end = wordRanges.count > fragmentWordCount ? last.upperBound : text.endIndex
        let fragment = text[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return fragment.isEmpty ? nil : fragment
    }
}

/// Something Dax can find in the browser himself, without asking Duck.ai.
struct DaxPetLookup: Equatable {
    enum Kind: Equatable {
        case openTab
        case history
        /// Weighing up what's open in several tabs.
        case compareTabs
    }

    let kind: Kind
    /// Words to search titles and addresses for.
    let terms: [String]
    /// How far back the user said, in days; 0 when they didn't.
    let daysBack: Int
}

enum DaxPetIntelligenceFactory {

    /// The on-device model where Apple Intelligence is on; otherwise Dax does without.
    @MainActor
    static func make() -> DaxPetIntelligence {
        if #available(macOS 26, *), isAvailable {
            return DaxPetOnDeviceIntelligence()
        }
        return DaxPetNoIntelligence()
    }

    /// Whether this Mac has Apple Intelligence on, in a language it speaks.
    static var isAvailable: Bool {
        guard #available(macOS 26, *) else { return false }
        return SystemLanguageModel.default.isAvailable && SystemLanguageModel.default.supportsLocale()
    }
}

struct DaxPetNoIntelligence: DaxPetIntelligence {
    var isOnDevice: Bool { false }
    func pageGlance(title: String, content: String) async -> DaxPetPageGlance? { nil }
    func refersToScreen(_ prompt: String, appName: String) async -> Bool { false }
    func suggestions(for attachments: [DaxPetAttachment]) async -> [String] { [] }
    func variations(of line: String) async -> [String] { [] }
    func kind(of attachments: [DaxPetAttachment]) async -> DaxPetDropKind? { nil }
    func lookup(_ prompt: String) async -> DaxPetLookup? { nil }
    func pick(_ prompt: String, from pages: [String], maximum: Int) async -> [Int] { [] }
    func screenTopic(_ text: String, appName: String) async -> DaxPetScreenTopic? { nil }
}

@available(macOS 26, *)
@MainActor
final class DaxPetOnDeviceIntelligence: DaxPetIntelligence {

    /// The model only sees the start of long content.
    static let contentLimit = 3000

    var isOnDevice: Bool { true }

    @Generable
    struct Suggestions {
        @Guide(description: "Requests the user could send to an AI assistant about the content, each at most five words, without quotes",
               .count(3))
        var requests: [String]
    }

    func suggestions(for attachments: [DaxPetAttachment]) async -> [String] {
        let content = Self.describe(attachments)
        guard !content.isEmpty else { return [] }
        let session = LanguageModelSession(instructions: """
            You are Dax, the DuckDuckGo duck. The user dropped something on you to ask Duck.ai about it. \
            Suggest short, useful requests they could send, phrased as commands like "Summarize the key points". \
            Reply in \(Self.userLanguage).
            """)
        guard let response = try? await session.respond(to: content, generating: Suggestions.self,
                                                        options: GenerationOptions(temperature: 0.6)) else { return [] }
        return response.content.requests
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”"))) }
            .filter { !$0.isEmpty }
    }

    @Generable
    struct Variations {
        @Guide(description: "Other ways for Dax to say the same line, each at most eight words", .count(4))
        var lines: [String]
    }

    func variations(of line: String) async -> [String] {
        let session = LanguageModelSession(instructions: """
            You write lines for Dax, the cheerful DuckDuckGo duck who lives on the user's desktop and passes \
            their questions to Duck.ai. Given a line Dax says, write other ways for him to say exactly the same \
            thing, in his voice: playful and warm, now and then with a "Quack!". Never change what the line means. \
            For example, for "On it!" you might write "Quack, on it!", "Leave it to me!" or "Working on it!". \
            No emoji. Reply in \(Self.userLanguage).
            """)
        guard let response = try? await session.respond(to: "Line: \(line)", generating: Variations.self,
                                                        options: GenerationOptions(temperature: 0.7)) else { return [] }
        return response.content.lines
    }

    @Generable
    enum Kind {
        case article
        case code
        case message
        case other
    }

    func kind(of attachments: [DaxPetAttachment]) async -> DaxPetDropKind? {
        let hasText = attachments.contains { attachment in
            switch attachment {
            case .text: return true
            case .file(let file): return file.mimeType == "application/pdf"
            case .link, .image: return false
            }
        }
        guard hasText else { return nil }
        let session = LanguageModelSession(instructions: """
            Classify content the user dropped. article: prose meant to be read, like a news story, report, \
            document or web page. code: source code, a stack trace or logs. message: an email or chat message written to the user. \
            other: anything else, like a short note or a list.
            """)
        guard let response = try? await session.respond(to: Self.describe(attachments), generating: Kind.self,
                                                        options: GenerationOptions(temperature: 0)) else { return nil }
        switch response.content {
        case .article: return .article
        case .code: return .code
        case .message: return .message
        case .other: return .other
        }
    }

    @Generable
    struct PageGlance {
        @Guide(description: "What the page is about, in one plain sentence of at most fifteen words")
        var summary: String
        @Guide(description: "Short follow-up requests the reader could send to an AI assistant about this page, each two to five words, without quotes",
               .count(3))
        var followUps: [String]
        @Guide(description: "The one sentence on the page that best shows what it's about, copied word for word")
        var keySentence: String
    }

    func pageGlance(title: String, content: String) async -> DaxPetPageGlance? {
        let session = LanguageModelSession(instructions: """
            You are Dax, the DuckDuckGo duck. Tell the user in one short, plain sentence what the web page \
            they're reading is about, using only what's on the page. Then suggest specific follow-up requests \
            they'd likely want to ask about it, phrased as commands like "Compare the prices" or \
            "Explain the main argument". Reply in \(Self.userLanguage).
            """)
        let page = "Title: \(title)\n\n\(content.prefix(Self.contentLimit))"
        guard let response = try? await session.respond(to: page, generating: PageGlance.self,
                                                        options: GenerationOptions(temperature: 0.4)) else { return nil }
        let summary = response.content.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return nil }
        let followUps = response.content.followUps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”"))) }
            .filter { !$0.isEmpty }
        let quote = response.content.keySentence.trimmingCharacters(in: .whitespacesAndNewlines)
        return DaxPetPageGlance(summary: summary, followUps: followUps, quote: quote.isEmpty ? nil : quote)
    }

    @Generable
    struct ScreenReference {
        @Guide(description: "In a few words, what the question points at, if anything")
        var reason: String
        @Guide(description: "True when the question points at something the user has open, rather than standing on its own")
        var needsTheScreen: Bool
    }

    func refersToScreen(_ prompt: String, appName: String) async -> Bool {
        let session = LanguageModelSession(instructions: """
            The user is looking at \(appName) and asks an AI assistant something. Decide whether the question points \
            at what they have open in \(appName). It does when it says "this", "that", "these" or "here" about \
            something unnamed, or asks to act on what's open without naming it: "what is this?", "summarize", \
            "summarize this email", "translate this", "what does this error mean?", "reply to this", "is this a scam?". \
            It doesn't when the question stands on its own: "what's the capital of France?", "write a poem about \
            ducks", "how do I boil an egg?", "help me write an email to my landlord".
            """)
        let response = try? await session.respond(to: "Question: \(prompt)", generating: ScreenReference.self,
                                                  options: GenerationOptions(temperature: 0))
        return response?.content.needsTheScreen ?? false
    }

    @Generable
    enum LookupAction {
        case findOpenTab
        case findPageFromHistory
        case compareOpenTabs
        case askAssistant
    }

    @Generable
    struct LookupIntent {
        @Guide(description: "In a few words, what the user wants")
        var reason: String
        @Guide(description: "What the user is asking for")
        var action: LookupAction
        @Guide(description: "One to three short words to search page titles and addresses for, like a site, product or topic; no dates, no filler words like page, tab or article",
               .count(1...3))
        var searchTerms: [String]
        @Guide(description: "How many days back the user means, 0 when they don't say")
        var daysBack: Int
    }

    func lookup(_ prompt: String) async -> DaxPetLookup? {
        let session = LanguageModelSession(instructions: """
            The user asks Dax, a helper in their web browser, for something. Decide what they want.
            findOpenTab: go to or find a tab they already have open, like "where's my flights tab?", \
            "go to github", "switch to the tab with the recipe", "which tab has my email?".
            findPageFromHistory: find a page they visited before, like "what was that article about rust I read \
            last week?", "find the recipe I looked at yesterday", "that hotel site from Monday".
            compareOpenTabs: compare or weigh up things they have open in several tabs, like "compare these hotels", \
            "which of these laptops is best?", "compare the flights I have open".
            askAssistant: anything else, which an AI assistant answers: questions, writing, and anything about \
            the page they're on, like "what's the capital of France?", "summarize this page", \
            "write a poem about tabs", "explain this", "how do I clear my history?".
            """)
        guard let intent = try? await session.respond(to: "Request: \(prompt)", generating: LookupIntent.self,
                                                      options: GenerationOptions(temperature: 0)).content else { return nil }
        let terms = intent.searchTerms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let kind: DaxPetLookup.Kind
        switch intent.action {
        case .findOpenTab: kind = .openTab
        case .findPageFromHistory: kind = .history
        case .compareOpenTabs: kind = .compareTabs
        case .askAssistant: return nil
        }
        return DaxPetLookup(kind: kind, terms: terms, daysBack: max(intent.daysBack, 0))
    }

    @Generable
    struct Picks {
        @Guide(description: "Numbers of the pages that match what the user is looking for, best match first; empty when none clearly matches")
        var numbers: [Int]
    }

    func pick(_ prompt: String, from pages: [String], maximum: Int) async -> [Int] {
        guard !pages.isEmpty else { return [] }
        let session = LanguageModelSession(instructions: """
            The user is looking for a page among these numbered ones. Give the numbers of the pages that are \
            what they're looking for, best first, at most \(maximum). Give none when no page clearly is.
            """)
        let list = pages.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        guard let picks = try? await session.respond(to: "Looking for: \(prompt)\n\nPages:\n\(list)", generating: Picks.self,
                                                     options: GenerationOptions(temperature: 0)).content else { return [] }
        var seen = Set<Int>()
        return picks.numbers
            .map { $0 - 1 }
            .filter { pages.indices.contains($0) && seen.insert($0).inserted }
            .prefix(maximum)
            .map { $0 }
    }

    @Generable
    struct ScreenTopic {
        @Guide(description: "What the user is looking at, in a few words, like a product, place, article or person")
        var topic: String
        @Guide(description: "One to three short words to search web page titles for, like the names of products, places, brands or people; no generic words",
               .count(1...3))
        var searchTerms: [String]
    }

    func screenTopic(_ text: String, appName: String) async -> DaxPetScreenTopic? {
        let session = LanguageModelSession(instructions: """
            This is text read off the user's screen in \(appName). Say what they're looking at, and words to search \
            their browsing history for pages about it. Leave out the app's own buttons and menus.
            """)
        guard let response = try? await session.respond(to: String(text.prefix(Self.contentLimit)), generating: ScreenTopic.self,
                                                        options: GenerationOptions(temperature: 0)).content else { return nil }
        let topic = response.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = response.searchTerms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !topic.isEmpty, !terms.isEmpty else { return nil }
        return DaxPetScreenTopic(topic: topic, terms: terms)
    }

    /// The user's language, by its English name, for the model to answer in.
    static var userLanguage: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
    }

    /// What was dropped, as text the model can read.
    static func describe(_ attachments: [DaxPetAttachment]) -> String {
        let parts = attachments.map { attachment -> String in
            switch attachment {
            case .text(_, let text):
                return "Text:\n\(text.prefix(contentLimit))"
            case .link(_, let url):
                return "A link: \(url.absoluteString)"
            case .image(let image):
                return "An image named \(image.fileName)"
            case .file(let file):
                let text = file.mimeType == "application/pdf" ? PDFDocument(data: file.data)?.string ?? "" : ""
                return text.isEmpty ? "A file named \(file.fileName)" : "A PDF named \(file.fileName):\n\(text.prefix(contentLimit))"
            }
        }
        return parts.joined(separator: "\n\n")
    }
}
