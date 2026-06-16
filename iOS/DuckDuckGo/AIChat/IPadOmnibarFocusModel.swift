//
//  IPadOmnibarFocusModel.swift
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

/// Pure, **iPad-only** decision model for the unified omnibar focus surface.
///
/// Given a snapshot of the situation (toggle mode, page kind, edit state) it decides which suggestions
/// surface to present. No UIKit, no side effects — fully unit-testable. Layout (popover height, anchor
/// inset, animation) is a *derivative* of the resulting `Surface`, computed by the view layer.
///
/// The central concept is the **unedited page URL**: when the field still shows the page's address and
/// the user hasn't typed (a tap/cursor move doesn't count), it is treated as "no query" — which yields
/// favorites in search and recents in Duck.ai, never autocomplete of the address itself.
enum IPadOmnibarFocusModel {

    enum Mode: Equatable {
        case search
        case duckAI
    }

    enum PageKind: Equatable {
        case newTabPage
        case serp
        case website   // any loaded site, including a Duck.ai page
    }

    /// What the popover should present. Layout is derived from this, not decided here.
    enum Surface: Equatable {
        case none
        case favorites
        case searchSuggestions(query: String)
        case duckAISuggestions(query: String)   // empty query → recents only
    }

    /// A snapshot of everything the decision depends on.
    struct Context: Equatable {
        var mode: Mode
        var pageKind: PageKind
        /// Whether the user has any favorites to show.
        var hasFavorites: Bool
        /// The omnibar's current text.
        var fieldText: String
        /// The current page's URL string, compared against `fieldText`.
        var pageURL: String?
        /// Sticky: true once the user has typed since the page URL was last displayed (a tap doesn't
        /// count, and typing-then-deleting back to the URL stays `true`).
        var userHasEditedText: Bool
    }

    /// The field shows the page's address untouched — not a user-entered query.
    static func isShowingUneditedPageURL(_ context: Context) -> Bool {
        guard !context.userHasEditedText, let pageURL = context.pageURL else { return false }
        return context.fieldText == pageURL
    }

    /// The query suggestions feed off: the unedited page URL is treated as "no query".
    static func effectiveQuery(_ context: Context) -> String {
        isShowingUneditedPageURL(context) ? "" : context.fieldText
    }

    /// The single source of truth for which surface the popover presents. Whether the Duck.ai list
    /// actually has rows to show (an async concern) is gated by the presenter, not here.
    static func surface(for context: Context) -> Surface {
        switch context.mode {
        case .duckAI:
            return .duckAISuggestions(query: effectiveQuery(context))
        case .search:
            return searchSurface(for: context)
        }
    }

    private static func searchSurface(for context: Context) -> Surface {
        let query = effectiveQuery(context)

        // No typed query (unedited page URL, or the field cleared/empty): favorites only on a website —
        // the new tab page shows its own grid and SERP shows nothing.
        if query.isEmpty {
            return context.hasFavorites && context.pageKind == .website ? .favorites : .none
        }

        // A real typed query autocompletes on every page, including the new tab page.
        return .searchSuggestions(query: query)
    }
}
