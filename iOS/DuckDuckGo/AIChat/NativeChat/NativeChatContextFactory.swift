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

    static func context(prompt: String, page: AIChatPageContextData?, selections: [AIChatSelectionContextData]) -> DuckAIChatCore.ChatContext? {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return try? DuckAIChatCore.ChatContext(page: page.map(PageContext.init),
                                               selections: selections.map(DuckAIChatCore.Selection.init),
                                               opening: .prompt(text))
    }

    /// Voice, image generation, attachments and tab-attachment sessions stay on the web.
    static func context(for request: AIChatOpeningRequest) -> DuckAIChatCore.ChatContext? {
        guard case .sharedHandler(let query, _, _) = request.prompt,
              case .query(let nativeQuery)? = query.nativePrompt.tool,
              nativeQuery.mode == nil,
              nativeQuery.attachments.isEmpty else { return nil }
        let text = (query.query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let page: AIChatPageContextData? = if case .single(let data)? = query.nativePrompt.pageContext { data } else { nil }
        let opening: Opening? = text.isEmpty || !query.autoSend ? nil : .prompt(text)
        return try? DuckAIChatCore.ChatContext(page: page.map(PageContext.init),
                                               selections: (query.nativePrompt.selections ?? []).map(DuckAIChatCore.Selection.init),
                                               opening: opening)
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
