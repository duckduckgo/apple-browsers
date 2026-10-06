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

/// Text selected in a page, and where it came from.
struct AIChatPageTextSelection {
    let text: String
    let url: URL?
    let faviconBase64: String?
}

/// The Duck.ai actions that can be taken on a text selection.
///
/// Only `ask` is offered in the selection edit menu; the others are offered inside the sheet.
enum AIChatTextSelectionAction: String, CaseIterable, Equatable {
    case summarize
    case ask
    case translate

    /// Ask only attaches the selection and waits for the user's own question.
    var autoSubmits: Bool {
        switch self {
        case .summarize, .translate: return true
        case .ask: return false
        }
    }

    /// The submitting actions carry the text themselves, so attaching it too would send it twice.
    var attachesSelection: Bool {
        !autoSubmits
    }

    /// Catalog id of the suggestion for this action. Ask has none: it is what attaches the selection.
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
