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

/// Builds the `AIChatSelectionContextData` payload the duck.ai web app expects for one attached
/// text selection. Kept aligned with `macOS/DuckDuckGo/AIChat/AIChatSelectionContextAttacher.swift`
/// so both platforms describe a selection identically.
enum AIChatSelectionContextBuilder {

    /// Matches the `maxContentLength` default in content-scope-scripts (page-context.js) and the macOS cap.
    static let maxSelectionContextLength = 9500

    /// How many selections one session may hold. A flat count rather than a token budget, matching
    /// macOS — a token-aware cap would have to model per-model limits the native side doesn't know.
    static let maxAttachedSelections = 5

    /// Longest snippet put in a chip label. The label truncates itself, so this only bounds the
    /// string handed to it rather than trying to match the chip's fixed width.
    static let maxDisplayTitleLength = 120

    /// Truncates `text` for the wire payload while describing the *original* in `fullContentLength`
    /// and `wordCount`, so the frontend can tell the user how much was selected even though it only
    /// receives the first `maxSelectionContextLength` characters.
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

    /// Re-expresses a selection as page-context data, so it can reach the model before the frontend
    /// reads selections off the prompt directly.
    ///
    /// **Interim.** `AIChatNativePrompt` has `platform`, `tool` and `pageContext` and no selection
    /// slot, and on iPhone *native* composes the prompt (`supportsNativeChatInput` is true when the
    /// unified input owns the input), unlike macOS where the frontend composes it and folds in its own
    /// selection list. So the only shape that reaches the model today is page context. The cost is
    /// that the model can't tell selected text from the page — which is exactly what the delivery flip
    /// fixes, and the only thing the frontend is needed for.
    ///
    /// `wordCount` has no page-context equivalent and is dropped here; it survives the flip.
    static func makePageContextData(from selection: AIChatSelectionContextData) -> AIChatPageContextData {
        AIChatPageContextData(
            title: selection.title,
            favicon: selection.favicon,
            url: selection.url,
            content: selection.content,
            truncated: selection.truncated,
            fullContentLength: selection.fullContentLength,
            attachable: true,
            // `tabId` is the frontend's discriminator for "a distinct attached context" versus "the
            // current page" (nil). Without it a selection sent alongside the page reads as a second
            // current-page entry and one of the two is discarded. The selection's own id is stable
            // and unique, so it serves.
            tabId: selection.id,
            attached: true
        )
    }

    /// Label for a selection's chip: the selected text, whitespace-collapsed and curly-quoted as
    /// macOS quotes it, so several chips are told apart by what they contain rather than all reading
    /// "Text selection".
    static func displayTitle(for content: String) -> String {
        let collapsed = content.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let snippet = collapsed.count > maxDisplayTitleLength
            ? String(collapsed.prefix(maxDisplayTitleLength)).trimmingCharacters(in: .whitespaces) + "…"
            : collapsed
        return "“\(snippet)”"
    }
}
