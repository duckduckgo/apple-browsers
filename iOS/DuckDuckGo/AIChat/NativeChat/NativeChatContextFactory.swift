//
//  NativeChatContextFactory.swift
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
import DuckAIChatCore
import Foundation
import UIKit
import ImageIO

/// The only place the app's AIChat context types become the native chat's `ChatContext`.
/// Returns nil for anything the native chat does not handle, so the caller keeps the web path.
enum NativeChatContextFactory {

    static func context(suggestionID: String,
                        prompt: String,
                        page: AIChatPageContextData?,
                        selections: [AIChatSelectionContextData],
                        uiLocale: String) -> DuckAIChatCore.ChatContext? {
        let language = TargetLanguage(code: ContextualSuggestionsMatcher.uiLanguageSubtag(uiLocale),
                                      name: ContextualSuggestionsMatcher.languageDisplayName(uiLocale))
        let opening: Opening
        switch suggestionID {
        case "summarize-page", "summarize-selection": opening = .request(.summarize)
        case "translate-page", "translate-selection": opening = .request(.translate(into: language))
        default: opening = .prompt(prompt)
        }
        return try? DuckAIChatCore.ChatContext(page: page.map(PageContext.init),
                                               selections: selections.map(DuckAIChatCore.Selection.init),
                                               opening: opening)
    }

    static func context(prompt: String, page: AIChatPageContextData?, selections: [AIChatSelectionContextData], attachments: AIChatPromptAttachments = .none) throws -> DuckAIChatCore.ChatContext? {
        let text = promptText(prompt, attachments: attachments)
        let images = try decode(attachments)
        guard !text.isEmpty || !images.isEmpty else { return nil }
        return try? DuckAIChatCore.ChatContext(page: page.map(PageContext.init),
                                               selections: selections.map(DuckAIChatCore.Selection.init),
                                               opening: .prompt(text), attachments: images)
    }

    @MainActor
    static func context(for request: AIChatOpeningRequest) throws -> DuckAIChatCore.ChatContext? {
        guard case .sharedHandler(let query, _, _) = request.prompt,
              case .query(let nativeQuery)? = query.nativePrompt.tool,
              nativeQuery.mode == nil else { return nil }
        let text = promptText(query.query ?? "", attachments: nativeQuery.attachments)
        let images = try decode(nativeQuery.attachments)
        let pages = pageParts(query.nativePrompt.pageContext)
        let opening: Opening? = (text.isEmpty && images.isEmpty) || !query.autoSend ? nil : .prompt(text)
        return try? DuckAIChatCore.ChatContext(pages: pages,
                                               selections: (query.nativePrompt.selections ?? []).map(DuckAIChatCore.Selection.init),
                                               opening: opening, attachments: images)
    }
    private static func pageParts(_ context: AIChatPageContextPayload?) -> [PageContext] {
        switch context {
        case .single(let page): return [PageContext(page)]
        case .multiple(let pages): return pages.map(PageContext.init)
        case nil: return []
        }
    }

    static func promptText(_ text: String, attachments: AIChatPromptAttachments) -> String {
        ([text] + (attachments.textPasted ?? []).map(\.content)).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    static func decode(_ attachments: AIChatPromptAttachments) throws -> [DuckAIChatCore.Attachment] {
        guard attachments.files?.isEmpty ?? true else { throw ChatError.unknown("Files are unavailable in local chat.") }
        let limits = ImageInputLimits.standard
        guard (attachments.images?.count ?? 0) <= limits.countPerTurn else { throw ChatError.unknown("Attach one image per message.") }
        return try (attachments.images ?? []).map { image in
            guard image.data.utf8.count <= ((limits.bytesPerImage + 2) / 3) * 4,
                  let data = Data(base64Encoded: image.data), data.count <= limits.bytesPerImage,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, max(width, height) <= limits.longestDimension,
                  CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
                throw ChatError.unknown("Invalid or oversized image. Choose an image again.")
            }
            return DuckAIChatCore.Attachment(id: UUID().uuidString, kind: .image(format: image.format), data: data)
        }
    }

    @MainActor
    static func send(_ prompt: String, attachments: AIChatPromptAttachments, pages: [AIChatPageContextData]? = nil, to session: ChatSession) {
        do { session.send(promptText(prompt, attachments: attachments), attachments: try decode(attachments),
                          context: pages.map { $0.map { .page(PageContext($0)) } }) } catch { session.reject(error as? ChatError ?? .unknown(error.localizedDescription)) }
    }

}

private extension PageContext {
    init(_ data: AIChatPageContextData) {
        self.init(title: data.title, url: URL(string: data.url), content: data.content)
    }
}

private extension DuckAIChatCore.Selection {
    init(_ data: AIChatSelectionContextData) {
        self.init(title: data.title, url: URL(string: data.url), content: data.content)
    }
}
