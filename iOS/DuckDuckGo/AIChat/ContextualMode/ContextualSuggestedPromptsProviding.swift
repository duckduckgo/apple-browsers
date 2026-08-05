//
//  ContextualSuggestedPromptsProviding.swift
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

struct ResolvePageSuggestionsInput {

    /// What the offered suggestions should act on.
    enum Scope {
        /// The current page, matched against its type signals, URL and domain.
        case page
        /// A single attached text selection. Only the selection-scoped catalog entries are offered —
        /// page-derived ones would act on the wrong thing.
        case selection
    }

    let pageTypeSignals: AIChatPageTypeSignals?
    let url: String?
    let uiLocale: String
    let scope: Scope

    init(pageTypeSignals: AIChatPageTypeSignals?, url: String?, uiLocale: String, scope: Scope = .page) {
        self.pageTypeSignals = pageTypeSignals
        self.url = url
        self.uiLocale = uiLocale
        self.scope = scope
    }
}

/// Coarse, pixel-safe classification of the current page, mirroring the frontend's `PageType`.
/// Analytics-only — never drives which suggestions are offered. Raw values are the pixel
/// parameter values.
enum SuggestionsPageType: String, Equatable {
    case recipe
    case product
    case article
    case video
    case job
    case book
    case event
    case place
    case forum
    case code
    case course
    case review
    case person
    case howto
    case faq
    case none
}

struct ResolvedPageSuggestions: Equatable {
    let suggestions: [ContextualSuggestedPrompt]
    /// Whether the suggestions came from a page-tailored (contextual) match rather than the generic defaults.
    let isSmart: Bool
    let pageType: SuggestionsPageType
}

protocol ContextualSuggestedPromptsProviding {
    /// Catalog-owned chip budget shared by suggestions and quick actions.
    var maxSuggestedPrompts: Int { get }
    /// Suggestions that must displace a regular suggestion rather than be trimmed from the end.
    var prioritySuggestionIDs: Set<String> { get }

    func resolveSuggestions(_ input: ResolvePageSuggestionsInput) async -> ResolvedPageSuggestions
}
