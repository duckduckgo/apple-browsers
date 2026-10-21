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
    /// A few short questions the user might ask Duck.ai about what they dropped on Dax.
    func suggestions(for attachments: [DaxPetAttachment]) async -> [String]
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
    func suggestions(for attachments: [DaxPetAttachment]) async -> [String] { [] }
}

@available(macOS 26, *)
@MainActor
final class DaxPetOnDeviceIntelligence: DaxPetIntelligence {

    /// The model only sees the start of long content.
    static let contentLimit = 3000

    @Generable
    struct Suggestions {
        @Guide(description: "Requests the user could send to an AI assistant about the content, each at most six words, without quotes",
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
