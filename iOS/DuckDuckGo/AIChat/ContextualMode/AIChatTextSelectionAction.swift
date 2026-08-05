//
//  AIChatTextSelectionAction.swift
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

/// The Duck.ai actions that can be taken on a text selection.
///
/// Only `ask` is offered in the selection edit menu — see `WebView.buildMenu`. Summarize and translate
/// are offered inside the sheet instead, once the user has already chosen to involve Duck.ai.
enum AIChatTextSelectionAction: String, CaseIterable, Equatable {
    case summarize
    case ask
    case translate

    /// Whether picking this action submits a prompt straight away.
    ///
    /// Matches macOS: summarize acts immediately (`revealChat(for: prompt)`), while ask only attaches
    /// the selection and waits for the user to write their own question (`revealChat()`, no prompt).
    var autoSubmits: Bool {
        switch self {
        case .summarize, .translate: return true
        case .ask: return false
        }
    }

    /// Whether the selected text becomes an attachment.
    ///
    /// Only ask does. Summarize and translate carry their text inside the tool payload (`TextSummary` /
    /// `Translation`), so attaching it as well would send the model the same text twice.
    var attachesSelection: Bool {
        !autoSubmits
    }

    /// Catalog id of the suggestion that performs this action on an attached selection. Ask has none —
    /// it is what attaches the selection in the first place, so there is nothing left to suggest.
    var selectionSuggestionID: String? {
        switch self {
        case .summarize: return "summarize-selection"
        case .translate: return "translate-selection"
        case .ask: return nil
        }
    }

    /// Suggestion ids offered against an attached selection, in display order.
    static let selectionSuggestionIDs = [summarize, translate].compactMap(\.selectionSuggestionID)

    init?(selectionSuggestionID id: String) {
        guard let match = Self.allCases.first(where: { $0.selectionSuggestionID == id }) else { return nil }
        self = match
    }
}
