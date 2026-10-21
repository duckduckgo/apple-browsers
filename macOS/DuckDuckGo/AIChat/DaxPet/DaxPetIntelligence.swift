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
}

struct DaxPetPageGlance: Equatable {
    let summary: String
    let followUps: [String]
}

enum DaxPetIntelligenceFactory {

    /// The on-device model where Apple Intelligence is on; otherwise Dax does without.
    @MainActor
    static func make() -> DaxPetIntelligence {
        if #available(macOS 26, *), SystemLanguageModel.default.isAvailable, SystemLanguageModel.default.supportsLocale() {
            return DaxPetOnDeviceIntelligence()
        }
        return DaxPetNoIntelligence()
    }
}

struct DaxPetNoIntelligence: DaxPetIntelligence {
    var isOnDevice: Bool { false }
    func pageGlance(title: String, content: String) async -> DaxPetPageGlance? { nil }
    func suggestions(for attachments: [DaxPetAttachment]) async -> [String] { [] }
    func variations(of line: String) async -> [String] { [] }
    func kind(of attachments: [DaxPetAttachment]) async -> DaxPetDropKind? { nil }
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
        return DaxPetPageGlance(summary: summary, followUps: followUps)
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
