//
//  AutocompleteViewModel.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Core
import Suggestions
import SwiftUI

/// Controls which suggestion types are displayed in autocomplete.
enum AutocompleteSuggestionFilter {
    /// Show all suggestions: search phrases, URLs, bookmarks, history, open tabs, AI chat.
    case all
    /// Show only URL-based suggestions: websites, bookmarks, history.
    /// Used in duck.ai mode as a fallback when chat history has no matches —
    /// users typing URLs should still get autocomplete without seeing search suggestions.
    case urlsOnly
}

protocol AutocompleteViewModelDelegate: NSObjectProtocol {

    func onSuggestionSelected(_ suggestion: Suggestion, ddgSuggestionIndex: Int?)
    func onSuggestionHighlighted(_ suggestion: Suggestion, forQuery query: String)
    func onTapAhead(_ suggestion: Suggestion)
    func deleteSuggestion(_ suggestion: Suggestion)

}

class AutocompleteViewModel: ObservableObject {

    @Published var selection: SuggestionModel? {
        didSet {
            if let selection {
                delegate?.onSuggestionHighlighted(selection.suggestion,
                                                  forQuery: query ?? "")
            }
        }
    }
    @Published var topHits = [SuggestionModel]()
    @Published var ddgSuggestions = [SuggestionModel]()
    @Published var localResults = [SuggestionModel]()
    @Published var aiChatSuggestions = [SuggestionModel]()
    @Published var query: String?
    @Published var emptySuggestion: [SuggestionModel]?
    @Published var isPad: Bool = false
    @Published var sectionTitle: String?
    weak var delegate: AutocompleteViewModelDelegate?

    let isAddressBarAtBottom: Bool
    let showAskAIChat: Bool
    var suggestionFilter: AutocompleteSuggestionFilter = .all

    init(isAddressBarAtBottom: Bool, showAskAIChat: Bool) {
        self.isAddressBarAtBottom = isAddressBarAtBottom
        self.showAskAIChat = showAskAIChat
    }

    func updateSuggestions(_ suggestions: SuggestionResult) {
        topHits = suggestions.topHits.map { SuggestionModel(suggestion: $0) }
        ddgSuggestions = suggestions.duckduckgoSuggestions.map { SuggestionModel(suggestion: $0) }
        localResults = suggestions.localSuggestions.map { SuggestionModel(suggestion: $0) }

        switch suggestionFilter {
        case .all:
            if topHits.isEmpty && ddgSuggestions.isEmpty && localResults.isEmpty {
                topHits = [SuggestionModel(suggestion: .phrase(phrase: query ?? ""), canShowTapAhead: false)]
            }
            if showAskAIChat, let query {
                aiChatSuggestions = [.init(suggestion: .askAIChat(value: query))]
            } else {
                aiChatSuggestions = []
            }
        case .urlsOnly:
            aiChatSuggestions = []
        }
    }

    func onSuggestionSelected(_ model: SuggestionModel) {
        let index = ddgSuggestions.firstIndex(of: model)
        delegate?.onSuggestionSelected(model.suggestion, ddgSuggestionIndex: index)
    }

    func onTapAhead(_ model: SuggestionModel) {
        delegate?.onTapAhead(model.suggestion)
    }

    /// True when the highlighted suggestion is the first selectable row.
    var isSelectionAtFirstRow: Bool {
        guard let selection else { return false }
        return (topHits + ddgSuggestions + localResults + aiChatSuggestions).first == selection
    }

    func nextSelection() {
        let all = topHits + ddgSuggestions + localResults + aiChatSuggestions
        let updated = SuggestionListKeyboardSelection.next(after: selection, in: all)
        // Assign only on change so a press at the edge doesn't re-fire onSuggestionHighlighted.
        if updated != selection {
            selection = updated
        }
    }

    func previousSelection() {
        let all = topHits + ddgSuggestions + localResults + aiChatSuggestions
        let updated = SuggestionListKeyboardSelection.previous(before: selection, in: all)
        if updated != selection {
            selection = updated
        }
    }

    func clearSelection() {
        selection = nil
        // Highlighting overwrote the omnibar with the suggestion text, so on deselect restore the
        // user's typed query via the existing highlight callback.
        if let query {
            delegate?.onSuggestionHighlighted(.phrase(phrase: query), forQuery: query)
        }
    }

    func deleteSuggestion(_ suggestion: SuggestionModel) {
        delegate?.deleteSuggestion(suggestion.suggestion)
    }

    struct SuggestionModel: Identifiable, Equatable {
        let id = UUID()
        let suggestion: Suggestion
        var canShowTapAhead = true

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
        }
    }

}

/// Keyboard arrow selection math for the autocomplete suggestion list.
enum SuggestionListKeyboardSelection {

    /// From no selection, picks the first item; otherwise advances one, clamping at the end. A selection not
    /// in `items` is left unchanged.
    static func next<Element: Equatable>(after current: Element?, in items: [Element]) -> Element? {
        guard let current else { return items.first }
        guard let index = items.firstIndex(of: current) else { return current }
        let nextIndex = index + 1
        return items.indices.contains(nextIndex) ? items[nextIndex] : current
    }

    /// A no-op from no selection; otherwise retreats one, clamping at the start.
    static func previous<Element: Equatable>(before current: Element?, in items: [Element]) -> Element? {
        guard let current, let index = items.firstIndex(of: current) else {
            return current
        }
        let previousIndex = index - 1
        return items.indices.contains(previousIndex) ? items[previousIndex] : current
    }

}
