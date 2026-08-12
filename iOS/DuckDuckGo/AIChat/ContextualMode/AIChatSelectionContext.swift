//
//  AIChatSelectionContext.swift
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

import AIChat
import Foundation

/// Builds the payload describing one attached text selection. Kept aligned with
/// `macOS/DuckDuckGo/AIChat/AIChatSelectionContextAttacher.swift`.
enum AIChatSelectionContextBuilder {

    /// Matches the `maxContentLength` default in content-scope-scripts (page-context.js) and the macOS cap.
    static let maxSelectionContextLength = 9500

    /// A flat count rather than a token budget, matching macOS — native can't model per-model limits.
    static let maxAttachedSelections = 5

    static let maxDisplayTitleLength = 120

    /// Truncates `text` for the payload while `fullContentLength` and `wordCount` keep describing the
    /// original, so how much was selected survives truncation.
    static func makeSelection(text: String,
                              url: URL?,
                              faviconBase64: String? = nil,
                              id: String = UUID().uuidString) -> AIChatSelectionContextData {
        let truncated = text.count > maxSelectionContextLength
        let content = truncated ? String(text.prefix(maxSelectionContextLength)) : text
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        let favicon = faviconBase64.map { [AIChatPageContextData.PageContextFavicon(href: $0, rel: "icon")] } ?? []

        return AIChatSelectionContextData(
            id: id,
            title: UserText.aiChatTextSelectionTitle,
            favicon: favicon,
            url: url?.absoluteString ?? "",
            content: content,
            truncated: truncated,
            fullContentLength: text.count,
            wordCount: wordCount
        )
    }

    /// Label for a selection's chip — "312 words · a dog…". Size leads because it is what stays legible
    /// when the chip truncates.
    static func displayTitle(for selection: AIChatSelectionContextData) -> String {
        let collapsed = selection.content.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let snippet = collapsed.count > maxDisplayTitleLength
            ? String(collapsed.prefix(maxDisplayTitleLength)).trimmingCharacters(in: .whitespaces) + "…"
            : collapsed
        return "\(UserText.aiChatTextSelectionWordCount(selection.wordCount)) · \(snippet)"
    }
}
